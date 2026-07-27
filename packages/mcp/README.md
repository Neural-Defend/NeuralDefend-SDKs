# neuraldefend-mcp

`neuraldefend-mcp` 1.0.2 is a secure, local Model Context Protocol (MCP) server for
NeuroVerify image and video authenticity analysis. It gives an MCP client two tools while
keeping API credentials out of tool arguments, restricting which local media can be read,
and returning a bounded integration contract instead of the Python SDK's raw response.

Use the results as decision-support signals. A low-risk result is not proof that media is
authentic, and a high-risk result should trigger human review rather than automatic
rejection.

## How it works

The MCP client starts `neuraldefend-mcp` as a child process and communicates with it over
standard input and standard output:

```text
MCP client
  └─ local stdio (MCP JSON-RPC)
      └─ neuraldefend-mcp
          ├─ validates and opens an allowlisted local file once
          └─ streams that open handle over TLS through the NeuroVerify Python SDK
              └─ NeuroVerify Detection API
```

There is no local HTTP listener. Standard output is reserved for the MCP protocol; safe
startup errors are written to standard error. The server does not return media bytes to the
MCP client and does not load an entire video into memory. It validates the opened file
handle and uploads that same bounded handle, reducing path substitution and
time-of-check/time-of-use risk.

## Requirements

- Python 3.10 or newer.
- A NeuralDefend API key authorized for the requested image or video analysis.
- An MCP client that can launch a local stdio server.
- Network access to the selected NeuroVerify API environment.
- Read access to dedicated local directories containing only media authorized for upload.

## Installation

Install the published 1.0.2 release:

```bash
python -m pip install "neuraldefend-mcp==1.0.2"
```

The package installs the `neuraldefend-mcp` command. The equivalent module entry point is:

```bash
python -m neuraldefend_mcp
```

Both entry points run the same stdio-only server. Starting either one directly is normally
useful only for diagnosing configuration: the process waits for MCP messages on standard
input after successful startup.

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key on PyPI — request access from the company first, then inject the key into
the MCP server environment.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   discuss deepfake detection, AI-generated media analysis, and API access for agents or
   applications.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key or
   staging credential.
