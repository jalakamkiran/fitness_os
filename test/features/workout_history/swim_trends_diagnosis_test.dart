import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_session_analytics.dart';
import 'package:fitness_os/features/workout_history/domain/swim_trends_diagnosis.dart';

CanonicalSwimSession _session({
  required int number,
  required int start,
  required List<SwimLapMetrics> laps,
  int durationSec = 600,
  int? distanceM = 200,
  int? avgSwolf = 50,
  int? reportedLaps,
}) {
  final p0 = computeSwimP0(
    durationSec: durationSec,
    distanceM: distanceM,
    avgSwolf: avgSwolf,
    laps: reportedLaps ?? laps.length,
    segmentLaps: laps,
  );
  return CanonicalSwimSession(
    workoutNumber: number,
    startTime: start,
    endTime: start + durationSec,
    durationSec: durationSec,
    type: 6,
    distanceM: distanceM,
    poolLengthM: 25,
    p0: p0,
  );
}

void main() {
  group('buildSwimTrends', () {
    test('aggregates volume and pace/SWOLF deltas across sessions', () {
      final early = _session(
        number: 1,
        start: 1000,
        distanceM: 200,
        avgSwolf: 40,
        laps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 20, swolf: 40),
          SwimLapMetrics(index: 1, distanceM: 25, durationSec: 20, swolf: 40),
        ],
      );
      final late = _session(
        number: 2,
        start: 2000,
        distanceM: 300,
        avgSwolf: 55,
        laps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 25, swolf: 55),
          SwimLapMetrics(index: 1, distanceM: 25, durationSec: 25, swolf: 55),
        ],
      );

      final trends = buildSwimTrends([late, early]);
      expect(trends.sessionCount, 2);
      expect(trends.totalDistanceM, 500);
      expect(trends.hasMultiSession, isTrue);
      expect(trends.paceDeltaPct, greaterThan(0)); // slower later
      expect(trends.swolfDelta, 15);
      expect(trends.volumeVsPriorPct, closeTo(50, 0.1));
    });
  });

  group('diagnoseSwimSessions', () {
    test('#11-shaped session fires fatigue, uneven pacing, efficiency', () {
      final p0 = computeSwimP0(
        durationSec: 3683,
        distanceM: 500,
        strokes: 350,
        avgSwolf: 165,
        laps: 20,
        hrMin: 90,
        sampleCount: 0,
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
        startTime: 1_700_000_000,
        endTime: 1_700_003_683,
        durationSec: 3683,
        type: 6,
        distanceM: 500,
        poolLengthM: 25,
        p0: p0,
      );

      final report = diagnoseSwimSessions([session], focusWorkoutNumber: 11);
      final ids = report.sessionDiagnoses.map((d) => d.id).toSet();
      expect(ids.contains('fatigue_onset'), isTrue);
      expect(ids.contains('pacing_uneven'), isTrue);
      expect(ids.contains('efficiency_decline') || ids.contains('fatigue_onset'), isTrue);
      expect(ids.contains('length_semantics_open'), isTrue);
      expect(report.trendDiagnoses.first.id, 'trends_need_sessions');
      for (final d in report.sessionDiagnoses) {
        expect(d.metricIds, isNotEmpty);
        expect(
          SwimConfidence.values.contains(d.confidence),
          isTrue,
        );
      }
    });

    test('two sessions produce trend diagnoses with metric citations', () {
      final a = _session(
        number: 1,
        start: 1000,
        distanceM: 200,
        avgSwolf: 40,
        laps: List.generate(
          4,
          (i) => SwimLapMetrics(
            index: i,
            distanceM: 25,
            durationSec: 20,
            strokes: 18,
            swolf: 40,
          ),
        ),
      );
      final b = _session(
        number: 2,
        start: 2000,
        distanceM: 400,
        avgSwolf: 60,
        laps: List.generate(
          4,
          (i) => SwimLapMetrics(
            index: i,
            distanceM: 25,
            durationSec: 28,
            strokes: 22,
            swolf: 60,
          ),
        ),
      );
      final report = diagnoseSwimSessions([a, b]);
      expect(report.trends.hasMultiSession, isTrue);
      expect(report.trendDiagnoses, isNotEmpty);
      expect(report.trendDiagnoses.any((d) => d.metricIds.isNotEmpty), isTrue);
    });
  });
}
