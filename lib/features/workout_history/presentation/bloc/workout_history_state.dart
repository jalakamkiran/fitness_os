import 'package:fitness_os/core/huawei/huawei_link.dart';

enum WorkoutHistoryPhase { idle, syncing, blocked, stuck }

class WorkoutHistoryState {
  const WorkoutHistoryState({
    this.phase = WorkoutHistoryPhase.idle,
    this.gateAPassed = false,
    this.workouts = const [],
    this.message,
  });

  final WorkoutHistoryPhase phase;
  final bool gateAPassed;
  final List<WorkoutSummary> workouts;
  final String? message;

  WorkoutHistoryState copyWith({
    WorkoutHistoryPhase? phase,
    bool? gateAPassed,
    List<WorkoutSummary>? workouts,
    String? message,
    bool clearMessage = false,
  }) {
    return WorkoutHistoryState(
      phase: phase ?? this.phase,
      gateAPassed: gateAPassed ?? this.gateAPassed,
      workouts: workouts ?? this.workouts,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}
