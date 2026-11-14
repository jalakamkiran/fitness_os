/**
 * Huawei workout type to lowercase string mapping
 * Consumed by adapter; can be updated as new types are added
 */

export const WORKOUT_TYPE_MAP: Record<number, string> = {
  1: "running",
  2: "walking",
  3: "cycling",
  4: "swimming",
  5: "hiking",
  6: "indoor_running",
  7: "indoor_cycling",
  8: "elliptical",
  9: "rowing",
  10: "strength",
  11: "yoga",
  12: "indoor_walking",
  // Badminton type 129 handled by concurrent PR - consume whatever exists
  129: "badminton",
  // MMA and other types
  150: "mma",
  // Add more mappings as discovered
};

export function mapWorkoutType(type: number): string {
  return WORKOUT_TYPE_MAP[type] || "other";
}
