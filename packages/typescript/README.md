<div align="center">

# NeuralDefend TypeScript SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Node.js or the browser in a few lines of code.**

[![npm](https://img.shields.io/npm/v/@neuraldefend/sdk?style=flat-square&logo=npm&logoColor=white&label=npm&color=CB3837)](https://www.npmjs.com/package/@neuraldefend/sdk)
[![Node.js](https://img.shields.io/badge/node-22%2B-5FA04E?style=flat-square&logo=nodedotjs&logoColor=white)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/types-included-3178C6?style=flat-square&logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![ESM + CJS](https://img.shields.io/badge/module-ESM%20%2B%20CJS-F7DF1E?style=flat-square&logo=javascript&logoColor=black)](#installation)
[![Browser ready](https://img.shields.io/badge/browser-ready-4285F4?style=flat-square&logo=googlechrome&logoColor=white)](#browser-onboarding-and-credential-safety)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start) · [Examples](#examples) · [Results](#working-with-results) · [Errors](#errors) · [Troubleshooting](#troubleshooting)

</div>

---

## In plain words

You give the SDK a photo or a video. It sends the file to Neural Defend's **NeuroVerify**
service and gives you back an answer like this:

> "This face has a **low** / **medium** / **high** risk of being fake."

That is the whole idea. You do not need to know anything about machine learning, HTTP, or
multipart uploads; the SDK handles all of that for you.

| You want to...          | Call                                    | You get back                                        |
| ----------------------- | --------------------------------------- | --------------------------------------------------- |
| Check a photo of a face | `await client.detectImage("photo.jpg")` | An `ImageResult` with one risk level                |
| Check a video           | `await client.detectVideo("clip.mp4")`  | A `VideoResult` with a video risk and an audio risk |

Think of the risk level as a traffic light:

| Risk level  | Meaning                                   | What to do                              |
| ----------- | ----------------------------------------- | --------------------------------------- |
| `low` 🟢    | Few signs of manipulation were found      | Continue, using your normal process     |
| `medium` 🟡 | The result is unclear                     | Ask for more evidence or a human review |
| `high` 🔴   | Strong signs of spoofing or AI generation | Escalate to a human reviewer            |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection** (`result.status === "rejected"`),
not a crash: the promise resolves, it does not throw. The [examples](#examples) show how
to handle each case.

## About this SDK

The official TypeScript and JavaScript client for the Neural Defend NeuroVerify image and
video authenticity APIs. Version `1.0.4` provides:

- typed, normalized image and video results;
- Node.js and browser entry points from one package;
- bounded media validation and deterministic MIME selection;
- cancellation, timeouts, rate-limit handling, and controlled retries; and
- forward-compatible handling of response statuses and risk bands introduced by newer API
  versions.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an error, including some HTTP 200 responses.
- `billable` is the authoritative billing indicator for each returned transaction.

Risk scores and risk bands are decision-support signals. They are not proof that media is
authentic or manipulated, and they should never be the sole basis for an automatic
acceptance, rejection, or adverse decision. Combine them with other evidence, policy
checks, and human review appropriate to your use case.

## Requirements

- `@neuraldefend/sdk` version `1.0.4`
- Node.js 22 or newer for server-side use
- A current evergreen browser for browser use
- A Neural Defend API key with access to the image and/or video endpoint
- Network access to the HTTPS API origin

The package has no runtime dependencies and ships its own TypeScript type definitions.

## Installation

Install the pinned release with your package manager:

```sh
npm install @neuraldefend/sdk@1.0.4
```

```sh
pnpm add @neuraldefend/sdk@1.0.4
```

```sh
yarn add @neuraldefend/sdk@1.0.4
```

Confirm the package can be imported:

```sh
node --input-type=module -e "import { NeuroVerifyClient } from '@neuraldefend/sdk'; console.log('@neuraldefend/sdk ready', typeof NeuroVerifyClient)"
```

```text
@neuraldefend/sdk ready function
```

The package supports ESM `import` and CommonJS `require()` in Node.js. Bundlers
automatically select the browser build for browser applications.

```js
// ESM (.mjs, or "type": "module")
import { NeuroVerifyClient } from "@neuraldefend/sdk";

// CommonJS (.cjs)
const { NeuroVerifyClient } = require("@neuraldefend/sdk");
```

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is
no self-service key on npm — request access from the company first, then configure the
SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media
   analysis, and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key,
   staging credential, or rate-limit details.
3. Store the key in a secret manager or `NEURALDEFEND_API_KEY` (Node.js), or pass
   `apiKey` explicitly. In browsers, never embed a long-lived production key in
   client-side code (see
   [Browser onboarding and credential safety](#browser-onboarding-and-credential-safety)).
4. For REST endpoint reference while you wait for a key, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## API key configuration

For Node.js, keep the onboarding key in a secret manager or environment variable.

macOS/Linux:

```bash
# Request a key at https://neuraldefend.com/ (Book a Demo), then export it:
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
```

PowerShell:

```powershell
# Request a key at https://neuraldefend.com/ (Book a Demo), then set it:
$env:NEURALDEFEND_API_KEY = "replace-with-your-api-key"
```

The Node.js client reads `NEURALDEFEND_API_KEY` when `apiKey` is not passed:

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

// Requires NEURALDEFEND_API_KEY from https://neuraldefend.com/ onboarding.
const client = new NeuroVerifyClient();
```

You can pass `apiKey` explicitly when it comes from an application secret provider:

```js
const client = new NeuroVerifyClient({
  apiKey: await secretProvider.get("neuraldefend-api-key"),
});
```

An explicit `apiKey` takes precedence over `NEURALDEFEND_API_KEY`. Never commit keys to
source control, example files, container images, or shell history.

## Quick start

### Node.js: check an image

Save as `detect-image.mjs` and run `node detect-image.mjs`:

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const result = await new NeuroVerifyClient().detectImage("selfie.jpg"); // uses NEURALDEFEND_API_KEY
console.log(JSON.stringify(result, null, 2));
```

That's it. You get the full response:

```json
{
  "uniqueTrxId": "trx_example_image_low",
  "filename": "selfie.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "status": "success",
  "scored": true,
  "rejected": false,
  "riskScore": 2.2,
  "riskLevel": "low",
  "message": "Not likely to be Spoof or AI-generated"
}
```

The field that matters most is `riskLevel`: `low`, `medium`, or `high`.

### Node.js: check a video

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const result = await new NeuroVerifyClient().detectVideo("clip.mp4");
console.log(JSON.stringify(result, null, 2));
```

You get the full response, with a separate result for the picture and for the sound:

```json
{
  "uniqueTrxId": "trx_example_video_modalities",
  "filename": "clip.mp4",
  "contentType": "video/mp4",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Face Swap Detection", "Audio Frequency Analysis"],
  "status": "success",
  "scored": true,
  "rejected": false,
  "hasAudio": true,
  "videoRiskScore": 2.2,
  "videoRiskLevel": "low",
  "videoMessage": "Not likely to be AI-generated",
  "audioRiskScore": 8.4,
  "audioRiskLevel": "high",
  "audioMessage": "Likely to be AI-generated",
  "overallRiskScore": 8.4
}
```

`overallRiskScore` is simply the higher of the two scores.

### Browser: send a photo to your backend

In a web page, the safest pattern is to upload the file to **your own** backend, which
calls the SDK from Node.js and keeps the Neural Defend key server-side. The backend half
is [Example 8](#8-add-a-check-to-an-express-api).

```ts
async function detectSelectedImage(fileInput: HTMLInputElement) {
  const file = fileInput.files?.[0];
  if (!file) throw new Error("Select an image first.");

  const body = new FormData();
  body.append("photo", file);
  const response = await fetch("/verify-selfie", {
    method: "POST",
    body,
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error("Analysis request failed.");
  return response.json();
}

const result = await detectSelectedImage(
  document.querySelector<HTMLInputElement>("#selfie")!,
);
console.log(result.status, result.riskLevel, result.message);
```

Output in the browser console (representative):

```text
success low Not likely to be Spoof or AI-generated
```

## Examples

Each Node.js example is complete: save it as a `.mjs` file (so top-level `await` works),
set `NEURALDEFEND_API_KEY`, and run it with `node`. The output shown under each example is
representative; your scores, transaction IDs, and messages will differ.

|  #  | Example                                                                        | You will learn                                         |
| :-: | ------------------------------------------------------------------------------ | ------------------------------------------------------ |
|  1  | [Check one photo](#1-check-one-photo)                                          | The smallest useful program                            |
|  2  | [Check a video with sound](#2-check-a-video-with-sound)                        | Reading the separate video and audio results           |
|  3  | [Turn a result into a decision](#3-turn-a-result-into-a-decision)              | Mapping low, medium, high, and rejected to actions     |
|  4  | [Upload bytes from memory](#4-upload-bytes-from-memory)                        | Checking a `Buffer`, `Uint8Array`, or `Blob`           |
|  5  | [Check a whole folder](#5-check-a-whole-folder)                                | Batch processing with a summary                        |
|  6  | [Handle every kind of error](#6-handle-every-kind-of-error)                    | Telling bad input, bad keys, and outages apart         |
|  7  | [Save an audit record](#7-save-an-audit-record)                                | Keeping transaction IDs for billing and support        |
|  8  | [Add a check to an Express API](#8-add-a-check-to-an-express-api)              | Receiving an upload on your server                     |
|  9  | [Check a photo in the browser](#9-check-a-photo-in-the-browser)                | Using `<input type="file">` with a short-lived key     |
| 10  | [Tune video sampling and time limits](#10-tune-video-sampling-and-time-limits) | Trading speed for coverage, timeouts, and cancellation |

### 1. Check one photo

Print just the answer instead of the whole response.

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const result = await new NeuroVerifyClient().detectImage("selfie.jpg");
console.log(result.riskLevel, result.message);
```

Output:

```text
low Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** answers: one for the picture and one for the sound.

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const result = await new NeuroVerifyClient().detectVideo("interview.mp4");
console.log("Video:", result.videoRiskLevel);
console.log("Audio:", result.audioRiskLevel);
```

Output:

```text
Video: low
Audio: high
```

Here the face looks real but the voice is likely fake. A video with no sound prints
`Audio: null`.

### 3. Turn a result into a decision

Your application usually needs one of a few actions. Write that mapping once and reuse it.
Always branch on the **risk level**, never on your own numeric threshold, because the
service may tune its scoring bands.

This example is TypeScript, so the compiler checks that every `status` and `riskLevel` is
handled. Save it as `decide.mts` and run it with `npx tsx decide.mts`.

```ts
import { NeuroVerifyClient, type ImageResult } from "@neuraldefend/sdk";

function decide(result: ImageResult): string {
  switch (result.status) {
    case "rejected":
      return `ASK FOR A NEW PHOTO - ${result.message}`;
    case "unknown":
      return `MANUAL REVIEW - unrecognized status "${result.originalStatus}"`;
    case "success":
      switch (result.riskLevel) {
        case "low":
          return "CONTINUE";
        case "medium":
          return "MANUAL REVIEW";
        case "high":
          return "ESCALATE";
      }
  }
}

const client = new NeuroVerifyClient();
for (const path of ["selfie.jpg", "printed_photo.jpg", "landscape.jpg"]) {
  console.log(
    `${path.padEnd(20)} -> ${decide(await client.detectImage(path))}`,
  );
}
```

Output:

```text
selfie.jpg           -> CONTINUE
printed_photo.jpg    -> ESCALATE
landscape.jpg        -> ASK FOR A NEW PHOTO - No face detected in the image
```

### 4. Upload bytes from memory

When a file arrives from a web form, a queue, or object storage, you often have bytes
instead of a path. Pass the bytes and a `filename`; the filename tells the SDK the format.

```js
import { readFile } from "node:fs/promises";
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const bytes = await readFile("selfie.jpg"); // a Buffer, or bytes from your storage service

const client = new NeuroVerifyClient();
const result = await client.detectImage(bytes, { filename: "selfie.jpg" });

console.log(
  `${bytes.byteLength.toLocaleString("en-US")} bytes checked -> ${result.riskLevel}`,
);
```

Output:

```text
482,113 bytes checked -> low
```

The same call accepts other in-memory and streaming inputs in Node.js:

| Input                    | Example                                                             | `filename` needed?              |
| ------------------------ | ------------------------------------------------------------------- | ------------------------------- |
| `Buffer` or `Uint8Array` | `client.detectImage(bytes, { filename: "selfie.jpg" })`             | Yes                             |
| Plain `Blob`             | `client.detectImage(new Blob([bytes]), { filename: "selfie.jpg" })` | Yes                             |
| `File`                   | `client.detectImage(file)`                                          | No, `File.name` is used         |
| File-backed stream       | `client.detectImage(createReadStream("selfie.jpg"))`                | No, the stream's `path` is used |
| Other readable stream    | `client.detectImage(stream, { filename: "selfie.jpg" })`            | Yes                             |

See [`client.detectImage`](#clientdetectimageinput-options) for the full rules.

### 5. Check a whole folder

Create one client and reuse it for every file. Each file is checked in turn and counted in
a summary.

```js
import { readdir } from "node:fs/promises";
import { extname, join } from "node:path";
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const IMAGE_TYPES = new Set([".jpg", ".jpeg", ".png", ".webp", ".heic"]);
const folder = "uploads";
const summary = {};

const client = new NeuroVerifyClient();
for (const name of (await readdir(folder)).sort()) {
  if (!IMAGE_TYPES.has(extname(name).toLowerCase())) continue;

  const result = await client.detectImage(join(folder, name));
  const outcome =
    result.status === "success" ? result.riskLevel : result.status;
  summary[outcome] = (summary[outcome] ?? 0) + 1;
  console.log(`${name.padEnd(24)} ${outcome.padEnd(9)} ${result.message}`);
}

console.log("\nSummary:", summary);
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: { low: 1, rejected: 1, medium: 1, high: 1 }
```

Each call is a separate transaction and may be billable. Check your rate limits before
running large batches.

### 6. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation                                    | How it shows up                                                                  | Who fixes it                    |
| -------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------- |
| The file was checked but could not be scored | A resolved result with `status === "rejected"`                                   | The end user sends better media |
| Your setup is wrong (missing key, bad path)  | `ValidationError`, `AuthenticationError`, `ScopeError`                           | You, the developer              |
| The service or network had a problem         | `RateLimitError`, `ServerError`, `TimeoutError`, `NetworkError`, `ProtocolError` | Try again later                 |

Every SDK error extends `NeuroVerifyError`, so you can check the specific classes first
with `instanceof` and catch the rest at the end.

```js
import {
  AuthenticationError,
  NeuroVerifyClient,
  NeuroVerifyError,
  RateLimitError,
  ScopeError,
  ValidationError,
} from "@neuraldefend/sdk";

try {
  const client = new NeuroVerifyClient();
  const result = await client.detectImage("selfie.jpg");

  if (result.status === "rejected") {
    console.log(`Please upload a different photo: ${result.message}`);
  } else if (result.status === "success") {
    console.log(`Risk: ${result.riskLevel}`);
  } else {
    console.log(
      `Unrecognized outcome; upgrade the SDK: ${result.originalStatus}`,
    );
  }
} catch (error) {
  if (error instanceof ValidationError) {
    console.error(`Fix the input or configuration: ${error.detail}`);
  } else if (error instanceof AuthenticationError) {
    console.error(
      "The API key is invalid or expired. Check NEURALDEFEND_API_KEY.",
    );
  } else if (error instanceof ScopeError) {
    console.error(
      "This key cannot use the image endpoint. Ask Neural Defend to add it.",
    );
  } else if (error instanceof RateLimitError) {
    console.error(
      `Too many requests. Try again in ${error.retryAfter} seconds.`,
    );
  } else if (error instanceof NeuroVerifyError) {
    console.error(
      `Service problem (${error.name}), request id: ${error.requestId}`,
    );
  } else {
    throw error; // not an SDK error: let it surface
  }
}
```

Output when the key is missing:

```text
Fix the input or configuration: apiKey is required; pass it explicitly or set NEURALDEFEND_API_KEY.
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

`ValidationError` also has a machine-readable `code`, such as `api_key_required` or
`filename_required`. The [Errors](#errors) section lists every error class.

### 7. Save an audit record

Every result has a `uniqueTrxId`. Store it: it is what support and billing will ask for.
Results are plain objects, so `JSON.stringify` works on them directly.

```js
import { appendFile } from "node:fs/promises";
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const client = new NeuroVerifyClient();
const result = await client.detectImage("selfie.jpg");

const record = {
  checkedAt: new Date().toISOString(),
  transactionId: result.uniqueTrxId,
  status: result.status,
  riskLevel: result.status === "success" ? result.riskLevel : null,
  billable: result.billable,
};

await appendFile("audit.jsonl", JSON.stringify(record) + "\n", "utf8");
console.log(JSON.stringify(record, null, 2));
```

Output:

```json
{
  "checkedAt": "2026-10-16T09:41:07.512Z",
  "transactionId": "trx_example_image_low",
  "status": "success",
  "riskLevel": "low",
  "billable": true
}
```

Store only the fields you need. Avoid logging filenames or `result.raw`, which may
contain personal data.

### 8. Add a check to an Express API

This [Express](https://expressjs.com/) server accepts a photo upload and returns the SDK's
normalized result. One client is created at startup and shared by all requests. Install
the extras first with `npm install express@5 multer`.

```js
import express from "express";
import multer from "multer";
import {
  NeuroVerifyClient,
  NeuroVerifyError,
  ValidationError,
} from "@neuraldefend/sdk";

const client = new NeuroVerifyClient(); // reads NEURALDEFEND_API_KEY on the server
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // the image limit is 10 MiB
});
const app = express();

app.post("/verify-selfie", upload.single("photo"), async (req, res) => {
  if (!req.file) {
    return res
      .status(400)
      .json({ error: 'Attach an image in the "photo" field.' });
  }
  try {
    const result = await client.detectImage(req.file.buffer, {
      filename: req.file.originalname || "upload.jpg",
    });
    res.json(result); // normalized fields only; result.raw is never included
  } catch (error) {
    if (error instanceof ValidationError) {
      return res.status(422).json({ error: error.detail });
    }
    if (error instanceof NeuroVerifyError) {
      return res
        .status(503)
        .json({ error: "Verification is temporarily unavailable" });
    }
    throw error;
  }
});

app.listen(3000, () => console.log("Listening on http://localhost:3000"));
```

Run it with `node server.mjs`, then call it:

```bash
curl -F "photo=@selfie.jpg" http://localhost:3000/verify-selfie
```

Output (formatted for readability):

```json
{
  "uniqueTrxId": "trx_example_image_low",
  "filename": "selfie.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "status": "success",
  "scored": true,
  "rejected": false,
  "riskScore": 2.2,
  "riskLevel": "low",
  "message": "Not likely to be Spoof or AI-generated"
}
```

In production, authenticate the user and apply your own quotas before forwarding media.

### 9. Check a photo in the browser

> **Only use this pattern when Neural Defend has approved a browser-exposable credential
> for your tenant.** Otherwise, use the backend pattern from
> [Example 8](#8-add-a-check-to-an-express-api).

The page asks **your own** backend for a short-lived credential, then checks the selected
file directly. A `File` from `<input type="file">` already carries its name, so no
`filename` option is needed. Bundlers such as Vite or webpack pick the browser build
automatically.

`index.html`:

```html
<input id="selfie" type="file" accept="image/*" />
<p id="result"></p>
<script type="module" src="./main.ts"></script>
```

`main.ts`:

```ts
import { NeuroVerifyClient, NeuroVerifyError } from "@neuraldefend/sdk";

// Your own route. It must authenticate the user and return a short-lived
// credential that Neural Defend approved for browser use. Never return a
// long-lived production key here.
async function getBrowserCredential(): Promise<string> {
  const response = await fetch("/api/neuraldefend/browser-credential", {
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error("Could not get a verification credential.");
  const { apiKey } = (await response.json()) as { apiKey: string };
  return apiKey;
}

const input = document.querySelector<HTMLInputElement>("#selfie")!;
const output = document.querySelector<HTMLParagraphElement>("#result")!;

input.addEventListener("change", async () => {
  const file = input.files?.[0];
  if (!file) return;
  output.textContent = "Checking...";

  try {
    // Browsers never read environment variables: apiKey is required.
    const client = new NeuroVerifyClient({
      apiKey: await getBrowserCredential(),
    });
    const result = await client.detectImage(file);

    if (result.status === "success") {
      output.textContent = `Risk: ${result.riskLevel}`;
    } else if (result.status === "rejected") {
      output.textContent = `Please try another photo: ${result.message}`;
    } else {
      output.textContent =
        "We could not read this result. Please try again later.";
    }
  } catch (error) {
    output.textContent =
      error instanceof NeuroVerifyError
        ? "Verification is temporarily unavailable."
        : "Something went wrong.";
  }
});
```

Output shown on the page:

```text
Risk: low
```

### 10. Tune video sampling and time limits

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `maxFrames` accepts 1 to 100. Large
uploads may also need a longer `timeoutMs` (default: 2 minutes per attempt).

```js
import { NeuroVerifyClient } from "@neuraldefend/sdk";

const client = new NeuroVerifyClient({ timeoutMs: 300_000 }); // 5 minutes per attempt

for (const maxFrames of [6, 24, 48]) {
  const started = performance.now();
  const result = await client.detectVideo("webinar.mp4", { maxFrames });
  const seconds = ((performance.now() - started) / 1000).toFixed(1);
  const outcome =
    result.status === "success" ? result.videoRiskLevel : result.status;
  console.log(
    `${String(maxFrames).padStart(2)} frames -> video ${outcome} in ${seconds}s`,
  );
}
```

Output:

```text
 6 frames -> video low in 4.8s
24 frames -> video low in 9.3s
48 frames -> video low in 15.6s
```

Each call above is a separate, billable transaction. Pick one setting for production.

To stop waiting after an overall deadline, including retry waits, pass an `AbortSignal`.
`timeoutMs` limits **each attempt** and throws `TimeoutError`; a signal limits **the
whole call** and throws `AbortError`.

```js
import { AbortError, NeuroVerifyClient, TimeoutError } from "@neuraldefend/sdk";

const client = new NeuroVerifyClient();

try {
  const result = await client.detectVideo("webinar.mp4", {
    maxFrames: 24,
    signal: AbortSignal.timeout(60_000), // give up after 60 seconds in total
  });
  console.log(`Finished: ${result.status}`);
} catch (error) {
  if (error instanceof AbortError) {
    console.log("Stopped: the 60-second deadline passed.");
  } else if (error instanceof TimeoutError) {
    console.log("One attempt took longer than timeoutMs.");
  } else {
    throw error;
  }
}
```

Output when the deadline passes:

```text
Stopped: the 60-second deadline passed.
```

For integration tests, `NeuroVerifyClient.staging({ apiKey, maxRetries: 0 })` sends
requests to the staging environment instead; see
[`NeuroVerifyClient.staging`](#neuroverifyclientstagingoptions).

## Browser onboarding and credential safety

> **Never embed a long-lived production API key in browser JavaScript, source maps,
> mobile bundles, static configuration, or HTML. Any browser user can extract it.**

Browser clients require an explicit `apiKey`; the browser build never reads environment
variables. Production keys are issued at **[neuraldefend.com](https://neuraldefend.com/)**
(Book a Demo) and must stay on your backend. The public API contract does not define a
browser credential-issuance endpoint, so do not expose an onboarding-issued API key, and
ask Neural Defend how browser-approved credentials are issued for your tenant before
building a credential route like the one in
[Example 9](#9-check-a-photo-in-the-browser).

For normal web applications, upload media to your authenticated application backend and
call this SDK from Node.js (see the
[browser quick start](#browser-send-a-photo-to-your-backend) and
[Example 8](#8-add-a-check-to-an-express-api)). This keeps the Neural Defend key
server-side and lets your backend enforce user authorization, quotas, audit logging, file
limits, and abuse controls.

The application backend should authenticate the user, enforce upload policy, and pass the
authorized bytes to a server-side `NeuroVerifyClient`. Only use the browser SDK directly
when Neural Defend has explicitly approved a browser-exposable credential for your tenant.
In that case, the browser build accepts only native `File` and `Blob` objects: a `File`
supplies its own name, while a plain `Blob` requires `{ filename: "photo.jpg" }`.

## Method reference

### `new NeuroVerifyClient(options?)`

Creates a production client. In Node.js, `options` is optional because the API key can
come from `NEURALDEFEND_API_KEY`. In browsers, `options.apiKey` is required.

```ts
const client = new NeuroVerifyClient({
  apiKey: "replace-with-your-api-key",
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

- `apiKey?: string` — API key sent in the `x-api-key` header. Whitespace is trimmed.
  Node.js falls back to `NEURALDEFEND_API_KEY`; browsers do not.
- `baseUrl?: string` — HTTPS origin. Defaults to `https://deepscan.neuraldefend.com`, or
  to `NEURALDEFEND_BASE_URL` in Node.js when set. Paths, credentials, query strings, and
  fragments are not accepted.
- `allowCustomBaseUrl?: boolean` — must be `true` before a non-Neural Defend origin is
  accepted. That origin will receive both the API key and uploaded media; enable this only
  for a trusted private deployment.
- `timeoutMs?: number` — timeout for each request attempt, including reading the response
  body. Default: `120000`; must be greater than zero.
- `maxRetries?: number` — retry count after the initial attempt. Default: `3`; integer
  from `0` through `3`.
- `retryAfterCapMs?: number` — maximum wait applied to a `Retry-After` value. Default:
  `60000`. Negative values are normalized to `0`.
- `userAgent?: string` — Node.js user agent override. The Node.js default for this release
  is `@neuraldefend/sdk/1.0.4`; browsers cannot set this header through the SDK.
- `fetch?: typeof globalThis.fetch` — custom Fetch-compatible implementation, primarily
  for controlled runtimes and testing.
- `onWarning?: (warning: ValidationWarning) => void` — receives non-fatal local validation
  warnings. This release emits `code: "unsupported_extension"` when a filename extension
  is not documented.

Configuration precedence:

1. `apiKey` option, then `NEURALDEFEND_API_KEY` (Node.js only); there is no default key.
2. `baseUrl` option, then `NEURALDEFEND_BASE_URL` (Node.js only), then the production
   origin.
3. All other options use only their explicit value or documented default; they have no
   environment-variable fallback.

API keys are redacted from the client's string and JSON representations. This is defense
in depth, not a substitute for secret handling. HTTP redirects are never followed.

### `NeuroVerifyClient.staging(options?)`

Creates a client for `https://stage.deepscan.neuraldefend.com`. Any `baseUrl` in
`options` and `NEURALDEFEND_BASE_URL` are ignored, so a test can never reach production by
mistake.

```ts
const client = NeuroVerifyClient.staging({
  apiKey: process.env.NEURALDEFEND_STAGING_API_KEY,
  maxRetries: 0, // fail fast in tests
});
```

Node.js can omit `options` if `NEURALDEFEND_API_KEY` contains a staging key. Browsers must
pass options with an explicit key. Staging is for integration testing only; use
credentials scoped to that environment.

### `client.detectImage(input, options?)`

Uploads media to `/detect/image` and resolves to `Promise<ImageResult>`.

Accepted inputs:

- Node.js: filesystem path (`string`), `Uint8Array`, `Buffer`, `Blob`, `File`, or a
  Node.js readable stream.
- Browser: `File` or `Blob`.

Options:

- `filename?: string` — multipart filename and MIME-selection input.
- `signal?: AbortSignal` — cancels stream preparation, retry waits, the upload, and
  response processing.

Filename behavior:

- A path uses its basename by default.
- A `File` uses `File.name` by default.
- A file-backed Node.js stream can use its string `path`.
- `Uint8Array`, `Buffer`, plain `Blob`, and unnamed streams require `options.filename`.
- `options.filename` overrides an inferred name for every input type.

Node.js accepts only readable regular-file paths and rejects a symbolic link when the
supplied file path itself is a symbolic link. Paths and streams are copied into a private,
size-bounded temporary file so each retry can create a fresh upload without retaining the
entire stream in memory. Temporary media is removed after the operation.

### `client.detectVideo(input, options?)`

Uploads media to `/detect/video` and resolves to `Promise<VideoResult>`. It accepts the
same platform-specific input types and filename rules as `detectImage()`.

Options:

- `filename?: string` — multipart filename and MIME-selection input.
- `signal?: AbortSignal` — cancellation signal.
- `maxFrames?: number` — maximum sampled frames; integer from `1` through `100`. The API
  default is `12`.
- `sampleRate?: number` — optional server sampling override; integer greater than or
  equal to `1`.

`maxFrames` and `sampleRate` are sent as the `max_frames` and `sample_rate` query
parameters. Increasing frame coverage can increase processing latency.

## Working with results

### Normalized fields

The SDK converts wire-format `snake_case` fields into typed `camelCase` properties and
converts wire `billable: "Y" | "N"` into a boolean. Common fields on image and video
results are:

- `uniqueTrxId: string`
- `filename: string`
- `contentType: string`
- `statusCode: number`
- `billable: boolean`
- `aiThreatSignals: readonly string[]`
- `status: "success" | "rejected" | "unknown"`
- `scored: boolean`
- `rejected: boolean`

Image results add `riskScore`, `riskLevel`, and `message`. Video results add `hasAudio`,
`videoRiskScore`, `videoRiskLevel`, `videoMessage`, `audioRiskScore`, `audioRiskLevel`,
`audioMessage`, and `overallRiskScore`. Scored risk values are in the API's `0.1` through
`10.0` range; higher values indicate higher observed AI/manipulation risk. Nullable score
and level fields are `null` when that modality was not scored. `aiThreatSignals`
identifies checks reported by the service on scored responses and may evolve; do not
build fixed logic around the list.

`ImageResult` and `VideoResult` are TypeScript discriminated unions (`ImageSuccess`,
`ImageRejected`, `ImageUnknown`, `VideoSuccessWithAudio`, `VideoSuccessWithoutAudio`,
`VideoRejected`, `VideoUnknown`), so checking `result.status` (and `result.hasAudio` for
video) narrows the type of the score fields.

Always branch on `result.status` before reading scored fields. A business rejection is a
resolved result, not a thrown error. This includes HTTP 400 validation/security responses
and HTTP 200 face-policy rejections.

### JSON serialization and `result.raw`

`JSON.stringify(result)` emits the stable normalized properties and excludes `raw`, which
is deliberately non-enumerable:

```ts
const auditRecord = JSON.stringify(result);
```

Every resolved result also exposes `result.raw`: the deeply frozen, redacted wire envelope
using the API's original field names. It is available for explicit diagnostics and
forward-compatibility investigation:

```ts
if (result.status === "unknown") {
  console.error("Original status:", result.originalStatus);
  console.error("Diagnostic wire envelope:", result.raw);
}
```

`raw` is not a stable application contract. It may contain filenames, messages, future
fields, or other personal/customer data. Do not routinely log or persist it. If diagnostic
collection is necessary, apply access controls, redaction, encryption, and a short
retention period. API keys found in server payload strings are redacted by the SDK, but
media-related data is not.

### Image outcomes

The following are representative normalized JSON values. Scores and messages vary with
submitted media and service evolution; do not write policy against these example numbers
or exact message text.

Low, medium, and high success results have `status: "success"`, a numeric `riskScore`,
and a service-owned `riskLevel`:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_image_low",
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
  "uniqueTrxId": "trx_example_image_medium",
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
  "uniqueTrxId": "trx_example_image_high",
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

Interpret `low` as lower observed risk, not proof of authenticity. Treat `medium` as
inconclusive and gather more evidence. Treat `high` as a reason to escalate or review, not
as sufficient evidence for an automatic rejection. Use the returned band rather than
reconstructing it from score thresholds.

No-face and multiple-face outcomes are billable HTTP 200 rejections because the service
performed face-policy processing:

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "uniqueTrxId": "trx_example_image_no_face",
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
  "uniqueTrxId": "trx_example_image_multiple_faces",
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

Server-side input validation and security failures are normally non-billable HTTP 400
rejections:

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "uniqueTrxId": "trx_example_image_security",
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

The same result shape covers unsupported formats, excessive file size, unsafe content,
inadequate dimensions, blur, brightness, contrast, or processing failures. Use `message`
for user guidance, but branch on `status` and structured fields rather than exact message
text. Do not retry unchanged media.

### Video outcomes

Video and audio are separate modalities, and either can have a different risk level. The
API does not return a combined risk score. A success with both modalities has
`hasAudio: true`. The example scores are representative, not fixed expectations:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "hasAudio": true,
  "uniqueTrxId": "trx_example_video_modalities",
  "filename": "voice_clone.mp4",
  "contentType": "video/mp4",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Face Swap Detection", "Audio Frequency Analysis"],
  "videoRiskScore": 2.2,
  "videoRiskLevel": "low",
  "videoMessage": "Not likely to be AI-generated",
  "audioRiskScore": 8.4,
  "audioRiskLevel": "high",
  "audioMessage": "Likely to be AI-generated",
  "overallRiskScore": 8.4
}
```

A video without an audio track can still be scored successfully:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "hasAudio": false,
  "uniqueTrxId": "trx_example_video_silent",
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

Video processing requires scorable single-face frames. Multi-face sampled frames are
skipped. If no sampled frame contains exactly one scorable face, the service returns the
same no-face rejection used for zero-face video and does not score audio:

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

Video format, size, and security failures are similarly returned as non-billable
`statusCode: 2` rejections with null modality fields.

### Unknown forward-compatible results

If a future API response uses an unknown outcome status or risk band, the SDK resolves an
`"unknown"` result instead of silently treating it as a known success or rejection. For
example:

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

Do not make a policy decision from an unknown result. Record the transaction ID, inspect
`raw` only under your diagnostic controls, and upgrade the SDK. Unknown numeric
`statusCode` values alone remain available on an otherwise valid known result.

## Errors

All SDK errors extend `NeuroVerifyError` and expose `detail`; HTTP-derived errors can also
expose `statusCode` and `requestId`.

- `ValidationError` — local configuration, option, filename, input, empty-file, or size
  validation failed before a valid request could complete. Its `code` identifies the
  validation category: `api_key_required`, `custom_base_url_requires_opt_in`,
  `empty_file`, `file_too_large`, `filename_required`, `invalid_base_url`,
  `invalid_max_frames`, `invalid_sample_rate`, `invalid_timeout`, `invalid_retries`, or
  `unsupported_input`. Correct the input; do not retry it unchanged.
- `AuthenticationError` — HTTP 401. Verify that the key is active and belongs to the
  selected environment. The SDK does not retry it.
- `ScopeError` — HTTP 403. The key lacks endpoint or plan access. The SDK does not retry
  it.
- `RateLimitError` — HTTP 429 after retries are exhausted. It may expose `retryAfter` in
  seconds plus string-valued `limit`, `remaining`, and `reset` metadata.
- `TimeoutError` — the configured per-attempt timeout elapsed. Timeouts are not
  automatically retried.
- `NetworkError` — no response was received, for example because of DNS, connectivity, or
  TLS failure. Network failures are not automatically retried.
- `ServerError` — HTTP 500/503 after retries are exhausted, or a wire result with
  `status: "error"`. It may expose a deeply frozen `raw` diagnostic envelope.
- `ProtocolError` — the response was malformed, missing its expected envelope, or
  contained invalid required fields. Do not assume retrying is safe; retain the
  request/transaction ID and contact support if it persists.
- `AbortError` — the caller's `AbortSignal` canceled preparation, a retry wait, upload, or
  response processing. This is distinct from a timeout.
- `HttpError` — another unexpected HTTP status. `AuthenticationError`, `ScopeError`,
  `RateLimitError`, and `ServerError` extend this class, so check it last.

Example handling for every concrete error:

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

Do not confuse a resolved business rejection with a thrown error. HTTP 400 validation or
security rejections that have the documented score envelope resolve to a result so your
application can inspect the API's message and `billable` value.

## Retries, billing, and idempotency

By default, the SDK makes the initial request and up to three retries:

- HTTP 500 and 503 use exponential delays of approximately 1, 2, and 4 seconds, with
  jitter.
- HTTP 429 honors a numeric or HTTP-date `Retry-After` value up to `retryAfterCapMs`;
  without a valid header it uses exponential delays.
- HTTP 400, 401, 403, other HTTP statuses, timeouts, protocol failures, aborts, and
  network failures are not retried.

Set `maxRetries: 0` to disable automatic retries.

Requests are not idempotent and the API does not expose an idempotency-key option through
this SDK. Every accepted attempt can receive a new `uniqueTrxId`; resubmitting the same
media, including automatic retries, may create separate transactions with separate
billing implications. The `billable` field is authoritative for the returned transaction.
A rejection can be billable, as shown by no-face and multiple-face policy outcomes.
Persist `uniqueTrxId` with your audit record and avoid application-level retries unless
you have accounted for duplicate processing and billing.

## Media formats and limits

Image uploads:

- Extensions: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`, `.webp`, `.heic`, `.heif`
- Exact maximum: 10 MiB (`10,485,760` bytes)
- API minimum resolution: 224 by 224 pixels
- Face policy: exactly one face

Video uploads:

- Extensions: `.mp4`, `.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`, `.ogg`, `.ogv`
- Exact maximum: `1,500,000,000` bytes
- Default frame sample maximum: `12`
- `maxFrames`: integer `1` through `100`
- `sampleRate`: integer greater than or equal to `1`
- Face policy: sampled frames with multiple faces are skipped; at least one scorable
  single-face frame is required

The SDK rejects empty and oversized input locally. It warns, but does not reject, an
undocumented extension because the server performs content and security validation. Known
extensions select deterministic MIME types. For an unknown extension, an explicit
`Blob.type` is preserved; otherwise the SDK uses `application/octet-stream`. A valid
extension does not bypass server-side format or security inspection.

## Security and privacy

- Upload media only with the data owner's authorization and an appropriate legal basis.
- Treat images, video, audio, filenames, transaction IDs, and diagnostics as potentially
  sensitive data. Face media may be biometric personal data.
- Apply your organization's consent, purpose limitation, retention, deletion, residency,
  encryption, access-control, and incident-response requirements.
- Keep production API keys in a managed secret store, rotate them, scope them to required
  endpoints and environments, and never expose them to an untrusted client.
- Authenticate and authorize users before accepting uploads through your backend. Enforce
  your own size, type, quota, and abuse controls before forwarding media.
- Avoid routine logging of `result.raw`, server messages, local paths, or filenames.
  Sanitize support bundles.
- Do not enable `allowCustomBaseUrl` unless the destination is trusted to receive both
  credentials and media.
- Do not use low risk as proof, or high risk as the sole reason for an adverse action.
  Design a review and appeal path for consequential decisions.

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

**`api_key_required`**

Set `NEURALDEFEND_API_KEY` in the Node.js process before constructing the client, or pass
`apiKey`. Browsers always require an explicit short-lived key.

**`filename_required`**

Pass `{ filename: "photo.jpg" }` or `{ filename: "clip.mp4" }` when using bytes, a plain
`Blob`, or a stream with no string path. Include the real extension.

**`file_too_large` or `empty_file`**

Check the exact byte limits above before upload. For streams, the SDK stops spooling once
the limit is exceeded.

**`unsupported_input`**

In Node.js, pass a path to a readable regular file (not a directory or symbolic link), a
`Buffer`/`Uint8Array`, a `Blob`/`File`, or a readable stream. In browsers, pass a `File`
or `Blob`.

**`unsupported_extension` warning**

Use a documented extension that matches the actual content. The warning does not mean the
upload is accepted; the server still inspects and may reject it.

**Image returns no face or multiple faces**

Use a well-lit, in-focus image at least 224 by 224 pixels with one clearly visible
subject. Crop group images to one subject before submission.

**Video returns no face even though faces are visible**

The API needs at least one sampled frame with exactly one scorable face. Frames containing
multiple faces are skipped. Use a single-subject clip or adjust `maxFrames` within the
supported range when broader temporal coverage is appropriate.

**No audio score**

Check `hasAudio` and `audioMessage`. `"No audio track detected"` means video scoring
succeeded without an audio modality. A no-face video rejection suppresses both modalities.

**401 or 403**

Confirm the key's environment, validity, endpoint scope, and plan access. Production and
staging keys may not be interchangeable.

**429**

The SDK already retries up to `maxRetries` and honors `Retry-After` up to the configured
cap. After `RateLimitError`, use its metadata for scheduling and reduce concurrency; do
not immediately loop.

**Timeout or network error**

Check connectivity and service reachability. For large video uploads, choose a realistic
`timeoutMs`. The SDK deliberately does not retry these failures because whether the
server accepted the media can be uncertain.

**500 or 503**

The SDK retries these responses automatically. If `ServerError` remains after the retry
budget, record `requestId` and the relevant transaction ID, then contact support. Do not
include media or unrestricted `raw` data in a support ticket unless requested through an
approved secure channel.

**`ProtocolError` or `status: "unknown"`**

Upgrade `@neuraldefend/sdk` and retry only after considering duplicate billing. If the
issue persists, provide the SDK version and request/transaction ID to support.

## Wire-level API documentation

For exhaustive response scenarios, wire field names, status codes, current messages, and
direct HTTP integration details, see:

- [Unified Face Authenticity Score](../../docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](../../docs/client/unified-video-authenticity.md)

The SDK's normalized result types are the application contract for SDK users. Use the wire
documents when diagnosing a payload or implementing without this SDK.

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the SDK version, endpoint, `requestId` or `uniqueTrxId`, and
a sanitized reproduction. Do not send API keys, raw customer media, or biometric/personal
data.
