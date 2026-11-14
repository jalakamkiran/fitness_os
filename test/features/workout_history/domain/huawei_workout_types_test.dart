import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_os/features/workout_history/domain/huawei_workout_types.dart';

void main() {
  group('HuaweiWorkoutTypes', () {
    group('workoutTypeLabel', () {
      test('returns correct label for verified types', () {
        expect(workoutTypeLabel(1), 'Walk');
        expect(workoutTypeLabel(2), 'Run');
        expect(workoutTypeLabel(5), 'Indoor run');
        expect(workoutTypeLabel(6), 'Pool swim');
        expect(workoutTypeLabel(140), 'Strength');
      });

      test('returns correct label for badminton (type 129)', () {
        expect(workoutTypeLabel(129), 'Badminton');
      });

      test('returns correct label for other racket sports', () {
        expect(workoutTypeLabel(130), 'Table tennis');
        expect(workoutTypeLabel(131), 'Tennis');
        expect(workoutTypeLabel(133), 'Squash');
      });

      test('returns fallback label for unknown types', () {
        expect(workoutTypeLabel(999), 'Workout type 999');
        expect(workoutTypeLabel(0), 'Workout type 0');
        expect(workoutTypeLabel(-1), 'Workout type -1');
      });

      test('returns correct labels for all mapped types', () {
        // Cardio
        expect(workoutTypeLabel(9), 'Elliptical');
        expect(workoutTypeLabel(10), 'Rower');
        expect(workoutTypeLabel(13), 'Cross trainer');

        // Cycling
        expect(workoutTypeLabel(3), 'Cycle');
        expect(workoutTypeLabel(7), 'Indoor cycle');

        // Swimming
        expect(workoutTypeLabel(8), 'Open water');

        // Outdoor
        expect(workoutTypeLabel(4), 'Climb');
        expect(workoutTypeLabel(11), 'Hiking');

        // Ball sports
        expect(workoutTypeLabel(134), 'Basketball');
        expect(workoutTypeLabel(135), 'Football');
        expect(workoutTypeLabel(137), 'Volleyball');

        // Winter
        expect(workoutTypeLabel(138), 'Skiing');
        expect(workoutTypeLabel(139), 'Snowboarding');

        // Strength & Combat
        expect(workoutTypeLabel(141), 'Yoga');
        expect(workoutTypeLabel(142), 'Pilates');
        expect(workoutTypeLabel(143), 'Boxing');
        expect(workoutTypeLabel(144), 'Martial arts');

        // Other
        expect(workoutTypeLabel(145), 'Dance');
        expect(workoutTypeLabel(146), 'Jump rope');
        expect(workoutTypeLabel(147), 'Stepper');
      });
    });

    group('workoutTypeCategory', () {
      test('returns correct category for verified types', () {
        expect(workoutTypeCategory(1), WorkoutCategory.cardio);
        expect(workoutTypeCategory(6), WorkoutCategory.swimming);
        expect(workoutTypeCategory(140), WorkoutCategory.strength);
      });

      test('returns racket category for badminton and related sports', () {
        expect(workoutTypeCategory(129), WorkoutCategory.racket);
        expect(workoutTypeCategory(130), WorkoutCategory.racket);
        expect(workoutTypeCategory(131), WorkoutCategory.racket);
        expect(workoutTypeCategory(133), WorkoutCategory.racket);
      });

      test('returns correct categories for other sport types', () {
        expect(workoutTypeCategory(3), WorkoutCategory.cycling);
        expect(workoutTypeCategory(4), WorkoutCategory.outdoor);
        expect(workoutTypeCategory(134), WorkoutCategory.ballSports);
        expect(workoutTypeCategory(138), WorkoutCategory.winter);
        expect(workoutTypeCategory(141), WorkoutCategory.flexibility);
        expect(workoutTypeCategory(143), WorkoutCategory.combat);
        expect(workoutTypeCategory(145), WorkoutCategory.other);
      });

      test('returns null for unknown types', () {
        expect(workoutTypeCategory(999), isNull);
        expect(workoutTypeCategory(0), isNull);
      });
    });

    group('isSwimWorkout', () {
      test('returns true for swimming types', () {
        expect(isSwimWorkout(6), isTrue);
        expect(isSwimWorkout(8), isTrue);
      });

      test('returns false for non-swimming types', () {
        expect(isSwimWorkout(1), isFalse);
        expect(isSwimWorkout(2), isFalse);
        expect(isSwimWorkout(129), isFalse);
        expect(isSwimWorkout(140), isFalse);
      });
    });

    group('isRunWorkout', () {
      test('returns true for running types', () {
        expect(isRunWorkout(1), isTrue); // Walk
        expect(isRunWorkout(2), isTrue); // Run
        expect(isRunWorkout(5), isTrue); // Indoor run
      });

      test('returns false for non-running types', () {
        expect(isRunWorkout(3), isFalse);
        expect(isRunWorkout(6), isFalse);
        expect(isRunWorkout(129), isFalse);
        expect(isRunWorkout(140), isFalse);
      });
    });

    group('isOutdoorRunWorkout', () {
      test('returns true only for outdoor run (type 2)', () {
        expect(isOutdoorRunWorkout(2), isTrue);
      });

      test('returns false for walk and indoor run', () {
        expect(isOutdoorRunWorkout(1), isFalse); // Walk
        expect(isOutdoorRunWorkout(5), isFalse); // Indoor run
      });

      test('returns false for other types', () {
        expect(isOutdoorRunWorkout(3), isFalse);
        expect(isOutdoorRunWorkout(6), isFalse);
        expect(isOutdoorRunWorkout(129), isFalse);
      });
    });

    group('isStrengthWorkout', () {
      test('returns true only for strength (type 140)', () {
        expect(isStrengthWorkout(140), isTrue);
      });

      test('returns false for non-strength types', () {
        expect(isStrengthWorkout(1), isFalse);
        expect(isStrengthWorkout(6), isFalse);
        expect(isStrengthWorkout(129), isFalse);
        expect(isStrengthWorkout(141), isFalse); // Yoga is not strength
      });
    });

    group('isOutdoorLandWorkout', () {
      test('returns true for walk and outdoor run', () {
        expect(isOutdoorLandWorkout(1), isTrue); // Walk
        expect(isOutdoorLandWorkout(2), isTrue); // Run
      });

      test('returns false for indoor run', () {
        expect(isOutdoorLandWorkout(5), isFalse);
      });

      test('returns false for other types', () {
        expect(isOutdoorLandWorkout(3), isFalse);
        expect(isOutdoorLandWorkout(6), isFalse);
        expect(isOutdoorLandWorkout(129), isFalse);
      });
    });

    group('isRacketSport', () {
      test('returns true for racket sports', () {
        expect(isRacketSport(129), isTrue); // Badminton
        expect(isRacketSport(130), isTrue); // Table tennis
        expect(isRacketSport(131), isTrue); // Tennis
        expect(isRacketSport(133), isTrue); // Squash
      });

      test('returns false for non-racket sports', () {
        expect(isRacketSport(1), isFalse);
        expect(isRacketSport(6), isFalse);
        expect(isRacketSport(134), isFalse); // Basketball
        expect(isRacketSport(140), isFalse);
      });

      test('returns false for unknown types', () {
        expect(isRacketSport(999), isFalse);
      });
    });

    group('HuaweiWorkoutType', () {
      test('contains correct metadata for badminton', () {
        final badminton = kHuaweiWorkoutTypes[129]!;
        expect(badminton.code, 129);
        expect(badminton.label, 'Badminton');
        expect(badminton.category, WorkoutCategory.racket);
        expect(badminton.verified, isTrue);
      });

      test('marks device-observed types as verified', () {
        expect(kHuaweiWorkoutTypes[1]!.verified, isTrue); // Walk
        expect(kHuaweiWorkoutTypes[2]!.verified, isTrue); // Run
        expect(kHuaweiWorkoutTypes[5]!.verified, isTrue); // Indoor run
        expect(kHuaweiWorkoutTypes[6]!.verified, isTrue); // Pool swim
        expect(kHuaweiWorkoutTypes[129]!.verified, isTrue); // Badminton
        expect(kHuaweiWorkoutTypes[140]!.verified, isTrue); // Strength
      });

      test('marks inferred types as unverified', () {
        expect(kHuaweiWorkoutTypes[130]!.verified, isFalse); // Table tennis
        expect(kHuaweiWorkoutTypes[131]!.verified, isFalse); // Tennis
        expect(kHuaweiWorkoutTypes[133]!.verified, isFalse); // Squash
      });
    });
  });
}