3. Set `NEURALDEFEND_API_KEY` in the process that launches `neuraldefend-mcp` (see
   [Secure configuration](#secure-configuration)). Never pass the key as an MCP tool
   argument or commit it to configuration files.
4. For REST endpoint reference, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## Secure configuration

Configuration is read from the server process environment at startup. The server refuses
to start if a required value is missing or unsafe.

| Variable | Required | Default | Accepted value | Why it is restricted |
|---|---:|---|---|---|
| `NEURALDEFEND_API_KEY` | Yes | — | Non-empty API key | Credentials never become tool arguments and are not exposed in results. |
| `NEURALDEFEND_MCP_ALLOWED_DIRS` | Yes | — | One or more existing absolute directories, separated by the platform path separator | Limits the local files an MCP client or agent can cause the server to read and upload. |
| `NEURALDEFEND_MCP_ENVIRONMENT` | No | `production` | `production` or `staging` | Pins credentials and media to a known NeuralDefend TLS origin; arbitrary URLs are rejected. |
| `NEURALDEFEND_MCP_MAX_CONCURRENCY` | No | `2` | Integer from `1` through `32` | Bounds simultaneous SDK calls, local file handles, network load, and accidental billing bursts. |

### API key

`NEURALDEFEND_API_KEY` is stripped of surrounding whitespace and passed to the Python SDK
when the server starts. It is never accepted as an MCP tool argument. Inject it through the
MCP client's secret store, an operating-system credential facility, or the environment of
the process that launches the MCP client.

Do not put a real key in:

- a committed MCP configuration;
- a prompt or tool argument;
- a shell-history example;
- application logs or issue reports.

### Allowed directories

`NEURALDEFEND_MCP_ALLOWED_DIRS` is mandatory. Use the platform path separator between
entries:

- Windows (`;`):

  ```text
  D:\Authorized Media;E:\Review Queue
  ```

- macOS (`:`):

  ```text
  /Users/alice/Authorized Media:/Volumes/ReviewQueue
  ```

- Linux (`:`):

  ```text
  /srv/authorized-media:/home/alice/review-queue
  ```

Configure the narrowest dedicated directories practical. Do not allow a home directory,
shared download directory, repository root, or other broad location merely for
convenience.

At startup, every allowlist entry must:

- be a non-empty absolute path;
- already exist and be a directory, not a file;
- not be a filesystem root such as `C:\` or `/`;
- contain no symlink, Windows junction, or other reparse-point component.

Duplicate roots are removed. Relative paths, empty entries, unsafe Windows device paths,
and alternate data stream forms are rejected.

For every tool invocation, `file_path` must:

- be an absolute path to an existing regular file below an allowed directory;
- contain no symlink, junction, or reparse-point component;
- identify a non-empty file within the media size limit;
- still resolve inside an allowed directory after the file has been opened.

These checks prevent path traversal, prefix-sibling mistakes, link escapes, device access,
alternate data stream access, and file-swap races. The server exposes only the validated
prefix if another process appends data after validation.

### API environment

Omit `NEURALDEFEND_MCP_ENVIRONMENT` for production. Set it to `staging` only for
non-production integration testing with staging credentials and approved test media.
Values are case-insensitive after trimming, but only `production` and `staging` are
accepted.

The MCP adapter deliberately ignores the Python SDK's general
`NEURALDEFEND_BASE_URL` override. This prevents an inherited environment variable from
redirecting the API key and uploaded media to an arbitrary origin.

### Maximum concurrency

`NEURALDEFEND_MCP_MAX_CONCURRENCY` limits active analyses across both tools. It must be a
base-10 integer from `1` through `32`; booleans, decimals, zero, negatives, and larger
values are rejected. Start with the default `2`. Raise it only after considering account
rate limits, host resources, expected media sizes, latency, and billing controls.

## MCP client configuration

The outer configuration key varies by client, but clients that use the common
`mcpServers` shape can use the following complete entries.

The `${NEURALDEFEND_API_KEY}` token below is a secret reference, not a literal key. Use it
only if your client expands that syntax. Otherwise, omit the key from the `env` object and
launch the MCP client from a securely populated environment, or replace the token with the
client's documented secret-store reference. Never replace it with a real key in a file
that may be committed, synchronized, backed up without encryption, or shared.

Every complete configuration below explicitly passes `NEURALDEFEND_API_KEY` into the MCP
server process. Obtain that key from **[neuraldefend.com](https://neuraldefend.com/)** (Book
a Demo) after Neural Defend onboarding — never paste a real key into a committed file.
Startup validates that it is a non-empty string; the NeuroVerify API then validates the
credential and its endpoint scope on each request.

### Windows

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "D:\\Authorized Media;E:\\Review Queue",
        "NEURALDEFEND_MCP_ENVIRONMENT": "production",
        "NEURALDEFEND_MCP_MAX_CONCURRENCY": "2"
      }
    }
  }
}
```

### macOS

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/Users/alice/Authorized Media:/Volumes/ReviewQueue",
        "NEURALDEFEND_MCP_ENVIRONMENT": "production",
        "NEURALDEFEND_MCP_MAX_CONCURRENCY": "2"
      }
    }
  }
}
```

### Linux

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "neuraldefend-mcp",
      "args": [],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/srv/authorized-media:/home/alice/review-queue",
        "NEURALDEFEND_MCP_ENVIRONMENT": "production",
        "NEURALDEFEND_MCP_MAX_CONCURRENCY": "2"
      }
    }
  }
}
```

If the installed console command is not on the MCP client's `PATH`, use the interpreter
from the environment where the package was installed:

