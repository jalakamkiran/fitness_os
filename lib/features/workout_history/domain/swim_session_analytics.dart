import 'dart:math' as math;

import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';

/// Session-level swim analytics (W2). Interval-first — not proven lengths.
enum SwimConfidence { high, med, low }

class SwimAnalyticsClaim {
  const SwimAnalyticsClaim({
    required this.id,
    required this.title,
    required this.summary,
    required this.confidence,
    required this.evidence,
  });

  final String id;
  final String title;
  final String summary;
  final SwimConfidence confidence;
  final String evidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'confidence': confidence.name,
        'evidence': evidence,
      };
}

class SwimIntervalEfficiency {
  const SwimIntervalEfficiency({
    required this.index,
    this.swolf,
    this.strokesPer25m,
    this.paceSecPer100m,
  });

  final int index;
  final int? swolf;
  final double? strokesPer25m;
  final int? paceSecPer100m;
}

class SwimSessionAnalytics {
  const SwimSessionAnalytics({
    required this.claims,
    required this.intervalEfficiencies,
    this.paceDecayPct,
    this.paceCvPct,
    this.swolfDelta,
    this.showHrPhysiology = false,
  });

  final List<SwimAnalyticsClaim> claims;
  final List<SwimIntervalEfficiency> intervalEfficiencies;

  /// Second-half mean pace vs first-half; positive = slowed (%).
  final double? paceDecayPct;

  /// Coefficient of variation of interval pace (%).
  final double? paceCvPct;

  /// Last SWOLF − first SWOLF (positive = worse).
  final int? swolfDelta;

  /// True only when in-workout samples exist.
  final bool showHrPhysiology;
}

/// Build W2 analytics from P0 metrics. Returns null if fewer than 2 paced intervals.
SwimSessionAnalytics? analyzeSwimSession(SwimP0Metrics p0) {
  final paced = p0.laps
      .where((l) => l.paceSecPer100m != null && l.paceSecPer100m! > 0)
      .toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  if (paced.length < 2) return null;

  final paces = paced.map((l) => l.paceSecPer100m!.toDouble()).toList();
  final decay = _halfDecayPct(paces);
  final cv = _cvPct(paces);

  final swolfLaps = p0.laps
      .where((l) => l.swolf != null && l.swolf! > 0)
      .toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final swolfDelta = swolfLaps.length >= 2
      ? swolfLaps.last.swolf! - swolfLaps.first.swolf!
      : null;

  final efficiencies = p0.laps.map((l) {
    double? per25;
    if (l.strokes != null && l.distanceM != null && l.distanceM! > 0) {
      per25 = l.strokes! * 25.0 / l.distanceM!;
    }
    return SwimIntervalEfficiency(
      index: l.index,
      swolf: l.swolf,
      strokesPer25m: per25,
      paceSecPer100m: l.paceSecPer100m,
    );
  }).toList();

  final baseConf = _baseConfidence(p0, paced.length);
  final claims = <SwimAnalyticsClaim>[
    _paceDecayClaim(decay, baseConf, paced.length),
    _consistencyClaim(cv, baseConf, paced.length),
  ];
  if (swolfDelta != null) {
    claims.add(_swolfTrendClaim(swolfDelta, baseConf, swolfLaps.length));
  }
  if (p0.lengthCoveragePartial) {
    claims.add(
      SwimAnalyticsClaim(
        id: 'length_coverage',
        title: 'Interval vs length count',
        summary:
            'Parsed ${p0.lapCount} intervals vs ${p0.reportedLaps} watch lengths — '
            'treat rows as intervals until a controlled probe confirms.',
        confidence: SwimConfidence.low,
        evidence: 'lengthCoveragePartial · lapCount · reportedLaps',
      ),
    );
  }

  final showHr = p0.hrCoverage == SwimHrCoverage.present;
  if (showHr) {
    claims.add(
      const SwimAnalyticsClaim(
        id: 'hr_samples',
        title: 'In-workout HR',
        summary: 'Sample stream present — zone/drift charts deferred to a later cut.',
        confidence: SwimConfidence.med,
        evidence: 'hrCoverage=present · sampleCount',
      ),
    );
  }

  return SwimSessionAnalytics(
    claims: claims,
    intervalEfficiencies: efficiencies,
    paceDecayPct: decay,
    paceCvPct: cv,
    swolfDelta: swolfDelta,
    showHrPhysiology: showHr,
  );
}

