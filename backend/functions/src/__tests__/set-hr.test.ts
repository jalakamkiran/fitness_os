import {
  computeAllSetHr,
  computeBaselineHr,
  filterBpm,
  sampleTimeMs,
  streamRegularity,
} from "../services/set-hr";
import {StrengthSetRecord, WorkoutHrStreamRecord} from "../models/types";

function makeStream(
    overrides: Partial<WorkoutHrStreamRecord> = {}
): WorkoutHrStreamRecord {
  return {
    id: "workout_1",
    type: 140,
    startMs: 1_000_000,
    intervalSec: 5,
    bpm: [],
    clockSkewMs: null,
    syncedAt: "2026-11-17T10:00:00.000Z",
    ...overrides,
  };
}

function makeSet(
    id: string,
    loggedAtMs: number,
    notifiedAtMs: number
): StrengthSetRecord {
  return {
    id,
    sessionId: "ps_test",
    exerciseId: "bench",
    exercise: "Bench press",
    setIndex: 1,
    plannedKg: 60,
    plannedReps: 8,
    actualKg: 60,
    actualReps: 8,
    failed: false,
    replyText: null,
    unknownReply: false,
    notifiedAtMs,
    loggedAtMs,
    loggedAt: "2026-11-17T10:00:00+05:30",
    source: "watch_reply",
    workoutId: "workout_1",
    syncedAt: "2026-11-17T10:00:00.000Z",
  };
}

describe("set-hr", () => {
  describe("filterBpm", () => {
    it("drops values outside 35–220", () => {
      expect(filterBpm([30, 100, 250])).toEqual([null, 100, null]);
    });
  });

  describe("sampleTimeMs", () => {
    it("applies clock skew", () => {
      const stream = makeStream({startMs: 0, intervalSec: 5, clockSkewMs: 2000});
      expect(sampleTimeMs(stream, 0)).toBe(-2000);
      expect(sampleTimeMs(stream, 1)).toBe(3000);
    });
  });

  describe("streamRegularity", () => {
    it("flags irregular streams", () => {
      const stream = makeStream({bpm: new Array(100).fill(100)});
      const r = streamRegularity(stream, 3600);
      expect(r.ok).toBe(false);
      expect(r.reason).toBe("paused_or_irregular");
    });

    it("accepts clean 5s series", () => {
      const count = 720;
      const stream = makeStream({bpm: new Array(count).fill(90)});
      expect(streamRegularity(stream, 3600).ok).toBe(true);
    });
  });

  describe("computeBaselineHr", () => {
    it("uses min+5 fallback when set within first 60s", () => {
      const start = 1_000_000;
      const bpm = [70, 72, 68, 90, 95, 100];
      const stream = makeStream({startMs: start, bpm});
      const sets = [makeSet("s1", start + 30_000, start + 10_000)];
      expect(computeBaselineHr(stream, sets, start)).toBe(73);
    });
  });

  describe("computeAllSetHr", () => {
    it("computes avg/max/drops for three sets on synthetic stream", () => {
      const startMs = 0;
      const intervalSec = 5;
      const durationSec = 600;
      const count = durationSec / intervalSec;
      const bpm: number[] = [];
      for (let i = 0; i < count; i++) {
        const t = i * intervalSec;
        bpm.push(80 + Math.sin(t / 30) * 10);
      }

      const set1Log = 120_000;
      const set2Log = 240_000;
      const set3Log = 360_000;
      for (let i = 0; i < count; i++) {
        const t = i * intervalSec * 1000;
        if (Math.abs(t - set1Log) < 2500) bpm[i] = 140;
        if (Math.abs(t - set2Log) < 2500) bpm[i] = 145;
        if (Math.abs(t - set3Log) < 2500) bpm[i] = 150;
      }

      const stream = makeStream({startMs, intervalSec, bpm});
      const sets = [
        makeSet("s1", set1Log, 60_000),
        makeSet("s2", set2Log, 180_000),
        makeSet("s3", set3Log, 300_000),
      ];
      sets[1].setIndex = 2;
      sets[2].setIndex = 3;

      const rows = computeAllSetHr(stream, sets, startMs, durationSec);
      expect(rows).toHaveLength(3);
      expect(rows[0].maxHr).toBeGreaterThanOrEqual(130);
      expect(rows[0].avgHr).not.toBeNull();
      expect(rows[0].hrAtEnd).not.toBeNull();
      expect(rows[0].reason).toBeNull();
    });

    it("returns nulls with reason when stream is irregular", () => {
      const stream = makeStream({bpm: [90, 91, 92]});
      const sets = [makeSet("s1", 10_000, 0)];
      const rows = computeAllSetHr(stream, sets, 0, 3600);
      expect(rows[0].avgHr).toBeNull();
      expect(rows[0].reason).toBe("paused_or_irregular");
    });

    it("sorts out-of-order sets by loggedAtMs", () => {
      const startMs = 0;
      const bpm = new Array(200).fill(85);
      bpm[40] = 130;
      bpm[80] = 135;
      const stream = makeStream({startMs, bpm});
      const late = makeSet("s2", 400_000, 300_000);
      late.setIndex = 2;
      const first = makeSet("s1", 200_000, 100_000);
      const rows = computeAllSetHr(stream, [late, first], startMs, 1000);
      expect(rows[0].setId).toBe("s1");
      expect(rows[1].setId).toBe("s2");
    });

    it("shifts windows with clock skew +2s", () => {
      const startMs = 0;
      const intervalSec = 5;
      const bpm = new Array(100).fill(80);
      bpm[20] = 120;
      const stream = makeStream({
        startMs,
        intervalSec,
        clockSkewMs: 2000,
        bpm,
      });
      const logMs = 20 * intervalSec * 1000 - 2000;
      const sets = [makeSet("s1", logMs, 0)];
      const rows = computeAllSetHr(stream, sets, startMs, 500);
      expect(rows[0].hrAtEnd).toBe(120);
    });
  });
});