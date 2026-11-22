/**
 * TypeScript models for Fitness OS backend
 * All times in ISO-8601 with +05:30 timezone (Asia/Kolkata)
 */

export interface WorkoutRecord {
  id: string;
  type: string;
  startTime: string;
  endTime: string;
  durationMin: number;
  activeKcal: number | null;
  avgHr: number | null;
  maxHr: number | null;
  distanceKm: number | null;
  steps: number | null;
  swimLaps: number | null;
  swimStrokes: number | null;
  swimAvgSwolf: number | null;
  swimPoolLength: number | null;
  load: number | null;
  aerobicEffect: number | null;
  anaerobicEffect: number | null;
  recoveryTime: number | null;
  syncedAt: string;
  contentHash?: string | null;
  clientId?: string | null;
}

export interface SleepRecord {
  id: string;
  startTime: string;
  endTime: string;
  totalMin: number;
  deepMin: number | null;
  remMin: number | null;
  lightMin: number | null;
  awakeMin: number | null;
  sleepScore: number | null;
  avgHr: number | null;
  avgHrv: number | null;
  avgBreathRate: number | null;
  avgSpO2: number | null;
  syncedAt: string;
  contentHash?: string | null;
  clientId?: string | null;
}

export interface DailyTotalsRecord {
  date: string;
  activeKcal: number | null;
  totalKcal: number | null;
  restingKcal: number | null;
  steps: number | null;
  distanceKm: number | null;
  syncedAt: string;
  contentHash?: string | null;
  clientId?: string | null;
}

export interface HeartRateRecord {
  date: string;
  restingHr: number | null;
  avgHr: number | null;
  maxHr: number | null;
  syncedAt: string;
  contentHash?: string | null;
  clientId?: string | null;
}

export interface HrvRecord {
  date: string;
  hrvMs: number | null;
  syncedAt: string;
}

export interface WeightRecord {
  id: string;
  timestamp: string;
  weightKg: number;
  syncedAt: string;
}

export interface MealRecord {
  id: string;
  timestamp: string;
  items: string[];
  grams: number[];
  kcal: number;
  protein: number | null;
  syncedAt: string;
}

export interface DailySummary {
  date: string;
  activeKcal: number | null;
  totalKcal: number | null;
  restingKcal: number | null;
  steps: number | null;
  distanceKm: number | null;
  restingHr: number | null;
  hrvMs: number | null;
  sleep: {
    start: string | null;
    end: string | null;
    totalMin: number | null;
    deepMin: number | null;
    remMin: number | null;
    lightMin: number | null;
    awakeMin: number | null;
    score: number | null;
  } | null;
  weightKg: number | null;
  workouts: Array<{
    id: string;
    type: string;
    start: string;
    end: string;
    durationMin: number;
    activeKcal: number | null;
    avgHr: number | null;
    maxHr: number | null;
  }>;
  lastSyncedAt: string | null;
}

export interface SyncStatus {
  workouts: string | null;
  sleep: string | null;
  dailyTotals: string | null;
  heartRate: string | null;
  hrv: string | null;
  weight: string | null;
  meals: string | null;
}
