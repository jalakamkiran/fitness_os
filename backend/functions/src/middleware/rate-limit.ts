import {Request, Response, NextFunction} from "express";
import * as admin from "firebase-admin";

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const MAX_REQUESTS_PER_HOUR = 60;

const rateLimitCache = new Map<string, RateLimitEntry>();

function cleanupExpiredEntries(): void {
  const now = Date.now();
  for (const [key, entry] of rateLimitCache.entries()) {
    if (entry.resetAt < now) {
      rateLimitCache.delete(key);
    }
  }
}

setInterval(cleanupExpiredEntries, 5 * 60 * 1000);

export function rateLimit(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const identifier = req.ip || "unknown";
  const now = Date.now();
  
  let entry = rateLimitCache.get(identifier);
  
  if (!entry || entry.resetAt < now) {
    entry = {
      count: 1,
      resetAt: now + RATE_LIMIT_WINDOW_MS,
    };
    rateLimitCache.set(identifier, entry);
    next();
    return;
  }
  
  if (entry.count >= MAX_REQUESTS_PER_HOUR) {
    const resetInSeconds = Math.ceil((entry.resetAt - now) / 1000);
    res.status(429).json({
      error: "Rate limit exceeded",
      retryAfter: resetInSeconds,
    });
    return;
  }
  
  entry.count++;
  next();
}

export async function persistentRateLimit(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const identifier = req.ip || "unknown";
  const now = Date.now();
  const hourKey = Math.floor(now / RATE_LIMIT_WINDOW_MS);
  const docId = `${identifier}_${hourKey}`;
  
  try {
    const db = admin.firestore();
    const rateLimitRef = db.collection("_rateLimit").doc(docId);
    
    await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(rateLimitRef);
      
      if (!doc.exists) {
        transaction.set(rateLimitRef, {
          count: 1,
          resetAt: (hourKey + 1) * RATE_LIMIT_WINDOW_MS,
        });
        return;
      }
      
      const data = doc.data()!;
      if (data.count >= MAX_REQUESTS_PER_HOUR) {
        const resetInSeconds = Math.ceil((data.resetAt - now) / 1000);
        throw new Error(`RATE_LIMIT:${resetInSeconds}`);
      }
      
      transaction.update(rateLimitRef, {
        count: admin.firestore.FieldValue.increment(1),
      });
    });
    
    next();
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("RATE_LIMIT:")) {
      const retryAfter = parseInt(error.message.split(":")[1]);
      res.status(429).json({
        error: "Rate limit exceeded",
        retryAfter,
      });
      return;
    }
    
    console.error("Rate limit error:", error);
    next();
  }
}
