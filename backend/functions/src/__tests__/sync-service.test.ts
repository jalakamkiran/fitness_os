import {syncFromApp} from "../services/sync-service";

jest.mock("firebase-admin", () => {
  const mockCommit = jest.fn().mockResolvedValue({});
  const mockSet = jest.fn();
  const mockBatch = {
    set: mockSet,
    commit: mockCommit,
  };
  const mockDoc = jest.fn(() => ({}));
  const mockCollection = jest.fn(() => ({
    doc: mockDoc,
  }));

  return {
    initializeApp: jest.fn(),
    firestore: jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    })),
  };
});

describe("Sync Service", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should sync workout data successfully", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const workoutPayload = {
      workouts: [{
        number: 1,
        type: 2, // running
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 500,
        hrMin: 140,
        hrMax: 180,
      }],
    };

    const result = await syncFromApp(workoutPayload);

    expect(result.synced).toBe(1);
    expect(mockCollection).toHaveBeenCalledWith("workouts");
    expect(mockDoc).toHaveBeenCalledWith("workout_1");
    expect(mockSet).toHaveBeenCalled();
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should sync sleep data successfully", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const sleepPayload = {
      sleep: [{
        beginUnix: 1700000000,
        endUnix: 1700028800,
        stages: [
          {timestampUnix: 1700000000, durationMin: 120, stage: 3}, // deep
          {timestampUnix: 1700007200, durationMin: 300, stage: 2}, // light
          {timestampUnix: 1700025000, durationMin: 60, stage: 4}, // REM
        ],
      }],
    };

    const result = await syncFromApp(sleepPayload);

    expect(result.synced).toBe(1);
    expect(mockCollection).toHaveBeenCalledWith("sleep");
    expect(mockSet).toHaveBeenCalled();
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should sync daily totals successfully", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const totalsPayload = {
      dailyTotals: [{
        dayKey: "2026-11-14",
        steps: 7825,
        activeKcal: 525,
        totalKcal: 2100,
      }],
    };

    const result = await syncFromApp(totalsPayload);

    expect(result.synced).toBe(1);
    expect(mockCollection).toHaveBeenCalledWith("dailyTotals");
    expect(mockSet).toHaveBeenCalled();
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should sync multiple data types in one call", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const mixedPayload = {
      workouts: [{
        number: 1,
        type: 6, // swimming
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 400,
      }],
      dailyTotals: [{
        dayKey: "2026-11-14",
        steps: 5000,
        activeKcal: 450,
      }],
      weight: [{
        timestampMs: 1700010000000,
        weightKg: 72.5,
      }],
    };

    const result = await syncFromApp(mixedPayload);

    expect(result.synced).toBe(3);
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should handle empty payload gracefully", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };

    admin.firestore = jest.fn(() => ({
      batch: () => mockBatch,
    }));

    const result = await syncFromApp({});

    expect(result.synced).toBe(0);
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should add syncedAt timestamp to all records", async () => {
    const admin = require("firebase-admin");
    let capturedData: any = null;
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn((ref, data) => {
      capturedData = data;
    });
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const workoutPayload = {
      workouts: [{
        number: 1,
        type: 2,
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
      }],
    };

    await syncFromApp(workoutPayload);

    expect(capturedData).toBeDefined();
    expect(capturedData.syncedAt).toBeDefined();
    expect(typeof capturedData.syncedAt).toBe("string");
    // Verify ISO 8601 format
    expect(capturedData.syncedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  });

  it("should handle workout with racket sport fields", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const badmintonPayload = {
      workouts: [{
        number: 17,
        type: 129, // badminton
        startTime: 1700050000,
        endTime: 1700050732,
        durationSec: 732,
        calories: 150,
        hrMin: 82,
        hrMax: 105,
      }],
    };

    const result = await syncFromApp(badmintonPayload);

    expect(result.synced).toBe(1);
    expect(mockSet).toHaveBeenCalled();
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should handle workout with swim-specific fields", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const swimPayload = {
      workouts: [{
        number: 23,
        type: 6, // pool swim
        startTime: 1700000000,
        endTime: 1700003600,
        durationSec: 3600,
        calories: 400,
        laps: 28,
        strokes: 2500,
        poolLength: 40,
        avgSwolf: 45,
        distanceM: 1200,
      }],
    };

    const result = await syncFromApp(swimPayload);

    expect(result.synced).toBe(1);
    expect(mockCommit).toHaveBeenCalled();
  });

  it("should handle workout with strength-specific fields", async () => {
    const admin = require("firebase-admin");
    const mockCommit = jest.fn().mockResolvedValue({});
    const mockSet = jest.fn();
    const mockBatch = {
      set: mockSet,
      commit: mockCommit,
    };
    const mockDoc = jest.fn(() => ({}));
    const mockCollection = jest.fn(() => ({doc: mockDoc}));

    admin.firestore = jest.fn(() => ({
      collection: mockCollection,
      batch: () => mockBatch,
    }));

    const strengthPayload = {
      workouts: [{
        number: 42,
        type: 140, // strength
        startTime: 1700007200,
        endTime: 1700010800,
        durationSec: 3600,
        calories: 300,
        load: 1500,
      }],
    };

    const result = await syncFromApp(strengthPayload);

    expect(result.synced).toBe(1);
    expect(mockCommit).toHaveBeenCalled();
  });
});
