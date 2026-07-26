# @neuraldefend/sdk

The official TypeScript and JavaScript client for the Neural Defend NeuroVerify
image and video authenticity APIs. It provides:

- typed, normalized image and video results;
- Node.js and browser entry points from one package;
- bounded media validation and deterministic MIME selection;
- cancellation, timeouts, rate-limit handling, and controlled retries; and
- forward-compatible handling of response statuses and risk bands introduced by
  newer API versions.

Risk scores and risk bands are decision-support signals. They are not proof that
media is authentic or manipulated, and they should never be the sole basis for an
automatic acceptance, rejection, or adverse decision. Combine them with other
evidence, policy checks, and human review appropriate to your use case.

## Requirements

- `@neuraldefend/sdk` version `1.0.2`
- Node.js 22 or newer for server-side use
- A current evergreen browser for browser use
- A Neural Defend API key with access to the image and/or video endpoint

The package has no runtime dependencies.

## Installation

```sh
npm install @neuraldefend/sdk@1.0.2
```

The package supports ESM imports and CommonJS `require()` in Node.js. Bundlers
automatically select the browser build for browser applications.

## API key setup

API keys are issued during Neural Defend customer onboarding. Contact your
account representative or `support@neuraldefend.com` if you need a key, an
endpoint scope, or environment access changed.

For Node.js, keep the key in a secret manager or environment variable:

```sh
# macOS/Linux
export NEURALDEFEND_API_KEY="your-api-key"
```

```powershell
# PowerShell
$env:NEURALDEFEND_API_KEY = "your-api-key"
```

The Node.js client reads `NEURALDEFEND_API_KEY` when `apiKey` is not passed
explicitly. Never commit keys to source control, example files, container images,
or shell history.

## Node.js quick start

### Image detection

Save the following as `detect-image.mjs`, then run
`node detect-image.mjs ./selfie.jpg`.

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const apiKey = process.env.NEURALDEFEND_API_KEY;
if (!apiKey) throw new Error("NEURALDEFEND_API_KEY is required");

const imagePath = process.argv[2];
if (!imagePath) {
  console.error("Usage: node detect-image.mjs <image-path>");
  process.exitCode = 1;
} else {
  const client = new NeuroVerifyClient({ apiKey });
  const result = await client.detectImage(imagePath);

  switch (result.status) {
    case "success":
      console.log({
        transactionId: result.uniqueTrxId,
        billable: result.billable,
        riskLevel: result.riskLevel,
        riskScore: result.riskScore,
        message: result.message,
      });
      break;

    case "rejected":
      console.log({
        transactionId: result.uniqueTrxId,
        billable: result.billable,
        reason: result.message,
      });
      break;

    case "unknown":
      console.error(
        "The API returned an outcome this SDK does not recognize. Upgrade the SDK before using it for policy decisions.",
      );
      console.error({
        transactionId: result.uniqueTrxId,
        originalStatus: result.originalStatus,
      });
      break;
  }
}
```

### Video detection

Save the following as `detect-video.mjs`, then run
`node detect-video.mjs ./clip.mp4`.

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const apiKey = process.env.NEURALDEFEND_API_KEY;
if (!apiKey) throw new Error("NEURALDEFEND_API_KEY is required");

const videoPath = process.argv[2];
if (!videoPath) {
  console.error("Usage: node detect-video.mjs <video-path>");
  process.exitCode = 1;
} else {
  const client = new NeuroVerifyClient({ apiKey });
  const result = await client.detectVideo(videoPath, {
    maxFrames: 24,
  });

  switch (result.status) {
    case "success":
      console.log({
        transactionId: result.uniqueTrxId,
        billable: result.billable,
        video: {
          riskLevel: result.videoRiskLevel,
          riskScore: result.videoRiskScore,
          message: result.videoMessage,
        },
        audio: result.hasAudio
          ? {
              riskLevel: result.audioRiskLevel,
              riskScore: result.audioRiskScore,
              message: result.audioMessage,
            }
          : {
              riskLevel: null,
              riskScore: null,
              message: result.audioMessage,
            },
        // Convenience maximum calculated by the SDK, not an API modality.
        overallRiskScore: result.overallRiskScore,
      });
      break;

    case "rejected":
      console.log({
        transactionId: result.uniqueTrxId,
        billable: result.billable,
        reason: result.videoMessage,
      });
      break;

    case "unknown":
      console.error(
        "The API returned an outcome this SDK does not recognize. Upgrade the SDK before using it for policy decisions.",
      );
      console.error({
        transactionId: result.uniqueTrxId,
        originalStatus: result.originalStatus,
      });
      break;
  }
}
```