```json
{
  "mcpServers": {
    "neuraldefend": {
      "command": "/absolute/path/to/python",
      "args": ["-m", "neuraldefend_mcp"],
      "env": {
        "NEURALDEFEND_API_KEY": "${NEURALDEFEND_API_KEY}",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": "/absolute/path/to/authorized-media",
        "NEURALDEFEND_MCP_ENVIRONMENT": "production",
        "NEURALDEFEND_MCP_MAX_CONCURRENCY": "2"
      }
    }
  }
}
```

On Windows, `command` may instead be an absolute path such as
`C:\\path\\to\\venv\\Scripts\\python.exe`, and the allowed directory must use a Windows
absolute path.

Restart the MCP server after changing its environment or allowlist. Configuration is
loaded once for the process lifespan.

## Authorization and billing gate

Before invoking either tool, the client or agent should:

1. Confirm that the data owner has authorized this media to be uploaded and analyzed.
2. Confirm that the file is in a purpose-specific allowed directory.
3. Tell the user that the call may create a billable transaction.
4. Confirm the requested tool and, for video, the requested frame count.
5. Avoid invoking the same analysis again merely to obtain a different score or message.

A local validation failure happens before upload and is reported as non-billable.
Service-side business rejections are normal results and can be billable. In particular,
no-face and face-policy rejections can return `billable: true`. For failures where it is
not safe to know whether the service accepted the request, `billable` is `null`.

## Tool reference

### `detect_image_authenticity(file_path)`

Assesses an authorized image containing exactly one clearly visible face.

| Argument | Type | Required | Constraints |
|---|---|---:|---|
| `file_path` | string | Yes | Absolute path to an allowlisted, regular, non-empty image file. |

Supported extensions are `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`, `.webp`,
`.heic`, and `.heif`. The maximum size is 10 MiB (10,485,760 bytes), the minimum
resolution is 224 × 224 pixels, and exactly one face is required. EXIF rotation is handled
by the service. Use a clear, frontal, well-lit image for the most useful result.

The server performs path, regular-file, non-empty, and size validation locally. Media
format, dimensions, quality, safety, and face-policy checks can produce a service business
rejection.

### `detect_video_authenticity(file_path, max_frames=12)`

Assesses authorized video and audio as independent modalities. The API deliberately
provides no combined MCP risk field.

| Argument | Type | Required | Default | Constraints |
|---|---|---:|---:|---|
| `file_path` | string | Yes | — | Absolute path to an allowlisted, regular, non-empty video file. |
| `max_frames` | integer | No | `12` | Integer from `1` through `100`; booleans are not accepted. |

Supported extensions are `.mp4`, `.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`,
`.ogg`, and `.ogv`. The maximum size is 1,500,000,000 bytes. Frames are sampled uniformly.
Frames with several faces are skipped; if no sampled frame has one scorable face, the
result is a billable business rejection. A silent video can still be a successful result:
the video modality is scored while the audio score and level are `null` and the audio
message is `No audio track detected`.

Increasing `max_frames` can improve temporal coverage but also increases processing work
and latency. It does not make repeated invocations idempotent.

## Reading tool results

Every MCP call result has two synchronized channels derived from the same internal
outcome:

- `content[0].text` is concise presentation text for a person or conversational agent. Its
  wording may evolve and must not be parsed as an API.
- `structuredContent` is the versioned integration contract. Automations should branch on
  its fields.

`isError` is `true` only when `structuredContent.status` is `error`. A service business
rejection uses `status: "rejected"` and `isError: false` because it is a valid, unscorable
business result.

### Image success: low risk

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_c1r7n6oy69zhunjrkp0p",
  "risk": {
    "image": {
      "score": 2.2,
      "level": "low",
      "message": "Not likely to be Spoof or AI-generated"
    }
  },
  "signals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ]
}
```

Low risk is not definitive proof of authenticity.

### Image success: medium risk

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_med123abc456def789",
  "risk": {
    "image": {
      "score": 5.5,
      "level": "medium",
      "message": "Less likely to be Spoof or AI-generated"
    }
  },
  "signals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ]
}
```

