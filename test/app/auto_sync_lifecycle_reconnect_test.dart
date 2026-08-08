import 'package:fitness_os/app/auto_sync_lifecycle.dart';
import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/huawei/one_shot_auto_sync.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Link extends HuaweiLink {
  _Link() : super();

  LinkState forced = LinkState.disconnected;
  int startCalls = 0;

  @override
  LinkState get state => forced;

  @override
  bool get sessionReady =>
      forced == LinkState.connected || forced == LinkState.gateAIncomplete;

  @override
  Future<void> start() async {
    startCalls++;
  }
}

class _Pairing implements DevicePairingRepository {
  _Pairing(this.link);

  final _Link link;
  int startLinkCalls = 0;
  int reconnectCalls = 0;
  RememberedDevice? remembered =
      const RememberedDevice(mac: 'AA:BB:CC:DD:EE:FF', name: 'GT5');

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
    link.forced = LinkState.connected;
    return const Right(null);
  }

  @override
  Future<RememberedDevice?> loadRemembered() async => remembered;

  @override
  Future<Either<Failure, void>> ensurePermissions() async => const Right(null);

  @override
  Future<Either<Failure, void>> startScan() async => const Right(null);

  @override
  Future<Either<Failure, void>> stopScan() async => const Right(null);

  @override
  Future<Either<Failure, void>> pair(String mac, String name) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> setAuthKey(String userId) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> forgetDevice() async => const Right(null);

  @override
  Future<Either<Failure, void>> recordR11Path(String path) async =>
      const Right(null);

  @override
  Future<GateAStatus> loadGateAStatus() async => const GateAStatus(
        killOk: true,
        rebootOk: true,
        btToggleOk: true,
        passed: true,
      );

  @override
  Future<Either<Failure, GateAStatus>> creditInterrupt({
    required GateAInterrupt interrupt,
    required bool reachedAuthenticated,
  }) async =>
      Right(await loadGateAStatus());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cold open starts link and reconnects remembered device before auto-sync',
    (tester) async {
      final link = _Link();
      final pairing = _Pairing(link);
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
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(pairing.startLinkCalls, 1);
      expect(pairing.reconnectCalls, 1);
      expect(passCalls, 1);
      expect(autoSync.passStarts, 1);
    },
  );

  testWidgets('skips reconnect when encrypted session already ready',
      (tester) async {
    final link = _Link()..forced = LinkState.connected;
    final pairing = _Pairing(link);
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
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(pairing.startLinkCalls, 1);
    expect(pairing.reconnectCalls, 0);
    expect(passCalls, 1);
  });
}