SwimConfidence _baseConfidence(SwimP0Metrics p0, int pacedCount) {
  if (p0.lengthCoveragePartial) return SwimConfidence.med;
  if (pacedCount >= 6 && !p0.lengthCoveragePartial) return SwimConfidence.high;
  if (pacedCount >= 4) return SwimConfidence.med;
  return SwimConfidence.low;
}

SwimAnalyticsClaim _paceDecayClaim(
  double? decayPct,
  SwimConfidence base,
  int n,
) {
  if (decayPct == null) {
    return SwimAnalyticsClaim(
      id: 'pace_decay',
      title: 'Pace decay',
      summary: 'Not enough interval halves to compare.',
      confidence: SwimConfidence.low,
      evidence: 'pacedIntervals=$n',
    );
  }
  final conf = n < 4 ? SwimConfidence.low : base;
  String summary;
  if (decayPct > 8) {
    summary =
        'Second half ~${decayPct.toStringAsFixed(0)}% slower than first — '
        'pace decay across intervals.';
  } else if (decayPct < -8) {
    summary =
        'Second half ~${(-decayPct).toStringAsFixed(0)}% faster — '
        'negative split across intervals.';
  } else {
    summary =
        'Pace held within ~${decayPct.abs().toStringAsFixed(0)}% first→second half.';
  }
  return SwimAnalyticsClaim(
    id: 'pace_decay',
    title: 'Pace decay',
    summary: summary,
    confidence: conf,
    evidence: 'firstHalfMeanPace vs secondHalfMeanPace · n=$n',
  );
}

SwimAnalyticsClaim _consistencyClaim(
  double? cvPct,
  SwimConfidence base,
  int n,
) {
  if (cvPct == null) {
    return const SwimAnalyticsClaim(
      id: 'pace_consistency',
      title: 'Pace consistency',
      summary: 'No interval paces to score.',
      confidence: SwimConfidence.low,
      evidence: 'pacedIntervals=0',
    );
  }
  final conf = n < 4 ? SwimConfidence.low : base;
  String summary;
  if (cvPct < 10) {
    summary = 'Tight pacing (CV ${cvPct.toStringAsFixed(0)}%).';
  } else if (cvPct < 20) {
    summary = 'Moderate pace scatter (CV ${cvPct.toStringAsFixed(0)}%).';
  } else {
    summary = 'Wide pace scatter (CV ${cvPct.toStringAsFixed(0)}%) — uneven intervals.';
  }
  return SwimAnalyticsClaim(
    id: 'pace_consistency',
    title: 'Pace consistency',
    summary: summary,
    confidence: conf,
    evidence: 'pace CV% · n=$n',
  );
}

SwimAnalyticsClaim _swolfTrendClaim(
  int delta,
  SwimConfidence base,
  int n,
) {
  final conf = n < 4 ? SwimConfidence.low : base;
  String summary;
  if (delta > 10) {
    summary = 'SWOLF rose by $delta first→last interval (efficiency worsened).';
  } else if (delta < -10) {
    summary = 'SWOLF fell by ${-delta} first→last interval (efficiency improved).';
  } else {
    summary = 'SWOLF roughly flat first→last (Δ $delta).';
  }
  return SwimAnalyticsClaim(
    id: 'swolf_trend',
    title: 'SWOLF trend',
    summary: summary,
    confidence: conf,
    evidence: 'firstSwolf vs lastSwolf · n=$n',
  );
}

double? _halfDecayPct(List<double> paces) {
  if (paces.length < 2) return null;
  final mid = paces.length ~/ 2;
  if (mid == 0 || mid >= paces.length) return null;
  final first = _mean(paces.sublist(0, mid));
  final second = _mean(paces.sublist(mid));
  if (first <= 0) return null;
  return ((second - first) / first) * 100.0;
}

double? _cvPct(List<double> values) {
  if (values.length < 2) return null;
  final m = _mean(values);
  if (m <= 0) return null;
  var sumSq = 0.0;
  for (final v in values) {
    final d = v - m;
    sumSq += d * d;
  }
  final variance = sumSq / values.length;
  final sigma = math.sqrt(variance);
  return (sigma / m) * 100.0;
}

double _mean(List<double> values) {
  var s = 0.0;
  for (final v in values) {
    s += v;
  }
  return s / values.length;
}
