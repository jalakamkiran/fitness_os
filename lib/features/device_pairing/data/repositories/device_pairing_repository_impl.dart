import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DevicePairingRepositoryImpl implements DevicePairingRepository {
  DevicePairingRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
  })  : _link = link,
        _prefs = prefs;

  final HuaweiLink _link;
  final SharedPreferences _prefs;

  @override
  Stream<HuaweiLinkEvent> get linkEvents => _link.events;

  @override
  LinkState get linkState => _link.state;

  @override
  List<DiscoveredDevice> get discovered => _link.discovered;

  @override
  String? get lastError => _link.lastError;

  @override
  String? get recoveryHint => _link.recoveryHint;

  @override
  Future<void> startLink() => _link.start();

  @override
  Future<Either<Failure, void>> ensurePermissions() async {
    final ok = await _link.ensurePermissions();
    if (!ok) {
      return const Left(PermissionFailure('Bluetooth permission required'));
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> startScan() async {
    await _link.startScan();
    if (_link.state == LinkState.permissionRequired) {
      return const Left(PermissionFailure('Bluetooth permission required'));
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> stopScan() async {
    await _link.stopScan();
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> pair(String mac, String name) async {
    await _link.connectAndAuthenticate(mac);
    if (_link.state == LinkState.gateAIncomplete ||
        _link.state == LinkState.connected) {
      await _prefs.setString(GateAPrefs.rememberedMac, mac);
      await _prefs.setString(GateAPrefs.rememberedName, name);
      return const Right(null);
    }
    return Left(
      AuthFailure(_link.lastError ?? 'Authentication failed'),
    );
  }

  @override
  Future<Either<Failure, void>> reconnectRemembered() async {
    final remembered = await loadRemembered();
    if (remembered == null) {
      return const Left(CacheFailure('No remembered device'));
    }
    await _link.reconnect(remembered.mac);
    if (_link.state == LinkState.gateAIncomplete ||
        _link.state == LinkState.connected) {
      final status = await loadGateAStatus();
      if (status.passed) {
        _link.markGateAPassed();
      }
      return const Right(null);
    }
    if (_link.state == LinkState.reconnectFailed ||
        _link.state == LinkState.bondRequired ||
        _link.state == LinkState.authFailed) {
      return Left(ReconnectFailure(_link.lastError ?? 'Reconnect failed'));
    }
    return Left(ReconnectFailure(_link.lastError ?? 'Reconnect incomplete'));
  }

  @override
  Future<Either<Failure, void>> setAuthKey(String userId) async {
    final trimmed = userId.trim();
    if (trimmed.isNotEmpty &&
        (trimmed.length != 17 || !RegExp(r'^\d{17}$').hasMatch(trimmed))) {
      return const Left(ValidationFailure('Auth key must be a 17-digit userId'));
    }
    await _link.setAuthKey(trimmed);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> forgetDevice() async {
    await _prefs.remove(GateAPrefs.rememberedMac);
    await _prefs.remove(GateAPrefs.rememberedName);
    await _prefs.remove(GateAPrefs.gateAKillOk);
    await _prefs.remove(GateAPrefs.gateARebootOk);
    await _prefs.remove(GateAPrefs.gateABtToggleOk);
    await _prefs.remove(GateAPrefs.gateAPassed);
    await _prefs.remove(GateAPrefs.lastSyncCursor);
    await _link.clearSecrets();
    await _link.disconnect();
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> recordR11Path(String path) async {
    await _prefs.setString(GateAPrefs.lastR11Path, path);
    return const Right(null);
  }

  @override
  Future<RememberedDevice?> loadRemembered() async {
    final mac = _prefs.getString(GateAPrefs.rememberedMac);
    final name = _prefs.getString(GateAPrefs.rememberedName);
    if (mac == null || mac.isEmpty) return null;
    return RememberedDevice(mac: mac, name: name ?? 'HUAWEI Watch GT 5');
  }

  @override
  Future<GateAStatus> loadGateAStatus() async {
    return GateAStatus(
      killOk: _prefs.getBool(GateAPrefs.gateAKillOk) ?? false,
      rebootOk: _prefs.getBool(GateAPrefs.gateARebootOk) ?? false,
      btToggleOk: _prefs.getBool(GateAPrefs.gateABtToggleOk) ?? false,
      passed: _prefs.getBool(GateAPrefs.gateAPassed) ?? false,
    );
  }

  @override
  Future<Either<Failure, GateAStatus>> creditInterrupt({
    required GateAInterrupt interrupt,
    required bool reachedAuthenticated,
  }) async {
    if (!reachedAuthenticated) {
      return const Left(
        ValidationFailure(
          'Interrupt credit rejected — reconnect did not reach authenticated session',
        ),
      );
    }
    final state = _link.state;
    if (state != LinkState.gateAIncomplete && state != LinkState.connected) {
      return const Left(
        ValidationFailure(
          'Interrupt credit rejected — link is not in an authenticated session',
        ),
      );
    }

    switch (interrupt) {
      case GateAInterrupt.kill:
        await _prefs.setBool(GateAPrefs.gateAKillOk, true);
      case GateAInterrupt.reboot:
        await _prefs.setBool(GateAPrefs.gateARebootOk, true);
      case GateAInterrupt.btToggle:
        await _prefs.setBool(GateAPrefs.gateABtToggleOk, true);
    }

    var status = await loadGateAStatus();
    if (status.allBits) {
      await _prefs.setBool(GateAPrefs.gateAPassed, true);
      status = status.copyWith(passed: true);
      _link.markGateAPassed();
    }
    return Right(status);
  }
}

class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'Permission required']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

class ReconnectFailure extends Failure {
  const ReconnectFailure([super.message = 'Reconnect failed']);
}

class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Validation failed']);
}
