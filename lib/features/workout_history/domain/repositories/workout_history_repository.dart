import 'package:fitness_os/core/error/failures.dart';
import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/core/utils/either.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

abstract class WorkoutHistoryRepository {
  Future<bool> isGateAPassed();
  Future<List<WorkoutSummary>> loadLocal();
  Future<Either<Failure, List<WorkoutSummary>>> syncFromWatch();

  /// True while channel Sync or local merge/persist is in flight (Forget busy gate).
  bool get isSyncOrMergeInFlight;

  /// After the latest `ok` persist: every incoming leftover write landed (or was
  /// empty). False when a leftover body was present but the side-file write failed
  /// — U4 must not stamp leftover-keep.
  bool get lastLeftoverPersistLanded;

  /// Wipe leftover + sample side-file dirs (and prefs leftovers when composed by U6).
  Future<void> clearLocal();

  /// Load persisted canonical swim for a workout number (side-file).
  Future<CanonicalSwimSession?> loadCanonicalSwim(int workoutNumber);

  /// Build P0 from a summary without requiring a prior side-file (detail UI).
  CanonicalSwimSession? canonicalSwimFromSummary(WorkoutSummary workout);

  /// All canonical swims (side-files + rebuild from local swim summaries).
  Future<List<CanonicalSwimSession>> loadAllCanonicalSwims();

  /// Trends + diagnoses; [focusWorkoutNumber] scopes session diagnoses.
  Future<SwimDiagnosisReport> loadSwimDiagnosisReport({int? focusWorkoutNumber});
}