The video API returns independent video and audio signals.
`overallRiskScore` is an SDK convenience equal to the video score when no audio
was scored, or the maximum of the video and audio scores when both were scored.
Do not treat it as a server-provided overall verdict.

## Browser onboarding and credential safety

> **Never embed a long-lived production API key in browser JavaScript, source
> maps, mobile bundles, static configuration, or HTML. Any browser user can
> extract it.**

Browser clients require an explicit `apiKey`; the browser build never reads
environment variables. The public API contract does not define a browser
credential-issuance endpoint. Do not expose an onboarding-issued API key or
invent a client-side key exchange based on this README.

For normal web applications, upload media to your authenticated application
backend and call this SDK from Node.js. This keeps the Neural Defend key
server-side and lets your backend enforce user authorization, quotas, audit
logging, file limits, and abuse controls.

Browser-side upload to an application-owned endpoint:

```ts
async function detectSelectedImage(fileInput: HTMLInputElement) {
  const file = fileInput.files?.[0];
  if (!file) throw new Error("Select an image first.");

  const body = new FormData();
  body.append("file", file);
  const response = await fetch("/api/media-authenticity/image", {
    method: "POST",
    body,
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error("Analysis request failed.");
  return response.json();
}
```

The application backend should authenticate the user, enforce upload policy,
and pass the authorized bytes to a server-side `NeuroVerifyClient`. Only use
the browser SDK directly when Neural Defend has explicitly approved a
browser-exposable credential for your tenant. In that case, the browser build
accepts only native `File` and `Blob` objects: a `File` supplies its own name,
while a plain `Blob` requires `{ filename: "photo.jpg" }`.

## Method reference

### `new NeuroVerifyClient(options?)`

Creates a production client. In Node.js, `options` is optional because the API
key can come from `NEURALDEFEND_API_KEY`. In browsers, `options.apiKey` is
required.

```ts
const client = new NeuroVerifyClient({
  apiKey: "short-lived-or-server-side-key",
  baseUrl: "https://deepscan.neuraldefend.com",
  allowCustomBaseUrl: false,
  timeoutMs: 120_000,
  maxRetries: 3,
  retryAfterCapMs: 60_000,
  userAgent: "my-service/2.4.0",
  fetch: globalThis.fetch,
  onWarning: (warning) => console.warn(warning.code, warning.message),
});
```

Constructor options:

- `apiKey?: string` — API key sent in the `x-api-key` header. Whitespace is
  trimmed. Node.js falls back to `NEURALDEFEND_API_KEY`; browsers do not.
- `baseUrl?: string` — HTTPS origin. Defaults to
  `https://deepscan.neuraldefend.com`, or to `NEURALDEFEND_BASE_URL` in
  Node.js when set. Paths, credentials, query strings, and fragments are not
  accepted.
- `allowCustomBaseUrl?: boolean` — must be `true` before a non-Neural Defend
  origin is accepted. That origin will receive both the API key and uploaded
  media; enable this only for a trusted private deployment.
- `timeoutMs?: number` — timeout for each request attempt, including reading
  the response body. Default: `120000`; must be greater than zero.
- `maxRetries?: number` — retry count after the initial attempt. Default: `3`;
  integer from `0` through `3`.
- `retryAfterCapMs?: number` — maximum wait applied to a `Retry-After` value.
  Default: `60000`. Negative values are normalized to `0`.
- `userAgent?: string` — Node.js user agent override. The Node.js default for
  this release is `@neuraldefend/sdk/1.0.2`; browsers cannot set this header
  through the SDK.
- `fetch?: typeof globalThis.fetch` — custom Fetch-compatible implementation,
  primarily for controlled runtimes and testing.
- `onWarning?: (warning: ValidationWarning) => void` — receives non-fatal
  local validation warnings. Version 1.0.1 emits
  `code: "unsupported_extension"` when a filename extension is not documented.

API keys are redacted from the client's string and JSON representations. This
is defense in depth, not a substitute for secret handling. HTTP redirects are
never followed.

### `NeuroVerifyClient.staging(options?)`

Creates a client for `https://stage.deepscan.neuraldefend.com`.

```ts
const client = NeuroVerifyClient.staging({
  apiKey: process.env.NEURALDEFEND_STAGING_API_KEY,
});
```

