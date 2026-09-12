sealed class WorkoutHistoryEvent {
  const WorkoutHistoryEvent();
}

final class WorkoutHistoryStarted extends WorkoutHistoryEvent {
  const WorkoutHistoryStarted();
}

final class WorkoutHistorySyncRequested extends WorkoutHistoryEvent {
  const WorkoutHistorySyncRequested();
}

/// Reloads local workouts after Forget / sync invalidation (IndexedStack keeps
/// this factory bloc alive across tabs).
final class WorkoutHistoryReloadRequested extends WorkoutHistoryEvent {
  const WorkoutHistoryReloadRequested();
}
