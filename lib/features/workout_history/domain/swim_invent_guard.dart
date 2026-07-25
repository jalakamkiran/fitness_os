import 'dart:math' as math;

import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';

/// Why invent-guard flagged a lap as garbage / non-working.
enum SwimLapFilterReason {
  incompleteLength,
  outlierStrokes,
  outlierDuration,
}

/// Per-lap invent-guard classification.
class SwimLapInventGuardVerdict {
  const SwimLapInventGuardVerdict({
    required this.isGarbage,
    this.reason,
  });

  final bool isGarbage;
  final SwimLapFilterReason? reason;
}

/// Classify a single lap. Prefer [filterSwimLapsForAnalytics] for session sets
/// so stroke/duration outliers use peer medians.
SwimLapInventGuardVerdict classifySwimLapInventGuard(
  SwimLapMetrics lap, {
  int? poolLengthM,
  double? medianStrokes,
  double? medianDur,
}) {
  final reason = _classify(
    lap,
    poolLengthM: poolLengthM != null && poolLengthM > 0 ? poolLengthM : null,
    medianStrokes: medianStrokes,
    medianDur: medianDur,
  );
  return SwimLapInventGuardVerdict(
    isGarbage: reason != null,
    reason: reason,
  );
}

/// Count laps invent-guard would hide (product default).
int countInventGuardFilteredLaps(
  List<SwimLapMetrics> laps, {
  int? poolLengthM,
}) {
  return _flaggedIndexes(laps, poolLengthM: poolLengthM).length;
}

/// Active laps for charts + interval table.
///
/// Product lock: garbage hidden by default (`includeFiltered: false`).
List<SwimLapMetrics> filterSwimLapsForAnalytics(
  List<SwimLapMetrics> laps, {
  int? poolLengthM,
  bool includeFiltered = false,
}) {
  final ordered = [...laps]..sort((a, b) => a.index.compareTo(b.index));
  if (includeFiltered) return ordered;
  final garbage = _flaggedIndexes(ordered, poolLengthM: poolLengthM);
  return ordered.where((l) => !garbage.contains(l.index)).toList();
}

Set<int> _flaggedIndexes(
  List<SwimLapMetrics> laps, {
  int? poolLengthM,
}) {
  if (laps.isEmpty) return {};

  final ordered = [...laps]..sort((a, b) => a.index.compareTo(b.index));
  final pool = poolLengthM != null && poolLengthM > 0 ? poolLengthM : null;

  final strokeVals = ordered
      .map((l) => l.strokes)
      .whereType<int>()
      .where((s) => s > 0)
      .toList()
    ..sort();
  final medianStrokes = _median(strokeVals);

  final durVals = ordered
      .map((l) => l.durationSec)
      .whereType<int>()
      .where((d) => d > 0)
      .toList()
    ..sort();
  final medianDur = _median(durVals);

  final flagged = <int>{};
  for (final lap in ordered) {
    final reason = _classify(
      lap,
      poolLengthM: pool,
      medianStrokes: medianStrokes,
      medianDur: medianDur,
    );
    if (reason != null) flagged.add(lap.index);
  }
  return flagged;
}

SwimLapFilterReason? _classify(
  SwimLapMetrics lap, {
  required int? poolLengthM,
  required double? medianStrokes,
  required double? medianDur,
}) {
  final dist = lap.distanceM;
  if (poolLengthM != null && dist != null && dist > 0) {
    // Incomplete length — design fixture uses 3m vs 25m pool.
    if (dist < poolLengthM * 0.4) {
      return SwimLapFilterReason.incompleteLength;
    }
  } else if (dist != null && dist > 0 && dist < 10) {
    return SwimLapFilterReason.incompleteLength;
  }

  final strokes = lap.strokes;
  final dur = lap.durationSec;

  // Absolute short-duration + absurd strokes (design fixture: 1s / 180 stk).
  if (dur != null &&
      dur > 0 &&
      dur <= 2 &&
      strokes != null &&
      strokes >= 80) {
    return SwimLapFilterReason.outlierDuration;
  }

  if (strokes != null && strokes > 0) {
    if (medianStrokes != null) {
      if (strokes >= math.max(100, (medianStrokes * 2.5).round())) {
        return SwimLapFilterReason.outlierStrokes;
      }
    } else if (strokes >= 100) {
      return SwimLapFilterReason.outlierStrokes;
    }
  }

  if (dur != null && dur > 0 && medianDur != null && medianDur >= 8) {
    if (dur <= math.max(2, (medianDur * 0.15).round()) &&
        strokes != null &&
        strokes >= 80) {
      return SwimLapFilterReason.outlierDuration;
    }
  }

  return null;
}

double? _median(List<int> sorted) {
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}
