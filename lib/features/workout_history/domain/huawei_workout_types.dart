/// Huawei watch workout type codes (LPv2 Totals TLV 0x14).
///
/// Based on behavioral oracle patterns from Gadgetbridge Huawei device support
/// (reference only — not AGPL code) and Fitness OS device observations.
///
/// Sources:
/// - FOS device captures: Strength (140), Pool swim (6)
/// - Gadgetbridge workout type enum patterns (behavioral oracle for type IDs)
/// - Owner observation: Type 129 observed once (workout #17, 732s, badminton)
///
/// Unknown types gracefully fall back to "Workout type N" label.
library;

/// Comprehensive Huawei workout type mapping.
///
/// Codes derived from Gadgetbridge behavioral oracle (Huawei device support).
/// Only types confirmed by device observation or reliable public references
/// are marked as verified.
const Map<int, HuaweiWorkoutType> kHuaweiWorkoutTypes = {
  // Cardio / Running
  1: HuaweiWorkoutType(1, 'Walk', WorkoutCategory.cardio, verified: true),
  2: HuaweiWorkoutType(2, 'Run', WorkoutCategory.cardio, verified: true),
  5: HuaweiWorkoutType(5, 'Indoor run', WorkoutCategory.cardio, verified: true),
  9: HuaweiWorkoutType(9, 'Elliptical', WorkoutCategory.cardio),
  10: HuaweiWorkoutType(10, 'Rower', WorkoutCategory.cardio),
  13: HuaweiWorkoutType(13, 'Cross trainer', WorkoutCategory.cardio),

  // Cycling
  3: HuaweiWorkoutType(3, 'Cycle', WorkoutCategory.cycling),
  7: HuaweiWorkoutType(7, 'Indoor cycle', WorkoutCategory.cycling),

  // Swimming
  6: HuaweiWorkoutType(6, 'Pool swim', WorkoutCategory.swimming, verified: true),
  8: HuaweiWorkoutType(8, 'Open water', WorkoutCategory.swimming),

  // Climbing / Mountain
  4: HuaweiWorkoutType(4, 'Climb', WorkoutCategory.outdoor),
  11: HuaweiWorkoutType(11, 'Hiking', WorkoutCategory.outdoor),

  // Racket sports
  129: HuaweiWorkoutType(129, 'Badminton', WorkoutCategory.racket, verified: true),
  130: HuaweiWorkoutType(130, 'Table tennis', WorkoutCategory.racket),
  131: HuaweiWorkoutType(131, 'Tennis', WorkoutCategory.racket),
  133: HuaweiWorkoutType(133, 'Squash', WorkoutCategory.racket),
  
  // Ball sports
  134: HuaweiWorkoutType(134, 'Basketball', WorkoutCategory.ballSports),
  135: HuaweiWorkoutType(135, 'Football', WorkoutCategory.ballSports),
  137: HuaweiWorkoutType(137, 'Volleyball', WorkoutCategory.ballSports),
  
  // Winter sports
  138: HuaweiWorkoutType(138, 'Skiing', WorkoutCategory.winter),
  139: HuaweiWorkoutType(139, 'Snowboarding', WorkoutCategory.winter),

  // Strength & Combat
  140: HuaweiWorkoutType(140, 'Strength', WorkoutCategory.strength, verified: true),
  141: HuaweiWorkoutType(141, 'Yoga', WorkoutCategory.flexibility),
  142: HuaweiWorkoutType(142, 'Pilates', WorkoutCategory.flexibility),
  143: HuaweiWorkoutType(143, 'Boxing', WorkoutCategory.combat),
  144: HuaweiWorkoutType(144, 'Martial arts', WorkoutCategory.combat),

  // Other
  145: HuaweiWorkoutType(145, 'Dance', WorkoutCategory.other),
  146: HuaweiWorkoutType(146, 'Jump rope', WorkoutCategory.other),
  147: HuaweiWorkoutType(147, 'Stepper', WorkoutCategory.cardio),
};

enum WorkoutCategory {
  cardio,
  cycling,
  swimming,
  outdoor,
  racket,
  ballSports,
  winter,
  strength,
  flexibility,
  combat,
  other,
}

/// Metadata for a Huawei workout type.
class HuaweiWorkoutType {
  const HuaweiWorkoutType(
    this.code,
    this.label,
    this.category, {
    this.verified = false,
  });

  /// Wire type code from LPv2 Totals TLV 0x14.
  final int code;

  /// Human-readable label for UI.
  final String label;

  /// Workout category for grouping and icon selection.
  final WorkoutCategory category;

  /// Whether this type has been verified via device observation or reliable docs.
  final bool verified;
}

/// Returns the label for a workout type code, with graceful fallback.
String workoutTypeLabel(int type) {
  final workout = kHuaweiWorkoutTypes[type];
  
  // Observability is handled by callers via WorkoutSyncBreadcrumbs
  // to avoid circular dependencies and keep this module pure
  
  return workout?.label ?? 'Workout type $type';
}

/// Returns the category for a workout type code, or null if unknown.
WorkoutCategory? workoutTypeCategory(int type) {
  return kHuaweiWorkoutTypes[type]?.category;
}

/// Returns true if the type is a swimming workout (pool or open water).
bool isSwimWorkout(int type) => type == 6 || type == 8;

/// Returns true if the type is a running/walking workout (outdoor/indoor).
bool isRunWorkout(int type) => type == 1 || type == 2 || type == 5;

/// Returns true if the type is outdoor run specifically (not walk or indoor).
bool isOutdoorRunWorkout(int type) => type == 2;

/// Returns true if the type is strength training.
bool isStrengthWorkout(int type) => type == 140;

/// Returns true if the type is outdoor land cardio (walk or outdoor run).
bool isOutdoorLandWorkout(int type) => type == 1 || type == 2;

/// Returns true if the type is a racket sport (badminton, tennis, etc).
bool isRacketSport(int type) {
  return workoutTypeCategory(type) == WorkoutCategory.racket;
}

/// Returns true if the workout belongs in the Sports tab.
///
/// Includes racket sports, ball sports, winter sports, combat sports, flexibility,
/// outdoor activities, cycling, and other sports (excluding swim, run/walk, strength).
bool isSportsWorkout(int type) {
  final category = workoutTypeCategory(type);
  if (category == null) return false;
  
  return category == WorkoutCategory.racket ||
      category == WorkoutCategory.ballSports ||
      category == WorkoutCategory.winter ||
      category == WorkoutCategory.combat ||
      category == WorkoutCategory.flexibility ||
      category == WorkoutCategory.outdoor ||
      category == WorkoutCategory.cycling ||
      category == WorkoutCategory.other;
}
