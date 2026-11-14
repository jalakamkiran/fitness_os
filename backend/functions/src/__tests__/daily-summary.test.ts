import {computeDailySummary} from "../services/daily-summary";

jest.mock("firebase-admin", () => {
  const mockGet = jest.fn();
  const mockWhere = jest.fn(() => ({
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
    const mockGet = jest.fn().mockResolvedValue({
      exists: false,
      empty: true,
      docs: [],
    });
    
    admin.firestore().collection().doc().get = mockGet;
    admin.firestore().collection().where().where().get = mockGet;
    
    const summary = await computeDailySummary("2026-11-14");
    
    expect(summary.date).toBe("2026-11-14");
    expect(summary.activeKcal).toBeNull();
    expect(summary.totalKcal).toBeNull();
    expect(summary.sleep).toBeNull();
    expect(summary.workouts).toEqual([]);
  });
  
  it("should include workout data when present", async () => {
    const admin = require("firebase-admin");
    
    const mockWorkoutsGet = jest.fn().mockResolvedValue({
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
    });
    
    const mockEmptyGet = jest.fn().mockResolvedValue({
      exists: false,
      empty: true,
      docs: [],
    });
    
    admin.firestore().collection = jest.fn((name: string) => {
      if (name === "workouts") {
        return {
          where: jest.fn(() => ({
            where: jest.fn(() => ({
              orderBy: jest.fn(() => ({
                get: mockWorkoutsGet,
              })),
            })),
          })),
        };
      }
      return {
        doc: jest.fn(() => ({get: mockEmptyGet})),
        where: jest.fn(() => ({
          where: jest.fn(() => ({
            orderBy: jest.fn(() => ({
              get: mockEmptyGet,
              limit: jest.fn(() => ({get: mockEmptyGet})),
            })),
            get: mockEmptyGet,
          })),
        })),
      };
    });
    
    const summary = await computeDailySummary("2026-11-14");
    
    expect(summary.workouts).toHaveLength(1);
    expect(summary.workouts[0].type).toBe("running");
    expect(summary.workouts[0].activeKcal).toBe(500);
  });
});
