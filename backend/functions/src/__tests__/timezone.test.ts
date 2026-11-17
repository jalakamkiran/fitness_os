import {istQueryBounds, istToDate, msToIST} from "../services/timezone";

describe("istQueryBounds", () => {
  const date = "2026-11-17";

  it("uses +05:30 bounds for an IST calendar day (not UTC Z)", () => {
    const {start, end} = istQueryBounds(date, date);

    expect(start).toBe("2026-11-17T00:00:00+05:30");
    expect(end).toBe("2026-11-17T23:59:59+05:30");
    expect(start).not.toContain("Z");
    expect(end).not.toContain("Z");
  });

  it("includes a 19:00 IST workout within same-day query bounds", () => {
    const {start, end} = istQueryBounds(date, date);
    const eveningWorkout = "2026-11-17T19:00:32+05:30";

    expect(eveningWorkout >= start).toBe(true);
    expect(eveningWorkout <= end).toBe(true);

    const eveningMs = istToDate(eveningWorkout).getTime();
    const startMs = istToDate(start).getTime();
    const endMs = istToDate(end).getTime();
    expect(eveningMs).toBeGreaterThanOrEqual(startMs);
    expect(eveningMs).toBeLessThanOrEqual(endMs);
  });

  it("excludes evening IST workouts under legacy UTC Z upper bound", () => {
    const endUtcZ = new Date(
        new Date(date + "T23:59:59+05:30").getTime()
    ).toISOString();
    const eveningWorkout = "2026-11-17T19:00:32+05:30";

    expect(eveningWorkout <= endUtcZ).toBe(false);
    expect(msToIST(new Date(date + "T23:59:59+05:30").getTime())).toBe(
        "2026-11-17T23:59:59+05:30"
    );
  });
});
