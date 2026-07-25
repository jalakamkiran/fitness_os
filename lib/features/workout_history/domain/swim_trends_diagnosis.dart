import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';

/// Multi-session swim trends (W3).
class SwimTrendPoint {
  const SwimTrendPoint({
    required this.workoutNumber,
    required this.startTime,
    this.distanceM,
    this.movingPaceSecPer100m,
    this.avgSwolf,
    this.intervalCount,
  });

  final int workoutNumber;
  final int startTime;
  final int? distanceM;
  final int? movingPaceSecPer100m;
  final int? avgSwolf;
  final int? intervalCount;
}

class SwimTrends {
  const SwimTrends({
    required this.points,
    required this.sessionCount,
    this.totalDistanceM,
    this.totalMovingSec,
    this.paceDeltaPct,
    this.swolfDelta,
    this.volumeVsPriorPct,
  });

  final List<SwimTrendPoint> points;
  final int sessionCount;
  final int? totalDistanceM;
  final int? totalMovingSec;

  /// Latest moving pace vs earliest (positive = slower).
  final double? paceDeltaPct;

  /// Latest avg SWOLF − earliest (positive = worse).
  final int? swolfDelta;

  /// Latest session distance vs previous (positive = more volume).
  final double? volumeVsPriorPct;

  bool get hasMultiSession => sessionCount >= 2;
}

/// Deterministic diagnosis (Evidence → Diagnosis). Never invents metrics.
class SwimDiagnosis {
  const SwimDiagnosis({
    required this.id,
    required this.title,
    required this.summary,
    required this.confidence,
    required this.metricIds,
    required this.evidence,
  });

  final String id;
  final String title;
  final String summary;
  final SwimConfidence confidence;
  final List<String> metricIds;
  final String evidence;
}

class SwimDiagnosisReport {
  const SwimDiagnosisReport({
    required this.sessionDiagnoses,
    required this.trendDiagnoses,
    required this.trends,
  });

  final List<SwimDiagnosis> sessionDiagnoses;
  final List<SwimDiagnosis> trendDiagnoses;
  final SwimTrends trends;
}

SwimTrends buildSwimTrends(List<CanonicalSwimSession> sessions) {
  final ordered = [...sessions]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final points = ordered
      .map(
        (s) => SwimTrendPoint(
          workoutNumber: s.workoutNumber,
          startTime: s.startTime,
          distanceM: s.distanceM,
          movingPaceSecPer100m: s.p0.movingAvgPaceSecPer100m,
          avgSwolf: s.p0.avgSwolf,
          intervalCount: s.p0.lapCount,
        ),
      )
      .toList();

  var totalDist = 0;
  var totalMoving = 0;
  var hasDist = false;
  var hasMoving = false;
  for (final s in ordered) {
    if (s.distanceM != null && s.distanceM! > 0) {
      totalDist += s.distanceM!;
      hasDist = true;
    }
    final moving = _movingSec(s.p0);
    if (moving != null) {
      totalMoving += moving;
      hasMoving = true;
    }
  }

  double? paceDelta;
  final paced = points.where((p) => p.movingPaceSecPer100m != null).toList();
  if (paced.length >= 2) {
    final first = paced.first.movingPaceSecPer100m!.toDouble();
    final last = paced.last.movingPaceSecPer100m!.toDouble();
    if (first > 0) paceDelta = ((last - first) / first) * 100.0;
  }

  int? swolfDelta;
  final swolfed = points.where((p) => p.avgSwolf != null).toList();
  if (swolfed.length >= 2) {
    swolfDelta = swolfed.last.avgSwolf! - swolfed.first.avgSwolf!;
  }

  double? volumeDelta;
  final vol = points.where((p) => p.distanceM != null && p.distanceM! > 0).toList();
  if (vol.length >= 2) {
    final prev = vol[vol.length - 2].distanceM!.toDouble();
    final last = vol.last.distanceM!.toDouble();
    if (prev > 0) volumeDelta = ((last - prev) / prev) * 100.0;
  }

  return SwimTrends(
    points: points,
    sessionCount: ordered.length,
    totalDistanceM: hasDist ? totalDist : null,
    totalMovingSec: hasMoving ? totalMoving : null,
    paceDeltaPct: paceDelta,
    swolfDelta: swolfDelta,
    volumeVsPriorPct: volumeDelta,
  );
}

