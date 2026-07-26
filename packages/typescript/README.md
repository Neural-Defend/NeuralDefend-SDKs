# @neuraldefend/sdk

Typed Node.js and browser client for the NeuroVerify image and video authenticity API.

## Install

```sh
npm install @neuraldefend/sdk
```

Node.js 22 or newer and current evergreen browsers are supported. The package has no runtime
dependencies.

## Node.js

```ts
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const client = new NeuroVerifyClient(); // reads NEURALDEFEND_API_KEY
const result = await client.detectImage("./selfie.jpg");

if (result.status === "success") {
  // Use the server-owned risk band for policy decisions.
  console.log(result.riskLevel, result.riskScore, result.uniqueTrxId);
} else if (result.status === "rejected") {
  console.log("Could not score:", result.message);
} else {
  console.log("Unknown future response:", result.raw);
}
```

Node inputs may be a path, readable stream, `Buffer`/`Uint8Array`, `File`, or `Blob`.
Pass `{ filename: "photo.jpg" }` with bytes, a plain `Blob`, or a stream without a
filesystem path. Paths are opened with `fs.openAsBlob`; streams are size-bounded while
being spooled to a private temporary file so retries remain safe and memory stays bounded.

## Browser

```ts
import { NeuroVerifyClient } from "@neuraldefend/sdk";

// Obtain a short-lived, endpoint-scoped, revocable credential from your backend.
const client = new NeuroVerifyClient({ apiKey: sessionApiKey });
const result = await client.detectImage(fileInput.files![0]);
```

Browsers require an explicit API key; browser builds never inspect environment variables.
Only `File` and `Blob` are accepted. Do not embed a long-lived production key in browser
JavaScript. If browser-safe short-lived credentials are not enabled for your tenant,
upload through your authenticated backend instead.

## Video

```ts
const result = await client.detectVideo("./clip.mp4", {
  maxFrames: 24,
  sampleRate: 2,
  signal: abortController.signal,
});

if (result.status === "success") {
  console.log("video:", result.videoRiskLevel);
  console.log(
    "audio:",
    result.hasAudio ? result.audioRiskLevel : "not present",
  );
  // Client-side convenience only; the API returns independent modality scores.
  console.log("overall score:", result.overallRiskScore);
}
```

## Outcomes and errors

Business rejections are normal results, including HTTP 400 input rejections and HTTP 200
face-policy rejections. Branch on `result.status`, never HTTP status or score thresholds.
Unknown statuses and risk bands become an `"unknown"` result and remain available in the
deeply frozen `raw` object. `billable` is authoritative for the transaction; a rejection
can still be billable.

`JSON.stringify(result)` emits normalized public fields only. `result.raw` remains
available for explicit diagnostics, but it is unstable and may contain filenames or
future personal/customer fields. Do not log or persist it without appropriate access and
retention controls.

The client raises:

- `AuthenticationError` for 401
- `ScopeError` for 403
- `RateLimitError` for an exhausted 429
- `ServerError` for an exhausted 500/503 response
- `HttpError` for another unexpected HTTP status
- `ValidationError`, `TimeoutError`, `AbortError`, `NetworkError`, or `ProtocolError`

429, 500, and 503 responses are retried three times after the initial request. Other
responses and network failures are never retried. Set `maxRetries: 0` to disable retries.
Every accepted attempt receives a new transaction ID and may have separate billing
implications.

Supported image extensions are `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`,
`.webp`, `.heic`, and `.heif` (10 MiB maximum). Supported video extensions are `.mp4`,
`.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`, `.ogg`, and `.ogv`
(1,500,000,000-byte maximum). Known extensions use deterministic MIME types. For an
unknown extension, an explicit `Blob.type` is preserved or
`application/octet-stream` is used.

## Configuration

```ts
new NeuroVerifyClient({
  apiKey: "...",
  baseUrl: "https://deepscan.neuraldefend.com",
  allowCustomBaseUrl: false,
  timeoutMs: 120_000,
  maxRetries: 3,
  retryAfterCapMs: 60_000,
  onWarning: (warning) => console.warn(warning.message),
});
```

Node also reads `NEURALDEFEND_API_KEY` and `NEURALDEFEND_BASE_URL`. Use
`NeuroVerifyClient.staging({ apiKey: "..." })` for staging. API keys are redacted from
string and JSON inspection. Non-Neural Defend origins are rejected by default. If a
trusted private deployment requires one, set `allowCustomBaseUrl: true` explicitly; that
origin receives the API key and uploaded media. Redirects are never followed.

Upload media only with the data owner's authorization and an appropriate legal basis.
Media can contain biometric personal data; apply your organization's retention, deletion,
residency, logging, and access-control requirements.
