/* eslint-disable @typescript-eslint/no-var-requires, @typescript-eslint/no-explicit-any */
import {computeDailySummary} from "../services/daily-summary";

jest.mock("firebase-admin", () => {
  const mockGet = jest.fn();
  const mockWhere: any = jest.fn(() => ({
    where: mockWhere,
    orderBy: jest.fn(() => ({
      get: mockGet,
      limit: jest.fn(() => ({get: mockGet})),
    })),
    get: mockGet,
  }));

  const mockCollection = jest.fn(() => ({
    doc: jest.fn(() => ({
      get: mockGet,
    })),
    where: mockWhere,
  }));

  return {
    initializeApp: jest.fn(),
    auth: jest.fn(() => ({
      verifyIdToken: jest.fn(),
    })),
    firestore: jest.fn(() => ({
      collection: mockCollection,
    })),
  };
});

describe("Daily Summary Service", () => {
  it("should compute daily summary with null values for missing data", async () => {
    const admin = require("firebase-admin");
    const mockEmptyDoc = {
      exists: false,
      data: () => null,
    };
    const mockEmptySnapshot = {
      empty: true,
      docs: [],
    };

    admin.firestore = jest.fn(() => ({
      collection: jest.fn(() => ({
        doc: jest.fn(() => ({
          get: jest.fn().mockResolvedValue(mockEmptyDoc),
        })),
        where: jest.fn(() => ({
          where: jest.fn(() => ({
            orderBy: jest.fn(() => ({
              get: jest.fn().mockResolvedValue(mockEmptySnapshot),
              limit: jest.fn(() => ({
                get: jest.fn().mockResolvedValue(mockEmptySnapshot),
              })),
            })),
            get: jest.fn().mockResolvedValue(mockEmptySnapshot),
          })),
        })),
      })),
    }));

    const summary = await computeDailySummary("2026-11-14");

    expect(summary.date).toBe("2026-11-14");
    expect(summary.activeKcal).toBeNull();
    expect(summary.totalKcal).toBeNull();
    expect(summary.sleep).toBeNull();
    expect(summary.workouts).toEqual([]);
  });

  it("should include workout data when present", async () => {
    const admin = require("firebase-admin");

    const mockEmptyDoc = {
      exists: false,
      data: () => null,
    };

    const mockEmptySnapshot = {
      empty: true,
      docs: [],
    };

    const mockWorkoutsSnapshot = {
      empty: false,
      docs: [{
        id: "workout_1",
        data: () => ({
          type: "running",
          startTime: "2026-11-14T06:00:00+05:30",
          endTime: "2026-11-14T07:00:00+05:30",
          durationMin: 60,
          activeKcal: 500,
          avgHr: 150,
          maxHr: 180,
          syncedAt: "2026-11-14T07:05:00+05:30",
        }),
      }],
    };

    admin.firestore = jest.fn(() => ({
      collection: jest.fn((name: string) => {
        if (name === "workouts") {
          return {
            where: jest.fn(() => ({
              where: jest.fn(() => ({
                orderBy: jest.fn(() => ({
                  get: jest.fn().mockResolvedValue(mockWorkoutsSnapshot),
                })),
              })),
            })),
          };
        }
        return {
          doc: jest.fn(() => ({
            get: jest.fn().mockResolvedValue(mockEmptyDoc),
          })),
          where: jest.fn(() => ({
            where: jest.fn(() => ({
              orderBy: jest.fn(() => ({
                get: jest.fn().mockResolvedValue(mockEmptySnapshot),
                limit: jest.fn(() => ({
                  get: jest.fn().mockResolvedValue(mockEmptySnapshot),
                })),
              })),
              get: jest.fn().mockResolvedValue(mockEmptySnapshot),
            })),
          })),
        };
      }),
    }));

    const summary = await computeDailySummary("2026-11-14");

    expect(summary.workouts).toHaveLength(1);
    expect(summary.workouts[0].type).toBe("running");
    expect(summary.workouts[0].activeKcal).toBe(500);
  });
});
