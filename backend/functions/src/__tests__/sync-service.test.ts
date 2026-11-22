/* eslint-disable @typescript-eslint/no-var-requires, @typescript-eslint/no-explicit-any */
import {getSyncManifest, syncFromApp} from "../services/sync-service";

function buildFirestoreMock(options?: {
  existingWorkout?: {startTime: string} | null;
  commitCount?: {value: number};
}) {
  const commitCount = options?.commitCount ?? {value: 0};
  const mockSet = jest.fn();

  const mockGet = jest.fn().mockResolvedValue({
    exists: options?.existingWorkout != null,
    data: () => options?.existingWorkout ?? undefined,
  });

  const mockDoc = jest.fn(() => ({
    get: mockGet,
  }));

  const mockCollection = jest.fn(() => ({doc: mockDoc}));

  const firestore = {
    collection: mockCollection,
    batch: jest.fn(() => {
      const b = {
        set: mockSet,
        commit: jest.fn().mockImplementation(async () => {
          commitCount.value++;
        }),
      };
      return b;
    }),
  };

  return {
    firestore,
    mockSet,
    mockDoc,
    mockCollection,
    mockGet,
    commitCount,
  };
}

jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  firestore: jest.fn(),
}));

jest.mock("../services/webhook-notifier", () => ({
  sendSyncWebhook: jest.fn().mockResolvedValue(undefined),
}));

describe("Sync Service", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  function installMock(existingWorkout?: {startTime: string} | null) {
    const admin = require("firebase-admin");
    const built = buildFirestoreMock({existingWorkout});
    admin.firestore = jest.fn(() => built.firestore);
    return built;
  }

  it("should sync workout data successfully with accepted ids", async () => {
    const {mockCollection, mockDoc, mockSet, commitCount} = installMock();

    const workoutPayload = {
      workouts: [{
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 500,
        hrMin: 140,
        hrMax: 180,
        clientId: "workout_1",
        contentHash: "abc123",
      }],
    };

    const result = await syncFromApp(workoutPayload);

    expect(result.synced).toBe(1);
    expect(result.accepted.workouts).toEqual(["workout_1"]);
    expect(result.rejected).toEqual([]);
    expect(result.checksumVerified).toBe(false);
    expect(mockCollection).toHaveBeenCalledWith("workouts");
    expect(mockDoc).toHaveBeenCalledWith("workout_1");
    expect(mockSet).toHaveBeenCalled();
    expect(commitCount.value).toBeGreaterThanOrEqual(1);
  });

  it("rejects invalid workout in payload", async () => {
    installMock();

    const result = await syncFromApp({
      workouts: [{
        number: 2,
        type: 2,
        startTime: 1700000000,
        endTime: 1700000000,
        durationSec: 0,
      }],
    });

    expect(result.synced).toBe(0);
    expect(result.rejected).toHaveLength(1);
    expect(result.rejected[0].kind).toBe("workout");
    expect(result.rejected[0].reason).toBe("end_before_start");
  });

  it("uses collision doc id when start time differs >60s", async () => {
    const {mockDoc} = installMock({startTime: "2019-01-01T00:00:00+05:30"});

    await syncFromApp({
      workouts: [{
        number: 5,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
      }],
    });

    expect(mockDoc).toHaveBeenCalledWith("workout_5_1700000000");
  });

  it("should sync sleep data successfully", async () => {
    const {mockCollection, mockSet, commitCount} = installMock();

    const sleepPayload = {
      sleep: [{
        beginUnix: 1700000000,
        endUnix: 1700028800,
        stages: [
          {timestampUnix: 1700000000, durationMin: 120, stage: 3},
        ],
      }],
    };

    const result = await syncFromApp(sleepPayload);

    expect(result.synced).toBe(1);
    expect(result.accepted.sleep).toHaveLength(1);
    expect(mockCollection).toHaveBeenCalledWith("sleep");
    expect(mockSet).toHaveBeenCalled();
    expect(commitCount.value).toBeGreaterThanOrEqual(1);
  });

  it("should sync daily totals and heart rate", async () => {
    const {commitCount} = installMock();

    const result = await syncFromApp({
      dailyTotals: [{
        dayKey: "2026-11-14",
        steps: 7825,
        activeKcal: 525,
        totalKcal: 2100,
      }],
      heartRate: [{
        dayKey: "2026-11-14",
        avgHr: 72,
        maxHr: 140,
      }],
    });

    expect(result.synced).toBe(2);
    expect(commitCount.value).toBeGreaterThanOrEqual(1);
  });

  it("should handle empty payload without batch commit", async () => {
    const {commitCount} = installMock();

    const result = await syncFromApp({});

    expect(result.synced).toBe(0);
    expect(commitCount.value).toBe(0);
  });

  it("commits in chunks of at most 400", async () => {
    const {commitCount} = installMock();

    const workouts = Array.from({length: 450}, (_, i) => ({
      number: i + 1,
      type: 2,
      startTime: 1700000000 + i,
      endTime: 1700003600 + i,
      durationSec: 3600,
    }));

    const result = await syncFromApp({workouts});

    expect(result.synced).toBe(450);
    expect(commitCount.value).toBe(2);
  });

  it("stores contentHash on workout record", async () => {
    const {mockSet} = installMock();
    let captured: any = null;
    mockSet.mockImplementation((_ref: unknown, data: unknown) => {
      captured = data;
    });

    await syncFromApp({
      workouts: [{
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        contentHash: "deadbeef",
        clientId: "workout_1",
      }],
    });

    expect(captured.contentHash).toBe("deadbeef");
    expect(captured.clientId).toBe("workout_1");
    expect(captured.syncedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("passes checksumVerified through result", async () => {
    installMock();
    const result = await syncFromApp({
      workouts: [{
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
      }],
    }, undefined, undefined, {checksumVerified: true});

    expect(result.checksumVerified).toBe(true);
  });
});

describe("getSyncManifest", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("returns manifest entries with hashes", async () => {
    const admin = require("firebase-admin");
    const mockGet = jest.fn().mockResolvedValue({
      docs: [{
        id: "workout_1",
        data: () => ({
          id: "workout_1",
          contentHash: "h1",
          clientId: "workout_1",
        }),
      }],
    });
    const chain = {
      where: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnValue({get: mockGet}),
    };
    admin.firestore = jest.fn(() => ({
      collection: jest.fn(() => chain),
    }));

    const manifest = await getSyncManifest("2026-11-01");

    expect(manifest.workouts).toHaveLength(1);
    expect(manifest.workouts[0]).toEqual({
      id: "workout_1",
      contentHash: "h1",
      clientId: "workout_1",
    });
  });
});