Medium risk should be reviewed with additional evidence.

### Image success: high risk

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_k8mdf2ab1xpqr7w3e9t6",
  "risk": {
    "image": {
      "score": 8.7,
      "level": "high",
      "message": "Likely to be Spoof detected"
    }
  },
  "signals": [
    "Visual Safety Screening",
    "Liveness Verification",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "AI Content Compliance"
  ]
}
```

High risk should be escalated for human review and must not be used as an automatic
rejection by itself.

### Image business rejection

This is a valid, potentially billable result, not an MCP error:

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "rejected",
  "statusCode": 6,
  "scored": false,
  "billable": true,
  "transactionId": "trx_nf123abc456def789",
  "risk": {
    "image": {
      "score": null,
      "level": null,
      "message": "No face detected in the image"
    }
  },
  "signals": []
}
```

“Could not score” means unscorable. It is not evidence that the image is authentic.

### Video success: both modalities scored

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_qro0hy17yeyridi0f4yu",
  "risk": {
    "video": {
      "score": 9.0,
      "level": "high",
      "message": "Likely to be AI-generated"
    },
    "audio": {
      "score": 2.2,
      "level": "low",
      "message": "Not likely to be AI-generated"
    }
  },
  "signals": [
    "Photometric Liveness Signal",
    "Identity Consistency Analysis",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "Audio Frequency Analysis",
    "AI Pixel-Level Manipulation",
    "Digital Content Provenance",
    "Frame-Level Visual Analysis"
  ]
}
```

Keep the video and audio decisions separate. In this example the low-risk audio result
does not offset the high-risk video result.

### Video success: no audio track

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "success",
  "statusCode": 1,
  "scored": true,
  "billable": true,
  "transactionId": "trx_vid_na123abc456def789",
  "risk": {
    "video": {
      "score": 2.1,
      "level": "low",
      "message": "Not likely to be AI-generated"
    },
    "audio": {
      "score": null,
      "level": null,
      "message": "No audio track detected"
    }
  },
  "signals": [
    "Photometric Liveness Signal",
    "Identity Consistency Analysis",
    "Face Swap Detection",
    "AI Generative Model Analysis",
    "Audio Frequency Analysis",
    "AI Pixel-Level Manipulation",
    "Digital Content Provenance",
    "Frame-Level Visual Analysis"
  ]
}
```

The call is successful because the video modality was scored. Null audio fields do not
mean low audio risk.

### Video business rejection: no scorable face

```json
{
  "schemaVersion": "1.0",
  "mediaType": "video",
  "status": "rejected",
  "statusCode": 6,
  "scored": false,
  "billable": true,
  "transactionId": "trx_77lgbdbn4kec3ouwbnjt",
  "risk": {
    "video": {
      "score": null,
      "level": null,
      "message": "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio."
    },
    "audio": {
      "score": null,
      "level": null,
      "message": null
    }
  },
  "signals": []
}
```

Audio is not scored when the sampled frames do not provide a scorable single face.

### Error object

Errors add an `error` object and set MCP `isError` to `true`. For example, a final
rate-limit failure is:

```json
{
  "schemaVersion": "1.0",
  "mediaType": "image",
  "status": "error",
  "statusCode": 429,
  "scored": false,
  "billable": false,
  "transactionId": null,
  "risk": {
    "image": null
  },
  "signals": [],
  "error": {
    "code": "rate_limit",
    "message": "The service rate limit was reached. Try again later.",
    "retryable": true
  }
}
```

## `structuredContent` contract

