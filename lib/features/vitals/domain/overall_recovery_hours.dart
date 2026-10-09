/// Overall hours remaining until ready for hard work (Fathom composition).
///
/// Stacks resolved session recovery with Huawei-shaped remaining + stress and
/// 1:1 wall-clock decay, then applies capped sleep / activity modifiers.
/// Athlete chrome should label this **Recovery time** + hours only.
library;

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/session_recovery.dart';

const int kOverallRecoveryLookbackDays = 7;
const double kOverallRecoveryCapHours = 96;

/// Result of [composeOverallRecoveryHours].
class OverallRecoveryHoursResult {
  const OverallRecoveryHoursResult({
    required this.asOf,
    required this.insufficientData,
    this.hoursRemaining,
  });

  /// Wall-clock instant used for decay.
  final DateTime asOf;

  /// True when there is nothing honest to show (hide vs `—` is a surface choice).
  final bool insufficientData;

  /// Remaining hours when [insufficientData] is false; null when insufficient.
  final double? hoursRemaining;

  /// Athlete-facing value: `14h`, `0h`, or `—`.
  String get displayLabel {
    if (insufficientData || hoursRemaining == null) return '—';
    final h = hoursRemaining!;
    if (h <= 0) return '0h';
    final rounded = h.round();
    if (rounded <= 0) return '0h';
    return '${rounded}h';
  }
}

/// Compose overall recovery hours from lookback sessions + sleep + day activity.
OverallRecoveryHoursResult composeOverallRecoveryHours({
  required List<WorkoutSummary> workouts,
  required DateTime now,
  int? sleepDurationSec,
  int? daySteps,
  int? dayCalories,
  int? medianDaySteps,
  int? medianDayCalories,
}) {
  final lookbackStart = now.subtract(
    const Duration(days: kOverallRecoveryLookbackDays),
  );
  final lookbackStartUnix = lookbackStart.millisecondsSinceEpoch ~/ 1000;

  final sessions = workouts
      .where((w) => w.endTime > 0 && w.endTime >= lookbackStartUnix)
      .toList()
    ..sort((a, b) => a.endTime.compareTo(b.endTime));

  var remain = 0.0;
  DateTime? lastMark;
  var anySessionContribution = false;

  for (final w in sessions) {
    final resolved = resolveSessionRecovery(w);
    if (resolved == null) continue;
    anySessionContribution = true;
    final end = DateTime.fromMillisecondsSinceEpoch(w.endTime * 1000);
    if (lastMark != null) {
      remain = _decay(remain, lastMark!, end);
    }
    remain = _min(kOverallRecoveryCapHours, remain + resolved.hours);
    lastMark = end;
  }

  if (lastMark != null) {
    remain = _decay(remain, lastMark!, now);
  }

  final hasSleep = sleepDurationSec != null && sleepDurationSec > 0;
  final hasActivity = daySteps != null || dayCalories != null;

  if (!anySessionContribution && !hasSleep && !hasActivity) {
    return OverallRecoveryHoursResult(
      asOf: now,
      insufficientData: true,
    );
  }

  final sleepMod = _sleepModifierHours(sleepDurationSec);
  final activityMod = _activityModifierHours(
    daySteps: daySteps,
    dayCalories: dayCalories,
    medianDaySteps: medianDaySteps,
    medianDayCalories: medianDayCalories,
  );
  remain = _clamp(remain + sleepMod + activityMod, 0, kOverallRecoveryCapHours);

  return OverallRecoveryHoursResult(
    asOf: now,
    insufficientData: false,
    hoursRemaining: remain,
  );
}

double _decay(double remain, DateTime from, DateTime to) {
  final hours = to.difference(from).inSeconds / 3600.0;
  if (hours <= 0) return remain;
  return remain - hours < 0 ? 0.0 : remain - hours;
}

double _sleepModifierHours(int? sleepDurationSec) {
  if (sleepDurationSec == null || sleepDurationSec <= 0) return 0;
  final min = sleepDurationSec / 60.0;
  if (min < 5 * 60) return 4;
  if (min < 6 * 60) return 2;
  return 0;
}

double _activityModifierHours({
  int? daySteps,
  int? dayCalories,
  int? medianDaySteps,
  int? medianDayCalories,
}) {
  double stepsMod = 0;
  if (daySteps != null &&
      medianDaySteps != null &&
      medianDaySteps > 0 &&
      daySteps > 0) {
    final ratio = daySteps / medianDaySteps;
    if (ratio >= 2) {
      stepsMod = 2;
    } else if (ratio >= 1.5) {
      stepsMod = 1;
    }
  }
  double calMod = 0;
  if (dayCalories != null &&
      medianDayCalories != null &&
      medianDayCalories > 0 &&
      dayCalories > 0) {
    final ratio = dayCalories / medianDayCalories;
    if (ratio >= 2) {
      calMod = 2;
    } else if (ratio >= 1.5) {
      calMod = 1;
    }
  }
  return stepsMod > calMod ? stepsMod : calMod;
}

double _min(double a, double b) => a < b ? a : b;

double _clamp(double v, double lo, double hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}
