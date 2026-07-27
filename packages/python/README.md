# NeuralDefend Python SDK

The official synchronous Python client for the NeuroVerify image and video authenticity
API. Version `1.0.2` provides typed result objects, streaming multipart uploads, bounded
retries, normalized JSON output, and explicit exceptions for operational failures.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an exception, including some HTTP 200 responses.
- `billable` is the authoritative billing indicator for each returned transaction.

Risk output is not proof of authenticity and must not be the sole basis for an automated
accept/reject decision. Use the server-provided risk level with other evidence, documented
policy, and human review where appropriate.

## Requirements

- Python 3.9 or newer
- A NeuroVerify API key with access to the image and/or video endpoint
- Network access to the configured HTTPS API origin

This guide documents `neuraldefend==1.0.2`.

## Installation

Install the pinned release in the same environment as your application:

```bash
python -m pip install "neuraldefend==1.0.2"
```

Confirm the package can be imported:

```bash
python -c "from neuraldefend import NeuroVerifyClient; print('neuraldefend ready')"
```

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key on PyPI — request access from the company first, then configure the SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media analysis,
   and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key,
   staging credential, or rate-limit details.
3. Store the key in a secret manager or the `NEURALDEFEND_API_KEY` environment variable
   (see below). Never commit it, embed it in client-side code, or paste it into logs or
   support tickets.
4. For REST endpoint reference while you wait for a key, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## API-key configuration

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

The default constructor reads `NEURALDEFEND_API_KEY`:

```python
from neuraldefend import NeuroVerifyClient

# Requires NEURALDEFEND_API_KEY from https://neuraldefend.com/ onboarding.
with NeuroVerifyClient() as client:
    ...
```

You can pass `api_key` explicitly when it comes from an application secret provider:

```python
with NeuroVerifyClient(api_key=secret_provider.get("neuraldefend-api-key")) as client:
    ...
```

An explicit `api_key` takes precedence over `NEURALDEFEND_API_KEY`. Avoid hard-coding the
key even when using the explicit argument.

## Quick start: image

Save this complete synchronous example as `detect_image.py`, set
`NEURALDEFEND_API_KEY`, and run `python detect_image.py /path/to/selfie.jpg`.

```python
import json
import os
import sys

from neuraldefend import NeuroVerifyClient


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: python detect_image.py IMAGE_PATH")

    # Get an API key from https://neuraldefend.com/ (Book a Demo), then export it.
    api_key = os.environ["NEURALDEFEND_API_KEY"]
    with NeuroVerifyClient(api_key=api_key) as client:
        result = client.detect_image(sys.argv[1])

    # to_dict() contains normalized, JSON-serializable public fields.
    print(json.dumps(result.to_dict(), indent=2))

    if result.scored:
        print(f"image risk: {result.risk_level} ({result.risk_score})")
        if result.high_risk:
            print("route to the review required by your policy")
    elif result.rejected:
        print(f"image was not scored: {result.message}")
    else:
        print(f"unrecognized future outcome: {result.status}")


if __name__ == "__main__":
    main()
```

## Quick start: video

Save this complete synchronous example as `detect_video.py`, set
`NEURALDEFEND_API_KEY`, and run `python detect_video.py /path/to/clip.mp4`.

```python
import json
import os
import sys

from neuraldefend import NeuroVerifyClient


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: python detect_video.py VIDEO_PATH")

    # Get an API key from https://neuraldefend.com/ (Book a Demo), then export it.
    api_key = os.environ["NEURALDEFEND_API_KEY"]
    with NeuroVerifyClient(api_key=api_key) as client:
        result = client.detect_video(
            sys.argv[1],
            max_frames=24,
            sample_rate=2,
        )

    # The normalized output includes both modalities and convenience properties.
    print(json.dumps(result.to_dict(), indent=2))

    if result.scored:
        print(f"video risk: {result.video_risk_level} ({result.video_risk_score})")
        if result.has_audio:
            print(f"audio risk: {result.audio_risk_level} ({result.audio_risk_score})")
        else:
            print(f"audio not scored: {result.audio_message}")
        print(f"maximum modality score: {result.overall_risk_score}")
    elif result.rejected:
        print(f"video was not scored: {result.video_message}")
    else:
        print(f"unrecognized future outcome: {result.status}")


if __name__ == "__main__":
    main()
```

