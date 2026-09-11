import 'package:fitness_os/features/device_pairing/domain/gate_a_prefs.dart';

/// Schema constants for the Outdoor Run target-session AI export (U5).
abstract final class RunSessionExportEnvelope {
  static const schemaVersion = 1;

  static const kind = 'run_session';

  static const consistencyClass = 'best_effort';

  static const sensitivityNotes =
      'Contains non-anonymized session health biometrics (HR, form, leftovers). '
      'Shared copies are not revoked by Forget Device. Do not commit.';

  /// Always omitted — never stamp as included.
  static const alwaysOmitted = <String>{
    'remembered_mac',
    'gemini_api_key',
    'native_huawei_secrets',
    'account_id',
    'bind_auth_tokens',
    'gps_location_series',
  };

  /// Peer to app-data / day-food caches (NOT nested under `exports/`).
  static const exportCacheDirName = GateAPrefs.runSessionExportsDir;

  static const softWarnBytes = 25 * 1024 * 1024;

  static const parseOk = 'ok';
  static const parseCorrupt = 'corrupt';
  static const parseAbsent = 'absent';
}
