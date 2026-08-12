import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/vitals/domain/morning_wellness.dart';

abstract class VitalsRepository {
  Future<bool> isGateAPassed();

  /// True while channel Sync/Enable or local merge/persist is in flight.
  bool get isSyncOrMergeInFlight;

  /// Encrypted session ready for Enable radio (mirrors link sessionReady).
  bool get sessionReady;

  Future<List<SleepSessionSummary>> loadSleepSessions();

  /// Message-path stage blocks for one sleep session merge key.
  /// Empty on missing/corrupt side-file (fail-closed; does not wipe prefs).
  Future<List<SleepStageSummary>> loadSleepStages(SleepSessionSummary session);

  Future<List<DailyHrDaySummary>> loadDailyHr();

  /// Per-minute HR samples for one local calendar day (`yyyy-MM-dd`), if persisted.
  Future<List<DailyHrSample>> loadDailyHrSeries(String dayKey);

  /// Continuous vitals HR samples in `[beginUnix, endUnix]` (inclusive bounds).
  /// Loads every local dayKey covering the span (overnight = two files).
  Future<List<DailyHrSample>> loadSleepHrWindow({
    required int beginUnix,
    required int endUnix,
  });

  /// TruSleep FileDownload enrich present for this session (side-file ref).
  Future<bool> isSleepEnrichPresent(SleepSessionSummary session);

  /// Complete Hooper-4 morning wellness for [session.mergeKey], or null.
  Future<MorningWellness?> loadMorningWellness(SleepSessionSummary session);

  /// Persist complete Hooper-4 once per session key (no-op if already complete).
  Future<void> saveMorningWellness(
    SleepSessionSummary session,
    MorningWellness wellness,
  );

  /// Sleep sessions whose local end falls in the given calendar month.
  Future<List<SleepSessionSummary>> loadSleepSessionsForMonth({
    required int year,
    required int month,
  });

  /// FitnessTotals day rows (replace-by-day store). Fail-closed on corrupt JSON.
  Future<List<FitnessTotalsDay>> loadFitnessTotals();

  /// Single local-day FitnessTotals row, or null if absent / load fail-closed.
  Future<FitnessTotalsDay?> loadFitnessTotalsForDay(String dayKey);

  /// Last explicit Enable SoT (null if never run or corrupt).
  Future<AutoTrackingEnableResult?> loadLastEnable();

  /// Gate A → syncActivity → container-scoped merge.
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch();

  /// Explicit auto-tracking enable → persist last-run.
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking();

  /// Wipe sleep + HR + fitness totals + last-enable prefs (+ side-file dirs when present).
  Future<void> clearLocal();
}

class VitalsSnapshot {
  const VitalsSnapshot({
    required this.sleepSessions,
    required this.dailyHr,
    this.message,
    this.partial = false,
    this.enableSkipped = false,
  });

  final List<SleepSessionSummary> sleepSessions;
  final List<DailyHrDaySummary> dailyHr;
  final String? message;
  final bool partial;
  final bool enableSkipped;
}