Node.js can omit `options` if `NEURALDEFEND_API_KEY` contains a staging key.
Browsers must pass options with an explicit key. Staging is for integration
testing only; use credentials scoped to that environment.

### `client.detectImage(input, options?)`

Uploads media to `/detect/image` and resolves to `Promise<ImageResult>`.

Accepted inputs:

- Node.js: filesystem path (`string`), `Uint8Array`, `Buffer`, `Blob`, `File`,
  or a Node.js readable stream.
- Browser: `File` or `Blob`.

Options:

- `filename?: string` — multipart filename and MIME-selection input.
- `signal?: AbortSignal` — cancels stream preparation, retry waits, the upload,
  and response processing.

Filename behavior:

- A path uses its basename by default.
- A `File` uses `File.name` by default.
- A file-backed Node.js stream can use its string `path`.
- `Uint8Array`, `Buffer`, plain `Blob`, and unnamed streams require
  `options.filename`.
- `options.filename` overrides an inferred name for every input type.

Node.js accepts only readable regular-file paths and rejects a symbolic link
when the supplied file path itself is a symbolic link. Paths and streams are
copied into a private, size-bounded temporary file so
each retry can create a fresh upload without retaining the entire stream in
memory. Temporary media is removed after the operation.

### `client.detectVideo(input, options?)`

Uploads media to `/detect/video` and resolves to `Promise<VideoResult>`. It
accepts the same platform-specific input types and filename rules as
`detectImage()`.

Options:

- `filename?: string` — multipart filename and MIME-selection input.
- `signal?: AbortSignal` — cancellation signal.
- `maxFrames?: number` — maximum sampled frames; integer from `1` through
  `100`. The API default is `12`.
- `sampleRate?: number` — optional server sampling override; integer greater
  than or equal to `1`.

`maxFrames` and `sampleRate` are sent as the `max_frames` and `sample_rate`
query parameters. Increasing frame coverage can increase processing latency.

## Working with results

### Normalized fields

The SDK converts wire-format `snake_case` fields into typed `camelCase`
properties and converts wire `billable: "Y" | "N"` into a boolean. Common
fields on image and video results are:

- `uniqueTrxId: string`
- `filename: string`
- `contentType: string`
- `statusCode: number`
- `billable: boolean`
- `aiThreatSignals: readonly string[]`
- `status: "success" | "rejected" | "unknown"`
- `scored: boolean`
- `rejected: boolean`

Image results add `riskScore`, `riskLevel`, and `message`. Video results add
`hasAudio`, `videoRiskScore`, `videoRiskLevel`, `videoMessage`,
`audioRiskScore`, `audioRiskLevel`, `audioMessage`, and `overallRiskScore`.
Scored risk values are in the API's `0.1` through `10.0` range; higher values
indicate higher observed AI/manipulation risk. Nullable score and level fields
are `null` when that modality was not scored. `aiThreatSignals` identifies
checks reported by the service on scored responses and may evolve; do not
build fixed logic around the list.

Always branch on `result.status` before reading scored fields. A business
rejection is a resolved result, not a thrown error. This includes HTTP 400
validation/security responses and HTTP 200 face-policy rejections.

### JSON serialization and `result.raw`

`JSON.stringify(result)` emits the stable normalized properties and excludes
`raw`, which is deliberately non-enumerable:

```ts
const auditRecord = JSON.stringify(result);
```

Every resolved result also exposes `result.raw`: the deeply frozen, redacted
wire envelope using the API's original field names. It is available for
explicit diagnostics and forward-compatibility investigation:

```ts
if (result.status === "unknown") {
  console.error("Original status:", result.originalStatus);
  console.error("Diagnostic wire envelope:", result.raw);
}
```

`raw` is not a stable application contract. It may contain filenames,
messages, future fields, or other personal/customer data. Do not routinely log
or persist it. If diagnostic collection is necessary, apply access controls,
redaction, encryption, and a short retention period. API keys found in server
payload strings are redacted by the SDK, but media-related data is not.

### Image outcomes

The following are representative normalized JSON values. Scores and messages
vary with submitted media and service evolution; do not write policy against
these example numbers or exact message text.