/// Session + trend diagnoses for [focus] (defaults to latest session).
SwimDiagnosisReport diagnoseSwimSessions(
  List<CanonicalSwimSession> sessions, {
  int? focusWorkoutNumber,
}) {
  final trends = buildSwimTrends(sessions);
  if (sessions.isEmpty) {
    return SwimDiagnosisReport(
      sessionDiagnoses: const [],
      trendDiagnoses: const [],
      trends: trends,
    );
  }

  final ordered = [...sessions]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final focus = focusWorkoutNumber == null
      ? ordered.last
      : ordered.firstWhere(
          (s) => s.workoutNumber == focusWorkoutNumber,
          orElse: () => ordered.last,
        );

  final analytics = analyzeSwimSession(focus.p0);
  final sessionDx = _sessionDiagnoses(focus, analytics);
  final trendDx = _trendDiagnoses(trends);

  return SwimDiagnosisReport(
    sessionDiagnoses: sessionDx,
    trendDiagnoses: trendDx,
    trends: trends,
  );
}

List<SwimDiagnosis> _sessionDiagnoses(
  CanonicalSwimSession session,
  SwimSessionAnalytics? analytics,
) {
  final out = <SwimDiagnosis>[];
  if (analytics == null) {
    out.add(
      const SwimDiagnosis(
        id: 'insufficient_intervals',
        title: 'Insufficient interval evidence',
        summary: 'Need at least two paced intervals for session diagnoses.',
        confidence: SwimConfidence.low,
        metricIds: ['pacedIntervals'],
        evidence: 'analyzeSwimSession → null',
      ),
    );
    return out;
  }

  final decay = analytics.paceDecayPct;
  final cv = analytics.paceCvPct;
  final swolfDelta = analytics.swolfDelta;
  final conf = _sessionConf(session.p0, analytics);

  // Fatigue onset — matches owner #11 felt experience pattern.
  if (decay != null && decay > 15) {
    out.add(
      SwimDiagnosis(
        id: 'fatigue_onset',
        title: 'Fatigue onset',
        summary:
            'Second-half pace ~${decay.toStringAsFixed(0)}% slower — '
            'fatigue / form break across intervals is likely.',
        confidence: conf,
        metricIds: ['paceDecayPct', 'paceSecPer100m'],
        evidence: 'paceDecayPct=${decay.toStringAsFixed(1)}',
      ),
    );
  } else if (_lateSwolfSpike(session.p0)) {
    out.add(
      SwimDiagnosis(
        id: 'fatigue_onset',
        title: 'Fatigue onset',
        summary:
            'Late-interval SWOLF spike vs early intervals — efficiency broke down late.',
        confidence: conf,
        metricIds: ['swolf', 'intervalEfficiencies'],
        evidence: 'lateSwolfSpike',
      ),
    );
  }

  if (cv != null && cv > 20) {
    out.add(
      SwimDiagnosis(
        id: 'pacing_uneven',
        title: 'Uneven pacing',
        summary:
            'Pace CV ${cv.toStringAsFixed(0)}% — intervals were inconsistent '
            '(rest, stroke changes, or fatigue).',
        confidence: conf,
        metricIds: ['paceCvPct'],
        evidence: 'paceCvPct=${cv.toStringAsFixed(1)}',
      ),
    );
  } else if (cv != null && cv < 10 && (decay == null || decay.abs() < 8)) {
    out.add(
      SwimDiagnosis(
        id: 'pacing_steady',
        title: 'Steady pacing',
        summary: 'Tight pace control (CV ${cv.toStringAsFixed(0)}%, little decay).',
        confidence: conf,
        metricIds: ['paceCvPct', 'paceDecayPct'],
        evidence: 'paceCvPct=${cv.toStringAsFixed(1)}',
      ),
    );
  }

  if (swolfDelta != null && swolfDelta > 10) {
    out.add(
      SwimDiagnosis(
        id: 'efficiency_decline',
        title: 'Efficiency decline',
        summary:
            'SWOLF rose by $swolfDelta first→last interval — stroke efficiency worsened.',
        confidence: conf,
        metricIds: ['swolfDelta', 'avgSwolf'],
        evidence: 'swolfDelta=$swolfDelta',
      ),
    );
  } else if (swolfDelta != null && swolfDelta < -10) {
    out.add(
      SwimDiagnosis(
        id: 'efficiency_improve',
        title: 'Efficiency improvement',
        summary:
            'SWOLF fell by ${-swolfDelta} first→last — efficiency improved through the set.',
        confidence: conf,
        metricIds: ['swolfDelta', 'avgSwolf'],
        evidence: 'swolfDelta=$swolfDelta',
      ),
    );
  }

  if (session.p0.lengthCoveragePartial) {
    out.add(
      SwimDiagnosis(
        id: 'length_semantics_open',
        title: 'Length semantics open',
        summary:
            'Parsed ${session.p0.lapCount} intervals vs ${session.p0.reportedLaps} '
            'watch lengths — diagnoses use intervals until probe confirms.',
        confidence: SwimConfidence.low,
        metricIds: ['lapCount', 'reportedLaps', 'lengthCoveragePartial'],
        evidence: 'lengthCoveragePartial=true',
      ),
    );
  }

  if (out.isEmpty) {
    out.add(
      SwimDiagnosis(
        id: 'no_strong_signal',
        title: 'No strong session signal',
        summary: 'Pace/SWOLF stayed within normal bands for this interval set.',
        confidence: SwimConfidence.med,
        metricIds: ['paceDecayPct', 'paceCvPct', 'swolfDelta'],
        evidence: 'no rule fired',
      ),
    );
  }

  return out;
}

