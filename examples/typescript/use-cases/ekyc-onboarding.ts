/**
 * eKYC onboarding: check a new applicant's selfie before opening the account.
 *
 *   export NEURALDEFEND_API_KEY="replace-with-your-api-key"
 *   npx tsx ekyc-onboarding.ts
 */
import { readFile } from "node:fs/promises";
import {
  NeuroVerifyClient,
  NeuroVerifyError,
  ValidationError,
  type ImageResult,
} from "@neuraldefend/sdk";

// Create one client and reuse it. It reads NEURALDEFEND_API_KEY.
const client = new NeuroVerifyClient();

// Stand-in for your database: keep one audit row per API call.
function saveAudit(record: Record<string, unknown>): void {
  console.log("audit:", JSON.stringify(record));
}

const DECISION_BY_RISK = {
  low: "APPROVE",
  medium: "MANUAL_REVIEW",
  high: "FRAUD_REVIEW",
} as const;

async function verifyOnboardingSelfie(
  applicantId: string,
  photoBytes: Uint8Array,
  filename: string,
) {
  let result: ImageResult;
  try {
    result = await client.detectImage(photoBytes, { filename });
  } catch (error) {
    if (error instanceof ValidationError) {
      return {
        applicantId,
        decision: "INVALID_INPUT",
        reason: error.detail,
        transactionId: null,
      };
    }
    if (error instanceof NeuroVerifyError) {
      return {
        applicantId,
        decision: "SERVICE_UNAVAILABLE",
        reason: error.detail,
        transactionId: null,
      };
    }
    throw error;
  }

  saveAudit({
    subject: applicantId,
    transactionId: result.uniqueTrxId,
    status: result.status,
    riskLevel: result.riskLevel,
    billable: result.billable,
    timestamp: new Date().toISOString(),
  });

  let decision: string;
  if (result.status === "rejected") {
    decision = "RETAKE_SELFIE"; // e.g. no face or a blurry photo
  } else if (result.status === "success") {
    decision = DECISION_BY_RISK[result.riskLevel];
  } else {
    decision = "MANUAL_REVIEW"; // a newer status this code does not know yet
  }

  return {
    applicantId,
    decision,
    reason: result.message,
    transactionId: result.uniqueTrxId,
  };
}

const photo = await readFile("selfie.jpg");
const decision = await verifyOnboardingSelfie("app_1001", photo, "selfie.jpg");
console.log(JSON.stringify(decision, null, 2));
