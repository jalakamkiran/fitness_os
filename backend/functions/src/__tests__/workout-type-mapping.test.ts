import {mapWorkoutType, WORKOUT_TYPE_MAP} from "../models/workout-type-mapping";

const EXPECTED_MAP: Record<number, string> = {
  1: "walking",
  2: "running",
  3: "cycling",
  4: "climbing",
  5: "indoor_running",
  6: "swimming",
  7: "indoor_cycling",
  8: "swimming",
  9: "elliptical",
  10: "rowing",
  11: "hiking",
  13: "cross_trainer",
  129: "badminton",
  130: "table_tennis",
  131: "tennis",
  133: "squash",
  134: "basketball",
  135: "football",
  137: "volleyball",
  138: "skiing",
  139: "snowboarding",
  140: "strength",
  141: "yoga",
  142: "pilates",
  143: "boxing",
  144: "martial_arts",
  145: "dance",
  146: "jump_rope",
  147: "stepper",
  150: "mma",
};

describe("mapWorkoutType", () => {
  it("maps every Huawei code in WORKOUT_TYPE_MAP to the expected label", () => {
    expect(WORKOUT_TYPE_MAP).toEqual(EXPECTED_MAP);
    for (const [code, label] of Object.entries(EXPECTED_MAP)) {
      expect(mapWorkoutType(Number(code))).toBe(label);
    }
  });

  it("maps Huawei type 140 to strength", () => {
    expect(mapWorkoutType(140)).toBe("strength");
  });

  it("maps Huawei type 10 to rowing, not strength", () => {
    expect(mapWorkoutType(10)).toBe("rowing");
    expect(mapWorkoutType(10)).not.toBe("strength");
  });

  it("swaps the old inverted walk/run codes", () => {
    expect(mapWorkoutType(1)).toBe("walking");
    expect(mapWorkoutType(1)).not.toBe("running");
    expect(mapWorkoutType(2)).toBe("running");
    expect(mapWorkoutType(2)).not.toBe("walking");
  });

  it("does not keep retired generic-map codes", () => {
    expect(mapWorkoutType(4)).toBe("climbing");
    expect(mapWorkoutType(5)).toBe("indoor_running");
    expect(mapWorkoutType(6)).toBe("swimming");
    expect(mapWorkoutType(8)).toBe("swimming");
    expect(mapWorkoutType(9)).toBe("elliptical");
    expect(mapWorkoutType(11)).toBe("hiking");
    expect(mapWorkoutType(12)).toBe("other");
  });

  it("keeps badminton type 129 and legacy mma 150", () => {
    expect(mapWorkoutType(129)).toBe("badminton");
    expect(mapWorkoutType(150)).toBe("mma");
  });

  it("falls back to other for unknown types", () => {
    expect(mapWorkoutType(999)).toBe("other");
  });
});
