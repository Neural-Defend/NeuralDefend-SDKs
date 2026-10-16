/**
 * KYC re-verification: ask an existing customer for a fresh selfie before a
 * sensitive action such as a large withdrawal.
 *
 *   export NEURALDEFEND_API_KEY="replace-with-your-api-key"
 *   npx tsx kyc-reverification.ts
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
  low: "ALLOW",
  medium: "STEP_UP",
  high: "BLOCK_AND_ALERT",
} as const;

async function reverifyCustomer(
  customerId: string,
  action: string,
  photoBytes: Uint8Array,
  filename: string,
) {
  let result: ImageResult;
  try {
    result = await client.detectImage(photoBytes, { filename });
  } catch (error) {
    if (error instanceof ValidationError) {
      return {
        customerId,
        action,
        decision: "INVALID_INPUT",
        reason: error.detail,
        transactionId: null,
      };
    }
    if (error instanceof NeuroVerifyError) {
      return {
        customerId,
        action,
        decision: "SERVICE_UNAVAILABLE",
        reason: error.detail,
        transactionId: null,
      };
    }
    throw error;
  }

  saveAudit({
    subject: customerId,
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
    decision = "STEP_UP"; // a newer status this code does not know yet
  }

  return {
    customerId,
    action,
    decision,
    reason: result.message,
    transactionId: result.uniqueTrxId,
  };
}

const photo = await readFile("selfie.jpg");
const decision = await reverifyCustomer(
  "cus_2002",
  "large_withdrawal",
  photo,
  "selfie.jpg",
);
console.log(JSON.stringify(decision, null, 2));
