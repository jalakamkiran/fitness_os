sealed class WorkoutHistoryEvent {
  const WorkoutHistoryEvent();
}

final class WorkoutHistoryStarted extends WorkoutHistoryEvent {
  const WorkoutHistoryStarted();
}

final class WorkoutHistorySyncRequested extends WorkoutHistoryEvent {
  const WorkoutHistorySyncRequested({this.forceFullHistory = false});

  /// One-shot Count window from mid-2022 (POC FALLBACK) — re-ask the watch
  /// for workouts already past the incremental cursor. Still hint-gated
  /// Data/Pace (no force-empty enrichment).
  final bool forceFullHistory;
}

/// Reloads local workouts after Forget / sync invalidation (IndexedStack keeps
/// this factory bloc alive across tabs).
final class WorkoutHistoryReloadRequested extends WorkoutHistoryEvent {
  const WorkoutHistoryReloadRequested();
}
