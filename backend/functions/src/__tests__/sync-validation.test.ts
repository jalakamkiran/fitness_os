import {
  validateWorkout,
  validateSleep,
  sanitizeSleepBody,
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

    it("accepts inflated stage sum after sanitize", () => {
      const begin = 1700000000;
      const end = begin + 7 * 3600;
      const body = {
        beginUnix: begin,
        endUnix: end,
        stages: Array.from({length: 60}, (_, i) => ({
          timestampUnix: begin + i * 10,
          durationMin: 1,
          stage: 1,
        })),
      } as Record<string, unknown>;
      const result = validateSleep(body, nowSec);
      expect(result).toEqual({ok: true});
      expect(body.beginUnix).toBe(begin);
      expect(body.endUnix).toBe(end);
    });

    it("strips sentinel enrich fields", () => {
      const body = {
        beginUnix: 1700000000,
        endUnix: 1700025200,
        avgSpO2: 255,
        sleepScore: 255,
        avgHr: 0,
      } as Record<string, unknown>;
      sanitizeSleepBody(body);
      expect(body.avgSpO2).toBeUndefined();
      expect(body.sleepScore).toBeUndefined();
      expect(body.avgHr).toBeUndefined();
      expect(validateSleep(body, nowSec)).toEqual({ok: true});
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
