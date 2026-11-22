/**
 * Per-set HR analysis from workout HR streams (5 s samples, strength type 140).
 */
import * as admin from "firebase-admin";
import {SetHrRecord, StrengthSetRecord, WorkoutHrStreamRecord} from "../models/types";
import {msToIST, unixToIST} from "./timezone";

export const HR_MIN_BPM = 35;
export const HR_MAX_BPM = 220;
export const IRREGULAR_COUNT_RATIO = 0.15;
export const MAX_STREAM_POINTS = 2880;
export const WORKOUT_LINK_BEFORE_MS = 60_000;
export const WORKOUT_LINK_AFTER_MS = 120_000;
export const EFFORT_BEFORE_MS = 60_000;
export const EFFORT_AFTER_MS = 15_000;
export const BASELINE_SEC = 60;
export const RECOVERY_BASELINE_MARGIN = 10;

export interface WorkoutWindow {
  id: string;
  type: string;
  startMs: number;
  endMs: number;
}

export function filterBpm(bpm: number[]): Array<number | null> {
  return bpm.map((v) => (v >= HR_MIN_BPM && v <= HR_MAX_BPM ? v : null));
}

export function sampleTimeMs(
    stream: Pick<WorkoutHrStreamRecord, "startMs" | "intervalSec" | "clockSkewMs">,
    index: number
): number {
  const skew = stream.clockSkewMs ?? 0;
  return stream.startMs + index * stream.intervalSec * 1000 - skew;
}

export function bpmAtOrNearest(
    stream: WorkoutHrStreamRecord,
    timeMs: number
): number | null {
  const filtered = filterBpm(stream.bpm);
  let bestIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < stream.bpm.length; i++) {
    const t = sampleTimeMs(stream, i);
    const dist = Math.abs(t - timeMs);
    if (dist < bestDist) {
      bestDist = dist;
      bestIdx = i;
    }
  }
  const val = filtered[bestIdx];
  return val;
}

export function streamRegularity(
    stream: WorkoutHrStreamRecord,
    durationSec: number | null
): {ok: boolean; reason?: string} {
  if (stream.bpm.length > MAX_STREAM_POINTS) {
    return {ok: false, reason: "stream_too_long"};
  }
  if (durationSec != null && durationSec > 0) {
    const expected = Math.round(durationSec / stream.intervalSec);
    if (expected > 0) {
      const ratio = Math.abs(stream.bpm.length - expected) / expected;
      if (ratio > IRREGULAR_COUNT_RATIO) {
        return {ok: false, reason: "paused_or_irregular"};
      }
    }
  }
  return {ok: true};
}

export function computeBaselineHr(
    stream: WorkoutHrStreamRecord,
    sets: StrengthSetRecord[],
    workoutStartMs: number
): number | null {
  const filtered = filterBpm(stream.bpm);
  const firstSetMs = sets.length > 0 ?
    Math.min(...sets.map((s) => s.loggedAtMs)) :
    Infinity;
  const baselineEndMs = workoutStartMs + BASELINE_SEC * 1000;

  if (firstSetMs <= baselineEndMs) {
    const vals: number[] = [];
    for (let i = 0; i < stream.bpm.length; i++) {
      const v = filtered[i];
      if (v != null) vals.push(v);
    }
    return vals.length > 0 ? Math.min(...vals) + 5 : null;
  }

  const vals: number[] = [];
  for (let i = 0; i < stream.bpm.length; i++) {
    const t = sampleTimeMs(stream, i);
    if (t >= workoutStartMs && t < baselineEndMs) {
      const v = filtered[i];
      if (v != null) vals.push(v);
    }
  }
  if (vals.length === 0) return null;
  const sorted = [...vals].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ?
    (sorted[mid - 1] + sorted[mid]) / 2 :
    sorted[mid];
}

function samplesInRange(
    stream: WorkoutHrStreamRecord,
    fromMs: number,
    toMs: number
): Array<{t: number; bpm: number}> {
  const filtered = filterBpm(stream.bpm);
  const out: Array<{t: number; bpm: number}> = [];
  for (let i = 0; i < stream.bpm.length; i++) {
    const t = sampleTimeMs(stream, i);
    if (t >= fromMs && t <= toMs) {
      const v = filtered[i];
      if (v != null) out.push({t, bpm: v});
    }
  }
  return out;
}

