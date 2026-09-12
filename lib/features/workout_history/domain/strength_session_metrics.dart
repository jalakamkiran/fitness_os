import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/presentation/view/workout_history_formatters.dart';

/// Derived / display helpers for GT5 strength (type 140) session UI.
///
/// Never invents recovery % or HR curves. Null fields stay absent — do not
/// zero-fill missing watch scalars (0 is only shown when the watch sent 0).
class StrengthSessionMetrics {
  const StrengthSessionMetrics(this.workout);

  final WorkoutSummary workout;

  bool get isStrength => isStrengthWorkout(workout.type);

  /// Compact duration for hero chips (`53m`, `1h 12m`).
  String? get durationLabel {
    final sec = workout.durationSec;
    if (sec <= 0) return null;
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  String? get caloriesLabel =>
      workout.calories == null ? null : '${workout.calories}';

  /// Heart-rate range from min–max when either bound is present.
  String? get hrRangeLabel {
    final min = workout.hrMin;
    final max = workout.hrMax;
    if (min != null && max != null) return '$min–$max';
    if (min != null) return '$min';
    if (max != null) return '$max';
    return null;
  }

  String? get loadLabel =>
      workout.load == null ? null : '${workout.load}';

  /// Watch [WorkoutSummary.recoveryTime] is minutes.
  String? get recoveryTimeLabel => formatRecoveryMinutes(workout.recoveryTime);

  String? get aerobicLabel =>
      workout.aerobicEffect == null ? null : '${workout.aerobicEffect}';

  String? get anaerobicLabel =>
      workout.anaerobicEffect == null ? null : '${workout.anaerobicEffect}';

  /// Calories per minute of session duration.
  String? get caloriesPerMinLabel {
    final cal = workout.calories;
    final sec = workout.durationSec;
    if (cal == null || sec <= 0) return null;
    final perMin = cal / (sec / 60.0);
    return perMin.toStringAsFixed(1);
  }

  /// Training load per hour of session duration.
  String? get loadPerHourLabel {
    final load = workout.load;
    final sec = workout.durationSec;
    if (load == null || sec <= 0) return null;
    final perHour = load / (sec / 3600.0);
    return perHour.toStringAsFixed(1);
  }

  bool get hasBasics =>
      durationLabel != null || caloriesLabel != null || hrRangeLabel != null;

  bool get hasImpact => loadLabel != null || recoveryTimeLabel != null;

  bool get hasIntensity =>
      caloriesPerMinLabel != null ||
      loadPerHourLabel != null ||
      aerobicLabel != null ||
      anaerobicLabel != null;
}

/// Formats watch recovery minutes for product UI (`1h`, `45m`, `1h 30m`).
String? formatRecoveryMinutes(int? minutes) {
  if (minutes == null) return null;
  if (minutes < 0) return null;
  if (minutes == 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

/// Chronological strength sessions ending at [current], newest last, max [limit].
List<WorkoutSummary> recentStrengthLoads({
  required WorkoutSummary current,
  required List<WorkoutSummary> all,
  int limit = 8,
}) {
  final strength = all.where((w) => isStrengthWorkout(w.type)).toList()
    ..sort((a, b) {
      final byStart = a.startTime.compareTo(b.startTime);
      if (byStart != 0) return byStart;
      return a.number.compareTo(b.number);
    });

  final idx = strength.indexWhere(
    (w) => w.number == current.number && w.startTime == current.startTime,
  );
  if (idx < 0) {
    // Current not in history yet — show current alone rather than a wrong window.
    return [current];
  }
  final endExclusive = idx + 1;
  final start = (endExclusive - limit).clamp(0, endExclusive);
  return strength.sublist(start, endExclusive);
}
