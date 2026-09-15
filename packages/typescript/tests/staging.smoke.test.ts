import { describe, expect, it } from "vitest";
import { NeuroVerifyClient } from "../src/index.js";

const apiKey = process.env.NEURALDEFEND_STAGING_API_KEY;
const imagePath = process.env.NEURALDEFEND_STAGING_IMAGE;
const videoPath = process.env.NEURALDEFEND_STAGING_VIDEO;
const enabled = Boolean(apiKey && imagePath && videoPath);

describe.skipIf(!enabled)("staging contract", () => {
  it("returns a consistent image result", async () => {
    // Use the SDK retry policy for HTTP 429/500/503. Staging smoke previously
    // set maxRetries: 0, so a single transient 503 failed the weekly job.
    const client = NeuroVerifyClient.staging({
      apiKey: apiKey!,
    });
    const result = await client.detectImage(imagePath!);

    expect(["success", "rejected"]).toContain(result.status);
    expect(result.uniqueTrxId).toBeTruthy();
    expect(typeof result.billable).toBe("boolean");
    expect(result.scored).toBe(result.status === "success");
    expect(result.rejected).toBe(result.status === "rejected");
  });

  it("returns a consistent video result", async () => {
    const client = NeuroVerifyClient.staging({
      apiKey: apiKey!,
    });
    const result = await client.detectVideo(videoPath!, { maxFrames: 2 });

    expect(["success", "rejected"]).toContain(result.status);
    expect(result.uniqueTrxId).toBeTruthy();
    expect(typeof result.billable).toBe("boolean");
    expect(result.scored).toBe(result.status === "success");
    expect(result.rejected).toBe(result.status === "rejected");
    if (result.status === "success") {
      expect(result.videoRiskScore).not.toBeNull();
      expect(["low", "medium", "high"]).toContain(result.videoRiskLevel);
    }
  });
});
