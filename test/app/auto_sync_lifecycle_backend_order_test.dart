import 'dart:async';

import 'package:fitness_os/app/auto_sync_lifecycle.dart';
import 'package:fitness_os/core/backend/sync_models.dart';
import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/backend/backend_sync_service.dart';
import 'package:fitness_os/core/backend/local_sync_snapshot.dart';
import 'package:fitness_os/core/backend/sync_ledger_store.dart';
import 'package:fitness_os/core/backend/sync_record_validator.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync_di.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/backend_fakes.dart';

class TestLink extends HuaweiLink {
  TestLink() : super();

  LinkState forced = LinkState.disconnected;

  @override
  LinkState get state => forced;

  @override
  bool get sessionReady =>
      forced == LinkState.connected || forced == LinkState.gateAIncomplete;
}

class TestPairing implements DevicePairingRepository {
  TestPairing(this.link);

  final TestLink link;
  int startLinkCalls = 0;
  int reconnectCalls = 0;
  RememberedDevice? remembered =
      const RememberedDevice(mac: 'AA:BB:CC:DD:EE:FF', name: 'GT5');
  Completer<Either<Failure, void>>? reconnectCompleter;

  @override
  Stream<HuaweiLinkEvent> get linkEvents => link.events;

  @override
  LinkState get linkState => link.state;

  @override
  List<DiscoveredDevice> get discovered => const [];

  @override
  String? get lastError => null;

  @override
  String? get recoveryHint => null;

  @override
  Future<void> startLink() async {
    startLinkCalls++;
    await link.start();
  }

  @override
  Future<Either<Failure, void>> reconnectRemembered() async {
    reconnectCalls++;
    final c = reconnectCompleter;
    if (c != null) return c.future;
    link.forced = LinkState.connected;
    return const Right(null);
  }

  @override
  Future<RememberedDevice?> loadRemembered() async => remembered;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingPusher implements BackendPusher {
  final events = <String>[];
  final List<Completer<void>> _gates = [];
  var holdPush = false;

  @override
  Future<PushOutcome> push(SyncTrigger trigger) async {
    events.add('push:${trigger.name}');
    if (holdPush) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    return PushOutcome(trigger: trigger, ok: true);
  }

  void releaseOne() {
    if (_gates.isNotEmpty) _gates.removeAt(0).complete();
  }

  @override
  void startRetryTimer() {}

  @override
  void stopRetryTimer() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('push(open) before reconnect; pass after connected', (tester) async {
    final link = TestLink();
    final pairing = TestPairing(link)
      ..reconnectCompleter = Completer<Either<Failure, void>>();
    final pusher = RecordingPusher();

    var passCalls = 0;
    final autoSync = OneShotAutoSync(
      isSessionReady: () => isAutoSyncSessionReady(link.state),
      isSyncBusy: () => false,
      runPass: () async {
        passCalls++;
      },
    );

    await tester.pumpWidget(
      AutoSyncLifecycle(
        autoSync: autoSync,
        link: link,
        pairing: pairing,
        backendPusher: pusher,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    expect(pusher.events, ['push:open']);
    expect(passCalls, 0);

    pairing.reconnectCompleter!.complete(const Right(null));
    link.forced = LinkState.connected;
    autoSync.onSessionReady();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(passCalls, 1);
  });

  testWidgets('order: push:open → pass → push:postWatch', (tester) async {
    final link = TestLink()..forced = LinkState.connected;
    final pairing = TestPairing(link);
    final pusher = RecordingPusher();
    final log = <String>[];

    final autoSync = OneShotAutoSync(
      isSessionReady: () => isAutoSyncSessionReady(link.state),
      isSyncBusy: () => false,
      runPass: () async {
        log.add('pass:start');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('pass:end');
        await pusher.push(SyncTrigger.postWatch);
      },
    );

    await tester.pumpWidget(
      AutoSyncLifecycle(
        autoSync: autoSync,
        link: link,
        pairing: pairing,
        backendPusher: pusher,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(pusher.events.first, 'push:open');
    expect(log, ['pass:start', 'pass:end']);
    expect(pusher.events.last, 'push:postWatch');
  });

  test('runAutoSyncPass always pushes postWatch after pass', () async {
    final pusher = RecordingPusher();
    final workouts = FakeWorkoutRepo();
    final vitals = FakeVitalsRepo();

    await runAutoSyncPass(
      workouts: workouts,
      vitals: vitals,
      pusher: pusher,
    );

    expect(pusher.events, contains('push:postWatch'));
  });

}