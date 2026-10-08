import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_invent_guard.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_insight.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

void main() {
  group('buildSwimSessionInsight', () {
    test('happy path: fatigue tip wins; story diagnosis matches tip source', () {
      final focus = _poolSession(
        number: 94,
        start: 1000,
        laps: _fadeLaps(16),
        poolM: 25,
        distanceM: 400,
        durationSec: 1180,
      );
      final prior = _poolSession(
        number: 90,
        start: 500,
        laps: _steadyLaps(12),
        poolM: 25,
        distanceM: 300,
        durationSec: 900,
      );
      final guarded = filterSwimLapsForAnalytics(
        focus.p0.laps,
        poolLengthM: focus.poolLengthM,
      );
      final report = diagnoseSwimSessions(
        [prior, focus],
        focusWorkoutNumber: 94,
      );

      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: guarded,
        sessionDiagnoses: report.sessionDiagnoses,
        recentHistory: [prior, focus],
        lockedHr: const SwimLockedHrKpis(avgBpm: 142, maxBpm: 168),
      );

      expect(insight.story, isNotEmpty);
      expect(insight.chips, isNotEmpty);
      expect(insight.primaryTip, isNotNull);
      expect(insight.primaryTip!.sourceDiagnosisId, insight.storyDiagnosisId);
      expect(insight.kpis.distanceM, isNotNull);
      expect(insight.kpis.avgHr, 142);
      expect(insight.kpis.maxHr, 168);
      // Athlete path: no bible / metric-id footers in tip copy.
      expect(insight.primaryTip!.why.toLowerCase(), isNot(contains('ch.')));
      expect(insight.primaryTip!.why.toLowerCase(), isNot(contains('metricids')));
    });

    test('archetype: fatigue_onset wins tip over efficiency_decline', () {
      final diagnoses = [
        const SwimDiagnosis(
          id: 'efficiency_decline',
          title: 'Efficiency decline',
          summary: 'swolf up',
          confidence: SwimConfidence.med,
          metricIds: ['swolfDelta'],
          evidence: 'x',
        ),
        const SwimDiagnosis(
          id: 'fatigue_onset',
          title: 'Fatigue onset',
          summary: 'decay',
          confidence: SwimConfidence.med,
          metricIds: ['paceDecayPct'],
          evidence: 'y',
        ),
        const SwimDiagnosis(
          id: 'pacing_uneven',
          title: 'Uneven',
          summary: 'cv',
          confidence: SwimConfidence.low,
          metricIds: ['paceCvPct'],
          evidence: 'z',
        ),
      ];
      final focus = _poolSession(
        number: 1,
        start: 1,
        laps: _fadeLaps(10),
        poolM: 25,
        distanceM: 250,
        durationSec: 600,
      );
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: diagnoses,
        recentHistory: const [],
      );
      expect(insight.storyDiagnosisId, 'fatigue_onset');
      expect(insight.primaryTip!.sourceDiagnosisId, 'fatigue_onset');
      expect(insight.primaryTip!.recId, 'shorter_sets');
      expect(insight.secondaryFindings.map((f) => f.diagnosisId), contains('efficiency_decline'));
      expect(insight.secondaryFindings.map((f) => f.diagnosisId), contains('pacing_uneven'));
    });

    test('coverage-only diagnoses → tip null + escape story; KPIs still present', () {
      final focus = _poolSession(
        number: 2,
        start: 1,
        laps: _steadyLaps(3),
        poolM: 25,
        distanceM: 75,
        durationSec: 210,
      );
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: const [
          SwimDiagnosis(
            id: 'insufficient_intervals',
            title: 'Insufficient',
            summary: 'need more',
            confidence: SwimConfidence.low,
            metricIds: ['pacedIntervals'],
            evidence: 'x',
          ),
        ],
        recentHistory: const [],
      );
      expect(insight.primaryTip, isNull);
      expect(insight.story.toLowerCase(), contains('not enough'));
      expect(insight.kpis.distanceM, isNotNull);
      expect(insight.kpis.durationPrimaryLabel, isNotNull);
    });

    test('thin history / missing pool length → chips omitted', () {
      final focus = _poolSession(
        number: 3,
        start: 10,
        laps: _steadyLaps(8),
        poolM: null,
        distanceM: 200,
        durationSec: 500,
      );
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: const [
          SwimDiagnosis(
            id: 'pacing_steady',
            title: 'Steady',
            summary: 'ok',
            confidence: SwimConfidence.med,
            metricIds: ['paceCvPct'],
            evidence: 'x',
          ),
        ],
        recentHistory: const [],
      );
      expect(insight.chips, isEmpty);
    });

    test('focus mid-history chips vs prior comparable; tip not from trend_*', () {
      final early = _poolSession(
        number: 1,
        start: 100,
        laps: _steadyLaps(8),
        poolM: 25,
        distanceM: 200,
        durationSec: 480,
        paceOverride: 90,
      );
      final mid = _poolSession(
        number: 2,
        start: 200,
        laps: _fadeLaps(10),
        poolM: 25,
        distanceM: 250,
        durationSec: 700,
      );
      final late = _poolSession(
        number: 3,
        start: 300,
        laps: _steadyLaps(8),
        poolM: 25,
        distanceM: 200,
        durationSec: 500,
        paceOverride: 85,
      );
      final report = diagnoseSwimSessions(
        [early, mid, late],
        focusWorkoutNumber: 2,
      );
      // Inject a trend diagnosis that must not win the tip.
      final sessionOnly = report.sessionDiagnoses;
      final withTrend = [
        ...sessionOnly,
        const SwimDiagnosis(
          id: 'trend_pace_slower',
          title: 'Pace trending slower',
          summary: 'global',
          confidence: SwimConfidence.high,
          metricIds: ['paceDeltaPct'],
          evidence: 'trend',
        ),
      ];

      final insight = buildSwimSessionInsight(
        focus: mid,
        inventGuardedLaps: filterSwimLapsForAnalytics(
          mid.p0.laps,
          poolLengthM: 25,
        ),
        sessionDiagnoses: withTrend,
        recentHistory: [early, mid, late],
      );

      expect(insight.storyDiagnosisId, isNot(startsWith('trend_')));
      if (insight.primaryTip != null) {
        expect(insight.primaryTip!.sourceDiagnosisId, isNot(startsWith('trend_')));
      }
      // Chips vs prior (early), not earliest→latest global trends.
      expect(insight.chips, isNotEmpty);
    });

    test('movingSec inconsistent with durationSec → duration total-only', () {
      final focus = _poolSession(
        number: 4,
        start: 1,
        laps: _steadyLaps(4),
        poolM: 25,
        distanceM: 100,
        durationSec: 60, // shorter than sum of lap durations
      );
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: const [],
        recentHistory: const [],
      );
      expect(insight.kpis.durationPrimaryLabel, '1:00');
      expect(insight.kpis.durationHint, isNull);
    });

    test('type 8 open-water: omit chips; builder does not throw', () {
      final focus = CanonicalSwimSession(
        workoutNumber: 8,
        startTime: 1,
        endTime: 2,
        durationSec: 1920,
        type: 8,
        distanceM: 1000,
        poolLengthM: null,
        p0: SwimP0Metrics(
          hrCoverage: SwimHrCoverage.absent,
          avgPaceSecPer100m: 100,
          avgSwolf: null,
          laps: List.generate(
            10,
            (i) => SwimLapMetrics(
              index: i,
              distanceM: 100,
              durationSec: 95 + i,
              strokes: 40,
              paceSecPer100m: 95 + i,
            ),
          ),
        ),
      );
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: const [
          SwimDiagnosis(
            id: 'pacing_steady',
            title: 'Steady',
            summary: 'ok',
            confidence: SwimConfidence.med,
            metricIds: ['paceCvPct'],
            evidence: 'x',
          ),
        ],
        recentHistory: const [],
      );
      expect(insight.chips, isEmpty);
      expect(insight.story, isNotEmpty);
    });

    test('HR omitted when lock not passed', () {
      final focus = _poolSession(
        number: 5,
        start: 1,
        laps: _steadyLaps(6),
        poolM: 25,
        distanceM: 150,
        durationSec: 400,
      );
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: const [],
        recentHistory: const [],
      );
      expect(insight.kpis.avgHr, isNull);
      expect(insight.kpis.maxHr, isNull);
    });

    test('banned pipeline vocabulary absent from athlete strings', () {
      final focus = _poolSession(
        number: 6,
        start: 1,
        laps: _fadeLaps(12),
        poolM: 25,
        distanceM: 300,
        durationSec: 800,
      );
      final report = diagnoseSwimSessions([focus], focusWorkoutNumber: 6);
      final insight = buildSwimSessionInsight(
        focus: focus,
        inventGuardedLaps: focus.p0.laps,
        sessionDiagnoses: report.sessionDiagnoses,
        recentHistory: const [],
      );
      final blob = [
        insight.story,
        insight.primaryTip?.title,
        insight.primaryTip?.why,
        ...insight.secondaryFindings.map((f) => '${f.title} ${f.body}'),
      ].whereType<String>().join(' ').toLowerCase();
      for (final banned in [
        'enrichment',
        'sync: ok',
        'type: 6',
        'p0 metrics',
        'evidence →',
        'qwen',
        'reasoner',
        'bible',
        'invent-guard',
      ]) {
        expect(blob.contains(banned), isFalse, reason: 'banned "$banned"');
      }
    });
  });
}