export function linkSetToWorkout(
    set: StrengthSetRecord,
    workouts: WorkoutWindow[]
): string | null {
  for (const w of workouts) {
    if (w.type !== "strength" && w.type !== "140") {
      const typeNum = parseInt(w.type, 10);
      if (typeNum !== 140) continue;
    }
    const winStart = w.startMs - WORKOUT_LINK_BEFORE_MS;
    const winEnd = w.endMs + WORKOUT_LINK_AFTER_MS;
    if (set.loggedAtMs >= winStart && set.loggedAtMs <= winEnd) {
      return w.id;
    }
  }
  for (const w of workouts) {
    const winStart = w.startMs - WORKOUT_LINK_BEFORE_MS;
    const winEnd = w.endMs + WORKOUT_LINK_AFTER_MS;
    if (set.loggedAtMs >= winStart && set.loggedAtMs <= winEnd) {
      return w.id;
    }
  }
  return null;
}

export function istStringToMs(ist: string): number {
  return new Date(ist).getTime();
}

export function workoutDocToWindow(
    id: string,
    data: FirebaseFirestore.DocumentData
): WorkoutWindow {
  const startMs = istStringToMs(data.startTime as string);
  const endMs = istStringToMs(data.endTime as string);
  return {
    id,
    type: String(data.type),
    startMs,
    endMs,
  };
}

export function computeSetHrRow(
    stream: WorkoutHrStreamRecord,
    sets: StrengthSetRecord[],
    setIndex: number,
    baselineHr: number | null,
    workoutStartMs: number,
    irregular: boolean
): SetHrRecord {
  const set = sets[setIndex];
  const base: SetHrRecord = {
    setId: set.id,
    windowStartMs: 0,
    windowEndMs: 0,
    avgHr: null,
    maxHr: null,
    hrAtEnd: null,
    drop30: null,
    drop60: null,
    recoverySec: null,
    baselineHr,
    samples: 0,
    reason: irregular ? "paused_or_irregular" : null,
  };

  if (irregular) {
    return base;
  }

  const prev = setIndex > 0 ? sets[setIndex - 1] : null;
  const windowStart = prev ?
    prev.loggedAtMs :
    Math.max(workoutStartMs, set.notifiedAtMs - 30_000);
  const windowEnd = set.loggedAtMs + EFFORT_AFTER_MS;
  base.windowStartMs = windowStart;
  base.windowEndMs = windowEnd;

  const windowSamples = samplesInRange(stream, windowStart, windowEnd);
  const effortStart = set.loggedAtMs - EFFORT_BEFORE_MS;
  const effortEnd = set.loggedAtMs + EFFORT_AFTER_MS;
  const effortSamples = samplesInRange(
      stream,
      Math.max(effortStart, windowStart),
      Math.min(effortEnd, windowEnd)
  );

  if (effortSamples.length < 3) {
    base.reason = "insufficient_samples";
    base.samples = effortSamples.length;
    return base;
  }

  base.samples = effortSamples.length;
  base.maxHr = Math.max(...windowSamples.map((s) => s.bpm));
  base.avgHr = Math.round(
      effortSamples.reduce((sum, s) => sum + s.bpm, 0) / effortSamples.length
  );
  base.hrAtEnd = bpmAtOrNearest(stream, set.loggedAtMs);

  const peak = Math.max(
      ...samplesInRange(stream, set.loggedAtMs, set.loggedAtMs + EFFORT_AFTER_MS)
          .map((s) => s.bpm),
      base.maxHr ?? 0
  );

  const nextBoundary = setIndex < sets.length - 1 ?
    sets[setIndex + 1].notifiedAtMs :
    set.loggedAtMs + 120_000;

  const at30 = bpmAtOrNearest(stream, set.loggedAtMs + 30_000);
  const at60 = bpmAtOrNearest(stream, set.loggedAtMs + 60_000);
  if (at30 != null && set.loggedAtMs + 30_000 < nextBoundary) {
    base.drop30 = peak - at30;
  }
  if (at60 != null && set.loggedAtMs + 60_000 < nextBoundary) {
    base.drop60 = peak - at60;
  }

  if (baselineHr != null) {
    const target = baselineHr + RECOVERY_BASELINE_MARGIN;
    const recoverySamples = samplesInRange(
        stream,
        set.loggedAtMs,
        nextBoundary
    ).filter((s) => s.t > set.loggedAtMs);
    for (const s of recoverySamples) {
      if (s.bpm <= target) {
        base.recoverySec = Math.round((s.t - set.loggedAtMs) / 1000);
        break;
      }
    }
  }

  return base;
}