Low, medium, and high success results have `status: "success"`, a numeric
`riskScore`, and a service-owned `riskLevel`:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_low",
  "filename": "selfie.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "riskScore": 2.2,
  "riskLevel": "low",
  "message": "Not likely to be Spoof or AI-generated"
}
```

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_medium",
  "filename": "portrait.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "riskScore": 5.5,
  "riskLevel": "medium",
  "message": "Less likely to be Spoof or AI-generated"
}
```

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_high",
  "filename": "printed_photo.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "riskScore": 8.7,
  "riskLevel": "high",
  "message": "Likely to be Spoof detected"
}
```

Interpret `low` as lower observed risk, not proof of authenticity. Treat
`medium` as inconclusive and gather more evidence. Treat `high` as a reason to
escalate or review, not as sufficient evidence for an automatic rejection.
Use the returned band rather than reconstructing it from score thresholds.

No-face and multiple-face outcomes are billable HTTP 200 rejections because
the service performed face-policy processing:

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "uniqueTrxId": "trx_example_no_face",
  "filename": "landscape.jpg",
  "contentType": "image/jpeg",
  "statusCode": 6,
  "billable": true,
  "aiThreatSignals": [],
  "riskScore": null,
  "riskLevel": null,
  "message": "No face detected in the image"
}
```

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "uniqueTrxId": "trx_example_multiple_faces",
  "filename": "group_photo.jpg",
  "contentType": "image/jpeg",
  "statusCode": 7,
  "billable": true,
  "aiThreatSignals": [],
  "riskScore": null,
  "riskLevel": null,
  "message": "Multiple faces detected in the image"
}
```

Server-side input validation and security failures are normally non-billable
HTTP 400 rejections:

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "uniqueTrxId": "trx_example_security",
  "filename": "suspicious.jpg.php",
  "contentType": "application/octet-stream",
  "statusCode": 2,
  "billable": false,
  "aiThreatSignals": [],
  "riskScore": null,
  "riskLevel": null,
  "message": "File failed security validation"
}
```

The same result shape covers unsupported formats, excessive file size, unsafe
content, inadequate dimensions, blur, brightness, contrast, or processing
failures. Use `message` for user guidance, but branch on `status` and structured
fields rather than exact message text.

### Video outcomes

A success with both modalities has `hasAudio: true`. The example scores are
representative, not fixed expectations:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "hasAudio": true,
  "uniqueTrxId": "trx_example_video",
  "filename": "selfie_video.mp4",
  "contentType": "video/mp4",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": [
    "Frame-Level Visual Analysis",
    "Audio Frequency Analysis"
  ],
  "videoRiskScore": 2.4,
  "videoRiskLevel": "low",
  "videoMessage": "Not likely to be AI-generated",
  "audioRiskScore": 2,
  "audioRiskLevel": "low",
  "audioMessage": "Not likely to be AI-generated",
  "overallRiskScore": 2.4
}
```

A video without an audio track can still be scored successfully:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "hasAudio": false,
  "uniqueTrxId": "trx_example_silent",
  "filename": "silent_clip.mp4",
  "contentType": "video/mp4",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Frame-Level Visual Analysis"],
  "videoRiskScore": 2.1,
  "videoRiskLevel": "low",
  "videoMessage": "Not likely to be AI-generated",
  "audioRiskScore": null,
  "audioRiskLevel": null,
  "audioMessage": "No audio track detected",
  "overallRiskScore": 2.1
}
```