`overall_risk_score` is a client-side convenience equal to the maximum available modality
score. It is not a combined score returned by the API and does not replace modality-aware
policy.

## Result handling

Detection methods return immutable `ImageResult` or `VideoResult` instances for both
successful scores and business rejections. Branch on `result.status` or the convenience
properties:

- `scored`: `True` only for a recognized successful, scored result.
- `rejected`: `True` when `status == "rejected"`.
- `ImageResult.high_risk`: `True` when `risk_level == "high"`.
- `VideoResult.has_audio`: `True` when an audio risk score is present.
- `VideoResult.overall_risk_score`: maximum non-null video/audio score, or `None`.

Do not infer success from HTTP 200. No-face and face-policy outcomes can be HTTP 200
rejections with null risk fields and may be billable. Do not create policy from numeric
thresholds: use the API-owned `low`, `medium`, and `high` bands because thresholds may be
tuned.

### `to_dict()` versus `raw`

`result.to_dict()` returns the stable normalized SDK fields:

- wire names use `snake_case`;
- wire `"Y"`/`"N"` billing values become Python `bool`;
- `ai_threat_signals` becomes a JSON-compatible list;
- derived convenience properties are included;
- the wire envelope and `raw` are intentionally excluded.

The returned dictionary can be serialized directly:

```python
payload = result.to_dict()
json_text = json.dumps(payload)
```

`result.raw` is the sanitized, deeply immutable score envelope retained for explicit
diagnostics and forward compatibility. It can contain additive fields not yet normalized
by the SDK. It is not automatically JSON-serializable because nested mappings and
sequences are immutable, and it may contain filenames or future personal/customer fields.
Do not log or persist `raw` without justified access, redaction, and retention controls.

## Representative normalized outputs

The values below are representative examples based on the documented API scenarios.
Scores, transaction IDs, messages, detected content types, and threat signals vary by
media and service evolution. These are normalized `to_dict()` shapes, not raw wire
envelopes.

### Image outcomes

Low, medium, and high are scored outcomes. Low means lower observed risk, not proof that
an image is authentic. Medium is inconclusive and should receive additional review. High
indicates stronger risk signals and should be escalated under your policy.

Representative low-risk result:

```json
{
  "unique_trx_id": "trx_example_image_low",
  "filename": "selfie.jpg",
  "content_type": "image/jpeg",
  "status": "success",
  "status_code": 1,
  "billable": true,
  "risk_score": 2.2,
  "risk_level": "low",
  "message": "Not likely to be Spoof or AI-generated",
  "ai_threat_signals": ["Visual Safety Screening", "Liveness Verification"],
  "scored": true,
  "rejected": false,
  "high_risk": false
}
```

Representative medium-risk result:

```json
{
  "unique_trx_id": "trx_example_image_medium",
  "filename": "portrait.jpg",
  "content_type": "image/jpeg",
  "status": "success",
  "status_code": 1,
  "billable": true,
  "risk_score": 5.5,
  "risk_level": "medium",
  "message": "Less likely to be Spoof or AI-generated",
  "ai_threat_signals": ["Visual Safety Screening", "Liveness Verification"],
  "scored": true,
  "rejected": false,
  "high_risk": false
}
```

Representative high-risk result:

```json
{
  "unique_trx_id": "trx_example_image_high",
  "filename": "printed_photo.jpg",
  "content_type": "image/jpeg",
  "status": "success",
  "status_code": 1,
  "billable": true,
  "risk_score": 8.7,
  "risk_level": "high",
  "message": "Likely to be Spoof detected",
  "ai_threat_signals": ["Visual Safety Screening", "Liveness Verification"],
  "scored": true,
  "rejected": false,
  "high_risk": true
}
```

No-face and multiple-face image results are normal, billable rejections even though the
HTTP response is 200:

```json
{
  "unique_trx_id": "trx_example_image_no_face",
  "filename": "landscape.jpg",
  "content_type": "image/jpeg",
  "status": "rejected",
  "status_code": 6,
  "billable": true,
  "risk_score": null,
  "risk_level": null,
  "message": "No face detected in the image",
  "ai_threat_signals": [],
  "scored": false,
  "rejected": true,
  "high_risk": false
}
```

