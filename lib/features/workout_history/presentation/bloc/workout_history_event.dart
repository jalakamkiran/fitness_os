sealed class WorkoutHistoryEvent {
  const WorkoutHistoryEvent();
}

final class WorkoutHistoryStarted extends WorkoutHistoryEvent {
  const WorkoutHistoryStarted();
}

final class WorkoutHistorySyncRequested extends WorkoutHistoryEvent {
  const WorkoutHistorySyncRequested();
}