List<SwimDiagnosis> _trendDiagnoses(SwimTrends trends) {
  if (!trends.hasMultiSession) {
    return [
      SwimDiagnosis(
        id: 'trends_need_sessions',
        title: 'Trends need more sessions',
        summary:
            trends.sessionCount == 0
                ? 'No canonical swims stored yet — Sync a pool swim first.'
                : 'Only ${trends.sessionCount} swim session — need ≥2 for pace/SWOLF/volume trends.',
        confidence: SwimConfidence.low,
        metricIds: ['sessionCount'],
        evidence: 'sessionCount=${trends.sessionCount}',
      ),
    ];
  }

  final out = <SwimDiagnosis>[];
  final conf = trends.sessionCount >= 4 ? SwimConfidence.high : SwimConfidence.med;

  if (trends.paceDeltaPct != null && trends.paceDeltaPct! > 8) {
    out.add(
      SwimDiagnosis(
        id: 'trend_pace_slower',
        title: 'Pace trending slower',
        summary:
            'Moving pace ${trends.paceDeltaPct!.toStringAsFixed(0)}% slower '
            'latest vs earliest swim.',
        confidence: conf,
        metricIds: ['movingAvgPaceSecPer100m', 'paceDeltaPct'],
        evidence: 'paceDeltaPct=${trends.paceDeltaPct!.toStringAsFixed(1)}',
      ),
    );
  } else if (trends.paceDeltaPct != null && trends.paceDeltaPct! < -8) {
    out.add(
      SwimDiagnosis(
        id: 'trend_pace_faster',
        title: 'Pace trending faster',
        summary:
            'Moving pace ${(-trends.paceDeltaPct!).toStringAsFixed(0)}% faster '
            'latest vs earliest swim.',
        confidence: conf,
        metricIds: ['movingAvgPaceSecPer100m', 'paceDeltaPct'],
        evidence: 'paceDeltaPct=${trends.paceDeltaPct!.toStringAsFixed(1)}',
      ),
    );
  }

  if (trends.swolfDelta != null && trends.swolfDelta! > 8) {
    out.add(
      SwimDiagnosis(
        id: 'trend_swolf_worse',
        title: 'SWOLF trending worse',
        summary: 'Avg SWOLF up ${trends.swolfDelta} across sessions.',
        confidence: conf,
        metricIds: ['avgSwolf', 'swolfDelta'],
        evidence: 'trendSwolfDelta=${trends.swolfDelta}',
      ),
    );
  } else if (trends.swolfDelta != null && trends.swolfDelta! < -8) {
    out.add(
      SwimDiagnosis(
        id: 'trend_swolf_better',
        title: 'SWOLF trending better',
        summary: 'Avg SWOLF down ${-trends.swolfDelta!} across sessions.',
        confidence: conf,
        metricIds: ['avgSwolf', 'swolfDelta'],
        evidence: 'trendSwolfDelta=${trends.swolfDelta}',
      ),
    );
  }

  if (trends.volumeVsPriorPct != null && trends.volumeVsPriorPct!.abs() > 15) {
    final up = trends.volumeVsPriorPct! > 0;
    out.add(
      SwimDiagnosis(
        id: up ? 'trend_volume_up' : 'trend_volume_down',
        title: up ? 'Volume up vs prior' : 'Volume down vs prior',
        summary:
            'Latest distance ${up ? '+' : ''}${trends.volumeVsPriorPct!.toStringAsFixed(0)}% '
            'vs previous swim.',
        confidence: conf,
        metricIds: ['distanceM', 'volumeVsPriorPct'],
        evidence: 'volumeVsPriorPct=${trends.volumeVsPriorPct!.toStringAsFixed(1)}',
      ),
    );
  }

  if (out.isEmpty) {
    out.add(
      SwimDiagnosis(
        id: 'trends_stable',
        title: 'Trends roughly stable',
        summary:
            '${trends.sessionCount} swims · '
            '${trends.totalDistanceM ?? 0} m total volume — no strong trend shift.',
        confidence: conf,
        metricIds: ['sessionCount', 'totalDistanceM', 'paceDeltaPct', 'swolfDelta'],
        evidence: 'no trend rule fired',
      ),
    );
  }

  return out;
}

