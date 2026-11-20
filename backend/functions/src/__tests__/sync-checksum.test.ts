import * as crypto from "crypto";

describe("sync body checksum", () => {
  it("computes sha256 hex of raw JSON bytes", () => {
    const body = Buffer.from("{\"workouts\":[]}", "utf8");
    const hash = crypto.createHash("sha256").update(body).digest("hex");
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
    expect(hash).toBe(
        crypto.createHash("sha256").update(body).digest("hex")
    );
  });

  it("mismatch when body differs", () => {
    const a = crypto.createHash("sha256").update("{\"a\":1}").digest("hex");
    const b = crypto.createHash("sha256").update("{\"a\":2}").digest("hex");
    expect(a).not.toBe(b);
  });
});
