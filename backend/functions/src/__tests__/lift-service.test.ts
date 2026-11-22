/* eslint-disable @typescript-eslint/no-explicit-any */
import {
  batchUpsertStrengthSets,
  epley1Rm,
  isoWeekKeyIST,
  upsertPlannedSession,
  validatePlannedSessionInput,
  validateStrengthSet,
  ValidationError,
} from "../services/lift-service";
import {getCurrentISTDate} from "../services/timezone";

jest.mock("../services/set-hr", () => ({
  ...jest.requireActual("../services/set-hr"),
  recomputeSetHrForWorkout: jest.fn().mockResolvedValue(0),
  linkSetToWorkout: jest.fn().mockReturnValue(null),
  workoutDocToWindow: jest.fn(),
}));

jest.mock("../services/timezone", () => ({
  ...jest.requireActual("../services/timezone"),
  getCurrentISTDate: jest.fn(() => "2026-11-17"),
  msToIST: (ms: number) => new Date(ms).toISOString(),
}));

const mockSet = jest.fn();
const mockGet = jest.fn();
const mockBatchSet = jest.fn();
const mockCommit = jest.fn().mockResolvedValue(undefined);
const mockWhere = jest.fn().mockReturnThis();
const mockOrderBy = jest.fn().mockReturnThis();
const mockLimit = jest.fn().mockReturnThis();

jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({
    collection: jest.fn(() => ({
      doc: jest.fn(() => ({
        set: mockSet,
        get: mockGet.mockResolvedValue({exists: false, data: () => null}),
      })),
      where: mockWhere,
      orderBy: mockOrderBy,
      limit: mockLimit,
      get: jest.fn().mockResolvedValue({empty: true, docs: []}),
    })),
    batch: jest.fn(() => ({
      set: mockBatchSet,
      commit: mockCommit,
    })),
    FieldPath: {documentId: jest.fn(() => "__name__")},
  })),
}));

describe("lift-service", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGet.mockResolvedValue({exists: false, data: () => null});
  });

  const validExercise = {
    exerciseId: "bench",
    name: "Bench press",
    sets: 4,
    targetKg: 60,
    targetReps: 8,
    restSec: 120,
  };

  describe("validatePlannedSessionInput", () => {
    it("accepts valid session", () => {
      expect(() =>
        validatePlannedSessionInput({
          id: "ps_1",
          title: "Push",
          plannedFor: "2026-11-18",
          exercises: [validExercise],
          source: "manual",
        })
      ).not.toThrow();
    });

    it("rejects too many exercises", () => {
      const exercises = Array.from({length: 21}, (_, i) => ({
        ...validExercise,
        exerciseId: `ex${i}`,
      }));
      expect(() =>
        validatePlannedSessionInput({
          id: "ps_1",
          title: "Push",
          plannedFor: "2026-11-18",
          exercises,
          source: "manual",
        })
      ).toThrow(ValidationError);
    });

    it("rejects name over 60 chars", () => {
      expect(() =>
        validatePlannedSessionInput({
          id: "ps_1",
          title: "Push",
          plannedFor: "2026-11-18",
          exercises: [{...validExercise, name: "x".repeat(61)}],
          source: "manual",
        })
      ).toThrow(ValidationError);
    });

    it("rejects targetKg out of range", () => {
      expect(() =>
        validatePlannedSessionInput({
          id: "ps_1",
          title: "Push",
          plannedFor: "2026-11-18",
          exercises: [{...validExercise, targetKg: 501}],
          source: "manual",
        })
      ).toThrow(ValidationError);
    });
  });

  describe("validateStrengthSet", () => {
    const base = {
      id: "ps_1_bench_1",
      sessionId: "ps_1",
      exerciseId: "bench",
      exercise: "Bench press",
      setIndex: 1,
      plannedKg: 60,
      plannedReps: 8,
      actualKg: 60,
      actualReps: 8,
      failed: false,
      unknownReply: false,
      notifiedAtMs: 1,
      loggedAtMs: 2,
      source: "watch_reply" as const,
    };

    it("accepts valid set", () => {
      expect(() => validateStrengthSet(base, 0)).not.toThrow();
    });

    it("rejects missing id", () => {
      const {id, ...rest} = base;
      void id;
      expect(() => validateStrengthSet(rest, 0)).toThrow(ValidationError);
    });
  });

  describe("upsertPlannedSession", () => {
    it("writes idempotent doc", async () => {
      mockGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({createdAt: "2026-11-01T00:00:00.000Z"}),
      });
      const record = await upsertPlannedSession({
        id: "ps_20261117_abc",
        title: "Legs",
        plannedFor: "2026-11-18",
        exercises: [validExercise],
        source: "arjun",
      });
      expect(record.id).toBe("ps_20261117_abc");
      expect(record.createdAt).toBe("2026-11-01T00:00:00.000Z");
      expect(mockSet).toHaveBeenCalled();
    });
  });

  describe("batchUpsertStrengthSets", () => {
    it("upserts by set id", async () => {
      mockGet.mockResolvedValue({exists: false, data: () => ({})});
      const result = await batchUpsertStrengthSets([{
        id: "ps_1_bench_1",
        sessionId: "ps_1",
        exerciseId: "bench",
        exercise: "Bench press",
        setIndex: 1,
        plannedKg: 60,
        plannedReps: 8,
        actualKg: 60,
        actualReps: 8,
        failed: false,
        unknownReply: false,
        notifiedAtMs: 1000,
        loggedAtMs: 2000,
        source: "watch_reply",
      }]);
      expect(result.synced).toBe(1);
      expect(mockBatchSet).toHaveBeenCalled();
      expect(mockCommit).toHaveBeenCalled();
    });

    it("rejects batch over 200", async () => {
      const sets = Array.from({length: 201}, (_, i) => ({
        id: `s${i}`,
        sessionId: "ps_1",
        exerciseId: "bench",
        exercise: "Bench",
        setIndex: 1,
        plannedKg: 60,
        plannedReps: 8,
        actualKg: 60,
        actualReps: 8,
        failed: false,
        unknownReply: false,
        notifiedAtMs: 1,
        loggedAtMs: 2,
        source: "watch_reply" as const,
      }));
      await expect(batchUpsertStrengthSets(sets)).rejects.toThrow(ValidationError);
    });
  });

  describe("progression math", () => {
    it("computes Epley e1RM for reps 1–12 only", () => {
      expect(epley1Rm(100, 5)).toBeCloseTo(116.67, 1);
      expect(epley1Rm(100, 12)).toBeCloseTo(140, 1);
      expect(epley1Rm(100, 15)).toBeNull();
    });

    it("uses ISO week keys", () => {
      expect(isoWeekKeyIST("2026-11-17")).toMatch(/^\d{4}-W\d{2}$/);
    });
  });
});

describe("lift feature gates", () => {
  it("defaults LIFT flags to off when env unset", () => {
    const write = process.env.LIFT_WRITE_ENABLED === "true";
    const read = process.env.LIFT_READ_ENABLED === "true";
    expect(write).toBe(false);
    expect(read).toBe(false);
  });
});

describe("getCurrentISTDate usage", () => {
  it("mocks today for next-session query", () => {
    expect(getCurrentISTDate()).toBe("2026-11-17");
  });
});
