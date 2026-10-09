/// Soft other-load warning for Programs (R17–R18).
///
/// Factual stacking of owned durations / load — never a recovery score,
/// never auto-cancels a swim chore.

/// Severity of a soft other-load signal.
enum SoftLoadWarnLevel {
  /// No soft warn.
  none,

  /// Mild / relative elevation (e.g. above trailing median only).
  info,

  /// Clear heavy same-day other activity.
  caution,
}

/// Lean other-sport sample for soft-warn (not a full [WorkoutSummary]).
class OtherLoadSample {
  const OtherLoadSample({
    required this.type,
    required this.typeLabel,
    required this.startTimeMs,
    required this.durationSec,
    this.loadOrTe,
    this.hrPeak,
  });

  /// Huawei workout type (6 / 8 = swim — excluded from other-load).
  final int type;

  /// Athlete-facing label (e.g. `Strength`).
  final String typeLabel;

  /// Workout start, epoch ms.
  final int startTimeMs;

  /// Active duration in seconds.
  final int durationSec;

  /// Training load or TE when the device provided it.
  final double? loadOrTe;

  /// Peak HR when present (unused for thresholds; reserved for copy/UI).
  final int? hrPeak;

  /// Pool swim (6) and open water (8) are not other-load for this warn.
  bool get isSwim => type == 6 || type == 8;

  bool get isOtherLoad => !isSwim;
}

/// Result of [SoftLoadWarn.evaluate]. Pure data — does not touch chores.
class SoftLoadWarnResult {
  const SoftLoadWarnResult({
    required this.warn,
    required this.level,
    required this.copy,
    this.todayOtherDurationMin = 0,
    this.trailingMedianDurationMin,
  });

  /// Whether UI should surface a soft warn banner.
  final bool warn;

  final SoftLoadWarnLevel level;

  /// Factual athlete copy (durations). Empty when [warn] is false.
  final String copy;

  /// Sum of same-calendar-day other-load minutes (for tests / UI).
  final int todayOtherDurationMin;

  /// Trailing median of other-load day durations in minutes, when available.
  final double? trailingMedianDurationMin;
}

/// Owner-relative soft warn for heavy other-sport load on a swim day.
class SoftLoadWarn {
  SoftLoadWarn._();

  /// Absolute same-day other-load duration that always warrants caution.
  static const int absoluteWarnDurationMin = 45;

  /// Relative multiplier vs trailing median duration / load.
  static const double medianMultiplier = 1.5;

  /// Lookback window for trailing median (other-load days only).
  static const int lookbackDaysMin = 14;
  static const int lookbackDaysMax = 28;

  /// Sleep shorter than this (minutes) is noted factually as a soft signal.
  static const int shortSleepThresholdMin = 360;

