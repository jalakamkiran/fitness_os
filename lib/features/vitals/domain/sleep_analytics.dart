import 'dart:math' as math;

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/vitals/domain/sleep_day.dart';

DateTime _localFromUnix(int unix) =>
    DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal();

/// Midpoint of asleep window (fallAsleep→wakeup, else session begin→end).
DateTime? sleepMidSleepLocal(
  TruSleepSequenceSession? summary,
  SleepSessionSummary session,
) {
  final startUnix = summary?.fallAsleepUnix ?? session.beginUnix;
  final endUnix = summary?.wakeupUnix ?? session.endUnix;
  if (startUnix <= 0 || endUnix <= startUnix) return null;
  final mid = startUnix + ((endUnix - startUnix) ~/ 2);
  return _localFromUnix(mid);
}

/// Main overnights ending within the last [dayCount] local calendar days.
List<SleepSessionSummary> recentOvernightSessions(
  List<SleepSessionSummary> sessions, {
  DateTime? now,
  int dayCount = 7,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final oldest = today.subtract(Duration(days: dayCount - 1));
  final coalesced = SleepDay.coalesceNocturnalSessions(sessions);
  final out = <SleepSessionSummary>[];
  for (final s in coalesced) {
    if (!SleepDay.isMainNightSleep(s)) continue;
    if (s.beginUnix <= 0 || s.endUnix <= s.beginUnix) continue;
    final end = _localFromUnix(s.endUnix);
    final endDay = DateTime(end.year, end.month, end.day);
    if (endDay.isBefore(oldest) || endDay.isAfter(today)) continue;
    out.add(s);
  }
  out.sort((a, b) => a.endUnix.compareTo(b.endUnix));
  return out;
}

/// Mean of non-null scores; null if fewer than 2 values.
double? meanOf(Iterable<int> values) {
  final list = values.toList();
  if (list.length < 2) return null;
  return list.fold<int>(0, (a, b) => a + b) / list.length;
}

/// Sample SD; null if fewer than 2 values.
double? stdDevOf(Iterable<int> values) {
  final list = values.toList();
  if (list.length < 2) return null;
  final mean = list.fold<int>(0, (a, b) => a + b) / list.length;
  var sumSq = 0.0;
  for (final v in list) {
    final d = v - mean;
    sumSq += d * d;
  }
  return math.sqrt(sumSq / (list.length - 1));
}

class SleepTrendPoint {
  const SleepTrendPoint({
    required this.endUnix,
    this.score,
    this.hrv,
  });

  final int endUnix;
  final int? score;
  final int? hrv;
}

class SleepTrendBand {
  const SleepTrendBand({
    required this.points,
    this.scoreMean,
    this.scoreHalfSd,
    this.hrvMean,
    this.hrvHalfSd,
  });

  final List<SleepTrendPoint> points;
  final double? scoreMean;
  final double? scoreHalfSd;
  final double? hrvMean;
  final double? hrvHalfSd;

  int? get latestScore {
    for (var i = points.length - 1; i >= 0; i--) {
      final s = points[i].score;
      if (s != null && s > 0) return s;
    }
    return null;
  }

  int? get latestHrv {
    for (var i = points.length - 1; i >= 0; i--) {
      final h = points[i].hrv;
      if (h != null) return h;
    }
    return null;
  }
}

SleepTrendBand buildSleepTrendBand(List<SleepTrendPoint> points) {
  final scores = [
    for (final p in points)
      if (p.score != null && p.score! > 0) p.score!,
  ];
  final hrvs = [
    for (final p in points)
      if (p.hrv != null) p.hrv!,
  ];
  final scoreMean = meanOf(scores);
  final hrvMean = meanOf(hrvs);
  final scoreSd = stdDevOf(scores);
  final hrvSd = stdDevOf(hrvs);
  return SleepTrendBand(
    points: points,
    scoreMean: scoreMean,
    scoreHalfSd: scoreSd == null ? null : scoreSd * 0.5,
    hrvMean: hrvMean,
    hrvHalfSd: hrvSd == null ? null : hrvSd * 0.5,
  );
}

/// One column in the Oura-style vertical timing chart.
class SleepTimingDay {
  const SleepTimingDay({
    required this.endDay,
    required this.bedUnix,
    required this.asleepUnix,
    required this.wakeUnix,
    required this.riseUnix,
    this.isToday = false,
  });

  final DateTime endDay;
  final int bedUnix;
  final int asleepUnix;
  final int wakeUnix;
  final int riseUnix;
  final bool isToday;

  bool get hasData => asleepUnix > 0 && wakeUnix > asleepUnix;

  /// Axis is local midnight→noon of [endDay] (0..12h). Late bedtimes map well.
  double get bedFrac => _fracOnEndDay(bedUnix);
  double get asleepFrac => _fracOnEndDay(asleepUnix);
  double get wakeFrac => _fracOnEndDay(wakeUnix);
  double get riseFrac => _fracOnEndDay(riseUnix);

  double _fracOnEndDay(int unix) {
    if (unix <= 0) return 0;
    final t = _localFromUnix(unix);
    final midnight = DateTime(endDay.year, endDay.month, endDay.day);
    final hours = t.difference(midnight).inSeconds / 3600.0;
    // Clamp to 0..12 display window; overnight start before midnight → 0.
    if (hours < 0) return 0;
    if (hours > 12) return 1;
    return hours / 12.0;
  }
}

List<SleepTimingDay> buildSleepTimingDays({
  required List<SleepSessionSummary> overnights,
  required Map<String, TruSleepSequenceSession?> summaries,
  DateTime? now,
  int dayCount = 7,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final byEndDay = <DateTime, SleepSessionSummary>{};
  for (final s in overnights) {
    final end = _localFromUnix(s.endUnix);
    final endDay = DateTime(end.year, end.month, end.day);
    final prior = byEndDay[endDay];
    if (prior == null || s.durationSec > prior.durationSec) {
      byEndDay[endDay] = s;
    }
  }

  final days = <SleepTimingDay>[];
  for (var i = dayCount - 1; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    final s = byEndDay[day];
    if (s == null) {
      days.add(SleepTimingDay(
        endDay: day,
        bedUnix: 0,
        asleepUnix: 0,
        wakeUnix: 0,
        riseUnix: 0,
        isToday: day == today,
      ));
      continue;
    }
    final sum = summaries[s.mergeKey];
    days.add(SleepTimingDay(
      endDay: day,
      bedUnix: sum?.bedTimeUnix ?? s.beginUnix,
      asleepUnix: sum?.fallAsleepUnix ?? s.beginUnix,
      wakeUnix: sum?.wakeupUnix ?? s.endUnix,
      riseUnix: sum?.risingUnix ?? s.endUnix,
      isToday: day == today,
    ));
  }
  return days;
}

class SleepStageMinutes {
  const SleepStageMinutes({
    this.light = 0,
    this.deep = 0,
    this.rem = 0,
    this.awake = 0,
  });

  final int light;
  final int deep;
  final int rem;
  final int awake;

  int get totalAsleep => light + deep + rem;
  int get total => light + deep + rem + awake;

  double? share(int mins) => total <= 0 ? null : mins / total;
}

SleepStageMinutes stageMinutesOf(List<SleepStageSummary> stages) {
  var light = 0, deep = 0, rem = 0, awake = 0;
  for (final s in stages) {
    switch (s.wireType) {
      case 1:
        light += s.durationMin;
      case 2:
        deep += s.durationMin;
      case 3:
        rem += s.durationMin;
      case 4 || 7:
        awake += s.durationMin;
      default:
        break;
    }
  }
  return SleepStageMinutes(light: light, deep: deep, rem: rem, awake: awake);
}

/// Rough architecture: deep-heavy first half, REM-heavy second half.
String? sleepArchitectureNote(List<SleepStageSummary> stages) {
  if (stages.length < 3) return null;
  final total = stages.fold<int>(0, (a, s) => a + s.durationMin);
  if (total < 60) return null;
  var deepEarly = 0, deepLate = 0, remEarly = 0, remLate = 0;
  var cursor = 0;
  final mid = total / 2;
  for (final s in stages) {
    final inEarly = cursor + s.durationMin / 2 < mid;
    switch (s.wireType) {
      case 2:
        if (inEarly) {
          deepEarly += s.durationMin;
        } else {
          deepLate += s.durationMin;
        }
      case 3:
        if (inEarly) {
          remEarly += s.durationMin;
        } else {
          remLate += s.durationMin;
        }
      default:
        break;
    }
    cursor += s.durationMin;
  }
  final deepOk = deepEarly >= deepLate;
  final remOk = remLate >= remEarly;
  if (deepOk && remOk) {
    return 'Deep early · REM late — matches expected overnight rhythm.';
  }
  if (!deepOk && !remOk) {
    return 'Architecture flipped vs typical deep-early / REM-late pattern.';
  }
  if (!deepOk) {
    return 'Deep weighted later than usual; REM timing looks typical.';
  }
  return 'REM weighted earlier than usual; deep timing looks typical.';
}
