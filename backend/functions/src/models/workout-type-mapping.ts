/**
 * Huawei workout type to lowercase string mapping
 * Aligned with lib/features/workout_history/domain/huawei_workout_types.dart
 */

export const WORKOUT_TYPE_MAP: Record<number, string> = {
  // Cardio / Running
  1: "walking",
  2: "running",
  5: "indoor_running",
  9: "elliptical",
  10: "rowing",
  13: "cross_trainer",
  147: "stepper",

  // Cycling
  3: "cycling",
  7: "indoor_cycling",

  // Swimming
  6: "swimming",
  8: "swimming",

  // Climbing / Mountain
  4: "climbing",
  11: "hiking",

  // Racket sports
  129: "badminton",
  130: "table_tennis",
  131: "tennis",
  133: "squash",

  // Ball sports
  134: "basketball",
  135: "football",
  137: "volleyball",

  // Winter sports
  138: "skiing",
  139: "snowboarding",

  // Strength & Combat
  140: "strength",
  141: "yoga",
  142: "pilates",
  143: "boxing",
  144: "martial_arts",

  // Other
  145: "dance",
  146: "jump_rope",

  // Legacy / unverified in Dart table
  150: "mma",
};

export function mapWorkoutType(type: number): string {
  return WORKOUT_TYPE_MAP[type] || "other";
}