Video processing requires scorable single-face frames. Multi-face sampled
frames are skipped. If no sampled frame contains exactly one scorable face,
the service returns the same no-face rejection used for zero-face video and
does not score audio:

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "hasAudio": false,
  "uniqueTrxId": "trx_example_video_no_face",
  "filename": "non_face_video.mp4",
  "contentType": "video/mp4",
  "statusCode": 6,
  "billable": true,
  "aiThreatSignals": [],
  "videoRiskScore": null,
  "videoRiskLevel": null,
  "videoMessage": "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.",
  "audioRiskScore": null,
  "audioRiskLevel": null,
  "audioMessage": null,
  "overallRiskScore": null
}
```

### Unknown forward-compatible results

If a future API response uses an unknown outcome status or risk band, version
1.0.1 resolves an `"unknown"` result instead of silently treating it as a
known success or rejection. For example:

```json
{
  "status": "unknown",
  "scored": false,
  "rejected": false,
  "originalStatus": "pending",
  "originalRiskLevel": "low",
  "uniqueTrxId": "trx_synthetic_image_base",
  "filename": "future.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ],
  "riskScore": 2.2,
  "riskLevel": "low",
  "message": "Not likely to be Spoof or AI-generated"
}
```

Do not make a policy decision from an unknown result. Record the transaction
ID, inspect `raw` only under your diagnostic controls, and upgrade the SDK.
Unknown numeric `statusCode` values alone remain available on an otherwise
valid known result.

## Errors

All SDK errors extend `NeuroVerifyError` and expose `detail`; HTTP-derived
errors can also expose `statusCode` and `requestId`.

- `ValidationError` — local configuration, option, filename, input, empty-file,
  or size validation failed before a valid request could complete. Its `code`
  identifies the validation category. Correct the input; do not retry it
  unchanged.
- `AuthenticationError` — HTTP 401. Verify that the key is active and belongs
  to the selected environment. The SDK does not retry it.
- `ScopeError` — HTTP 403. The key lacks endpoint or plan access. The SDK does
  not retry it.
- `RateLimitError` — HTTP 429 after retries are exhausted. It may expose
  `retryAfter` in seconds plus string-valued `limit`, `remaining`, and `reset`
  metadata.
- `TimeoutError` — the configured per-attempt timeout elapsed. Timeouts are not
  automatically retried.
- `NetworkError` — no response was received, for example because of DNS,
  connectivity, or TLS failure. Network failures are not automatically
  retried.
- `ServerError` — HTTP 500/503 after retries are exhausted, or a wire result
  with `status: "error"`. It may expose a deeply frozen `raw` diagnostic
  envelope.
- `ProtocolError` — the response was malformed, missing its expected envelope,
  or contained invalid required fields. Do not assume retrying is safe; retain
  the request/transaction ID and contact support if it persists.
- `AbortError` — the caller's `AbortSignal` canceled preparation, a retry wait,
  upload, or response processing. This is distinct from a timeout.
- `HttpError` — another unexpected HTTP status. The specific HTTP error
  classes above extend this class.

```ts
import {
  AbortError,
  AuthenticationError,
  HttpError,
  NetworkError,
  NeuroVerifyClient,
  ProtocolError,
  RateLimitError,
  ScopeError,
  ServerError,
  TimeoutError,
  ValidationError,
} from "@neuraldefend/sdk";

const client = new NeuroVerifyClient();

try {
  const result = await client.detectImage("./selfie.jpg");
  // Handle result.status here.
  console.log(result.status, result.uniqueTrxId);
} catch (error) {
  if (error instanceof ValidationError) {
    console.error("Fix the request:", error.code, error.detail);
  } else if (error instanceof AuthenticationError) {
    console.error("Check the API key.");
  } else if (error instanceof ScopeError) {
    console.error("Request image endpoint access.");
  } else if (error instanceof RateLimitError) {
    console.error("Rate limit exhausted. Retry after:", error.retryAfter);
  } else if (error instanceof TimeoutError) {
    console.error("The request timed out.");
  } else if (error instanceof NetworkError) {
    console.error("No response was received.");
  } else if (error instanceof ServerError) {
    console.error("Service error:", error.statusCode, error.requestId);
  } else if (error instanceof ProtocolError) {
    console.error("Unexpected response contract:", error.requestId);
  } else if (error instanceof AbortError) {
    console.error("Canceled by caller.");
  } else if (error instanceof HttpError) {
    console.error("Unexpected HTTP response:", error.statusCode);
  } else {
    throw error;
  }
}
```

To cancel a request:

```ts
const controller = new AbortController();
const pending = client.detectVideo("./clip.mp4", {
  signal: controller.signal,
});

controller.abort();
await pending; // Rejects with AbortError.
```

## Retries, billing, and idempotency

By default, the SDK makes the initial request and up to three retries:

- HTTP 500 and 503 use exponential delays of approximately 1, 2, and 4
  seconds, with jitter.
- HTTP 429 honors a numeric or HTTP-date `Retry-After` value up to
  `retryAfterCapMs`; without a valid header it uses exponential delays.
- HTTP 400, 401, 403, other HTTP statuses, timeouts, protocol failures, aborts,
  and network failures are not retried.

Set `maxRetries: 0` to disable automatic retries.

Requests are not idempotent and the API does not expose an idempotency-key
option through this SDK. Every accepted attempt can receive a new
`uniqueTrxId`; resubmitting the same media, including automatic retries, may
create separate transactions with separate billing implications. The
`billable` field is authoritative for the returned transaction. A rejection
can be billable, as shown by no-face and multiple-face policy outcomes. Persist
`uniqueTrxId` with your audit record and avoid application-level retries unless
you have accounted for duplicate processing and billing.

## Media formats and limits

Image uploads:

- Extensions: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`, `.webp`,
  `.heic`, `.heif`
