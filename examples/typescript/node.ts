/**
 * Node.js image detection example.
 *
 * Get an API key from https://neuraldefend.com/ (Book a Demo), then:
 *   export NEURALDEFEND_API_KEY="your-api-key"
 *   npx tsx node.ts ./selfie.jpg
 */
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const input = process.argv[2];
if (!input) {
  throw new Error("Usage: npx tsx node.ts <image-path>");
}

// Reads NEURALDEFEND_API_KEY set after Neural Defend onboarding.
const client = new NeuroVerifyClient();
const result = await client.detectImage(input);

switch (result.status) {
  case "success":
    console.log({
      transactionId: result.uniqueTrxId,
      billable: result.billable,
      riskLevel: result.riskLevel,
      riskScore: result.riskScore,
    });
    break;
  case "rejected":
    console.log(`Could not score: ${result.message}`);
    break;
  case "unknown":
    console.log(
      "The service returned a newer outcome; upgrade the SDK before using it for policy decisions.",
    );
    break;
}
