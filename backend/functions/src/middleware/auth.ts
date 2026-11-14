import {Request, Response, NextFunction} from "express";
import * as admin from "firebase-admin";

export interface AuthenticatedRequest extends Request {
  userId?: string;
  isReadOnly?: boolean;
  isWriteAccess?: boolean;
}

const DEVICE_WRITE_KEY_ENV = "DEVICE_WRITE_KEY";
const READ_ONLY_API_KEY_ENV = "READ_ONLY_API_KEY";

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
      const deviceKey = process.env[DEVICE_WRITE_KEY_ENV];
      
      if (deviceKey && token === deviceKey) {
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
      const readKey = process.env[READ_ONLY_API_KEY_ENV];
      
      if (readKey && token === readKey) {
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
