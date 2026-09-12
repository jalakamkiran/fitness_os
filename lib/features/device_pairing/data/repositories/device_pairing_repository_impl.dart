import 'dart:io';

import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';
import 'package:fitness_os/features/device_pairing/domain/repositories/device_pairing_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DevicePairingRepositoryImpl implements DevicePairingRepository {
  DevicePairingRepositoryImpl({
    required HuaweiLink link,
    required SharedPreferences prefs,
    Future<void> Function()? onForgetWipeExtras,
    void Function()? onForgot,
    bool Function()? isForgetBlocked,
    Directory? Function()? supportRootOverride,
    Directory? Function()? tempRootOverride,
  })  : _link = link,
        _prefs = prefs,
        _onForgetWipeExtras = onForgetWipeExtras,
        _onForgot = onForgot,
        _isForgetBlocked = isForgetBlocked,
        _supportRootOverride = supportRootOverride,
        _tempRootOverride = tempRootOverride;

  final HuaweiLink _link;
  final SharedPreferences _prefs;
  Future<void> Function()? _onForgetWipeExtras;
  void Function()? _onForgot;
  bool Function()? _isForgetBlocked;
  final Directory? Function()? _supportRootOverride;
  final Directory? Function()? _tempRootOverride;
  bool _forgetInFlight = false;

  /// True while [forgetDevice] body is running (not the same as isForgetBlocked).
  bool get forgetInFlight => _forgetInFlight;

  /// Registered by vitals DI — clears sleep/HR without pairing constructing that graph.
  set onForgetWipeExtras(Future<void> Function()? callback) {
    _onForgetWipeExtras = callback;
  }

  set onForgot(void Function()? callback) {
    _onForgot = callback;
  }

  set isForgetBlocked(bool Function()? callback) {
    _isForgetBlocked = callback;
  }

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
    final macHex = trimmed.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    final isMac = macHex.length == 12;
    final isUserId =
        trimmed.length == 17 && RegExp(r'^\d{17}$').hasMatch(trimmed);
    if (trimmed.isNotEmpty && !isMac && !isUserId) {
      return const Left(
        ValidationFailure(
          'Enter a 17-digit Huawei userId or a phone BT MAC (AA:BB:CC:DD:EE:FF)',
        ),
      );
    }
    await _link.setAuthKey(trimmed);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> forgetDevice() async {
    if (_link.syncInFlight ||
        _forgetInFlight ||
        (_isForgetBlocked?.call() ?? false)) {
      return const Left(
        ValidationFailure(
          'Sync in progress — wait for it to finish, then Forget',
        ),
      );
    }
    // Fail closed: wipe extras must be registered so leftover/sample/export
    // residue cannot survive a "successful" Forget (diagnostics_di last-writer).
    final wipeExtras = _onForgetWipeExtras;
    if (wipeExtras == null) {
      return const Left(
        ValidationFailure(
          'Forget blocked — wipe extras not registered',
        ),
      );
    }
    _forgetInFlight = true;
    try {
      // Mid-flight busy re-check before any destructive mutation — export/sync
      // that started after Forget began can still abort cleanly.
      if (_link.syncInFlight || (_isForgetBlocked?.call() ?? false)) {
        return const Left(
          ValidationFailure(
            'Sync in progress — wait for it to finish, then Forget',
          ),
        );
      }
      await _prefs.remove(GateAPrefs.rememberedMac);
      await _prefs.remove(GateAPrefs.rememberedName);
      await _prefs.remove(GateAPrefs.gateAKillOk);
      await _prefs.remove(GateAPrefs.gateARebootOk);
      await _prefs.remove(GateAPrefs.gateABtToggleOk);
      await _prefs.remove(GateAPrefs.gateAPassed);
      await _prefs.remove(GateAPrefs.lastSyncCursor);
      await _prefs.remove(GateAPrefs.lastActivitySyncCursor);
      await _prefs.remove(GateAPrefs.activitySyncImplVersion);
      await _prefs.remove(GateAPrefs.fileSleepSotActive);
      await _prefs.remove(GateAPrefs.swimSegmentParserVersion);
      // Peer to swimSegmentParserVersion — wipe here only (not also in workout
      // clearLocal) so Forget has one owner for leftover-keep version.
      await _prefs.remove(GateAPrefs.leftoverKeepImplVersion);
      await _prefs.remove(GateAPrefs.workoutsJson);

      await wipeExtras();
      // Verify vitals / food / leftover / sample / export residue gone.
      final sleepLeft = _prefs.containsKey(GateAPrefs.sleepSessionsJson);
      final hrLeft = _prefs.containsKey(GateAPrefs.dailyHrJson);
      final totalsLeft = _prefs.containsKey(GateAPrefs.fitnessTotalsDayJson);
      final enableLeft =
          _prefs.containsKey(GateAPrefs.lastAutoTrackingEnableJson);
      final activityCursorLeft =
          _prefs.containsKey(GateAPrefs.lastActivitySyncCursor);
      final activityVerLeft =
          _prefs.containsKey(GateAPrefs.activitySyncImplVersion);
      final fileSotLeft = _prefs.containsKey(GateAPrefs.fileSleepSotActive);
      final leftoverKeepLeft =
          _prefs.containsKey(GateAPrefs.leftoverKeepImplVersion);
      if (sleepLeft ||
          hrLeft ||
          totalsLeft ||
          enableLeft ||
          activityCursorLeft ||
          activityVerLeft ||
          fileSotLeft ||
          leftoverKeepLeft) {
        return const Left(
          ValidationFailure('Forget verify failed — vitals residue remains'),
        );
      }

      // Verify food keys and files gone
      final foodIndexLeft = _prefs.containsKey(GateAPrefs.foodMealsIndexJson);
      if (foodIndexLeft) {
        return const Left(
          ValidationFailure('Forget verify failed — food prefs residue remains'),
        );
      }

      // Verify no meal / leftover / sample / export-cache residue (food-meals bar).
      try {
        final root = await _supportRoot();
        final mealsDir = Directory('${root.path}/${GateAPrefs.foodMealsDir}');
        if (await _dirHasFiles(mealsDir)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — food meal files residue remains',
            ),
          );
        }

        final leftoversDir =
            Directory('${root.path}/${GateAPrefs.workoutLeftoversDir}');
        if (await _dirHasFiles(leftoversDir)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — workout leftover files residue remains',
            ),
          );
        }

        // Lean workouts prefs must be cleared with the privacy unit.
        if (_prefs.containsKey(GateAPrefs.workoutsJson)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — workouts prefs residue remains',
            ),
          );
        }

        final samplesDir =
            Directory('${root.path}/${GateAPrefs.workoutHrSamplesDir}');
        if (await _dirHasFiles(samplesDir)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — workout HR sample files residue remains',
            ),
          );
        }

        // R14: run leftover / sample / pace dirs must be empty after wipe.
        for (final rel in [
          GateAPrefs.workoutTotalsLeftoversDir,
          GateAPrefs.workoutDataPagesDir,
          GateAPrefs.workoutPaceBlocksDir,
        ]) {
          final dir = Directory('${root.path}/$rel');
          if (await _dirHasFiles(dir)) {
            return Left(
              ValidationFailure(
                'Forget verify failed — run session files residue remains ($rel)',
              ),
            );
          }
        }

        final temp = await _tempRoot();
        final runExportDir = Directory(
          '${temp.path}/${GateAPrefs.runSessionExportsDir}',
        );
        if (await _dirHasFiles(runExportDir)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — run session export cache residue remains',
            ),
          );
        }

        final strengthExport = Directory(
          '${temp.path}/$strengthSessionExportCacheDirName',
        );
        if (await _dirHasFiles(strengthExport)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — strength export cache residue remains',
            ),
          );
        }

        final sharePlus = Directory('${temp.path}/share_plus');
        if (await _dirHasFiles(sharePlus)) {
          return const Left(
            ValidationFailure(
              'Forget verify failed — share_plus cache residue remains',
            ),
          );
        }
      } catch (_) {
        // If we can't check, fail safe
        return const Left(
          ValidationFailure(
            'Forget verify failed — could not verify food/workout residue',
          ),
        );
      }
      await _link.clearSecrets();
      await _link.disconnect();
      _onForgot?.call();
      return const Right(null);
    } finally {
      _forgetInFlight = false;
    }
  }

  Future<Directory> _supportRoot() async {
    final override = _supportRootOverride?.call();
    return override ?? await getApplicationSupportDirectory();
  }

  Future<Directory> _tempRoot() async {
    final override = _tempRootOverride?.call();
    return override ?? await getTemporaryDirectory();
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

/// Keep in sync with [StrengthSessionExportService.exportCacheDirName].
const strengthSessionExportCacheDirName = 'strength_session_exports';

Future<bool> _dirHasFiles(Directory dir) async {
  if (!await dir.exists()) return false;
  return dir.list(recursive: true).any((entity) => entity is File);
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