```json
{
  "unique_trx_id": "trx_example_image_multiple_faces",
  "filename": "group_photo.jpg",
  "content_type": "image/jpeg",
  "status": "rejected",
  "status_code": 7,
  "billable": true,
  "risk_score": null,
  "risk_level": null,
  "message": "Multiple faces detected in the image",
  "ai_threat_signals": [],
  "scored": false,
  "rejected": true,
  "high_risk": false
}
```

Input-quality and security failures are returned as non-billable business rejections,
normally over HTTP 400; they are not raised as `ValidationError` because the request
reached the API:

```json
{
  "unique_trx_id": "trx_example_image_quality",
  "filename": "blurry.jpg",
  "content_type": "image/jpeg",
  "status": "rejected",
  "status_code": 2,
  "billable": false,
  "risk_score": null,
  "risk_level": null,
  "message": "Image is too blurry for analysis",
  "ai_threat_signals": [],
  "scored": false,
  "rejected": true,
  "high_risk": false
}
```

```json
{
  "unique_trx_id": "trx_example_image_security",
  "filename": "suspicious.jpg.php",
  "content_type": "application/octet-stream",
  "status": "rejected",
  "status_code": 2,
  "billable": false,
  "risk_score": null,
  "risk_level": null,
  "message": "File failed security validation",
  "ai_threat_signals": [],
  "scored": false,
  "rejected": true,
  "high_risk": false
}
```

For a rejection, show the message to the caller where appropriate and request corrected
media. Do not retry unchanged media.

### Video outcomes

Video and audio are separate modalities. Either modality can have a different risk level.
The API does not return a combined risk score.

Representative result with both modalities:

```json
{
  "unique_trx_id": "trx_example_video_modalities",
  "filename": "voice_clone.mp4",
  "content_type": "video/mp4",
  "status": "success",
  "status_code": 1,
  "billable": true,
  "video_risk_score": 2.2,
  "video_risk_level": "low",
  "video_message": "Not likely to be AI-generated",
  "audio_risk_score": 8.4,
  "audio_risk_level": "high",
  "audio_message": "Likely to be AI-generated",
  "ai_threat_signals": ["Face Swap Detection", "Audio Frequency Analysis"],
  "scored": true,
  "rejected": false,
  "has_audio": true,
  "overall_risk_score": 8.4
}
```

A video without an audio track can still be successfully scored:

```json
{
  "unique_trx_id": "trx_example_video_silent",
  "filename": "silent_clip.mp4",
  "content_type": "video/mp4",
  "status": "success",
  "status_code": 1,
  "billable": true,
  "video_risk_score": 2.1,
  "video_risk_level": "low",
  "video_message": "Not likely to be AI-generated",
  "audio_risk_score": null,
  "audio_risk_level": null,
  "audio_message": "No audio track detected",
  "ai_threat_signals": ["Frame-Level Visual Analysis"],
  "scored": true,
  "rejected": false,
  "has_audio": false,
  "overall_risk_score": 2.1
}
```

Multi-face sampled frames are skipped. If no sampled frame contains exactly one scorable
face, the response uses the same no-face rejection shape and audio is not scored:

```json
{
  "unique_trx_id": "trx_example_video_no_face",
  "filename": "non_face_video.mp4",
  "content_type": "video/mp4",
  "status": "rejected",
  "status_code": 6,
  "billable": true,
  "video_risk_score": null,
  "video_risk_level": null,
  "video_message": "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.",
  "audio_risk_score": null,
  "audio_risk_level": null,
  "audio_message": null,
  "ai_threat_signals": [],
  "scored": false,
  "rejected": true,
  "has_audio": false,
  "overall_risk_score": null
}
```

Video format, size, and security failures are similarly returned as non-billable
`status_code: 2` rejections with null modality fields.

## Method reference

### `NeuroVerifyClient(...)`

```python
NeuroVerifyClient(
    api_key=None,
    base_url=None,
    timeout=120.0,
    max_retries=3,
    user_agent=None,
    *,
    allow_custom_base_url=False,
    transport=None,
)
```

- `api_key: str | None`: explicit key, or `NEURALDEFEND_API_KEY` when `None`. The selected
  value is stripped and must be non-empty.
- `base_url: str | None`: explicit API origin, or `NEURALDEFEND_BASE_URL` when `None`, or
  `https://deepscan.neuraldefend.com` when neither is set.
- `timeout: int | float`: positive HTTP operation timeout in seconds. Booleans are
  rejected.
