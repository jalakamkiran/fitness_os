/// Schema constants and stamps for the owner-initiated app-data JSON export.
abstract final class AppDataExportEnvelope {
  static const schemaVersion = 1;

  static const consistencyClass = 'best_effort';

  static const sensitivityNotes =
      'Contains health biometrics and workout history. Not anonymized. Do not commit.';

  /// Candidate omissions — stamped only when still absent after assemble
  /// (option 2: include when already present on device; no new persistence).
  static const candidateOmissions = <String>[
    'swim_sample_data_pages',
    'swim_pace_blocks',
    'ephemeral_coach_reasoner_outputs',
    'diagnosis_and_recommendation_snapshots',
    'daily_activity_calories_beyond_workout_totals_sum',
    'remembered_mac',
    'gemini_api_key',
    'native_huawei_secrets',
  ];

  /// Always omitted for privacy (never stamp as "included").
  static const alwaysOmitted = <String>{
    'remembered_mac',
    'gemini_api_key',
    'native_huawei_secrets',
  };

  static const exportCacheDirName = 'exports';

  static const softWarnBytes = 25 * 1024 * 1024;

  static const parseOk = 'ok';
  static const parseCorrupt = 'corrupt';
  static const parseAbsent = 'absent';
}
