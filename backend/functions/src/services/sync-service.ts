import * as admin from "firebase-admin";
import {
  WorkoutRecord,
  SleepRecord,
  DailyTotalsRecord,
  HeartRateRecord,
  HrvRecord,
  WeightRecord,
  MealRecord,
} from "../models/types";
import {unixToIST, msToIST, istQueryBounds, getCurrentISTDate} from "./timezone";
import {mapWorkoutType} from "../models/workout-type-mapping";
import {sendSyncWebhook} from "./webhook-notifier";
import {
  validateWorkout,
  validateSleep,
  validateTotals,
  validateHr,
} from "./sync-validation";

const FIRESTORE_BATCH_LIMIT = 400;

export interface AppSyncPayload {
  workouts?: Array<{
    number: number;
    type: number;
    startTime: number;
    endTime: number;
    durationSec: number;
    calories?: number;
    distanceM?: number;
    steps?: number;
    hrMin?: number;
    hrMax?: number;
    laps?: number;
    strokes?: number;
    avgSwolf?: number;
    poolLength?: number;
    load?: number;
    aerobicEffect?: number;
    anaerobicEffect?: number;
    recoveryTime?: number;
    contentHash?: string;
    clientId?: string;
  }>;
  sleep?: Array<{
    beginUnix: number;
    endUnix: number;
    stages?: Array<{
      timestampUnix: number;
      durationMin: number;
      stage: number;
    }>;
    sleepScore?: number;
    avgHr?: number;
    avgHrv?: number;
    avgBreathRate?: number;
    avgSpO2?: number;
    contentHash?: string;
    clientId?: string;
  }>;
  dailyTotals?: Array<{
    dayKey: string;
    activeKcal?: number;
    totalKcal?: number;
    steps?: number;
    distanceM?: number;
    contentHash?: string;
    clientId?: string;
  }>;
  heartRate?: Array<{
    dayKey: string;
    restingHr?: number;
    avgHr?: number;
    maxHr?: number;
    contentHash?: string;
    clientId?: string;
  }>;
  hrv?: Array<{
    dayKey: string;
    hrvMs?: number;
    contentHash?: string;
    clientId?: string;
  }>;
  weight?: Array<{
    timestampMs: number;
    weightKg: number;
    contentHash?: string;
    clientId?: string;
  }>;
  meals?: Array<{
    id: string;
    timestampMs: number;
    items: string[];
    grams: number[];
    kcal: number;
    protein?: number;
    contentHash?: string;
    clientId?: string;
  }>;
  meta?: Record<string, unknown>;
}

export interface SyncRejectedItem {
  id: string;
  kind: string;
  reason: string;
}

export interface SyncFromAppResult {
  accepted: Record<string, string[]>;
  rejected: SyncRejectedItem[];
  checksumVerified: boolean;
  synced: number;
}

export interface ManifestEntry {
  id: string;
  contentHash: string | null;
  clientId: string | null;
}

export interface SyncManifest {
  workouts: ManifestEntry[];
  sleep: ManifestEntry[];
  dailyTotals: ManifestEntry[];
  heartRate: ManifestEntry[];
}

type WriteOp = {
  ref: FirebaseFirestore.DocumentReference;
  data: FirebaseFirestore.DocumentData;
};

function emptyAccepted(): Record<string, string[]> {
  return {
    workouts: [],
    sleep: [],
    dailyTotals: [],
    heartRate: [],
  };
}

function pushAccepted(
    accepted: Record<string, string[]>,
    kind: string,
    id: string
): void {
  if (!accepted[kind]) accepted[kind] = [];
  accepted[kind].push(id);
}

async function commitWriteOps(
    db: admin.firestore.Firestore,
    ops: WriteOp[]
): Promise<void> {
  for (let i = 0; i < ops.length; i += FIRESTORE_BATCH_LIMIT) {
    const batch = db.batch();
    const slice = ops.slice(i, i + FIRESTORE_BATCH_LIMIT);
    for (const op of slice) {
      batch.set(op.ref, op.data, {merge: true});
    }
    await batch.commit();
  }
}

function istStartTimeToUnix(ist: string): number {
  return Math.floor(new Date(ist).getTime() / 1000);
}

async function resolveWorkoutDocId(
    db: admin.firestore.Firestore,
    workout: NonNullable<AppSyncPayload["workouts"]>[number]
): Promise<string> {
  const baseId = `workout_${workout.number}`;
  const docRef = db.collection("workouts").doc(baseId);
  const snap = await docRef.get();
  if (!snap.exists) {
    return baseId;
  }
  const existing = snap.data();
  if (existing?.startTime && typeof existing.startTime === "string") {
    const existingUnix = istStartTimeToUnix(existing.startTime);
    if (Math.abs(existingUnix - workout.startTime) > 60) {
      return `workout_${workout.number}_${workout.startTime}`;
    }
  }
  return baseId;
}