- `max_retries: int`: retry count from `0` through `3`. The default `3` permits four total
  HTTP attempts.
- `user_agent: str | None`: custom `User-Agent`; a falsey value uses
  `neuraldefend-python/1.0.2`.
- `allow_custom_base_url: bool`: explicit opt-in required for a non-Neural Defend origin.
  That origin receives the API key and uploaded media.
- `transport: httpx.BaseTransport | None`: advanced transport injection, intended for
  controlled testing. Supplying one also permits an HTTP test origin; production traffic
  must use HTTPS.

The implementation also has three actual underscore-prefixed constructor arguments used
by deterministic retry tests: `_sleep` defaults to `time.sleep`, `_random` defaults to
`random.random`, and `_clock` defaults to the current UTC time. They have no environment
fallback and explicit values win. These are private, unsupported integration details and
should not be used by customer applications.

Base URLs must be origin-only URLs with no credentials, path, query, or fragment. The
production and staging origins use HTTPS. Redirects are never followed. API keys are
redacted from the client representation and SDK-generated error detail.

Configuration precedence is:

1. `api_key` argument, then `NEURALDEFEND_API_KEY`; there is no default key.
2. `base_url` argument, then `NEURALDEFEND_BASE_URL`, then the production origin.
3. All other constructor arguments use only their explicit value or documented default;
   they have no environment-variable fallback.

### `NeuroVerifyClient.staging(...)`

```python
NeuroVerifyClient.staging(api_key=None, **kwargs)
```

Creates a client pinned to `https://stage.deepscan.neuraldefend.com`. It ignores both a
`base_url` supplied in `kwargs` and `NEURALDEFEND_BASE_URL`. `api_key` still takes
precedence over `NEURALDEFEND_API_KEY`; other constructor options can be passed through
`kwargs`.

Use staging only with a staging credential supplied during onboarding:

```python
with NeuroVerifyClient.staging(api_key=staging_key, max_retries=0) as client:
    result = client.detect_image("staging-fixture.jpg")
```

### `detect_image(...)`

```text
client.detect_image(file, *, filename=None) -> ImageResult
```

- `file`: filesystem path (`str` or `os.PathLike`), `bytes`, or a readable binary
  file-like object.
- `filename`: optional non-empty upload name. It is required for `bytes` and nameless
  streams. When supplied for a path or named stream, its basename overrides the inferred
  upload name.

The path must be a readable, non-empty regular file. Local validation failures raise
`ValidationError` before a request is sent.

### `detect_video(...)`

```text
client.detect_video(
    file,
    *,
    filename=None,
    max_frames=None,
    sample_rate=None,
) -> VideoResult
```

- `file` and `filename`: same behavior as `detect_image`.
- `max_frames: int | None`: optional maximum number of frames to sample, from `1` through
  `100`. When omitted, the API default is 12.
- `sample_rate: int | None`: optional sampling override; must be an integer of at least
  `1`. The SDK and published API contract specify no upper bound.

`bool` is not accepted for either integer option.

### `close()` and context management

```python
client.close()
```

Closes the underlying HTTP connection pool. Prefer context management so cleanup also
occurs when detection raises:

```python
with NeuroVerifyClient() as client:
    image = client.detect_image("selfie.jpg")
    video = client.detect_video("clip.mp4")
```

If a client is not used in a `with` statement, call `close()` in a `finally` block.

## Input types and stream lifecycle

### Paths

Paths are opened in binary mode and streamed rather than loaded into memory. The SDK
validates that the target is a regular, non-empty file within the endpoint limit, keeps
the file open across retries so every attempt reads the same handle, and closes the handle
when the detection call finishes.

### Bytes

Bytes are accepted when `filename` is supplied:

```python
image_bytes = image_path.read_bytes()
result = client.detect_image(image_bytes, filename="selfie.jpg")
```

Bytes are held in memory and replayed safely for retries. Empty or oversized values are
rejected locally.

### Binary file-like streams

Named binary streams can provide their upload name through `.name`; otherwise pass
`filename`:

```python
with open("selfie.jpg", "rb") as stream:
    result = client.detect_image(stream)
```

```python
from io import BytesIO

stream = BytesIO(image_bytes)
result = client.detect_image(stream, filename="selfie.jpg")
```

Caller-owned streams are never closed by the SDK.

