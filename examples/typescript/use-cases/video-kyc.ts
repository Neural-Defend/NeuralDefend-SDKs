/**
 * Video KYC: review a recorded video KYC session for face swaps and cloned voices.
 *
 *   export NEURALDEFEND_API_KEY="replace-with-your-api-key"
 *   npx tsx video-kyc.ts
 */
import {
  NeuroVerifyClient,
  NeuroVerifyError,
  ValidationError,
  type VideoResult,
} from "@neuraldefend/sdk";

// Create one client and reuse it. It reads NEURALDEFEND_API_KEY.
const client = new NeuroVerifyClient();

// Stand-in for your database: keep one audit row per API call.
function saveAudit(record: Record<string, unknown>): void {
  console.log("audit:", JSON.stringify(record));
}

async function reviewVideoKycSession(sessionId: string, recordingPath: string) {
  let result: VideoResult;
  try {
    // Pass the path so the SDK streams the recording instead of loading it.
    result = await client.detectVideo(recordingPath, { maxFrames: 24 });
  } catch (error) {
    if (error instanceof ValidationError) {
      return {
        sessionId,
        decision: "INVALID_INPUT",
        reason: error.detail,
        videoRiskLevel: null,
        audioRiskLevel: null,
        transactionId: null,
      };
    }
    if (error instanceof NeuroVerifyError) {
      return {
        sessionId,
        decision: "SERVICE_UNAVAILABLE",
        reason: error.detail,
        videoRiskLevel: null,
        audioRiskLevel: null,
        transactionId: null,
      };
    }
    throw error;
  }

  saveAudit({
    subject: sessionId,
    transactionId: result.uniqueTrxId,
    status: result.status,
    videoRiskLevel: result.videoRiskLevel,
    audioRiskLevel: result.audioRiskLevel,
    billable: result.billable,
    timestamp: new Date().toISOString(),
  });

  let decision: string;
  let reason = result.videoMessage;
  if (result.status === "rejected") {
    decision = "RE_RECORD"; // e.g. no face in the recording
  } else if (result.status !== "success") {
    decision = "AGENT_REVIEW"; // a newer status this code does not know yet
  } else if (
    result.videoRiskLevel === "high" ||
    result.audioRiskLevel === "high"
  ) {
    decision = "FRAUD_REVIEW";
  } else if (!result.hasAudio) {
    decision = "AGENT_REVIEW";
    reason = "No audio track in the session recording";
  } else if (
    result.videoRiskLevel === "medium" ||
    result.audioRiskLevel === "medium"
  ) {
    decision = "AGENT_REVIEW";
  } else {
    decision = "APPROVE";
  }

  return {
    sessionId,
    decision,
    reason,
    videoRiskLevel: result.videoRiskLevel,
    audioRiskLevel: result.audioRiskLevel,
    transactionId: result.uniqueTrxId,
  };
}

const decision = await reviewVideoKycSession("vkyc_3003", "session.mp4");
console.log(JSON.stringify(decision, null, 2));
