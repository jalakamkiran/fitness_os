import {Request, Response, NextFunction} from "express";
import * as admin from "firebase-admin";

export interface AuthenticatedRequest extends Request {
  userId?: string;
  isReadOnly?: boolean;
  isWriteAccess?: boolean;
}

let readOnlyKey: string | undefined;
let deviceWriteKey: string | undefined;

export function initializeKeys(readKey: string, writeKey: string): void {
  readOnlyKey = readKey;
  deviceWriteKey = writeKey;
}

export async function authenticateWrite(
    req: AuthenticatedRequest,
    res: Response,
    next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader) {
      res.status(401).json({error: "Missing authorization header"});
      return;
    }

    // Check device write key first (simple bearer token)
    if (authHeader.startsWith("Bearer ")) {
      const token = authHeader.substring(7);

      if (deviceWriteKey && token === deviceWriteKey) {
        req.userId = "device";
        req.isWriteAccess = true;
        next();
        return;
      }

      // Try Firebase Auth token
      try {
        const decodedToken = await admin.auth().verifyIdToken(token);
        req.userId = decodedToken.uid;
        req.isWriteAccess = true;
        next();
        return;
      } catch (error) {
        res.status(401).json({error: "Invalid authentication token"});
        return;
      }
    }

    res.status(401).json({error: "Invalid authorization format"});
  } catch (error) {
    console.error("Authentication error:", error);
    res.status(500).json({error: "Internal authentication error"});
  }
}

export async function authenticateRead(
    req: AuthenticatedRequest,
    res: Response,
    next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader) {
      res.status(401).json({error: "Missing authorization header"});
      return;
    }

    if (authHeader.startsWith("Bearer ")) {
      const token = authHeader.substring(7);

      if (readOnlyKey && token === readOnlyKey) {
        req.isReadOnly = true;
        next();
        return;
      }

      res.status(403).json({error: "Invalid read-only API key"});
      return;
    }

    res.status(401).json({error: "Invalid authorization format"});
  } catch (error) {
    console.error("Authentication error:", error);
    res.status(500).json({error: "Internal authentication error"});
  }
}
