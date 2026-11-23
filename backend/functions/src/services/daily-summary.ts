import * as admin from "firebase-admin";
import {DailySummary} from "../models/types";
import {getISTDate, istQueryBounds, sleepDayQueryBounds} from "./timezone";

function sleepDurationMs(data: Record<string, unknown>): number {
  const start = data.startTime;
  const end = data.endTime;
  if (typeof start !== "string" || typeof end !== "string") return 0;
  const s = new Date(start).getTime();
  const e = new Date(end).getTime();
  if (!Number.isFinite(s) || !Number.isFinite(e) || e <= s) return 0;
  return e - s;
}

function pickLongestSleepDoc<T extends {data: () => Record<string, unknown>}>(
    docs: T[]
): T {
  let best = docs[0];
  let bestDur = sleepDurationMs(best.data());
  for (let i = 1; i < docs.length; i++) {
    const d = sleepDurationMs(docs[i].data());
    if (d > bestDur) {
      bestDur = d;
      best = docs[i];
    }
  }
  return best;
}

export async function computeDailySummary(date: string): Promise<DailySummary> {
  const db = admin.firestore();

  const {start, end} = istQueryBounds(date, date);
  const sleepBounds = sleepDayQueryBounds(date);

  const [
    totalsDoc,
    hrDoc,
    hrvDoc,
    sleepDocs,
    workoutDocs,
    weightDocs,
  ] = await Promise.all([
    db.collection("dailyTotals").doc(date).get(),
    db.collection("heartRate").doc(date).get(),
    db.collection("hrv").doc(date).get(),
    db.collection("sleep")
        .where("startTime", ">=", sleepBounds.start)
        .where("startTime", "<", sleepBounds.end)
        .get(),
    db.collection("workouts")
        .where("startTime", ">=", start)
        .where("startTime", "<=", end)
        .orderBy("startTime", "desc")
        .get(),
    db.collection("weight")
        .where("timestamp", ">=", start)
        .where("timestamp", "<=", end)
        .orderBy("timestamp", "desc")
        .limit(1)
        .get(),
  ]);

  const totals = totalsDoc.exists ? totalsDoc.data() : null;
  const hr = hrDoc.exists ? hrDoc.data() : null;
  const hrv = hrvDoc.exists ? hrvDoc.data() : null;

  let sleep = null;
  if (!sleepDocs.empty) {
    const pick = pickLongestSleepDoc(sleepDocs.docs);
    const sleepData = pick.data();
    sleep = {
      start: sleepData.startTime || null,
      end: sleepData.endTime || null,
      totalMin: sleepData.totalMin || null,
      deepMin: sleepData.deepMin || null,
      remMin: sleepData.remMin || null,
      lightMin: sleepData.lightMin || null,
      awakeMin: sleepData.awakeMin || null,
      score: sleepData.sleepScore || null,
    };
  }

  const workouts = workoutDocs.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      type: data.type,
      start: data.startTime,
      end: data.endTime,
      durationMin: data.durationMin,
      activeKcal: data.activeKcal || null,
      avgHr: data.avgHr || null,
      maxHr: data.maxHr || null,
    };
  });

  const weight = !weightDocs.empty ? weightDocs.docs[0].data()?.weightKg || null : null;

  const lastSyncedTimes = [
    totals?.syncedAt,
    hr?.syncedAt,
    hrv?.syncedAt,
    ...sleepDocs.docs.map((d) => d.data().syncedAt),
    ...workoutDocs.docs.map((d) => d.data().syncedAt),
    ...weightDocs.docs.map((d) => d.data().syncedAt),
  ].filter(Boolean);

  const lastSyncedAt = lastSyncedTimes.length > 0 ?
    lastSyncedTimes.sort().reverse()[0] :
    null;

  return {
    date,
    activeKcal: totals?.activeKcal || null,
    totalKcal: totals?.totalKcal || null,
    restingKcal: totals?.restingKcal || null,
    steps: totals?.steps || null,
    distanceKm: totals?.distanceKm || null,
    restingHr: hr?.restingHr || null,
    hrvMs: hrv?.hrvMs || null,
    sleep,
    weightKg: weight,
    workouts,
    lastSyncedAt,
  };
}

export async function computeDailySummaries(
    fromDate: string,
    toDate: string
): Promise<DailySummary[]> {
  const summaries: DailySummary[] = [];
  const start = new Date(fromDate + "T00:00:00+05:30");
  const end = new Date(toDate + "T00:00:00+05:30");

  for (
    let current = start;
    current <= end;
    current.setDate(current.getDate() + 1)
  ) {
    const dateStr = getISTDate(Math.floor(current.getTime() / 1000));
    const summary = await computeDailySummary(dateStr);
    summaries.push(summary);
  }

  return summaries;
}
