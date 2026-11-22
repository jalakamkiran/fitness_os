/**
 * Per-record sync validation (mirrors lib/core/backend/sync_record_validator.dart).
 */

const DAY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MIN_EPOCH_SEC = Math.floor(new Date("2020-01-01T00:00:00Z").getTime() / 1000);
const MAX_RECORD_BYTES = 200 * 1024;

export type ValidationOutcome = {ok: true} | {ok: false; reason: string};

function tooLarge(body: unknown): ValidationOutcome | null {
  const encoded = Buffer.byteLength(JSON.stringify(body), "utf8");
  if (encoded > MAX_RECORD_BYTES) {
    return {ok: false, reason: "too_large"};
  }
  return null;
}

export function validateWorkout(
    body: Record<string, unknown>,
    nowSec: number
): ValidationOutcome {
  const size = tooLarge(body);
  if (size) return size;

  const start = body.startTime;
  const end = body.endTime;
  const durationSec = body.durationSec;
  if (typeof start !== "number" || typeof end !== "number" || typeof durationSec !== "number") {
    return {ok: false, reason: "missing_fields"};
  }
  const startI = Math.trunc(start);
  const endI = Math.trunc(end);
  const durI = Math.trunc(durationSec);

  if (startI < MIN_EPOCH_SEC || startI > nowSec + 86400) {
    return {ok: false, reason: "future_time"};
  }
  if (endI <= startI) {
    return {ok: false, reason: "end_before_start"};
  }
  if (durI <= 0 || durI > 86400) {
    return {ok: false, reason: "negative_duration"};
  }
  if (durI > (endI - startI) + 120) {
    return {ok: false, reason: "duration_exceeds_span"};
  }

  for (const key of ["calories", "distanceM", "steps", "hrMin", "hrMax"]) {
    const v = body[key];
    if (v != null && typeof v === "number") {
      if (!Number.isFinite(v)) return {ok: false, reason: "non_finite"};
      if (v < 0) return {ok: false, reason: "negative_value"};
    }
  }

  const hrMin = body.hrMin as number | undefined;
  const hrMax = body.hrMax as number | undefined;
  if (hrMin != null && hrMax != null) {
    if (hrMin < 25 || hrMax > 250 || hrMin > hrMax) {
      return {ok: false, reason: "hr_out_of_range"};
    }
  }

  const cal = body.calories as number | undefined;
  if (cal != null && cal > 10000) {
    return {ok: false, reason: "calories_out_of_range"};
  }
  const dist = body.distanceM as number | undefined;
  if (dist != null && dist > 500000) {
    return {ok: false, reason: "distance_out_of_range"};
  }
  const steps = body.steps as number | undefined;
  if (steps != null && steps > 200000) {
    return {ok: false, reason: "steps_out_of_range"};
  }

  return {ok: true};
}

export function validateSleep(
    body: Record<string, unknown>,
    nowSec: number
): ValidationOutcome {
  const begin = body.beginUnix;
  const end = body.endUnix;
  if (typeof begin !== "number" || typeof end !== "number") {
    return {ok: false, reason: "missing_fields"};
  }
  const beginI = Math.trunc(begin);
  const endI = Math.trunc(end);
  if (endI <= beginI) {
    return {ok: false, reason: "end_before_start"};
  }
  if (endI - beginI > 20 * 3600) {
    return {ok: false, reason: "span_too_long"};
  }
  if (beginI < MIN_EPOCH_SEC || beginI > nowSec + 86400) {
    return {ok: false, reason: "future_time"};
  }

  const stages = body.stages;
  let stageSumMin = 0;
  if (Array.isArray(stages)) {
    for (const s of stages) {
      if (!s || typeof s !== "object") continue;
      const stageObj = s as Record<string, unknown>;
      const dur = stageObj.durationMin;
      const stage = stageObj.stage;
      if (typeof dur === "number" && dur < 0) {
        return {ok: false, reason: "negative_duration"};
      }
      if (typeof stage === "number" && ![1, 2, 3, 4].includes(Math.trunc(stage))) {
        return {ok: false, reason: "bad_stage"};
      }
      if (typeof dur === "number") stageSumMin += Math.trunc(dur);
    }
  }
  const spanMin = Math.floor((endI - beginI) / 60);
  if (stageSumMin > spanMin + 30) {
    return {ok: false, reason: "stage_sum_exceeds_span"};
  }

  const score = body.sleepScore as number | undefined;
  if (score != null && (score < 0 || score > 100)) {
    return {ok: false, reason: "sleep_score_out_of_range"};
  }
  const avgHr = body.avgHr as number | undefined;
  if (avgHr != null && (avgHr < 25 || avgHr > 200)) {
    return {ok: false, reason: "hr_out_of_range"};
  }
  const spo2 = body.avgSpO2 as number | undefined;
  if (spo2 != null && (spo2 < 50 || spo2 > 100)) {
    return {ok: false, reason: "spo2_out_of_range"};
  }
  const breath = body.avgBreathRate as number | undefined;
  if (breath != null && (breath < 0 || breath > 60)) {
    return {ok: false, reason: "breath_out_of_range"};
  }

  return {ok: true};
}

export function validateTotals(
    body: Record<string, unknown>,
    now: Date
): ValidationOutcome {
  const dayKey = body.dayKey;
  if (typeof dayKey !== "string" || !DAY_KEY_PATTERN.test(dayKey)) {
    return {ok: false, reason: "bad_day_key"};
  }
  const parsed = new Date(`${dayKey}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    return {ok: false, reason: "bad_day_key"};
  }
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  if (parsed > tomorrow) {
    return {ok: false, reason: "future_time"};
  }

  const kcal = body.totalKcal as number | undefined;
  if (kcal != null && kcal > 20000) {
    return {ok: false, reason: "calories_out_of_range"};
  }
  const steps = body.steps as number | undefined;
  if (steps != null) {
    if (!Number.isFinite(steps) || steps < 0) {
      return {ok: false, reason: "negative_value"};
    }
    if (steps > 200000) {
      return {ok: false, reason: "steps_out_of_range"};
    }
  }

  return {ok: true};
}

export function validateHr(body: Record<string, unknown>): ValidationOutcome {
  const avg = body.avgHr;
  const max = body.maxHr;
  if (typeof avg !== "number" || typeof max !== "number") {
    return {ok: false, reason: "missing_fields"};
  }
  if (avg < 25 || max > 250 || avg > max) {
    return {ok: false, reason: "hr_out_of_range"};
  }
  return {ok: true};
}