- Exact maximum: 10 MiB (`10,485,760` bytes)
- API minimum resolution: 224 by 224 pixels
- Face policy: exactly one face

Video uploads:

- Extensions: `.mp4`, `.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`,
  `.ogg`, `.ogv`
- Exact maximum: `1,500,000,000` bytes
- Default frame sample maximum: `12`
- `maxFrames`: integer `1` through `100`
- `sampleRate`: integer greater than or equal to `1`
- Face policy: sampled frames with multiple faces are skipped; at least one
  scorable single-face frame is required

The SDK rejects empty and oversized input locally. It warns, but does not
reject, an undocumented extension because the server performs content and
security validation. Known extensions select deterministic MIME types. For an
unknown extension, an explicit `Blob.type` is preserved; otherwise the SDK
uses `application/octet-stream`. A valid extension does not bypass server-side
format or security inspection.

## Security and privacy

- Upload media only with the data owner's authorization and an appropriate
  legal basis.
- Treat images, video, audio, filenames, transaction IDs, and diagnostics as
  potentially sensitive data. Face media may be biometric personal data.
- Apply your organization's consent, purpose limitation, retention, deletion,
  residency, encryption, access-control, and incident-response requirements.
- Keep production API keys in a managed secret store, rotate them, scope them
  to required endpoints and environments, and never expose them to an
  untrusted client.
- Authenticate and authorize users before accepting uploads through your
  backend. Enforce your own size, type, quota, and abuse controls before
  forwarding media.
- Avoid routine logging of `result.raw`, server messages, local paths, or
  filenames. Sanitize support bundles.
- Do not enable `allowCustomBaseUrl` unless the destination is trusted to
  receive both credentials and media.
- Do not use low risk as proof, or high risk as the sole reason for an adverse
  action. Design a review and appeal path for consequential decisions.

## Troubleshooting

**`api_key_required`**

Set `NEURALDEFEND_API_KEY` in the Node.js process before constructing the
client, or pass `apiKey`. Browsers always require an explicit short-lived key.

**`filename_required`**

Pass `{ filename: "photo.jpg" }` or `{ filename: "clip.mp4" }` when using
bytes, a plain `Blob`, or a stream with no string path. Include the real
extension.

**`file_too_large` or `empty_file`**

Check the exact byte limits above before upload. For streams, the SDK stops
spooling once the limit is exceeded.

**`unsupported_extension` warning**

Use a documented extension that matches the actual content. The warning does
not mean the upload is accepted; the server still inspects and may reject it.

**Image returns no face or multiple faces**

Use a well-lit, in-focus image at least 224 by 224 pixels with one clearly
visible subject. Crop group images to one subject before submission.

**Video returns no face even though faces are visible**

The API needs at least one sampled frame with exactly one scorable face.
Frames containing multiple faces are skipped. Use a single-subject clip or
adjust `maxFrames` within the supported range when broader temporal coverage
is appropriate.

**401 or 403**

Confirm the key's environment, validity, endpoint scope, and plan access.
Production and staging keys may not be interchangeable.

**429**

The SDK already retries up to `maxRetries` and honors `Retry-After` up to the
configured cap. After `RateLimitError`, use its metadata for scheduling and
reduce concurrency; do not immediately loop.

**Timeout or network error**

Check connectivity and service reachability. For large video uploads, choose a
realistic `timeoutMs`. The SDK deliberately does not retry these failures
because whether the server accepted the media can be uncertain.

**500 or 503**

The SDK retries these responses automatically. If `ServerError` remains after
the retry budget, record `requestId` and the relevant transaction ID, then
contact support. Do not include media or unrestricted `raw` data in a support
ticket unless requested through an approved secure channel.

**`ProtocolError` or `status: "unknown"`**

Upgrade `@neuraldefend/sdk` and retry only after considering duplicate billing.
If the issue persists, provide the SDK version and request/transaction ID to
support.

## Wire-level API documentation

For exhaustive response scenarios, wire field names, status codes, current
messages, and direct HTTP integration details, see:

- [Unified Face Authenticity Score](../../docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](../../docs/client/unified-video-authenticity.md)

The SDK's normalized result types are the application contract for SDK users.
Use the wire documents when diagnosing a payload or implementing without this
SDK.