export async function syncFromApp(
    payload: AppSyncPayload,
    webhookUrl?: string,
    webhookKey?: string,
    options?: {checksumVerified?: boolean}
): Promise<SyncFromAppResult> {
  const db = admin.firestore();
  const writeOps: WriteOp[] = [];
  const accepted = emptyAccepted();
  const rejected: SyncRejectedItem[] = [];
  const syncedAt = new Date().toISOString();
  const nowSec = Math.floor(Date.now() / 1000);
  const now = new Date();

  if (payload.workouts) {
    for (const workout of payload.workouts) {
      const ackId = workout.clientId ?? `workout_${workout.number}`;
      const validation = validateWorkout(
          workout as unknown as Record<string, unknown>,
          nowSec
      );
      if (!validation.ok) {
        rejected.push({id: ackId, kind: "workout", reason: validation.reason});
        continue;
      }

      const docId = await resolveWorkoutDocId(db, workout);
      const docRef = db.collection("workouts").doc(docId);

      const record: WorkoutRecord & {contentHash?: string | null; clientId?: string | null} = {
        id: docId,
        type: mapWorkoutType(workout.type),
        startTime: unixToIST(workout.startTime),
        endTime: unixToIST(workout.endTime),
        durationMin: Math.round(workout.durationSec / 60),
        activeKcal: workout.calories || null,
        avgHr: workout.hrMin && workout.hrMax ?
          Math.round((workout.hrMin + workout.hrMax) / 2) : null,
        maxHr: workout.hrMax || null,
        distanceKm: workout.distanceM ? workout.distanceM / 1000 : null,
        steps: workout.steps || null,
        swimLaps: workout.laps || null,
        swimStrokes: workout.strokes || null,
        swimAvgSwolf: workout.avgSwolf || null,
        swimPoolLength: workout.poolLength || null,
        load: workout.load || null,
        aerobicEffect: workout.aerobicEffect || null,
        anaerobicEffect: workout.anaerobicEffect || null,
        recoveryTime: workout.recoveryTime || null,
        syncedAt,
        contentHash: workout.contentHash ?? null,
        clientId: workout.clientId ?? ackId,
      };

      writeOps.push({ref: docRef, data: record});
      pushAccepted(accepted, "workouts", ackId);
    }
  }

  if (payload.sleep) {
    for (const sleep of payload.sleep) {
      const ackId = sleep.clientId ?? `sleep_${sleep.beginUnix}`;
      const validation = validateSleep(
          sleep as unknown as Record<string, unknown>,
          nowSec
      );
      if (!validation.ok) {
        rejected.push({id: ackId, kind: "sleep", reason: validation.reason});
        continue;
      }

      const id = `sleep_${sleep.beginUnix}`;
      const docRef = db.collection("sleep").doc(id);

      const stages = sleep.stages || [];
      const deepMin = stages
          .filter((s) => s.stage === 3)
          .reduce((sum, s) => sum + s.durationMin, 0);
      const remMin = stages
          .filter((s) => s.stage === 4)
          .reduce((sum, s) => sum + s.durationMin, 0);
      const lightMin = stages
          .filter((s) => s.stage === 2)
          .reduce((sum, s) => sum + s.durationMin, 0);
      const awakeMin = stages
          .filter((s) => s.stage === 1)
          .reduce((sum, s) => sum + s.durationMin, 0);

      const record: SleepRecord & {contentHash?: string | null; clientId?: string | null} = {
        id,
        startTime: unixToIST(sleep.beginUnix),
        endTime: unixToIST(sleep.endUnix),
        totalMin: Math.round((sleep.endUnix - sleep.beginUnix) / 60),
        deepMin: deepMin > 0 ? deepMin : null,
        remMin: remMin > 0 ? remMin : null,
        lightMin: lightMin > 0 ? lightMin : null,
        awakeMin: awakeMin > 0 ? awakeMin : null,
        sleepScore: sleep.sleepScore || null,
        avgHr: sleep.avgHr || null,
        avgHrv: sleep.avgHrv || null,
        avgBreathRate: sleep.avgBreathRate || null,
        avgSpO2: sleep.avgSpO2 || null,
        syncedAt,
        contentHash: sleep.contentHash ?? null,
        clientId: sleep.clientId ?? ackId,
      };

      writeOps.push({ref: docRef, data: record});
      pushAccepted(accepted, "sleep", ackId);
    }
  }

  if (payload.dailyTotals) {
    for (const totals of payload.dailyTotals) {
      const ackId = totals.clientId ?? totals.dayKey;
      const validation = validateTotals(
          totals as unknown as Record<string, unknown>,
          now
      );
      if (!validation.ok) {
        rejected.push({id: ackId, kind: "dailyTotals", reason: validation.reason});
        continue;
      }

      const docRef = db.collection("dailyTotals").doc(totals.dayKey);

      const activeKcal = totals.activeKcal || null;
      const totalKcal = totals.totalKcal || null;
      const restingKcal = totalKcal && activeKcal ?
        totalKcal - activeKcal : null;

      const record: DailyTotalsRecord & {contentHash?: string | null; clientId?: string | null} = {
        date: totals.dayKey,
        activeKcal,
        totalKcal,
        restingKcal,
        steps: totals.steps || null,
        distanceKm: totals.distanceM ? totals.distanceM / 1000 : null,
        syncedAt,
        contentHash: totals.contentHash ?? null,
        clientId: totals.clientId ?? ackId,
      };

      writeOps.push({ref: docRef, data: record});
      pushAccepted(accepted, "dailyTotals", ackId);
    }
  }

  if (payload.heartRate) {
    for (const hr of payload.heartRate) {
      const ackId = hr.clientId ?? hr.dayKey;
      const validation = validateHr(hr as unknown as Record<string, unknown>);
      if (!validation.ok) {
        rejected.push({id: ackId, kind: "heartRate", reason: validation.reason});
        continue;
      }

      const docRef = db.collection("heartRate").doc(hr.dayKey);

      const record: HeartRateRecord & {contentHash?: string | null; clientId?: string | null} = {
        date: hr.dayKey,
        restingHr: hr.restingHr || null,
        avgHr: hr.avgHr || null,
        maxHr: hr.maxHr || null,
        syncedAt,
        contentHash: hr.contentHash ?? null,
        clientId: hr.clientId ?? ackId,
      };

      writeOps.push({ref: docRef, data: record});
      pushAccepted(accepted, "heartRate", ackId);
    }
  }

  if (payload.hrv) {
    for (const hrvData of payload.hrv) {
      const docRef = db.collection("hrv").doc(hrvData.dayKey);

      const record: HrvRecord & {contentHash?: string | null; clientId?: string | null} = {
        date: hrvData.dayKey,
        hrvMs: hrvData.hrvMs || null,
        syncedAt,
        contentHash: hrvData.contentHash ?? null,
        clientId: hrvData.clientId ?? hrvData.dayKey,
      };

      writeOps.push({ref: docRef, data: record});
    }
  }

  if (payload.weight) {
    for (const weightData of payload.weight) {
      const id = `weight_${weightData.timestampMs}`;
      const docRef = db.collection("weight").doc(id);

      const record: WeightRecord & {contentHash?: string | null; clientId?: string | null} = {
        id,
        timestamp: msToIST(weightData.timestampMs),
        weightKg: weightData.weightKg,
        syncedAt,
        contentHash: weightData.contentHash ?? null,
        clientId: weightData.clientId ?? id,
      };

      writeOps.push({ref: docRef, data: record});
    }
  }

  if (payload.meals) {
    for (const meal of payload.meals) {
      const docRef = db.collection("meals").doc(meal.id);

      const record: MealRecord & {contentHash?: string | null; clientId?: string | null} = {
        id: meal.id,
        timestamp: msToIST(meal.timestampMs),
        items: meal.items,
        grams: meal.grams,
        kcal: meal.kcal,
        protein: meal.protein || null,
        syncedAt,
        contentHash: meal.contentHash ?? null,
        clientId: meal.clientId ?? meal.id,
      };

      writeOps.push({ref: docRef, data: record});
    }
  }

  if (writeOps.length > 0) {
    await commitWriteOps(db, writeOps);
  }

  const syncCount = Object.values(accepted).reduce((sum, ids) => sum + ids.length, 0);

  sendSyncWebhook(webhookUrl, webhookKey, payload, "owner").catch((error) => {
    console.error("[Sync] Webhook notification failed:", error);
  });

  return {
    accepted,
    rejected,
    checksumVerified: options?.checksumVerified ?? false,
    synced: syncCount,
  };
}