`schemaVersion` is currently `"1.0"`. Consumers should require a supported major schema
version and ignore additive fields they do not understand. Do not parse the presentation
text to reconstruct these fields.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | string | Version of this bounded MCP projection, not the upstream wire schema. |
| `mediaType` | `"image"` or `"video"` | Tool result media kind. |
| `status` | `"success"`, `"rejected"`, or `"error"` | Primary branch for result handling. |
| `statusCode` | integer or `null` | Sanitized service/business status when available; not sufficient by itself to determine whether media was scored. |
| `scored` | boolean | `true` only for a contract-valid successful score. |
| `billable` | boolean or `null` | Authoritative boolean when known; `null` means billing could not be determined safely. |
| `transactionId` | string or `null` | Safe service transaction identifier for audit correlation. |
| `risk` | object | `{ "image": ... }` for images; `{ "video": ..., "audio": ... }` for videos. |
| `risk.*.score` | number or `null` | Opaque score from 0.1 through 10.0. Do not create local thresholds. |
| `risk.*.level` | `"low"`, `"medium"`, `"high"`, or `null` | Service risk band to use for business decision rules. |
| `risk.*.message` | string or `null` | Sanitized service explanation or modality status. |
| `signals` | array of strings | Sanitized informational checks/signals; do not depend on a fixed list. |
| `error` | object, errors only | Sanitized `code`, `message`, and `retryable` fields. |

The output is intentionally bounded:

- only explicitly allowlisted fields are emitted;
- messages are limited to 500 characters;
- at most 32 signals are emitted, each limited to 120 characters;
- scores outside 0.1–10.0, unknown success risk levels, and inconsistent success shapes
  become a `protocol` error;
- transaction identifiers must match a conservative character and length allowlist.

Local paths, filenames, media bytes, response headers, API keys, SDK exception details,
future unknown response fields, and the SDK `raw` payload are never included. Known
sensitive values and absolute-path patterns are redacted from returned messages and
signals.

## Error codes and retryability

| `error.code` | Typical cause | `statusCode` | `billable` | `retryable` |
|---|---|---:|---:|---:|
| `local_validation` | Unsafe path, missing/empty/oversized file, invalid `max_frames`, or Python SDK input validation | `null` | `false` | `false` |
| `authentication` | Invalid or missing service credential | `401` | `false` | `false` |
| `scope` | API key lacks permission for the requested analysis | `403` | `false` | `false` |
| `rate_limit` | Final service rate-limit response | `429` | `false` | `true` |
| `server` | Final service failure | Usually `500` or `503` | `false` | `true` |
| `transport` | Timeout, network, or unclassified transport failure | Usually `null` | `null` | `false` |
| `protocol` | Unsupported or malformed service/SDK result | Usually `null` | `null` | `false` |

`retryable` is deliberately conservative. Only final rate-limit and server errors are
marked `true`. A timeout or transport failure is not marked retryable because the request
may already have been accepted and billing may be ambiguous.

The Python SDK owns network retry behavior; this MCP layer adds no retries. By default the
SDK retries only HTTP 429, 500, and 503, up to three retries after the initial attempt.
Receiving an MCP error therefore means the SDK's policy has already completed. Any later
manual retry is a new, non-idempotent invocation and should pass through the authorization
and billing gate again.

## Decision guidance

Branch on `status`, not `statusCode` alone:

1. `error`: no score is available. Inspect `error.code`, `retryable`, and `billable`.
2. `rejected`: the service processed the request but could not score it. Do not interpret
   null risk fields as low risk, and do not retry unchanged media automatically.
3. `success`: use the service-provided `level` for policy. Treat the numeric score as
   opaque because band thresholds can change.

For successful risk levels:

- `low`: not definitive proof of authenticity;
- `medium`: review with additional evidence;
- `high`: escalate for human review; do not auto-reject from this result alone.

For video, assess `risk.video` and `risk.audio` independently. The MCP contract has no
overall risk field. If one modality is unscored, do not silently treat it as low risk.

## Billing, transactions, and idempotency

Every accepted API attempt receives a new transaction identifier. Requests are not
idempotent: analyzing the same file again creates a separate transaction and may be
billable again. The Python SDK may also make multiple HTTP attempts under its narrow retry
policy, with separate transaction and billing implications.

- Use `billable` from the result; do not infer billing from MCP `isError`, HTTP status, or
  whether a score exists.
