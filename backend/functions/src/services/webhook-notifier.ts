import * as https from "https";
import * as http from "http";
import {URL} from "url";
import {AppSyncPayload} from "./sync-service";

export interface WebhookPayload {
  event: "sync_completed";
  userId: string;
  timestamp: string;
  dataTypes: string[];
  summary: {
    workouts?: Array<{
      id: string;
      type: string;
      startTime: string;
      durationMin: number;
      activeKcal: number | null;
    }>;
    sleep?: Array<{
      id: string;
      date: string;
      totalMin: number;
    }>;
    dailyTotals?: Array<{
      date: string;
      activeKcal: number | null;
      steps: number | null;
    }>;
    heartRate?: Array<{date: string}>;
    hrv?: Array<{date: string}>;
    weight?: Array<{timestamp: string; weightKg: number}>;
    meals?: Array<{id: string; timestamp: string; kcal: number}>;
  };
}

/**
 * Send a sync notification webhook.
 * 
 * Fire-and-forget with short timeout. Webhook failures never fail the sync.
 * If FATHOM_SYNC_WEBHOOK_URL is unset, skips silently.
 * 
 * @param webhookUrl URL to POST to (from Firebase secret)
 * @param webhookKey Bearer token for Authorization header (from Firebase secret)
 * @param syncPayload Original sync payload from app
 * @param userId User ID (typically "owner" for single-user app)
 */
export async function sendSyncWebhook(
  webhookUrl: string | undefined,
  webhookKey: string | undefined,
  syncPayload: AppSyncPayload,
  userId: string = "owner"
): Promise<void> {
  // Skip silently if webhook URL not configured
  if (!webhookUrl || webhookUrl.trim() === "") {
    return;
  }

  try {
    const dataTypes = buildDataTypes(syncPayload);
    if (dataTypes.length === 0) {
      // No data in sync, skip webhook
      return;
    }

    const payload: WebhookPayload = {
      event: "sync_completed",
      userId,
      timestamp: new Date().toISOString(),
      dataTypes,
      summary: buildSummary(syncPayload),
    };

    await postWebhook(webhookUrl, webhookKey, payload);
  } catch (error) {
    // Log error but never fail the sync
    console.error("[Webhook] Failed to send sync notification:", error);
  }
}

function buildDataTypes(payload: AppSyncPayload): string[] {
  const types: string[] = [];
  if (payload.workouts && payload.workouts.length > 0) types.push("workouts");
  if (payload.sleep && payload.sleep.length > 0) types.push("sleep");
  if (payload.dailyTotals && payload.dailyTotals.length > 0) types.push("dailyTotals");
  if (payload.heartRate && payload.heartRate.length > 0) types.push("heartRate");
  if (payload.hrv && payload.hrv.length > 0) types.push("hrv");
  if (payload.weight && payload.weight.length > 0) types.push("weight");
  if (payload.meals && payload.meals.length > 0) types.push("meals");
  return types;
}

function buildSummary(payload: AppSyncPayload): WebhookPayload["summary"] {
  const summary: WebhookPayload["summary"] = {};

  if (payload.workouts && payload.workouts.length > 0) {
    summary.workouts = payload.workouts.map((w) => ({
      id: `workout_${w.number}`,
      type: String(w.type),
      startTime: unixToISO(w.startTime),
      durationMin: Math.round(w.durationSec / 60),
      activeKcal: w.calories || null,
    }));
  }

  if (payload.sleep && payload.sleep.length > 0) {
    summary.sleep = payload.sleep.map((s) => ({
      id: `sleep_${s.beginUnix}`,
      date: unixToDateOnly(s.beginUnix),
      totalMin: Math.round((s.endUnix - s.beginUnix) / 60),
    }));
  }

  if (payload.dailyTotals && payload.dailyTotals.length > 0) {
    summary.dailyTotals = payload.dailyTotals.map((t) => ({
      date: t.dayKey,
      activeKcal: t.activeKcal || null,
      steps: t.steps || null,
    }));
  }

  if (payload.heartRate && payload.heartRate.length > 0) {
    summary.heartRate = payload.heartRate.map((hr) => ({date: hr.dayKey}));
  }

  if (payload.hrv && payload.hrv.length > 0) {
    summary.hrv = payload.hrv.map((hrv) => ({date: hrv.dayKey}));
  }

  if (payload.weight && payload.weight.length > 0) {
    summary.weight = payload.weight.map((w) => ({
      timestamp: msToISO(w.timestampMs),
      weightKg: w.weightKg,
    }));
  }

  if (payload.meals && payload.meals.length > 0) {
    summary.meals = payload.meals.map((m) => ({
      id: m.id,
      timestamp: msToISO(m.timestampMs),
      kcal: m.kcal,
    }));
  }

  return summary;
}

function postWebhook(
  webhookUrl: string,
  webhookKey: string | undefined,
  payload: WebhookPayload
): Promise<void> {
  return new Promise((resolve, reject) => {
    const url = new URL(webhookUrl);
    const protocol = url.protocol === "https:" ? https : http;

    const data = JSON.stringify(payload);
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(data).toString(),
      "User-Agent": "Fathom-Fitness-OS/1.0",
    };

    // Add Authorization header if key is provided
    if (webhookKey && webhookKey.trim() !== "") {
      headers["Authorization"] = `Bearer ${webhookKey}`;
    }

    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname + url.search,
      method: "POST",
      headers,
      timeout: 5000, // 5-second timeout
    };

    const req = protocol.request(options, (res) => {
      // Consume response body to avoid memory leaks
      res.on("data", () => {
        // Ignore response body
      });
      res.on("end", () => {
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          console.log(`[Webhook] Sent successfully: ${res.statusCode}`);
          resolve();
        } else {
          console.warn(`[Webhook] Server returned ${res.statusCode}`);
          // Still resolve - webhook failures don't fail the sync
          resolve();
        }
      });
    });

    req.on("error", (error) => {
      console.error("[Webhook] Request failed:", error.message);
      // Still resolve - webhook failures don't fail the sync
      resolve();
    });

    req.on("timeout", () => {
      console.error("[Webhook] Request timed out after 5s");
      req.destroy();
      // Still resolve - webhook failures don't fail the sync
      resolve();
    });

    req.write(data);
    req.end();
  });
}

function unixToISO(unix: number): string {
  return new Date(unix * 1000).toISOString();
}

function unixToDateOnly(unix: number): string {
  const date = new Date(unix * 1000);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function msToISO(ms: number): string {
  return new Date(ms).toISOString();
}