- Seekable streams must support `seek()` and `tell()`. The SDK validates their full size
  and rewinds them to byte zero before the initial request and every retry, regardless of
  their position on entry.
- Non-seekable streams are consumed once, checked against the byte limit while streaming,
  and require a client configured with `max_retries=0`.
- Text streams are rejected; `read()` must return `bytes`.

The filename controls deterministic multipart metadata and MIME selection. Known
extensions receive the MIME types below. An unknown extension emits `UserWarning` and is
sent as `application/octet-stream`; the server still inspects the actual content.

## Supported media and limits

Image uploads have an exact maximum of 10 MiB (`10,485,760` bytes):

- `.jpg`, `.jpeg` — `image/jpeg`
- `.png` — `image/png`
- `.bmp` — `image/bmp`
- `.tif`, `.tiff` — `image/tiff`
- `.webp` — `image/webp`
- `.heic` — `image/heic`
- `.heif` — `image/heif`

Images must be at least 224 × 224 pixels and contain exactly one face for scoring. EXIF
orientation is handled by the service. No-face and multiple-face images are rejected as
described above.

Video uploads have an exact maximum of `1,500,000,000` bytes:

- `.mp4` — `video/mp4`
- `.avi` — `video/vnd.avi`
- `.mov` — `video/quicktime`
- `.mkv` — `video/matroska`
- `.wmv` — `video/x-ms-wmv`
- `.flv` — `video/x-flv`
- `.webm` — `video/webm`
- `.ogg`, `.ogv` — `video/ogg`

The service samples 12 frames by default. A sampled frame must contain one face to be
scorable; multi-face frames are skipped. If no scorable single-face frame remains, the
entire request is rejected and audio is not scored.

## Exceptions

All public SDK exceptions derive from `NeuroVerifyError` and expose `detail`,
`status_code`, and `request_id` where available.

- `ValidationError`: invalid local configuration or input, such as a missing key,
  unreadable path, missing filename, oversized file, text stream, or out-of-range option.
  No HTTP request is made for failures detected locally.
- `AuthenticationError`: HTTP 401; the selected key is invalid, expired, or inactive.
- `ScopeError`: HTTP 403; the key lacks access to the requested endpoint.
- `RateLimitError`: final HTTP 429 after configured retries. It also exposes
  `retry_after`, `limit`, `remaining`, and `reset`.
- `ServerError`: an API error envelope, including final HTTP 500/503 responses. When
  available, `envelope` contains an immutable sanitized error envelope.
- `TimeoutError`: an HTTP timeout. It is not retried automatically.
- `NetworkError`: a non-timeout transport failure. It is not retried automatically.
- `ProtocolError`: valid transport response with malformed JSON or a response that does
  not satisfy the required NeuroVerify envelope. A malformed final HTTP 500/503 response
  remains a `ServerError`.
- `HttpError`: another unclassified HTTP status. Authentication, scope, rate-limit, and
  server errors are subclasses of `HttpError`, so catch this last.

Example handling for every concrete exception:

```python
from neuraldefend import (
    AuthenticationError,
    HttpError,
    NetworkError,
    NeuroVerifyClient,
    ProtocolError,
    RateLimitError,
    ScopeError,
    ServerError,
    TimeoutError as NeuroVerifyTimeoutError,
    ValidationError,
)

try:
    with NeuroVerifyClient() as client:
        result = client.detect_image("selfie.jpg")
except ValidationError as error:
    print(f"fix configuration or input: {error.detail}")
except AuthenticationError as error:
    print(f"verify the API key (request {error.request_id})")
except ScopeError as error:
    print(f"request image endpoint access (request {error.request_id})")
except RateLimitError as error:
    print(f"rate limited; retry-after={error.retry_after}, request={error.request_id}")
except ServerError as error:
    print(f"service error {error.status_code}, request={error.request_id}")
except NeuroVerifyTimeoutError as error:
    print(f"request timed out: {error.detail}")
except NetworkError as error:
    print(f"network failure: {error.detail}")
except ProtocolError as error:
    print(f"unexpected API response, request={error.request_id}")
except HttpError as error:
    print(f"unexpected HTTP {error.status_code}, request={error.request_id}")
else:
    if result.rejected:
        print(f"valid request but media was not scored: {result.message}")
```

Do not confuse a returned business rejection with an exception. HTTP 400 validation or
security rejections that have the documented score envelope return a result so your
application can inspect the API's message and `billable` value.

