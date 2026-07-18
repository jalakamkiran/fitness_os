import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';

abstract class VitalsRepository {
  Future<bool> isGateAPassed();

  /// True while channel Sync/Enable or local merge/persist is in flight.
  bool get isSyncOrMergeInFlight;

  /// Encrypted session ready for Enable radio (mirrors link sessionReady).
  bool get sessionReady;

  Future<List<SleepSessionSummary>> loadSleepSessions();

  Future<List<DailyHrDaySummary>> loadDailyHr();

  /// Last explicit Enable SoT (null if never run or corrupt).
  Future<AutoTrackingEnableResult?> loadLastEnable();

  /// Gate A → syncActivity → container-scoped merge.
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch();

  /// Explicit auto-tracking enable → persist last-run.
  Future<Either<Failure, AutoTrackingEnableResult>> enableAutoTracking();

  /// Wipe sleep + HR + last-enable prefs (+ side-file dirs when present).
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
