import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_recommendations.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

void main() {
  group('recommendationsForDiagnoses', () {
    test('maps fatigue + uneven pacing to allow-listed recs', () {
      const diagnoses = [
        SwimDiagnosis(
          id: 'fatigue_onset',
          title: 'Fatigue onset',
          summary: 'slowed',
          confidence: SwimConfidence.med,
          metricIds: ['paceDecayPct'],
          evidence: 'x',
        ),
        SwimDiagnosis(
          id: 'pacing_uneven',
          title: 'Uneven',
          summary: 'cv',
          confidence: SwimConfidence.med,
          metricIds: ['paceCvPct'],
          evidence: 'y',
        ),
      ];
      final recs = recommendationsForDiagnoses(diagnoses);
      final ids = recs.map((r) => r.id).toSet();
      expect(ids.contains('shorter_sets'), isTrue);
      expect(ids.contains('technique_before_volume'), isTrue);
      expect(ids.contains('even_split_focus'), isTrue);
      expect(ids.contains('invented_drill'), isFalse);
    });

    test('filterCoachOrderedIds drops unknown ids', () {
      final filtered = filterCoachOrderedIds(
        ['shorter_sets', 'hacked_drill', 'even_split_focus', 'shorter_sets'],
        {'shorter_sets', 'even_split_focus'},
      );
      expect(filtered, ['shorter_sets', 'even_split_focus']);
    });

    test('#11-shaped report produces recs with trace fields', () {
      final p0 = computeSwimP0(
        durationSec: 3683,
        distanceM: 500,
        avgSwolf: 165,
        laps: 20,
        segmentLaps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 11, strokes: 124, swolf: 135),
          SwimLapMetrics(index: 1, distanceM: 25, durationSec: 12, strokes: 36, swolf: 48),
          SwimLapMetrics(index: 2, distanceM: 25, durationSec: 11, strokes: 69, swolf: 80),
          SwimLapMetrics(index: 3, distanceM: 25, durationSec: 17, strokes: 71, swolf: 88),
          SwimLapMetrics(index: 4, distanceM: 25, durationSec: 8, strokes: 323, swolf: 331),
          SwimLapMetrics(index: 5, distanceM: 25, durationSec: 22, strokes: 124, swolf: 146),
        ],
      );
      final session = CanonicalSwimSession(
        workoutNumber: 11,
        startTime: 1,
        endTime: 2,
        durationSec: 3683,
        type: 6,
        distanceM: 500,
        p0: p0,
      );
      final report = diagnoseSwimSessions([session], focusWorkoutNumber: 11);
      final recs = recommendationsForReport(report);
      expect(recs, isNotEmpty);
      final payload = buildCoachPromptPayload(
        report: report,
        recommendations: recs,
        workoutNumber: 11,
      );
      expect(payload['allowedRecIds'], isA<List>());
      expect((payload['allowedRecIds'] as List), isNotEmpty);
      for (final r in recs) {
        expect(r.sourceDiagnosisIds, isNotEmpty);
        expect(r.metricIds, isNotEmpty);
      }
    });
  });
}
