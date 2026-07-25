import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/offline_swim_reasoner.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

void main() {
  test('offline reasoner prioritizes fatigue over meta probe notes', () {
    const report = SwimDiagnosisReport(
      sessionDiagnoses: [
        SwimDiagnosis(
          id: 'fatigue_onset',
          title: 'Fatigue',
          summary: 'decay',
          confidence: SwimConfidence.high,
          metricIds: ['paceDecayPct'],
          evidence: 'x',
        ),
        SwimDiagnosis(
          id: 'length_semantics_open',
          title: 'Length open',
          summary: 'partial',
          confidence: SwimConfidence.low,
          metricIds: ['lapCount'],
          evidence: 'y',
        ),
      ],
      trendDiagnoses: [
        SwimDiagnosis(
          id: 'trends_need_sessions',
          title: 'Need sessions',
          summary: 'n=1',
          confidence: SwimConfidence.low,
          metricIds: ['sessionCount'],
          evidence: 'z',
        ),
      ],
      trends: SwimTrends(points: [], sessionCount: 1),
    );

    final recs = recommendationsForReport(report);
    final result = reasonOffline(report: report, recommendations: recs);
    expect(result.ok, isTrue);
    expect(result.source, 'offline');
    expect(result.orderedRecIds, isNotEmpty);
    expect(result.orderedRecIds.first, isNot(equals('log_another_session')));
    expect(
      {'shorter_sets', 'technique_before_volume'}
          .intersection(result.orderedRecIds.toSet()),
      isNotEmpty,
    );
  });
}