export function computeAllSetHr(
    stream: WorkoutHrStreamRecord,
    sets: StrengthSetRecord[],
    workoutStartMs: number,
    durationSec: number | null
): SetHrRecord[] {
  const regularity = streamRegularity(stream, durationSec);
  const irregular = !regularity.ok;
  const sorted = [...sets].sort((a, b) => a.loggedAtMs - b.loggedAtMs);
  const baseline = irregular ?
    null :
    computeBaselineHr(stream, sorted, workoutStartMs);

  return sorted.map((_, idx) =>
    computeSetHrRow(stream, sorted, idx, baseline, workoutStartMs, irregular)
  );
}

export async function recomputeSetHrForWorkout(
    workoutId: string
): Promise<number> {
  const db = admin.firestore();
  const streamRef = db.collection("workoutHrStreams").doc(workoutId);
  const streamSnap = await streamRef.get();
  if (!streamSnap.exists) return 0;

  const stream = streamSnap.data() as WorkoutHrStreamRecord;

  const workoutSnap = await db.collection("workouts").doc(workoutId).get();
  let durationSec: number | null = null;
  let workoutStartMs = stream.startMs;
  if (workoutSnap.exists) {
    const w = workoutSnap.data()!;
    workoutStartMs = istStringToMs(w.startTime as string);
    const endMs = istStringToMs(w.endTime as string);
    durationSec = Math.round((endMs - workoutStartMs) / 1000);
  }

  const winStart = workoutStartMs - WORKOUT_LINK_BEFORE_MS;
  const winEnd = workoutStartMs + (durationSec ?? 0) * 1000 + WORKOUT_LINK_AFTER_MS;

  const setsSnap = await db.collection("strengthSets")
      .where("loggedAtMs", ">=", winStart)
      .where("loggedAtMs", "<=", winEnd)
      .get();

  const sets = setsSnap.docs.map((d) => d.data() as StrengthSetRecord);
  const sessionIds = [...new Set(sets.map((s) => s.sessionId))];

  const allSets: StrengthSetRecord[] = [...sets];
  for (const sid of sessionIds) {
    const more = await db.collection("strengthSets")
        .where("sessionId", "==", sid)
        .get();
    for (const doc of more.docs) {
      const rec = doc.data() as StrengthSetRecord;
      if (!allSets.find((s) => s.id === rec.id)) {
        allSets.push(rec);
      }
    }
  }

  const linkedSets = allSets.filter(
      (s) => s.workoutId === workoutId ||
        linkSetToWorkout(s, [{
          id: workoutId,
          type: "strength",
          startMs: workoutStartMs,
          endMs: workoutStartMs + (durationSec ?? 0) * 1000,
        }]) === workoutId
  );

  if (linkedSets.length === 0) return 0;

  const rows = computeAllSetHr(
      stream,
      linkedSets,
      workoutStartMs,
      durationSec
  );

  const batch = db.batch();
  for (const row of rows) {
    batch.set(db.collection("setHr").doc(row.setId), row, {merge: true});
    const setRef = db.collection("strengthSets").doc(row.setId);
    batch.set(setRef, {workoutId}, {merge: true});
  }
  await batch.commit();
  return rows.length;
}

export function workoutStartMsFromStream(stream: WorkoutHrStreamRecord): number {
  return stream.startMs;
}

/** For sync: map app payload (no syncedAt) to stored record */
export function toWorkoutHrStreamRecord(
    input: Omit<WorkoutHrStreamRecord, "syncedAt">,
    syncedAt: string
): WorkoutHrStreamRecord {
  return {...input, syncedAt};
}

export function msToLoggedAt(ms: number): string {
  return msToIST(ms);
}

export function unixWorkoutToMs(startTimeUnix: number): number {
  return startTimeUnix * 1000;
}

export {unixToIST};
