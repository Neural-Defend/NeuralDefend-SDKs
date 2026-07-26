import { NeuroVerifyClient } from "@neuraldefend/sdk";

export async function inspectImage(
  file: File,
  shortLivedApiKey: string,
): Promise<string> {
  // Never embed a long-lived production key in browser JavaScript. Obtain a
  // short-lived, scoped, revocable credential from your authenticated backend.
  const client = new NeuroVerifyClient({ apiKey: shortLivedApiKey });
  const result = await client.detectImage(file);

  if (result.status === "success") {
    return `${result.riskLevel} risk (${result.riskScore}/10)`;
  }
  if (result.status === "rejected") {
    return `Could not score: ${result.message}`;
  }
  return "The service returned an outcome this SDK version does not recognize.";
}
