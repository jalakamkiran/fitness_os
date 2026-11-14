import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import express from "express";
import {authenticateRead, authenticateWrite, initializeKeys} from "./middleware/auth";
import {rateLimit} from "./middleware/rate-limit";
import {computeDailySummary, computeDailySummaries} from "./services/daily-summary";
import {syncFromApp} from "./services/sync-service";
import {validateDateRange, parseDateRange} from "./services/timezone";
import {SyncStatus} from "./models/types";

const READ_ONLY_API_KEY = defineSecret("READ_ONLY_API_KEY");
const DEVICE_WRITE_KEY = defineSecret("DEVICE_WRITE_KEY");

admin.initializeApp();

const app = express();
app.use(express.json());

// Initialize auth keys from secrets
app.use((req, res, next) => {
  initializeKeys(READ_ONLY_API_KEY.value(), DEVICE_WRITE_KEY.value());
  next();
});

app.get("/api/v1/daily-summary", authenticateRead, rateLimit, async (req, res) => {
  try {
    const {date, from, to} = req.query;
    
    if (date && typeof date === "string") {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        res.status(400).json({error: "Invalid date format. Use YYYY-MM-DD"});
        return;
      }
      
      const summary = await computeDailySummary(date);
      res.json(summary);
      return;
    }
    
    if (from && to && typeof from === "string" && typeof to === "string") {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
        res.status(400).json({error: "Invalid date format. Use YYYY-MM-DD"});
        return;
      }
      
      if (!validateDateRange(from, to)) {
        res.status(400).json({error: "Date range must be 31 days or less"});
        return;
      }
      
      const summaries = await computeDailySummaries(from, to);
      res.json(summaries);
      return;
    }
    
    res.status(400).json({error: "Provide either ?date=YYYY-MM-DD or ?from=YYYY-MM-DD&to=YYYY-MM-DD"});
  } catch (error) {
    console.error("Error fetching daily summary:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

app.get("/api/v1/workouts", authenticateRead, rateLimit, async (req, res) => {
  try {
    const {from, to} = req.query;
    
    if (!from || !to || typeof from !== "string" || typeof to !== "string") {
      res.status(400).json({error: "Provide ?from=YYYY-MM-DD&to=YYYY-MM-DD"});
      return;
    }
    
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
      res.status(400).json({error: "Invalid date format. Use YYYY-MM-DD"});
      return;
    }
    
    if (!validateDateRange(from, to)) {
      res.status(400).json({error: "Date range must be 31 days or less"});
      return;
    }
    
    const {startMs, endMs} = parseDateRange(from, to);
    const db = admin.firestore();
    
    const snapshot = await db.collection("workouts")
      .where("startTime", ">=", new Date(startMs).toISOString())
      .where("startTime", "<=", new Date(endMs).toISOString())
      .orderBy("startTime", "desc")
      .get();
    
    const workouts = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: data.id,
        type: data.type,
        startTime: data.startTime,
        endTime: data.endTime,
        durationMin: data.durationMin,
        activeKcal: data.activeKcal,
        avgHr: data.avgHr,
        maxHr: data.maxHr,
        distanceKm: data.distanceKm,
        steps: data.steps,
        swimLaps: data.swimLaps,
        swimStrokes: data.swimStrokes,
        swimAvgSwolf: data.swimAvgSwolf,
        swimPoolLength: data.swimPoolLength,
        load: data.load,
        aerobicEffect: data.aerobicEffect,
        anaerobicEffect: data.anaerobicEffect,
        recoveryTime: data.recoveryTime,
      };
    });
    
    res.json(workouts);
  } catch (error) {
    console.error("Error fetching workouts:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

app.get("/api/v1/weight", authenticateRead, rateLimit, async (req, res) => {
  try {
    const {from, to} = req.query;
    
    if (!from || !to || typeof from !== "string" || typeof to !== "string") {
      res.status(400).json({error: "Provide ?from=YYYY-MM-DD&to=YYYY-MM-DD"});
      return;
    }
    
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
      res.status(400).json({error: "Invalid date format. Use YYYY-MM-DD"});
      return;
    }
    
    if (!validateDateRange(from, to)) {
      res.status(400).json({error: "Date range must be 31 days or less"});
      return;
    }
    
    const {startMs, endMs} = parseDateRange(from, to);
    const db = admin.firestore();
    
    const snapshot = await db.collection("weight")
      .where("timestamp", ">=", new Date(startMs).toISOString())
      .where("timestamp", "<=", new Date(endMs).toISOString())
      .orderBy("timestamp", "desc")
      .get();
    
    const weights = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        timestamp: data.timestamp,
        weightKg: data.weightKg,
      };
    });
    
    res.json(weights);
  } catch (error) {
    console.error("Error fetching weight:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

app.get("/api/v1/sync-status", authenticateRead, rateLimit, async (req, res) => {
  try {
    const db = admin.firestore();
    
    const [workoutsSnap, sleepSnap, totalsSnap, hrSnap, hrvSnap, weightSnap, mealsSnap] =
      await Promise.all([
        db.collection("workouts").orderBy("syncedAt", "desc").limit(1).get(),
        db.collection("sleep").orderBy("syncedAt", "desc").limit(1).get(),
        db.collection("dailyTotals").orderBy("syncedAt", "desc").limit(1).get(),
        db.collection("heartRate").orderBy("syncedAt", "desc").limit(1).get(),
        db.collection("hrv").orderBy("syncedAt", "desc").limit(1).get(),
        db.collection("weight").orderBy("syncedAt", "desc").limit(1).get(),
        db.collection("meals").orderBy("syncedAt", "desc").limit(1).get(),
      ]);
    
    const status: SyncStatus = {
      workouts: !workoutsSnap.empty ? workoutsSnap.docs[0].data().syncedAt : null,
      sleep: !sleepSnap.empty ? sleepSnap.docs[0].data().syncedAt : null,
      dailyTotals: !totalsSnap.empty ? totalsSnap.docs[0].data().syncedAt : null,
      heartRate: !hrSnap.empty ? hrSnap.docs[0].data().syncedAt : null,
      hrv: !hrvSnap.empty ? hrvSnap.docs[0].data().syncedAt : null,
      weight: !weightSnap.empty ? weightSnap.docs[0].data().syncedAt : null,
      meals: !mealsSnap.empty ? mealsSnap.docs[0].data().syncedAt : null,
    };
    
    res.json(status);
  } catch (error) {
    console.error("Error fetching sync status:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

app.post("/api/v1/sync", authenticateWrite, async (req, res) => {
  try {
    const result = await syncFromApp(req.body);
    res.json(result);
  } catch (error) {
    console.error("Error syncing data:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

const MEALS_WRITE_ENABLED = process.env.MEALS_WRITE_ENABLED === "true";

app.post("/api/v1/meals", authenticateWrite, async (req, res) => {
  if (!MEALS_WRITE_ENABLED) {
    res.status(403).json({error: "Meal logging is disabled"});
    return;
  }
  
  try {
    const {timestamp, items, grams, kcal, protein} = req.body;
    
    if (!timestamp || !items || !grams || !kcal) {
      res.status(400).json({error: "Missing required fields: timestamp, items, grams, kcal"});
      return;
    }
    
    if (!Array.isArray(items) || !Array.isArray(grams)) {
      res.status(400).json({error: "items and grams must be arrays"});
      return;
    }
    
    if (items.length !== grams.length) {
      res.status(400).json({error: "items and grams arrays must have the same length"});
      return;
    }
    
    const db = admin.firestore();
    const mealId = `meal_${Date.now()}`;
    const syncedAt = new Date().toISOString();
    
    await db.collection("meals").doc(mealId).set({
      id: mealId,
      timestamp,
      items,
      grams,
      kcal,
      protein: protein || null,
      syncedAt,
    });
    
    res.json({id: mealId, synced: true});
  } catch (error) {
    console.error("Error logging meal:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

export const api = onRequest(
  {
    region: "asia-south1",
    secrets: [READ_ONLY_API_KEY, DEVICE_WRITE_KEY],
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 2,
    timeoutSeconds: 60,
  },
  app
);
