import {mapWorkoutType} from "../models/workout-type-mapping";

describe("mapWorkoutType", () => {
  it("maps Huawei type 140 to strength", () => {
    expect(mapWorkoutType(140)).toBe("strength");
  });

  it("maps Huawei type 10 to rowing, not strength", () => {
    expect(mapWorkoutType(10)).toBe("rowing");
    expect(mapWorkoutType(10)).not.toBe("strength");
  });

  it("keeps badminton type 129", () => {
    expect(mapWorkoutType(129)).toBe("badminton");
  });

  it("falls back to other for unknown types", () => {
    expect(mapWorkoutType(999)).toBe("other");
  });
});
