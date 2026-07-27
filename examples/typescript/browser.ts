import { NeuroVerifyClient } from "@neuraldefend/sdk";

export async function inspectImage(
  file: File,
  shortLivedApiKey: string,
): Promise<string> {
  // Production keys come from https://neuraldefend.com/ (Book a Demo). Never embed a
  // long-lived key in browser JavaScript — obtain a short-lived, scoped credential from
  // your authenticated backend instead.
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
