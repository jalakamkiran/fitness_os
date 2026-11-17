import * as admin from "firebase-admin";
import {
  PlannedExercise,
  PlannedSessionRecord,
  SetHrRecord,
  StrengthSetRecord,
} from "../models/types";
import {getCurrentISTDate, msToIST} from "./timezone";
import {linkSetToWorkout, msToLoggedAt, recomputeSetHrForWorkout, workoutDocToWindow} from "./set-hr";

const MAX_EXERCISES = 20;
const MIN_SETS = 1;
const MAX_SETS = 10;
const MIN_KG = 0;
const MAX_KG = 500;
const MIN_REPS = 1;
const MAX_REPS = 50;
const MIN_REST = 0;
const MAX_REST = 900;
const MAX_NAME_LEN = 60;
const MAX_BATCH_SETS = 200;
const STRENGTH_TYPE = 140;

export class ValidationError extends Error {
  constructor(public field: string, message: string) {
    super(message);
    this.name = "ValidationError";
  }
}

function validateExercise(ex: PlannedExercise, index: number): void {
  const prefix = `exercises[${index}]`;
  if (!ex.exerciseId || typeof ex.exerciseId !== "string") {
    throw new ValidationError(`${prefix}.exerciseId`, "exerciseId required");
  }
  if (!ex.name || typeof ex.name !== "string") {
    throw new ValidationError(`${prefix}.name`, "name required");
  }
  if (ex.name.length > MAX_NAME_LEN) {
    throw new ValidationError(`${prefix}.name`, `name must be ≤ ${MAX_NAME_LEN} chars`);
  }
  if (!Number.isInteger(ex.sets) || ex.sets < MIN_SETS || ex.sets > MAX_SETS) {
    throw new ValidationError(`${prefix}.sets`, `sets must be ${MIN_SETS}–${MAX_SETS}`);
  }
  if (typeof ex.targetKg !== "number" || ex.targetKg < MIN_KG || ex.targetKg > MAX_KG) {
    throw new ValidationError(`${prefix}.targetKg`, `targetKg must be ${MIN_KG}–${MAX_KG}`);
  }
  if (!Number.isInteger(ex.targetReps) || ex.targetReps < MIN_REPS || ex.targetReps > MAX_REPS) {
    throw new ValidationError(`${prefix}.targetReps`, `targetReps must be ${MIN_REPS}–${MAX_REPS}`);
  }
  if (!Number.isInteger(ex.restSec) || ex.restSec < MIN_REST || ex.restSec > MAX_REST) {
    throw new ValidationError(`${prefix}.restSec`, `restSec must be ${MIN_REST}–${MAX_REST}`);
  }
}

export function validatePlannedSessionInput(
    body: Partial<PlannedSessionRecord>
): void {
  if (!body.id || typeof body.id !== "string") {
    throw new ValidationError("id", "id required");
  }
  if (!body.title || typeof body.title !== "string") {
    throw new ValidationError("title", "title required");
  }
  if (!body.plannedFor || !/^\d{4}-\d{2}-\d{2}$/.test(body.plannedFor)) {
    throw new ValidationError("plannedFor", "plannedFor must be YYYY-MM-DD");
  }
  if (!body.exercises || !Array.isArray(body.exercises)) {
    throw new ValidationError("exercises", "exercises required");
  }
  if (body.exercises.length < 1 || body.exercises.length > MAX_EXERCISES) {
    throw new ValidationError("exercises", `exercises count must be 1–${MAX_EXERCISES}`);
  }
  const source = body.source;
  if (source !== "arjun" && source !== "manual" && source !== "debug") {
    throw new ValidationError("source", "source must be arjun, manual, or debug");
  }
  const status = body.status;
  if (status && !["planned", "in_progress", "done", "skipped"].includes(status)) {
    throw new ValidationError("status", "invalid status");
  }
  body.exercises.forEach((ex, i) => validateExercise(ex, i));
}