CanonicalSwimSession _poolSession({
  required int number,
  required int start,
  required List<SwimLapMetrics> laps,
  required int? poolM,
  required int distanceM,
  required int durationSec,
  int? paceOverride,
}) {
  final paced = laps
      .map(
        (l) => SwimLapMetrics(
          index: l.index,
          distanceM: l.distanceM,
          durationSec: l.durationSec,
          strokes: l.strokes,
          swolf: l.swolf,
          paceSecPer100m: paceOverride ?? l.paceSecPer100m,
          style: l.style,
        ),
      )
      .toList();
  final p0 = computeSwimP0(
    durationSec: durationSec,
    distanceM: distanceM,
    avgSwolf: 50,
    laps: paced.length,
    poolLengthCm: poolM == null ? null : poolM * 100,
    segmentLaps: paced,
  );
  return CanonicalSwimSession(
    workoutNumber: number,
    startTime: start,
    endTime: start + durationSec,
    durationSec: durationSec,
    type: 6,
    distanceM: distanceM,
    poolLengthM: poolM,
    p0: p0,
  );
}

List<SwimLapMetrics> _fadeLaps(int n) {
  return List.generate(n, (i) {
    final t = n <= 1 ? 0.0 : i / (n - 1);
    final dur = (22 + t * 10).round();
    final strokes = (34 + t * 8).round();
    return SwimLapMetrics(
      index: i,
      distanceM: 25,
      durationSec: dur,
      strokes: strokes,
      swolf: dur + strokes,
      paceSecPer100m: ((dur / 25) * 100).round(),
    );
  });
}

List<SwimLapMetrics> _steadyLaps(int n) {
  return List.generate(n, (i) {
    return SwimLapMetrics(
      index: i,
      distanceM: 25,
      durationSec: 23,
      strokes: 35,
      swolf: 58,
      paceSecPer100m: 92,
    );
  });
}
