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
import {unixToIST, msToIST} from "./timezone";
import {mapWorkoutType} from "../models/workout-type-mapping";

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
  }>;
  dailyTotals?: Array<{
    dayKey: string;
    activeKcal?: number;
    totalKcal?: number;
    steps?: number;
    distanceM?: number;
  }>;
  heartRate?: Array<{
    dayKey: string;
    restingHr?: number;
    avgHr?: number;
    maxHr?: number;
  }>;
  hrv?: Array<{
    dayKey: string;
    hrvMs?: number;
  }>;
  weight?: Array<{
    timestampMs: number;
    weightKg: number;
  }>;
  meals?: Array<{
    id: string;
    timestampMs: number;
    items: string[];
    grams: number[];
    kcal: number;
    protein?: number;
  }>;
}

export async function syncFromApp(payload: AppSyncPayload): Promise<{synced: number}> {
  const db = admin.firestore();
  const batch = db.batch();
  let syncCount = 0;
  const syncedAt = new Date().toISOString();

  if (payload.workouts) {
    for (const workout of payload.workouts) {
      const id = `workout_${workout.number}`;
      const docRef = db.collection("workouts").doc(id);

      const record: WorkoutRecord = {
        id,
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
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  if (payload.sleep) {
    for (const sleep of payload.sleep) {
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

      const record: SleepRecord = {
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
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  if (payload.dailyTotals) {
    for (const totals of payload.dailyTotals) {
      const docRef = db.collection("dailyTotals").doc(totals.dayKey);

      const activeKcal = totals.activeKcal || null;
      const totalKcal = totals.totalKcal || null;
      const restingKcal = totalKcal && activeKcal ?
        totalKcal - activeKcal : null;

      const record: DailyTotalsRecord = {
        date: totals.dayKey,
        activeKcal,
        totalKcal,
        restingKcal,
        steps: totals.steps || null,
        distanceKm: totals.distanceM ? totals.distanceM / 1000 : null,
        syncedAt,
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  if (payload.heartRate) {
    for (const hr of payload.heartRate) {
      const docRef = db.collection("heartRate").doc(hr.dayKey);

      const record: HeartRateRecord = {
        date: hr.dayKey,
        restingHr: hr.restingHr || null,
        avgHr: hr.avgHr || null,
        maxHr: hr.maxHr || null,
        syncedAt,
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  if (payload.hrv) {
    for (const hrvData of payload.hrv) {
      const docRef = db.collection("hrv").doc(hrvData.dayKey);

      const record: HrvRecord = {
        date: hrvData.dayKey,
        hrvMs: hrvData.hrvMs || null,
        syncedAt,
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  if (payload.weight) {
    for (const weightData of payload.weight) {
      const id = `weight_${weightData.timestampMs}`;
      const docRef = db.collection("weight").doc(id);

      const record: WeightRecord = {
        id,
        timestamp: msToIST(weightData.timestampMs),
        weightKg: weightData.weightKg,
        syncedAt,
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  if (payload.meals) {
    for (const meal of payload.meals) {
      const docRef = db.collection("meals").doc(meal.id);

      const record: MealRecord = {
        id: meal.id,
        timestamp: msToIST(meal.timestampMs),
        items: meal.items,
        grams: meal.grams,
        kcal: meal.kcal,
        protein: meal.protein || null,
        syncedAt,
      };

      batch.set(docRef, record, {merge: true});
      syncCount++;
    }
  }

  await batch.commit();

  return {synced: syncCount};
}