export function validateStrengthSet(set: Partial<StrengthSetRecord>, index: number): void {
  const p = `sets[${index}]`;
  const required = [
    "id", "sessionId", "exerciseId", "exercise", "setIndex",
    "plannedKg", "plannedReps", "actualKg", "actualReps",
    "notifiedAtMs", "loggedAtMs", "source",
  ] as const;
  for (const key of required) {
    if (set[key] === undefined || set[key] === null) {
      throw new ValidationError(`${p}.${key}`, `${key} required`);
    }
  }
  if (set.source !== "watch_reply" && set.source !== "watch_ack") {
    throw new ValidationError(`${p}.source`, "invalid source");
  }
  if (typeof set.failed !== "boolean" || typeof set.unknownReply !== "boolean") {
    throw new ValidationError(`${p}.failed`, "failed and unknownReply must be booleans");
  }
}

export async function upsertPlannedSession(
    body: Partial<PlannedSessionRecord>
): Promise<PlannedSessionRecord> {
  validatePlannedSessionInput(body);
  const db = admin.firestore();
  const now = new Date().toISOString();
  const existing = await db.collection("plannedSessions").doc(body.id!).get();
  const createdAt = existing.exists ?
    (existing.data()!.createdAt as string) :
    now;

  const record: PlannedSessionRecord = {
    id: body.id!,
    title: body.title!,
    plannedFor: body.plannedFor!,
    exercises: body.exercises as PlannedExercise[],
    source: body.source as PlannedSessionRecord["source"],
    status: (body.status ?? "planned") as PlannedSessionRecord["status"],
    createdAt,
    updatedAt: now,
  };

  await db.collection("plannedSessions").doc(record.id).set(record, {merge: true});
  return record;
}

export async function getNextPlannedSession(): Promise<PlannedSessionRecord | null> {
  const db = admin.firestore();
  const today = getCurrentISTDate();

  const snapshot = await db.collection("plannedSessions")
      .where("status", "in", ["planned", "in_progress"])
      .where("plannedFor", ">=", today)
      .orderBy("plannedFor", "asc")
      .limit(1)
      .get();

  if (snapshot.empty) return null;
  return snapshot.docs[0].data() as PlannedSessionRecord;
}