- Preserve `transactionId` under your organization's audit and access-control policy when
  correlation or dispute resolution is required.
- Do not loop until a preferred risk result appears.
- Do not automatically repeat a business rejection.
- Treat `billable: null` as unknown, not false.

## Privacy and data handling

Uploaded media can contain biometric and other sensitive personal data. Before enabling
the server:

- establish authorization and an appropriate legal basis for every upload;
- limit the allowlist to purpose-specific directories with controlled write access;
- apply organizational retention, deletion, residency, access-control, and incident
  response requirements;
- avoid placing sensitive media, local paths, or API keys in prompts, logs, screenshots,
  tickets, or telemetry;
- remove media from the review directory according to your retention policy.

The bounded MCP result reduces accidental leakage but does not replace governance for the
media uploaded to the service or for transaction and risk data retained by the MCP client.

## Troubleshooting

### Server does not start

- `NEURALDEFEND_API_KEY is required.`: inject a non-empty key into the server process.
- `NEURALDEFEND_MCP_ALLOWED_DIRS is required.`: configure at least one existing absolute
  directory.
- `contains an empty entry`: remove a leading, trailing, or doubled path separator.
- `must be between 1 and 32`: correct `NEURALDEFEND_MCP_MAX_CONCURRENCY`.
- `must be either 'production' or 'staging'`: remove a custom URL or unsupported
  environment name.
- The client reports that the process exited but shows no protocol output: inspect the MCP
  client's captured standard error. Startup errors intentionally never use standard
  output.
- `neuraldefend-mcp` is not found: use the absolute Python interpreter path with
  `-m neuraldefend_mcp`.

### Path is rejected

- Pass an absolute file path. The MCP client's working directory is not used to resolve
  relative paths.
- Confirm the file is below an allowed directory, not merely in a path with the same text
  prefix.
- Confirm the file exists, is regular, non-empty, and within the applicable size limit.
- Remove symlink, junction, reparse-point, or linked parent components. Both allowed
  roots and invocation paths are checked component by component.
- On Windows, do not use device namespaces, reserved device names, or alternate data
  streams.
- If another process replaces or moves a file while it opens, retry only after stabilizing
  the file. The server rejects changed handles rather than uploading uncertain content.
- Restart the server after changing `NEURALDEFEND_MCP_ALLOWED_DIRS`.

Path failures return `local_validation` without echoing the sensitive path.

### Media is rejected

A `status: "rejected"` result is not a startup or transport problem. Read the modality
message, correct the media, and obtain authorization before a new invocation. Common
causes include no face, several faces, unsupported format, dimensions or quality outside
accepted limits, safety screening, and excessive file size. A no-face or face-policy
rejection may still be billable.

For video, multi-face frames are skipped. If no sampled frame contains one scorable face,
both modalities remain unscored and the business result is rejected.

### API error

- `authentication` / 401: replace or correctly inject the API key, then restart the MCP
  server.
- `scope` / 403: request the required image or video analysis permission for the key.
- `rate_limit` / 429: respect account limits and delay before a separately authorized new
  invocation.
- `server` / 500 or 503: the SDK has already applied its retry policy. Retry later only
  after considering non-idempotency and billing.
- `transport`: check DNS, TLS, proxy, firewall, and service reachability. Do not assume the
  failed call was non-billable.
- `protocol`: update compatible `neuraldefend-mcp` and `neuraldefend` packages together or
  contact support; do not use partial fields from an unsupported result.

## Related documentation

- [NeuralDefend Python SDK](../python/README.md)
- [Wire-level image client documentation](../../docs/client/unified-face-authenticity.md)
- [Wire-level video client documentation](../../docs/client/unified-video-authenticity.md)

The wire-level documents describe the complete service response scenarios. Integrations
using this MCP server should depend on the bounded `structuredContent` contract documented
here, not on upstream-only fields.

## Development

For repository maintainers:

```bash
python -m pip install -e ".[dev]"
pytest
ruff check .
mypy
python -m build
twine check dist/*
```
