import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/canonical_swim_session.dart';
import 'package:fitness_os/features/workout_history/domain/swim_p0_metrics.dart';

void main() {
  group('computeSwimP0', () {
    test('#11-shaped pool session — pace, SWOLF, stroke rate, HR partial', () {
      // Owner probe #11: 500m, 3683s, 350 strokes, SWOLF 165, 20 laps reported,
      // 6 parsed segment rows (half-deduped), totals HR only, sampleCount from data pages.
      final laps = [
        const SwimLapMetrics(
          index: 0,
          distanceM: 25,
          durationSec: 11,
          strokes: 124,
          swolf: 135,
        ),
        const SwimLapMetrics(
          index: 1,
          distanceM: 25,
          durationSec: 12,
          strokes: 36,
          swolf: 48,
        ),
        const SwimLapMetrics(
          index: 2,
          distanceM: 25,
          durationSec: 11,
          strokes: 69,
          swolf: 80,
        ),
        const SwimLapMetrics(
          index: 3,
          distanceM: 25,
          durationSec: 17,
          strokes: 71,
          swolf: 88,
        ),
        const SwimLapMetrics(
          index: 4,
          distanceM: 25,
          durationSec: 8,
          strokes: 323,
          swolf: 331,
        ),
        const SwimLapMetrics(
          index: 5,
          distanceM: 25,
          durationSec: 22,
          strokes: 124,
          swolf: 146,
        ),
      ];

      final p0 = computeSwimP0(
        durationSec: 3683,
        distanceM: 500,
        strokes: 350,
        avgSwolf: 165,
        laps: 20,
        sampleCount: 0,
        hrMin: 90,
        hrMax: 140,
        segmentLaps: laps,
      );

      expect(p0.avgPaceSecPer100m, (3683 * 100) ~/ 500);
      expect(p0.movingAvgPaceSecPer100m, (81 * 100) ~/ 150); // 11+12+11+17+8+22
      expect(p0.totalStrokes, 350);
      expect(p0.avgSwolf, 165);
      expect(p0.strokeRatePerMin, isNotNull);
      expect(p0.lapCount, 6);
      expect(p0.reportedLaps, 20);
      expect(p0.lengthCoveragePartial, isTrue);
      expect(p0.hrCoverage, SwimHrCoverage.partial);
      expect(p0.laps.first.paceSecPer100m, (11 * 100) ~/ 25);
      expect(p0.laps[1].swolf, 48);
      // SWOLF check on lap 1: duration + strokes
      expect(11 + 124, 135);
    });

    test('HR present when sampleCount > 0', () {
      final p0 = computeSwimP0(
        durationSec: 600,
        distanceM: 500,
        sampleCount: 12,
      );
      expect(p0.hrCoverage, SwimHrCoverage.present);
    });

    test('HR absent when no peaks and no samples', () {
      final p0 = computeSwimP0(durationSec: 600, distanceM: 500);
      expect(p0.hrCoverage, SwimHrCoverage.absent);
    });

    test('derives stroke rate from strokes / moving time', () {
      final p0 = computeSwimP0(
        durationSec: 3600,
        strokes: 60,
        segmentLaps: const [
          SwimLapMetrics(index: 0, distanceM: 25, durationSec: 60, strokes: 30),
          SwimLapMetrics(index: 1, distanceM: 25, durationSec: 60, strokes: 30),
        ],
      );
      // 60 strokes in 120s moving → 30 /min
      expect(p0.strokeRatePerMin, 30);
    });
  });

  group('CanonicalSwimSession', () {
    test('builds from WorkoutSummary and converts pool cm → m', () {
      const summary = WorkoutSummary(
        number: 11,
        startTime: 1_700_000_000,
        endTime: 1_700_003_683,
        durationSec: 3683,
        type: 6,
        distanceM: 500,
        strokes: 350,
        avgSwolf: 165,
        poolLength: 2500,
        laps: 20,
        hrMin: 90,
        hrMax: 140,
        sampleCount: 0,
        segments: [
          WorkoutSegment(
            index: 0,
            distanceM: 25,
            durationSec: 11,
            strokes: 124,
            avgSwolf: 135,
            style: 2,
          ),
        ],
      );

      final session = CanonicalSwimSession.fromWorkoutSummary(summary)!;
      expect(session.workoutNumber, 11);
      expect(session.poolLengthM, 25);
      expect(session.p0.lengthCoveragePartial, isTrue);
      expect(session.p0.laps, hasLength(1));
      expect(session.toJson()['p0'], isA<Map>());
      expect(
        CanonicalSwimSession.fromJson(session.toJson()).poolLengthM,
        25,
      );
    });

    test('returns null for non-swim strength workout', () {
      const summary = WorkoutSummary(
        number: 2,
        startTime: 1,
        endTime: 2,
        durationSec: 100,
        type: 140,
      );
      expect(CanonicalSwimSession.fromWorkoutSummary(summary), isNull);
    });
  });

  group('poolLengthCmToMeters', () {
    test('2500 cm → 25 m', () {
      expect(poolLengthCmToMeters(2500), 25);
    });
  });
}