function manifestRow(
    data: FirebaseFirestore.DocumentData,
    fallbackId: string
): ManifestEntry {
  return {
    id: (data.id as string) ?? fallbackId,
    contentHash: (data.contentHash as string) ?? null,
    clientId: (data.clientId as string) ?? null,
  };
}

export async function getSyncManifest(from: string): Promise<SyncManifest> {
  const db = admin.firestore();
  const to = getCurrentISTDate();
  const {start} = istQueryBounds(from, to);

  const [workoutsSnap, sleepSnap, totalsSnap, hrSnap] = await Promise.all([
    db.collection("workouts")
        .where("startTime", ">=", start)
        .orderBy("startTime")
        .get(),
    db.collection("sleep")
        .where("startTime", ">=", start)
        .orderBy("startTime")
        .get(),
    db.collection("dailyTotals")
        .where("date", ">=", from)
        .orderBy("date")
        .get(),
    db.collection("heartRate")
        .where("date", ">=", from)
        .orderBy("date")
        .get(),
  ]);

  return {
    workouts: workoutsSnap.docs.map((doc) => manifestRow(doc.data(), doc.id)),
    sleep: sleepSnap.docs.map((doc) => manifestRow(doc.data(), doc.id)),
    dailyTotals: totalsSnap.docs.map((doc) => manifestRow(doc.data(), doc.id)),
    heartRate: hrSnap.docs.map((doc) => manifestRow(doc.data(), doc.id)),
  };
}
