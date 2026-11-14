import {authenticateRead, authenticateWrite} from "../middleware/auth";
import {Request, Response, NextFunction} from "express";

jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  auth: jest.fn(() => ({
    verifyIdToken: jest.fn(),
  })),
}));

describe("Authentication Middleware", () => {
  let mockReq: Partial<Request>;
  let mockRes: Partial<Response>;
  let mockNext: NextFunction;
  
  beforeEach(() => {
    mockReq = {
      headers: {},
    };
    mockRes = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn(),
    };
    mockNext = jest.fn();
    process.env.READ_ONLY_API_KEY = "test-read-key";
    process.env.DEVICE_WRITE_KEY = "test-write-key";
  });
  
  describe("authenticateRead", () => {
    it("should accept valid read-only API key", async () => {
      mockReq.headers = {
        authorization: "Bearer test-read-key",
      };
      
      await authenticateRead(
        mockReq as Request,
        mockRes as Response,
        mockNext
      );
      
      expect(mockNext).toHaveBeenCalled();
      expect(mockRes.status).not.toHaveBeenCalled();
    });
    
    it("should reject invalid API key", async () => {
      mockReq.headers = {
        authorization: "Bearer wrong-key",
      };
      
      await authenticateRead(
        mockReq as Request,
        mockRes as Response,
        mockNext
      );
      
      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockNext).not.toHaveBeenCalled();
    });
    
    it("should reject missing authorization header", async () => {
      await authenticateRead(
        mockReq as Request,
        mockRes as Response,
        mockNext
      );
      
      expect(mockRes.status).toHaveBeenCalledWith(401);
      expect(mockNext).not.toHaveBeenCalled();
    });
  });
  
  describe("authenticateWrite", () => {
    it("should accept valid device write key", async () => {
      mockReq.headers = {
        authorization: "Bearer test-write-key",
      };
      
      await authenticateWrite(
        mockReq as Request,
        mockRes as Response,
        mockNext
      );
      
      expect(mockNext).toHaveBeenCalled();
      expect(mockRes.status).not.toHaveBeenCalled();
    });
    
    it("should reject invalid write key", async () => {
      mockReq.headers = {
        authorization: "Bearer wrong-key",
      };
      
      const admin = require("firebase-admin");
      admin.auth().verifyIdToken.mockRejectedValue(new Error("Invalid token"));
      
      await authenticateWrite(
        mockReq as Request,
        mockRes as Response,
        mockNext
      );
      
      expect(mockRes.status).toHaveBeenCalledWith(401);
      expect(mockNext).not.toHaveBeenCalled();
    });
  });
});
