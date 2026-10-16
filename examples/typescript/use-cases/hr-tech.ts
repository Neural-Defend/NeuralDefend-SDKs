/**
 * HR tech: screen a job candidate's recorded interview and ID photo.
 *
 *   export NEURALDEFEND_API_KEY="replace-with-your-api-key"
 *   npx tsx hr-tech.ts
 */
import { readFile } from "node:fs/promises";
import {
  NeuroVerifyClient,
  NeuroVerifyError,
  ValidationError,
  type ImageResult,
  type VideoResult,
} from "@neuraldefend/sdk";

// Create one client and reuse it. It reads NEURALDEFEND_API_KEY.
const client = new NeuroVerifyClient();

// Stand-in for your database: keep one audit row per API call.
function saveAudit(record: Record<string, unknown>): void {
  console.log("audit:", JSON.stringify(record));
}

async function screenCandidate(
  candidateId: string,
  interviewPath: string,
  photoBytes: Uint8Array,
  photoFilename: string,
) {
  let video: VideoResult;
  let photo: ImageResult;
  try {
    video = await client.detectVideo(interviewPath);
    saveAudit({
      subject: candidateId,
      transactionId: video.uniqueTrxId,
      status: video.status,
      videoRiskLevel: video.videoRiskLevel,
      audioRiskLevel: video.audioRiskLevel,
      billable: video.billable,
      timestamp: new Date().toISOString(),
    });

    photo = await client.detectImage(photoBytes, { filename: photoFilename });
    saveAudit({
      subject: candidateId,
      transactionId: photo.uniqueTrxId,
      status: photo.status,
      riskLevel: photo.riskLevel,
      billable: photo.billable,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    if (error instanceof ValidationError) {
      return {
        candidateId,
        decision: "INVALID_INPUT",
        flags: [],
        transactionIds: [],
        reason: error.detail,
      };
    }
    if (error instanceof NeuroVerifyError) {
      return {
        candidateId,
        decision: "SERVICE_UNAVAILABLE",
        flags: [],
        transactionIds: [],
        reason: error.detail,
      };
    }
    throw error;
  }

  const flags: string[] = [];
  if (video.videoRiskLevel === "high") flags.push("FACE_SWAP_SUSPECTED");
  if (video.audioRiskLevel === "high") flags.push("VOICE_CLONE_SUSPECTED");
  if (photo.riskLevel === "high") flags.push("PHOTO_SPOOF_SUSPECTED");

  const levels = [video.videoRiskLevel, video.audioRiskLevel, photo.riskLevel];
  let decision: string;
  if (flags.length > 0) {
    decision = "RECRUITER_REVIEW";
  } else if (
    video.status !== "success" ||
    photo.status !== "success" ||
    levels.includes("medium")
  ) {
    // rejected, a newer status this code does not know yet, or inconclusive
    decision = "ADDITIONAL_VERIFICATION";
  } else {
    decision = "CLEAR";
  }

  return {
    candidateId,
    decision,
    flags,
    transactionIds: [video.uniqueTrxId, photo.uniqueTrxId],
  };
}

const idPhoto = await readFile("id_photo.jpg");
const decision = await screenCandidate(
  "cand_4004",
  "interview.mp4",
  idPhoto,
  "id_photo.jpg",
);
console.log(JSON.stringify(decision, null, 2));
