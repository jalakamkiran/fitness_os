import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';

abstract class DevicePairingRepository {
  Stream<HuaweiLinkEvent> get linkEvents;
  LinkState get linkState;
  List<DiscoveredDevice> get discovered;
  String? get lastError;
  String? get recoveryHint;

  Future<void> startLink();
  Future<Either<Failure, void>> ensurePermissions();
  Future<Either<Failure, void>> startScan();
  Future<Either<Failure, void>> stopScan();
  Future<Either<Failure, void>> pair(String mac, String name);
  Future<Either<Failure, void>> reconnectRemembered();
  Future<Either<Failure, void>> setAuthKey(String userId);
  Future<Either<Failure, void>> forgetDevice();
  Future<Either<Failure, void>> recordR11Path(String path);

  Future<RememberedDevice?> loadRemembered();
  Future<GateAStatus> loadGateAStatus();
  Future<Either<Failure, GateAStatus>> creditInterrupt({
    required GateAInterrupt interrupt,
    required bool reachedAuthenticated,
  });
}

class RememberedDevice {
  const RememberedDevice({required this.mac, required this.name});
  final String mac;
  final String name;
}

enum GateAInterrupt { kill, reboot, btToggle }

class GateAStatus {
  const GateAStatus({
    required this.killOk,
    required this.rebootOk,
    required this.btToggleOk,
    required this.passed,
  });

  final bool killOk;
  final bool rebootOk;
  final bool btToggleOk;
  final bool passed;

  bool get allBits => killOk && rebootOk && btToggleOk;

  GateAStatus copyWith({
    bool? killOk,
    bool? rebootOk,
    bool? btToggleOk,
    bool? passed,
  }) {
    return GateAStatus(
      killOk: killOk ?? this.killOk,
      rebootOk: rebootOk ?? this.rebootOk,
      btToggleOk: btToggleOk ?? this.btToggleOk,
      passed: passed ?? this.passed,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GateAStatus &&
        other.killOk == killOk &&
        other.rebootOk == rebootOk &&
        other.btToggleOk == btToggleOk &&
        other.passed == passed;
  }

  @override
  int get hashCode => Object.hash(killOk, rebootOk, btToggleOk, passed);
}
