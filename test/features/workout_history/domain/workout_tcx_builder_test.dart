import 'package:fitness_os/core/huawei/huawei_link.dart';
import 'package:fitness_os/features/workout_history/domain/workout_tcx_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildWorkoutTcx', () {
    test('emits distance stream trackpoints for Strava (not lap-only)', () {
      const workout = WorkoutSummary(
        number: 60,
        startTime: 1757386583, // 2026-09-09T02:56:23Z
        endTime: 1757387883,
        durationSec: 1300,
        type: 1,
        calories: 186,
        distanceM: 2790,
        hrMin: 84,
        hrMax: 181,
      );

      final xml = buildWorkoutTcx(workout);

      expect(xml, contains('Sport="Other"')); // Walk → Other (TCX schema)
      expect(xml, contains('<DistanceMeters>2790</DistanceMeters>'));
      expect(xml, contains('<Track>'));
      expect(xml, contains('<Trackpoint>'));
      expect(xml, contains('<DistanceMeters>0.0</DistanceMeters>'));
      expect(xml, contains('<DistanceMeters>2790.0</DistanceMeters>'));
      expect(xml, contains('Huawei type=1 (Walk)'));
      expect('<Trackpoint>'.allMatches(xml).length, greaterThanOrEqualTo(2));
    });

    test('emits Running sport and track for pool-less run', () {
      const workout = WorkoutSummary(
        number: 12,
        startTime: 1700000000,
        endTime: 1700001800,
        durationSec: 1800,
        type: 2,
        calories: 320,
        distanceM: 5000,
      );

      final xml = buildWorkoutTcx(workout);
      expect(xml, contains('Sport="Running"'));
      expect(xml, contains('<DistanceMeters>5000.0</DistanceMeters>'));
      expect(xml, contains('<Track>'));
    });

    test('emits one Lap per segment with tracks', () {
      const workout = WorkoutSummary(
        number: 3,
        startTime: 1700000000,
        endTime: 1700000600,
        durationSec: 600,
        type: 6,
        distanceM: 200,
        segments: [
          WorkoutSegment(index: 0, distanceM: 50, durationSec: 80),
          WorkoutSegment(index: 1, distanceM: 50, durationSec: 85),
          WorkoutSegment(index: 2, distanceM: 50, durationSec: 90),
          WorkoutSegment(index: 3, distanceM: 50, durationSec: 95),
        ],
      );

      final xml = buildWorkoutTcx(workout);
      expect('<Lap '.allMatches(xml).length, 4);
      expect('<Track>'.allMatches(xml).length, 4);
      expect(xml, contains('Sport="Other"')); // swim → Other
    });

    test('maps bike and strength sports', () {
      expect(
        buildWorkoutTcx(
          const WorkoutSummary(
            number: 1,
            startTime: 1,
            endTime: 2,
            durationSec: 1,
            type: 3,
          ),
        ),
        contains('Sport="Biking"'),
      );
      expect(
        buildWorkoutTcx(
          const WorkoutSummary(
            number: 1,
            startTime: 1,
            endTime: 2,
            durationSec: 1,
            type: 140,
          ),
        ),
        contains('Sport="Other"'),
      );
    });

    test('includes Notes without nested tags', () {
      final xml = buildWorkoutTcx(
        const WorkoutSummary(
          number: 1,
          startTime: 1,
          endTime: 2,
          durationSec: 1,
          type: 6,
          poolLength: 2500,
        ),
      );
      expect(xml, contains('<Notes>'));
      expect(xml, contains('</Notes>'));
      expect(xml, contains('Pool length 25 m'));
    });
  });

  group('workoutTcxFileStem', () {
    test('uses UTC stamp and sport slug', () {
      final stem = workoutTcxFileStem(
        const WorkoutSummary(
          number: 1,
          startTime: 1700000000,
          endTime: 1700000100,
          durationSec: 100,
          type: 6,
        ),
      );
      expect(stem, startsWith('fathom_pool_swim_'));
      expect(stem, contains('20231114'));
    });
  });
}
