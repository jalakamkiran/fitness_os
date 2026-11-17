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
}

export interface DailyTotalsRecord {
  date: string;
  activeKcal: number | null;
  totalKcal: number | null;
  restingKcal: number | null;
  steps: number | null;
  distanceKm: number | null;
  syncedAt: string;
}

export interface HeartRateRecord {
  date: string;
  restingHr: number | null;
  avgHr: number | null;
  maxHr: number | null;
  syncedAt: string;
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
  strengthSets: string | null;
}

export interface PlannedExercise {
  exerciseId: string;
  name: string;
  sets: number;
  targetKg: number;
  targetReps: number;
  restSec: number;
}

export interface PlannedSessionRecord {
  id: string;
  title: string;
  plannedFor: string;
  exercises: PlannedExercise[];
  source: "arjun" | "manual" | "debug";
  status: "planned" | "in_progress" | "done" | "skipped";
  createdAt: string;
  updatedAt: string;
}

export interface StrengthSetRecord {
  id: string;
  sessionId: string;
  exerciseId: string;
  exercise: string;
  setIndex: number;
  plannedKg: number;
  plannedReps: number;
  actualKg: number;
  actualReps: number;
  failed: boolean;
  replyText: string | null;
  unknownReply: boolean;
  notifiedAtMs: number;
  loggedAtMs: number;
  loggedAt: string;
  source: "watch_reply" | "watch_ack";
  workoutId: string | null;
  syncedAt: string;
}

export interface WorkoutHrStreamRecord {
  id: string;
  type: number;
  startMs: number;
  intervalSec: number;
  bpm: number[];
  clockSkewMs: number | null;
  syncedAt: string;
}

export interface SetHrRecord {
  setId: string;
  windowStartMs: number;
  windowEndMs: number;
  avgHr: number | null;
  maxHr: number | null;
  hrAtEnd: number | null;
  drop30: number | null;
  drop60: number | null;
  recoverySec: number | null;
  baselineHr: number | null;
  samples: number;
  reason?: string | null;
}
