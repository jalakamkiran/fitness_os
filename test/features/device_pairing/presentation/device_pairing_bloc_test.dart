import 'dart:async';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/data/repositories/device_pairing_repository_impl.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_bloc.dart';
import 'package:fitness_os/features/device_pairing/presentation/bloc/device_pairing_event.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements DevicePairingRepository {
  _FakeRepo();

  final _controller = StreamController<HuaweiLinkEvent>.broadcast();
  LinkState _state = LinkState.disconnected;
  RememberedDevice? remembered;
  GateAStatus gateA = const GateAStatus(
    killOk: false,
    rebootOk: false,
    btToggleOk: false,
    passed: false,
  );
  final devices = <DiscoveredDevice>[];
  String? error;
  String? hint;
  bool secretsCleared = false;

  @override
  Stream<HuaweiLinkEvent> get linkEvents => _controller.stream;

  @override
  LinkState get linkState => _state;

  @override
  List<DiscoveredDevice> get discovered => devices;

  @override
  String? get lastError => error;

  @override
  String? get recoveryHint => hint;

  @override
  Future<void> startLink() async {}

  @override
  Future<Either<Failure, void>> ensurePermissions() async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> startScan() async {
    _state = LinkState.scanning;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> stopScan() async {
    _state = LinkState.disconnected;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> pair(String mac, String name) async {
    remembered = RememberedDevice(mac: mac, name: name);
    _state = LinkState.gateAIncomplete;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> reconnectRemembered() async {
    if (remembered == null) {
      return const Left(CacheFailure('none'));
    }
    _state = LinkState.gateAIncomplete;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> setAuthKey(String userId) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> forgetDevice() async {
    remembered = null;
    gateA = const GateAStatus(
      killOk: false,
      rebootOk: false,
      btToggleOk: false,
      passed: false,
    );
    secretsCleared = true;
    _state = LinkState.disconnected;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> recordR11Path(String path) async =>
      const Right(null);

  @override
  Future<RememberedDevice?> loadRemembered() async => remembered;

  @override
  Future<GateAStatus> loadGateAStatus() async => gateA;

  @override
  Future<Either<Failure, GateAStatus>> creditInterrupt({
    required GateAInterrupt interrupt,
    required bool reachedAuthenticated,
  }) async {
    if (!reachedAuthenticated) {
      return const Left(ValidationFailure('rejected'));
    }
    switch (interrupt) {
      case GateAInterrupt.kill:
        gateA = gateA.copyWith(killOk: true);
      case GateAInterrupt.reboot:
        gateA = gateA.copyWith(rebootOk: true);
      case GateAInterrupt.btToggle:
        gateA = gateA.copyWith(btToggleOk: true);
    }
    if (gateA.allBits) {
      gateA = gateA.copyWith(passed: true);
      _state = LinkState.connected;
    }
    return Right(gateA);
  }
}

void main() {
  test('AE1: scan → select → remembered across bloc recreation', () async {
    final repo = _FakeRepo();
    final bloc = DevicePairingBloc(repository: repo);
    bloc.add(const DevicePairingStarted());
    await pumpEventQueue();

    bloc.add(const DevicePairingScanRequested());
    await pumpEventQueue();
    expect(bloc.state.linkState, LinkState.scanning);

    bloc.add(
      const DevicePairingSelectDevice(
        mac: 'AA:BB:CC:DD:EE:FF',
        name: 'HUAWEI Watch GT 5-A07',
      ),
    );
    await pumpEventQueue();
    expect(bloc.state.remembered?.mac, 'AA:BB:CC:DD:EE:FF');
    expect(bloc.state.linkState, LinkState.gateAIncomplete);

    await bloc.close();
    final bloc2 = DevicePairingBloc(repository: repo);
    bloc2.add(const DevicePairingStarted());
    await pumpEventQueue();
    expect(bloc2.state.remembered?.mac, 'AA:BB:CC:DD:EE:FF');
    await bloc2.close();
  });

  test('Forget Device clears identity and Gate A', () async {
    final repo = _FakeRepo()
      ..remembered = const RememberedDevice(
        mac: 'AA:BB:CC:DD:EE:FF',
        name: 'GT5',
      )
      ..gateA = const GateAStatus(
        killOk: true,
        rebootOk: true,
        btToggleOk: true,
        passed: true,
      );

    final bloc = DevicePairingBloc(repository: repo);
    bloc.add(const DevicePairingForgetRequested());
    await pumpEventQueue();
    expect(bloc.state.remembered, isNull);
    expect(bloc.state.gateA.passed, isFalse);
    expect(repo.secretsCleared, isTrue);
    await bloc.close();
  });

  test('permission_required maps from repo failure', () async {
    final repo = _PermissionDeniedRepo();
    final bloc = DevicePairingBloc(repository: repo);
    bloc.add(const DevicePairingScanRequested());
    await pumpEventQueue();
    expect(bloc.state.linkState, LinkState.permissionRequired);
    expect(bloc.state.message, contains('permission'));
    await bloc.close();
  });
}

class _PermissionDeniedRepo extends _FakeRepo {
  @override
  Future<Either<Failure, void>> startScan() async {
    _state = LinkState.permissionRequired;
    return const Left(PermissionFailure('Bluetooth permission required'));
  }
}
