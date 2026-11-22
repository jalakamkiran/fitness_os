import {
  validateWorkout,
  validateSleep,
  validateTotals,
  validateHr,
} from "../services/sync-validation";

describe("sync-validation", () => {
  const nowSec = Math.floor(new Date("2026-11-14T12:00:00Z").getTime() / 1000);
  const now = new Date("2026-11-14T12:00:00Z");

  describe("validateWorkout", () => {
    const valid = {
      startTime: 1700000000,
      endTime: 1700003600,
      durationSec: 3600,
    };

    it("accepts valid workout", () => {
      expect(validateWorkout(valid, nowSec)).toEqual({ok: true});
    });

    it("rejects missing fields", () => {
      const result = validateWorkout({startTime: 1}, nowSec);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("missing_fields");
    });

    it("rejects end before start", () => {
      const result = validateWorkout({
        ...valid,
        endTime: valid.startTime,
      }, nowSec);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("end_before_start");
    });

    it("rejects hr out of range", () => {
      const result = validateWorkout({...valid, hrMin: 10, hrMax: 300}, nowSec);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("hr_out_of_range");
    });
  });

  describe("validateSleep", () => {
    it("accepts valid sleep", () => {
      const result = validateSleep({
        beginUnix: 1700000000,
        endUnix: 1700028800,
      }, nowSec);
      expect(result).toEqual({ok: true});
    });

    it("rejects span too long", () => {
      const result = validateSleep({
        beginUnix: 1700000000,
        endUnix: 1700000000 + 21 * 3600,
      }, nowSec);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("span_too_long");
    });
  });

  describe("validateTotals", () => {
    it("accepts valid totals", () => {
      expect(validateTotals({
        dayKey: "2026-11-13",
        steps: 5000,
      }, now)).toEqual({ok: true});
    });

    it("rejects bad day key", () => {
      const result = validateTotals({dayKey: "11-13-2026"}, now);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("bad_day_key");
    });
  });

  describe("validateHr", () => {
    it("accepts valid hr", () => {
      expect(validateHr({avgHr: 70, maxHr: 120})).toEqual({ok: true});
    });

    it("rejects missing fields", () => {
      const result = validateHr({avgHr: 70});
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("missing_fields");
    });
  });
});