## Retries, billability, and idempotency

The SDK retries only HTTP 429, 500, and 503:

- HTTP 429 honors a valid `Retry-After` duration or HTTP date, capped at 3,600 seconds. If
  the header is absent or invalid, waits are 1, 2, and 4 seconds.
- HTTP 500/503 waits use exponential delays of 1, 2, and 4 seconds plus up to 25% jitter.
- HTTP 400, 401, 403, other HTTP statuses, timeouts, and network failures are not retried.
- `max_retries=0` disables retries; `max_retries=3` allows up to four total attempts.

Requests are not idempotent. Every accepted attempt receives a new `unique_trx_id`, and
retries or manual resubmission may create separate billable transactions. A timeout or
network failure can leave billability unknown because the client may not have received
the server response. Preserve returned transaction IDs for audit, support, and billing
correlation, and avoid adding another retry layer without accounting for the SDK's own
attempts.

`billable` describes the returned transaction only. A successful score is normally
billable; no-face and face-policy rejections can also be billable. Input validation and
security rejections are normally non-billable. Always use the actual returned value.

## Privacy and security

- Upload media only with the data owner's authorization and an appropriate legal basis.
- Treat images, video, audio, filenames, and diagnostics as potentially biometric or
  otherwise sensitive personal data.
- Apply your organization's consent, residency, encryption, retention, deletion,
  access-control, and audit requirements.
- Keep API keys in a secret manager or server-side environment. Rotate a key if exposure
  is suspected.
- Do not send a production key or customer media to an untrusted `base_url`.
  `allow_custom_base_url=True` is a deliberate trust decision.
- Redirects are disabled so credentials and media are not forwarded to another origin.
- Minimize production logging. Prefer transaction IDs and normalized status fields over
  filenames, raw payloads, media bytes, headers, or keys.
- Do not disguise content with a different extension; the server performs format and
  security validation.

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

**`api_key is required`**

Set `NEURALDEFEND_API_KEY` in the same process environment that starts Python, or pass a
non-empty `api_key` from a secret provider.

**HTTP 401 / `AuthenticationError`**

Verify that the selected key is current and belongs to the intended environment. An
explicit constructor key overrides the environment variable.

**HTTP 403 / `ScopeError`**

The key does not have access to the endpoint. Request the required image or video scope
during onboarding.

**`filename is required`**

Pass `filename="photo.jpg"` or `filename="clip.mp4"` when uploading bytes or a stream
without a usable `.name`.

**`non-seekable streams require max_retries=0`**

Use `NeuroVerifyClient(max_retries=0)`, provide a seekable binary stream, or upload from a
path. A non-seekable stream cannot be replayed safely.

**Unsupported-extension warning**

Use a documented extension matching the real content. The request is still sent as
`application/octet-stream`, and the API may reject it after content inspection.

**HTTP 200 but no score**

Inspect `status`, `status_code`, and the result message. No-face and face-policy outcomes
are expected business rejections, not transport success indicators.

**No audio score**

Check `has_audio` and `audio_message`. `"No audio track detected"` means video scoring
succeeded without an audio modality. A no-face video rejection suppresses both modalities.

**Repeated 429**

Inspect the `RateLimitError` metadata, reduce concurrency, and confirm tenant limits with
your account manager. The SDK has already exhausted its configured retries when the
exception is raised.

**Timeout or network failure**

Confirm egress, DNS, TLS interception, proxy behavior, and the configured timeout. These
failures are not retried automatically because the server may already have accepted a
billable request.

**Security or quality rejection**

Do not retry the same media. Correct the format, dimensions, quality, face count, or
security issue indicated by the result message, then submit only if a new request is
appropriate.

## Wire-level API documentation

For the exhaustive HTTP envelopes, status codes, risk-band descriptions, messages,
billability scenarios, and request examples, see:

- [Unified Face Authenticity Score](../../docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](../../docs/client/unified-video-authenticity.md)

The wire API uses an outer endpoint-specific envelope and `"Y"`/`"N"` billing strings.
The Python SDK intentionally normalizes those details in `ImageResult` and `VideoResult`.

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the SDK version, endpoint, `request_id` or
`unique_trx_id`, and a sanitized reproduction. Do not send API keys, raw customer media,
or biometric/personal data.