  /// Evaluate soft warn for [day] from recent other-load samples.
  ///
  /// Swims (type 6 / 8) are ignored. Missing [OtherLoadSample.loadOrTe] /
  /// [OtherLoadSample.hrPeak] degrades to duration heuristics — never throws.
  /// Optional [sleepDurationMin] may add a factual sleep note when short;
  /// it never invents a readiness or recovery score.
  static SoftLoadWarnResult evaluate({
    required List<OtherLoadSample> recent,
    required DateTime day,
    int? sleepDurationMin,
  }) {
    final dayLocal = DateTime(day.year, day.month, day.day);
    final other = recent.where((s) => s.isOtherLoad).toList(growable: false);

    final todaySamples = other.where((s) {
      final start = DateTime.fromMillisecondsSinceEpoch(s.startTimeMs);
      return _sameCalendarDay(start, dayLocal);
    }).toList(growable: false);

    final todayDurationSec = todaySamples.fold<int>(
      0,
      (sum, s) => sum + (s.durationSec < 0 ? 0 : s.durationSec),
    );
    final todayDurationMin = todayDurationSec ~/ 60;

    final todayLoad = _sumLoad(todaySamples);

    final medianDurationMin = _trailingMedianDailyDurationMin(
      samples: other,
      day: dayLocal,
    );
    final medianLoad = _trailingMedianDailyLoad(
      samples: other,
      day: dayLocal,
    );

    final absoluteHit = todayDurationMin >= absoluteWarnDurationMin;
    final relativeDurationHit = medianDurationMin != null &&
        medianDurationMin > 0 &&
        todayDurationMin >= medianMultiplier * medianDurationMin;
    final relativeLoadHit = todayLoad != null &&
        medianLoad != null &&
        medianLoad > 0 &&
        todayLoad >= medianMultiplier * medianLoad;

    final shortSleep = sleepDurationMin != null &&
        sleepDurationMin >= 0 &&
        sleepDurationMin < shortSleepThresholdMin;

    final activityHeavy =
        absoluteHit || relativeDurationHit || relativeLoadHit;
    final warn = activityHeavy || shortSleep;

    if (!warn) {
      return SoftLoadWarnResult(
        warn: false,
        level: SoftLoadWarnLevel.none,
        copy: '',
        todayOtherDurationMin: todayDurationMin,
        trailingMedianDurationMin: medianDurationMin,
      );
    }

    // Absolute ≥45 or any activity-heavy relative/load hit → caution.
    // Sleep-only short night → info. Never a scored recovery label.
    final SoftLoadWarnLevel level;
    if (activityHeavy) {
      level = SoftLoadWarnLevel.caution;
    } else {
      level = SoftLoadWarnLevel.info;
    }

    final copy = _buildCopy(
      todaySamples: todaySamples,
      sleepDurationMin: shortSleep ? sleepDurationMin : null,
    );

    return SoftLoadWarnResult(
      warn: true,
      level: level,
      copy: copy,
      todayOtherDurationMin: todayDurationMin,
      trailingMedianDurationMin: medianDurationMin,
    );
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static double? _sumLoad(List<OtherLoadSample> samples) {
    var any = false;
    var sum = 0.0;
    for (final s in samples) {
      final v = s.loadOrTe;
      if (v == null) continue;
      any = true;
      sum += v;
    }
    return any ? sum : null;
  }

  /// Median of daily other-load duration (minutes) over other-load days in
  /// the [lookbackDaysMin]–[lookbackDaysMax] window before [day].
  static double? _trailingMedianDailyDurationMin({
    required List<OtherLoadSample> samples,
    required DateTime day,
  }) {
    final byDay = <String, int>{};
    final windowStart = day.subtract(const Duration(days: lookbackDaysMax));
    final windowEnd = day; // exclusive of evaluated day

    for (final s in samples) {
      final start = DateTime.fromMillisecondsSinceEpoch(s.startTimeMs);
      final d = DateTime(start.year, start.month, start.day);
      if (d.isBefore(windowStart) || !d.isBefore(windowEnd)) continue;
      final key = _dayKey(d);
      final sec = s.durationSec < 0 ? 0 : s.durationSec;
      byDay[key] = (byDay[key] ?? 0) + sec;
    }

    if (byDay.isEmpty) return null;

    // Prefer days inside the trailing window; require at least one other-load
    // day. When many days exist, use up to the last 28 other-load days.
    final mins = byDay.values.map((sec) => sec / 60.0).toList()..sort();
    if (mins.length > lookbackDaysMax) {
      return _median(mins.sublist(mins.length - lookbackDaysMax));
    }
    // Soft preference: if fewer than lookbackDaysMin other-load days, still
    // use whatever we have (owner-relative with sparse history).
    return _median(mins);
  }

  static double? _trailingMedianDailyLoad({
    required List<OtherLoadSample> samples,
    required DateTime day,
  }) {
    final byDay = <String, double>{};
    final windowStart = day.subtract(const Duration(days: lookbackDaysMax));
    final windowEnd = day;

    for (final s in samples) {
      final load = s.loadOrTe;
      if (load == null) continue;
      final start = DateTime.fromMillisecondsSinceEpoch(s.startTimeMs);
      final d = DateTime(start.year, start.month, start.day);
      if (d.isBefore(windowStart) || !d.isBefore(windowEnd)) continue;
      final key = _dayKey(d);
      byDay[key] = (byDay[key] ?? 0) + load;
    }

    if (byDay.isEmpty) return null;
    final values = byDay.values.toList()..sort();
    return _median(values);
  }

  static double _median(List<double> sortedAscending) {
    final n = sortedAscending.length;
    if (n == 0) return 0;
    final mid = n ~/ 2;
    if (n.isOdd) return sortedAscending[mid];
    return (sortedAscending[mid - 1] + sortedAscending[mid]) / 2.0;
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _buildCopy({
    required List<OtherLoadSample> todaySamples,
    int? sleepDurationMin,
  }) {
    final byLabel = <String, int>{};
    for (final s in todaySamples) {
      final label = s.typeLabel.trim().isEmpty
          ? 'workout'
          : s.typeLabel.trim().toLowerCase();
      final sec = s.durationSec < 0 ? 0 : s.durationSec;
      byLabel[label] = (byLabel[label] ?? 0) + sec;
    }

    final parts = <String>[];
    final labels = byLabel.keys.toList()..sort();
    for (final label in labels) {
      final mins = byLabel[label]! ~/ 60;
      if (mins <= 0 && byLabel[label]! > 0) {
        // Sub-minute: still show 1 min so copy stays factual.
        parts.add('$label 1 min');
      } else if (mins > 0) {
        parts.add('$label $mins min');
      }
    }

    if (sleepDurationMin != null) {
      parts.add('sleep ${_formatSleep(sleepDurationMin)}');
    }

    return parts.join(' · ');
  }

  static String _formatSleep(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h h';
    return '$h h $m min';
  }
}
