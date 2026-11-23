/**
 * Per-record sync validation (mirrors lib/core/backend/sync_record_validator.dart).
 */

const DAY_KEY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MIN_EPOCH_SEC = Math.floor(new Date("2020-01-01T00:00:00Z").getTime() / 1000);
const MAX_RECORD_BYTES = 200 * 1024;
const STAGE_SPAN_SLACK_MIN = 30;

export const SLEEP_SOFT_QUARANTINE_REASONS = new Set([
  "stage_sum_exceeds_span",
  "bad_stage",
  "spo2_out_of_range",
  "hr_out_of_range",
  "breath_out_of_range",
  "sleep_score_out_of_range",
  "negative_duration",
]);

export type ValidationOutcome = {ok: true} | {ok: false; reason: string};

function tooLarge(body: unknown): ValidationOutcome | null {
  const encoded = Buffer.byteLength(JSON.stringify(body), "utf8");
  if (encoded > MAX_RECORD_BYTES) {
    return {ok: false, reason: "too_large"};
  }
  return null;
}

function dropOutOfRangeEnrich(body: Record<string, unknown>): void {
  const keepIf = (key: string, ok: (v: number) => boolean) => {
    const v = body[key];
    if (typeof v === "number" && !ok(v)) delete body[key];
  };
  keepIf("sleepScore", (v) => v >= 0 && v <= 100);
  keepIf("avgHr", (v) => v >= 25 && v <= 200);
  keepIf("avgSpO2", (v) => v >= 50 && v <= 100);
  keepIf("avgBreathRate", (v) => v >= 0 && v <= 60);
}

function scaleStagesToFit(
    stages: Array<Record<string, unknown>>,
    targetSum: number
): void {
  const sum = stages.reduce(
      (s, st) => s + Math.trunc(st.durationMin as number),
      0
  );
  if (sum <= targetSum) return;
  let allocated = 0;
  for (let i = 0; i < stages.length; i++) {
    const d = Math.trunc(stages[i].durationMin as number);
    if (i === stages.length - 1) {
      stages[i].durationMin = Math.max(0, Math.min(targetSum, targetSum - allocated));
    } else {
      const scaled = Math.floor((d * targetSum) / sum);
      stages[i].durationMin = scaled;
      allocated += scaled;
    }
  }
}

/** Drops sentinel enrich fields and normalizes stages (mutates body). */
export function sanitizeSleepBody(body: Record<string, unknown>): void {
  dropOutOfRangeEnrich(body);

  const begin = body.beginUnix;
  const end = body.endUnix;
  if (typeof begin !== "number" || typeof end !== "number") return;
  const beginI = Math.trunc(begin);
  const endI = Math.trunc(end);
  if (endI <= beginI) return;
  const spanMin = Math.floor((endI - beginI) / 60);

  const stages = body.stages;
  if (!Array.isArray(stages) || stages.length === 0) {
    delete body.stages;
    return;
  }

  const cleaned: Array<Record<string, unknown>> = [];
  for (const s of stages) {
    if (!s || typeof s !== "object") continue;
    const stageObj = s as Record<string, unknown>;
    const dur = stageObj.durationMin;
    const stage = stageObj.stage;
    if (typeof dur !== "number" || dur < 0) continue;
    if (typeof stage !== "number" || ![1, 2, 3, 4].includes(Math.trunc(stage))) {
      continue;
    }
    cleaned.push({...stageObj});
  }

  if (cleaned.length === 0) {
    delete body.stages;
    return;
  }

  let stageSumMin = cleaned.reduce(
      (sum, st) => sum + Math.trunc(st.durationMin as number),
      0
  );
  if (stageSumMin > spanMin + STAGE_SPAN_SLACK_MIN) {
    if (spanMin <= 0) {
      delete body.stages;
      return;
    }
    scaleStagesToFit(cleaned, spanMin);
    stageSumMin = cleaned.reduce(
        (sum, st) => sum + Math.trunc(st.durationMin as number),
        0
    );
    if (stageSumMin > spanMin + STAGE_SPAN_SLACK_MIN) {
      delete body.stages;
      return;
    }
  }
  body.stages = cleaned;
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
  sanitizeSleepBody(body);

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