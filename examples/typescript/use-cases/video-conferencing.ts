/**
 * Video conferencing: check a short clip of a meeting participant for deepfakes.
 *
 *   export NEURALDEFEND_API_KEY="replace-with-your-api-key"
 *   npx tsx video-conferencing.ts
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

async function checkMeetingClip(
  meetingId: string,
  participantId: string,
  clipPath: string,
) {
  let result: VideoResult;
  try {
    result = await client.detectVideo(clipPath);
  } catch (error) {
    if (error instanceof ValidationError) {
      return {
        meetingId,
        participantId,
        decision: "INVALID_INPUT",
        reason: error.detail,
        transactionId: null,
      };
    }
    if (error instanceof NeuroVerifyError) {
      return {
        meetingId,
        participantId,
        decision: "SERVICE_UNAVAILABLE",
        reason: error.detail,
        transactionId: null,
      };
    }
    throw error;
  }

  saveAudit({
    subject: participantId,
    transactionId: result.uniqueTrxId,
    status: result.status,
    videoRiskLevel: result.videoRiskLevel,
    audioRiskLevel: result.audioRiskLevel,
    billable: result.billable,
    timestamp: new Date().toISOString(),
  });

  let decision: string;
  if (result.status === "rejected") {
    decision = "SKIP"; // e.g. camera off or no face in the clip
  } else if (result.status !== "success") {
    decision = "WATCH"; // a newer status this code does not know yet
  } else if (
    result.videoRiskLevel === "high" ||
    result.audioRiskLevel === "high"
  ) {
    decision = "ALERT_HOST";
  } else if (
    result.videoRiskLevel === "medium" ||
    result.audioRiskLevel === "medium"
  ) {
    decision = "WATCH";
  } else {
    decision = "OK";
  }

  return {
    meetingId,
    participantId,
    decision,
    reason: result.videoMessage,
    transactionId: result.uniqueTrxId,
  };
}

const decision = await checkMeetingClip("mtg_5005", "user_42", "clip_0001.mp4");
console.log(JSON.stringify(decision, null, 2));