async function updateSessionStatusFromSets(sessionId: string): Promise<void> {
  const db = admin.firestore();
  const sessionRef = db.collection("plannedSessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) return;

  const session = sessionSnap.data() as PlannedSessionRecord;
  const setsSnap = await db.collection("strengthSets")
      .where("sessionId", "==", sessionId)
      .get();

  const loggedIds = new Set(setsSnap.docs.map((d) => d.id));
  let expected = 0;
  for (const ex of session.exercises) {
    for (let i = 1; i <= ex.sets; i++) {
      expected++;
      const id = `${sessionId}_${ex.exerciseId}_${i}`;
      if (!loggedIds.has(id)) {
        await sessionRef.set({
          status: "in_progress",
          updatedAt: new Date().toISOString(),
        }, {merge: true});
        return;
      }
    }
  }

  if (expected > 0 && loggedIds.size >= expected) {
    await sessionRef.set({
      status: "done",
      updatedAt: new Date().toISOString(),
    }, {merge: true});
  } else if (loggedIds.size > 0) {
    await sessionRef.set({
      status: "in_progress",
      updatedAt: new Date().toISOString(),
    }, {merge: true});
  }
}

async function relinkSetsToWorkouts(sets: StrengthSetRecord[]): Promise<void> {
  const db = admin.firestore();
  if (sets.length === 0) return;

  const minMs = Math.min(...sets.map((s) => s.loggedAtMs)) - 120_000;
  const maxMs = Math.max(...sets.map((s) => s.loggedAtMs)) + 120_000;
  const minIst = msToIST(minMs);
  const maxIst = msToIST(maxMs);

  const wSnap = await db.collection("workouts")
      .where("startTime", ">=", minIst)
      .where("startTime", "<=", maxIst)
      .get();

  const workouts = wSnap.docs
      .map((d) => workoutDocToWindow(d.id, d.data()))
      .filter((w) => {
        const type = w.type;
        return type === "strength" || type === String(STRENGTH_TYPE) ||
          parseInt(type, 10) === STRENGTH_TYPE;
      });

  const batch = db.batch();
  for (const set of sets) {
    const wid = linkSetToWorkout(set, workouts);
    if (wid && wid !== set.workoutId) {
      batch.set(
          db.collection("strengthSets").doc(set.id),
          {workoutId: wid},
          {merge: true}
      );
    }
  }
  await batch.commit();
}

export async function batchUpsertStrengthSets(
    sets: Partial<StrengthSetRecord>[]
): Promise<{synced: number}> {
  if (!Array.isArray(sets)) {
    throw new ValidationError("sets", "sets must be an array");
  }
  if (sets.length === 0) {
    return {synced: 0};
  }
  if (sets.length > MAX_BATCH_SETS) {
    throw new ValidationError("sets", `max ${MAX_BATCH_SETS} sets per batch`);
  }

  sets.forEach((s, i) => validateStrengthSet(s, i));

  const db = admin.firestore();
  const syncedAt = new Date().toISOString();
  const batch = db.batch();
  const records: StrengthSetRecord[] = [];
  const workoutIds = new Set<string>();

  for (const raw of sets) {
    const record: StrengthSetRecord = {
      id: raw.id!,
      sessionId: raw.sessionId!,
      exerciseId: raw.exerciseId!,
      exercise: raw.exercise!,
      setIndex: raw.setIndex!,
      plannedKg: raw.plannedKg!,
      plannedReps: raw.plannedReps!,
      actualKg: raw.actualKg!,
      actualReps: raw.actualReps!,
      failed: raw.failed!,
      replyText: raw.replyText ?? null,
      unknownReply: raw.unknownReply!,
      notifiedAtMs: raw.notifiedAtMs!,
      loggedAtMs: raw.loggedAtMs!,
      loggedAt: raw.loggedAt ?? msToLoggedAt(raw.loggedAtMs!),
      source: raw.source!,
      workoutId: raw.workoutId ?? null,
      syncedAt,
    };
    records.push(record);
    batch.set(db.collection("strengthSets").doc(record.id), record, {merge: true});
    if (record.workoutId) workoutIds.add(record.workoutId);
  }

  await batch.commit();

  await relinkSetsToWorkouts(records);

  const sessionIds = [...new Set(records.map((r) => r.sessionId))];
  for (const sid of sessionIds) {
    await updateSessionStatusFromSets(sid);
  }

  for (const rec of records) {
    const snap = await db.collection("strengthSets").doc(rec.id).get();
    const wid = snap.data()?.workoutId as string | null;
    if (wid) workoutIds.add(wid);
  }

  for (const wid of workoutIds) {
    await recomputeSetHrForWorkout(wid);
  }

  return {synced: records.length};
}

export function epley1Rm(kg: number, reps: number): number | null {
  if (reps < 1 || reps > 12) return null;
  return kg * (1 + reps / 30);
}

export function isoWeekKeyIST(dateYmd: string): string {
  const d = new Date(dateYmd + "T12:00:00+05:30");
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil(
      (((d.getTime() - yearStart.getTime()) / 86400000) + 1) / 7
  );
  return `${d.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;
}

export interface ProgressionWeekRow {
  week: string;
  exercise: string;
  sets: number;
  reps: number;
  volumeKg: number;
  topSetKg: number;
  e1rm: number | null;
  avgSetHr: number | null;
  avgRecoverySec: number | null;
  volumeDeltaPct: number | null;
  e1rmDeltaPct: number | null;
}

export async function getProgression(weeks: number): Promise<ProgressionWeekRow[]> {
  const db = admin.firestore();
  const clamped = Math.min(26, Math.max(1, weeks));
  const today = getCurrentISTDate();
  const todayDate = new Date(today + "T12:00:00+05:30");
  const fromDate = new Date(todayDate);
  fromDate.setUTCDate(fromDate.getUTCDate() - clamped * 7);

  const setsSnap = await db.collection("strengthSets")
      .where("loggedAt", ">=", msToIST(fromDate.getTime()))
      .get();

  const setIds = setsSnap.docs.map((d) => d.id);
  const hrBySet = new Map<string, SetHrRecord>();
  if (setIds.length > 0) {
    const chunks: string[][] = [];
    for (let i = 0; i < setIds.length; i += 30) {
      chunks.push(setIds.slice(i, i + 30));
    }
    for (const chunk of chunks) {
      const hrSnap = await db.collection("setHr")
          .where(admin.firestore.FieldPath.documentId(), "in", chunk)
          .get();
      for (const doc of hrSnap.docs) {
        hrBySet.set(doc.id, doc.data() as SetHrRecord);
      }
    }
  }

  type Agg = {
    exercise: string;
    sets: number;
    reps: number;
    volumeKg: number;
    topSetKg: number;
    e1rmMax: number;
    hrSum: number;
    hrCount: number;
    recSum: number;
    recCount: number;
  };

  const byWeekExercise = new Map<string, Agg>();

  for (const doc of setsSnap.docs) {
    const s = doc.data() as StrengthSetRecord;
    const week = isoWeekKeyIST(s.loggedAt.slice(0, 10));
    const key = `${week}\0${s.exercise}`;
    let agg = byWeekExercise.get(key);
    if (!agg) {
      agg = {
        exercise: s.exercise,
        sets: 0,
        reps: 0,
        volumeKg: 0,
        topSetKg: 0,
        e1rmMax: 0,
        hrSum: 0,
        hrCount: 0,
        recSum: 0,
        recCount: 0,
      };
      byWeekExercise.set(key, agg);
    }
    agg.sets += 1;
    agg.reps += s.actualReps;
    if (!s.failed) {
      agg.volumeKg += s.actualKg * s.actualReps;
      agg.topSetKg = Math.max(agg.topSetKg, s.actualKg);
      const e1 = epley1Rm(s.actualKg, s.actualReps);
      if (e1 != null) agg.e1rmMax = Math.max(agg.e1rmMax, e1);
    }
    const hr = hrBySet.get(s.id);
    if (hr?.avgHr != null) {
      agg.hrSum += hr.avgHr;
      agg.hrCount += 1;
    }
    if (hr?.recoverySec != null) {
      agg.recSum += hr.recoverySec;
      agg.recCount += 1;
    }
  }

  const rows: ProgressionWeekRow[] = [];
  const sortedKeys = [...byWeekExercise.keys()].sort();

  const prevByExercise = new Map<string, {volume: number; e1rm: number}>();

  for (const key of sortedKeys) {
    const [week] = key.split("\0");
    const agg = byWeekExercise.get(key)!;
    const e1rm = agg.e1rmMax > 0 ? Math.round(agg.e1rmMax * 10) / 10 : null;
    const prev = prevByExercise.get(agg.exercise);
    let volumeDeltaPct: number | null = null;
    let e1rmDeltaPct: number | null = null;
    if (prev && prev.volume > 0) {
      volumeDeltaPct = Math.round(
          ((agg.volumeKg - prev.volume) / prev.volume) * 1000
      ) / 10;
    }
    if (prev && prev.e1rm > 0 && e1rm != null) {
      e1rmDeltaPct = Math.round(((e1rm - prev.e1rm) / prev.e1rm) * 1000) / 10;
    }
    prevByExercise.set(agg.exercise, {
      volume: agg.volumeKg,
      e1rm: e1rm ?? prev?.e1rm ?? 0,
    });

    rows.push({
      week,
      exercise: agg.exercise,
      sets: agg.sets,
      reps: agg.reps,
      volumeKg: Math.round(agg.volumeKg * 10) / 10,
      topSetKg: agg.topSetKg,
      e1rm,
      avgSetHr: agg.hrCount > 0 ?
        Math.round(agg.hrSum / agg.hrCount) :
        null,
      avgRecoverySec: agg.recCount > 0 ?
        Math.round(agg.recSum / agg.recCount) :
        null,
      volumeDeltaPct,
      e1rmDeltaPct,
    });
  }

  return rows;
}

export async function getSessionDetail(sessionId: string): Promise<{
  session: PlannedSessionRecord | null;
  sets: StrengthSetRecord[];
  setHr: SetHrRecord[];
} | null> {
  const db = admin.firestore();
  const sessionSnap = await db.collection("plannedSessions").doc(sessionId).get();
  if (!sessionSnap.exists) return null;

  const setsSnap = await db.collection("strengthSets")
      .where("sessionId", "==", sessionId)
      .orderBy("loggedAtMs", "asc")
      .get();

  const sets = setsSnap.docs.map((d) => d.data() as StrengthSetRecord);
  const setHr: SetHrRecord[] = [];
  for (const s of sets) {
    const hrSnap = await db.collection("setHr").doc(s.id).get();
    if (hrSnap.exists) {
      setHr.push(hrSnap.data() as SetHrRecord);
    }
  }

  return {
    session: sessionSnap.data() as PlannedSessionRecord,
    sets,
    setHr,
  };
}
