import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';

abstract class VitalsRepository {
  Future<bool> isGateAPassed();

  /// True while channel Sync or local merge is in flight (Forget must refuse).
  bool get isSyncOrMergeInFlight;

  Future<List<SleepSessionSummary>> loadSleepSessions();

  Future<List<DailyHrDaySummary>> loadDailyHr();

  /// Gate A → syncActivity → container-scoped merge.
  Future<Either<Failure, VitalsSnapshot>> syncFromWatch();

  /// Wipe sleep + HR prefs (+ side-file dirs when present). Idempotent.
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