SwimConfidence _sessionConf(SwimP0Metrics p0, SwimSessionAnalytics analytics) {
  if (p0.lengthCoveragePartial) return SwimConfidence.med;
  final n = analytics.intervalEfficiencies.length;
  if (n >= 6) return SwimConfidence.high;
  if (n >= 4) return SwimConfidence.med;
  return SwimConfidence.low;
}

bool _lateSwolfSpike(SwimP0Metrics p0) {
  final withSwolf = p0.laps.where((l) => l.swolf != null && l.swolf! > 0).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  if (withSwolf.length < 3) return false;
  final early = withSwolf.take(withSwolf.length ~/ 2).map((l) => l.swolf!).toList();
  final late = withSwolf.skip(withSwolf.length ~/ 2).map((l) => l.swolf!).toList();
  if (early.isEmpty || late.isEmpty) return false;
  final earlyMean = early.reduce((a, b) => a + b) / early.length;
  final lateMax = late.reduce((a, b) => a > b ? a : b);
  return lateMax > earlyMean * 1.8 && lateMax - earlyMean > 40;
}

int? _movingSec(SwimP0Metrics p0) {
  var sum = 0;
  var any = false;
  for (final l in p0.laps) {
    if (l.durationSec != null && l.durationSec! > 0) {
      sum += l.durationSec!;
      any = true;
    }
  }
  return any ? sum : null;
}
