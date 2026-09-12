/// Pref keys owned by Dart (identity + Gate A). Secrets stay native-only.
abstract final class GateAPrefs {
  static const rememberedMac = 'remembered_mac';
  static const rememberedName = 'remembered_name';
  static const gateAKillOk = 'gate_a_kill_ok';
  static const gateARebootOk = 'gate_a_reboot_ok';
  static const gateABtToggleOk = 'gate_a_bt_toggle_ok';
  static const gateAPassed = 'gate_a_passed';
  static const lastSyncCursor = 'last_sync_cursor';
  /// Activity Sync (vitals) incremental cursor — distinct from workout [lastSyncCursor].
  static const lastActivitySyncCursor = 'last_activity_sync_cursor';
  /// Bumped when activity Sync merge rules change; forces one wide-window re-pull.
  static const activitySyncImplVersion = 'activity_sync_impl_version';
  /// Legacy leftover-keep one-shot stamp — cleared on Forget; Sync no longer reads it.
  static const leftoverKeepImplVersion = 'leftover_keep_impl_version';
  static const lastR11Path = 'last_r11_winning_path';
  /// Bumped when swim segment wire parse changes; stamped after successful Sync.
  static const swimSegmentParserVersion = 'swim_segment_parser_version';
  /// Bumped when run/session leftover+stream merge remap rules change.
  /// Escape hatch for enrichment-monotonic leftover/scalar replacement.
  static const runSessionParserVersion = 'run_session_parser_version';
  /// JSON list of synced workout summaries (Gate B local store).
  static const workoutsJson = 'workouts_json';
  /// JSON list of sleep session intervals (begin/end).
  static const sleepSessionsJson = 'sleep_sessions_json';
  /// JSON list of daily HR day summaries (min/avg/max/count).
  static const dailyHrJson = 'daily_hr_json';
  /// JSON list of FitnessTotals day rollups (calories/steps/duration).
  static const fitnessTotalsDayJson = 'fitness_totals_day_json';
  /// Side-file subdir under application support for per-day HR minute series.
  static const dailyHrSeriesDir = 'vitals/hr_series';
  /// Side-file subdir for per-session sleep stage lists (message-path SoT).
  static const sleepStagesDir = 'vitals/sleep_stages';
  /// Side-file subdir for TruSleep FileDownload enrich refs (present|absent).
  static const sleepEnrichDir = 'vitals/sleep_enrich';
  /// Native-persisted TruSleep blobs (len/path only in enrich JSON; never commit).
  static const sleepFilesDir = 'vitals/sleep_files';
  /// True after any file-interval display SoT upsert (messages never own begin/end).
  static const fileSleepSotActive = 'file_sleep_sot_active';
  /// JSON map of feel-on-wake survey answers keyed by sleep merge key.
  static const sleepFeelOnWakeJson = 'sleep_feel_on_wake_json';
  /// Side-file subdir for canonical swim sessions (one JSON per workout #).
  static const canonicalSwimDir = 'workouts/canonical_swim';
  /// Sport-agnostic Totals leftover TLV bodies (keyed by workout #).
  static const workoutTotalsLeftoversDir = 'workouts/totals_leftovers';
  /// Sport-agnostic WorkoutData sample page bodies (keyed by workout #).
  static const workoutDataPagesDir = 'workouts/data_pages';
  /// Sport-agnostic Pace block bodies (keyed by workout #).
  static const workoutPaceBlocksDir = 'workouts/pace_blocks';
  /// Temp-dir cache for Outdoor Run session AI exports (Forget wipe + verify).
  static const runSessionExportsDir = 'run_session_exports';
  /// Native-persisted workout HR sample point files (path+counts on channel; never series).
  static const workoutHrSamplesDir = 'workouts/hr_samples';
  /// Dart-persisted Totals leftover / recovery-HR opaque blobs (len+path in prefs; never bodies).
  static const workoutLeftoversDir = 'workouts/leftovers';
  /// Gemini API key for W4 coach (device-local; never commit).
  static const geminiApiKey = 'gemini_api_key';
  /// Last explicit Enable auto-tracking result (outcomes-only allowlist).
  static const lastAutoTrackingEnableJson = 'last_auto_tracking_enable_json';

  /// Home one-shot sync outcome: `ok` | `failed` (absent = never synced from Home).
  static const homeLastSyncStatus = 'home_last_sync_status';

  /// Unix ms of last Home-observed successful sync pass.
  static const homeLastSyncAtMs = 'home_last_sync_at_ms';

  /// JSON list of meal metadata (FoodMeal index).
  static const foodMealsIndexJson = 'food_meals_index_json';
  /// Side-file subdir for meal photos: {dayKey}/{mealId}.jpg
  static const foodMealsDir = 'food/meals';
  
  /// JSON map of meal schedule config (slots/times/enabled).
  static const foodScheduleJson = 'food_schedule_json';
  /// Reminders globally enabled (default false until user opts in).
  static const foodRemindersEnabled = 'food_reminders_enabled';
}
