<div align="center">

# NeuralDefend Python SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Python in a few lines of code.**

[![PyPI](https://img.shields.io/pypi/v/neuraldefend?style=flat-square&logo=pypi&logoColor=white&label=PyPI&color=3775A9)](https://pypi.org/project/neuraldefend/)
[![Python](https://img.shields.io/badge/python-3.9%2B-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start-image) · [Examples](#examples) · [Results](#result-handling) · [Errors](#exceptions) · [Troubleshooting](#troubleshooting)

</div>

---

## In plain words

You give the SDK a photo or a video. It sends the file to Neural Defend's **NeuroVerify**
service and gives you back an answer like this:

> "This face has a **low** / **medium** / **high** risk of being fake."

That is the whole idea. You do not need to know anything about machine learning, HTTP, or
file uploads; the SDK handles all of that for you.

| You want to... | Call | You get back |
|---|---|---|
| Check a photo of a face | `client.detect_image("photo.jpg")` | An `ImageResult` with one risk level |
| Check a video | `client.detect_video("clip.mp4")` | A `VideoResult` with a video risk and an audio risk |

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `low` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `medium` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `high` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection**, not a crash. The
[examples](#examples) show how to handle each case.

## About this SDK

The official synchronous Python client for the NeuroVerify image and video authenticity
API. Version `1.0.3` provides typed result objects, streaming multipart uploads, bounded
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

This guide documents `neuraldefend==1.0.3`.

## Installation

Install the pinned release in the same environment as your application:

```bash
python -m pip install "neuraldefend==1.0.3"
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

```python
import json

from neuraldefend import NeuroVerifyClient

result = NeuroVerifyClient().detect_image("selfie.jpg")  # uses NEURALDEFEND_API_KEY
print(json.dumps(result.to_dict(), indent=2))
```

That's it. You get the full response:

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

The field that matters most is `risk_level`: `low`, `medium`, or `high`.

## Quick start: video

```python
import json

from neuraldefend import NeuroVerifyClient

result = NeuroVerifyClient().detect_video("clip.mp4")
print(json.dumps(result.to_dict(), indent=2))
```

You get the full response, with a separate result for the picture and for the sound:

```json
{
  "unique_trx_id": "trx_example_video_modalities",
  "filename": "clip.mp4",
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

`overall_risk_score` is simply the higher of the two scores.

## Examples

> **Building for a specific industry?** See the [industry use cases](../../docs/use-cases/README.md):
> eKYC onboarding, KYC re-verification, Video KYC, HR tech, and video conferencing, with
> complete code for this SDK.

Each example is complete: copy it into a `.py` file, set `NEURALDEFEND_API_KEY`, and run
it. The output shown under each example is representative; your scores, transaction IDs,
and messages will differ.

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Check one photo](#1-check-one-photo) | The smallest useful program |
| 2 | [Check a video with sound](#2-check-a-video-with-sound) | Reading the separate video and audio results |
| 3 | [Turn a result into a decision](#3-turn-a-result-into-a-decision) | Mapping low, medium, high, and rejected to actions |
| 4 | [Upload bytes from memory](#4-upload-bytes-from-memory) | Checking files that never touch the disk |
| 5 | [Check a whole folder](#5-check-a-whole-folder) | Batch processing with a summary table |
| 6 | [Handle every kind of error](#6-handle-every-kind-of-error) | Telling bad input, bad keys, and outages apart |
| 7 | [Save an audit record](#7-save-an-audit-record) | Keeping transaction IDs for billing and support |
| 8 | [Add a check to a web API](#8-add-a-check-to-a-web-api) | Using the SDK inside a FastAPI endpoint |
| 9 | [Test against staging](#9-test-against-staging) | Using the staging environment safely |
| 10 | [Tune video sampling](#10-tune-video-sampling) | Trading speed for coverage on long videos |

### 1. Check one photo

Print just the answer instead of the whole response.

```python
from neuraldefend import NeuroVerifyClient

result = NeuroVerifyClient().detect_image("selfie.jpg")
print(result.risk_level, result.message)
```

Output:

```text
low Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** answers: one for the picture and one for the sound.

```python
from neuraldefend import NeuroVerifyClient

result = NeuroVerifyClient().detect_video("interview.mp4")
print("Video:", result.video_risk_level)
print("Audio:", result.audio_risk_level)
```

Output:

```text
Video: low
Audio: high
```

Here the face looks real but the voice is likely fake. A video with no sound prints
`Audio: None`.

### 3. Turn a result into a decision

Your application usually needs one of a few actions. Write that mapping once and reuse
it. Always branch on the **risk level**, never on your own numeric threshold, because the
service may tune its scoring bands.

```python
from neuraldefend import ImageResult, NeuroVerifyClient


def decide(result: ImageResult) -> str:
    if result.rejected:
        return f"ASK FOR A NEW PHOTO - {result.message}"
    if not result.scored:
        return f"MANUAL REVIEW - unrecognized status {result.status!r}"
    return {
        "low": "CONTINUE",
        "medium": "MANUAL REVIEW",
        "high": "ESCALATE",
    }.get(result.risk_level, "MANUAL REVIEW")


with NeuroVerifyClient() as client:
    for path in ["selfie.jpg", "printed_photo.jpg", "landscape.jpg"]:
        print(f"{path:<20} -> {decide(client.detect_image(path))}")
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

```python
from pathlib import Path

from neuraldefend import NeuroVerifyClient

image_bytes = Path("selfie.jpg").read_bytes()  # or bytes from your storage service

with NeuroVerifyClient() as client:
    result = client.detect_image(image_bytes, filename="selfie.jpg")

print(f"{len(image_bytes):,} bytes checked -> {result.risk_level}")
```

Output:

```text
482,113 bytes checked -> low
```

Open file objects work too: `client.detect_image(open("selfie.jpg", "rb"))`. See
[Input types](#input-types-and-stream-lifecycle) for streams and retries.

### 5. Check a whole folder

Reuse one client for many files; it keeps the connection open and is much faster than
creating a client per file.

```python
from collections import Counter
from pathlib import Path

from neuraldefend import NeuroVerifyClient

IMAGE_TYPES = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
folder = Path("uploads")
summary = Counter()

with NeuroVerifyClient() as client:
    for path in sorted(folder.iterdir()):
        if path.suffix.lower() not in IMAGE_TYPES:
            continue
        result = client.detect_image(path)
        outcome = result.risk_level if result.scored else "rejected"
        summary[outcome] += 1
        print(f"{path.name:<24} {outcome:<9} {result.message}")

print("\nSummary:", dict(summary))
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: {'low': 1, 'rejected': 1, 'medium': 1, 'high': 1}
```

Each call is a separate transaction and may be billable. Check your rate limits before
running large batches.

### 6. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation | How it shows up | Who fixes it |
|---|---|---|
| The file was checked but could not be scored | A result with `rejected == True` | The end user sends better media |
| Your setup is wrong (missing key, bad path) | `ValidationError`, `AuthenticationError`, `ScopeError` | You, the developer |
| The service or network had a problem | `RateLimitError`, `ServerError`, `TimeoutError`, `NetworkError` | Try again later |

```python
from neuraldefend import (
    AuthenticationError,
    NeuroVerifyClient,
    NeuroVerifyError,
    RateLimitError,
    ScopeError,
    ValidationError,
)

try:
    with NeuroVerifyClient() as client:
        result = client.detect_image("selfie.jpg")
except ValidationError as error:
    print(f"Fix the input or configuration: {error.detail}")
except AuthenticationError:
    print("The API key is invalid or expired. Check NEURALDEFEND_API_KEY.")
except ScopeError:
    print("This key cannot use the image endpoint. Ask Neural Defend to add it.")
except RateLimitError as error:
    print(f"Too many requests. Try again in {error.retry_after} seconds.")
except NeuroVerifyError as error:
    print(f"Service problem ({type(error).__name__}), request id: {error.request_id}")
else:
    if result.rejected:
        print(f"Please upload a different photo: {result.message}")
    else:
        print(f"Risk: {result.risk_level}")
```

Output when the key is missing:

```text
Fix the input or configuration: api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

The [Exceptions](#exceptions) section lists every error class.

### 7. Save an audit record

Every result has a `unique_trx_id`. Store it: it is what support and billing will ask for.
`to_dict()` gives you a plain dictionary that is safe to turn into JSON.

```python
import json
from datetime import datetime, timezone

from neuraldefend import NeuroVerifyClient

with NeuroVerifyClient() as client:
    result = client.detect_image("selfie.jpg")

record = {
    "checked_at": datetime.now(timezone.utc).isoformat(),
    "transaction_id": result.unique_trx_id,
    "status": result.status,
    "risk_level": result.risk_level,
    "billable": result.billable,
}

with open("audit.jsonl", "a", encoding="utf-8") as log:
    log.write(json.dumps(record) + "\n")

print(json.dumps(record, indent=2))
```

Output:

```json
{
  "checked_at": "2026-10-16T09:41:07.512310+00:00",
  "transaction_id": "trx_example_image_low",
  "status": "success",
  "risk_level": "low",
  "billable": true
}
```

Store only the fields you need. Avoid logging filenames or `result.raw`, which may contain
personal data.

### 8. Add a check to a web API

This [FastAPI](https://fastapi.tiangolo.com/) endpoint accepts an upload and returns the
SDK's normalized result. One client is created at startup and shared by all requests.
Install the extras first with `pip install fastapi uvicorn python-multipart`.

```python
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, UploadFile

from neuraldefend import NeuroVerifyClient, NeuroVerifyError, ValidationError

client = NeuroVerifyClient()


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    client.close()  # release connections when the server stops


app = FastAPI(lifespan=lifespan)


@app.post("/verify-selfie")
def verify_selfie(photo: UploadFile) -> dict:
    # A plain `def` endpoint runs in a worker thread, so the blocking SDK call is safe here.
    try:
        result = client.detect_image(photo.file, filename=photo.filename or "upload.jpg")
    except ValidationError as error:
        raise HTTPException(status_code=422, detail=error.detail)
    except NeuroVerifyError:
        raise HTTPException(status_code=503, detail="Verification is temporarily unavailable")
    return result.to_dict()
```

Run it with `uvicorn app:app`, then call it:

```bash
curl -F "photo=@selfie.jpg" http://127.0.0.1:8000/verify-selfie
```

Output:

```json
{"unique_trx_id": "trx_example_image_low", "filename": "selfie.jpg", "content_type": "image/jpeg", "status": "success", "status_code": 1, "billable": true, "risk_score": 2.2, "risk_level": "low", "message": "Not likely to be Spoof or AI-generated", "ai_threat_signals": ["Visual Safety Screening", "Liveness Verification"], "scored": true, "rejected": false, "high_risk": false}
```

### 9. Test against staging

Neural Defend can issue a separate staging key during onboarding. `staging()` always uses
the staging server, so a test can never reach production by mistake.

```python
import os

from neuraldefend import NeuroVerifyClient

with NeuroVerifyClient.staging(
    api_key=os.environ["NEURALDEFEND_STAGING_API_KEY"],
    max_retries=0,  # fail fast in tests
) as client:
    result = client.detect_image("tests/fixtures/selfie.jpg")

print(f"staging: {result.status} / {result.risk_level}")
```

Output:

```text
staging: success / low
```

### 10. Tune video sampling

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `max_frames` accepts 1 to 100.

```python
import time

from neuraldefend import NeuroVerifyClient

with NeuroVerifyClient(timeout=300) as client:  # allow more time for large uploads
    for frames in (6, 24, 48):
        started = time.perf_counter()
        result = client.detect_video("webinar.mp4", max_frames=frames)
        seconds = time.perf_counter() - started
        print(f"{frames:>2} frames -> video {result.video_risk_level} in {seconds:.1f}s")
```

Output:

```text
 6 frames -> video low in 4.8s
24 frames -> video low in 9.3s
48 frames -> video low in 15.6s
```

Each call above is a separate, billable transaction. Pick one setting for production.

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
    allow_http_for_testing=False,
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
  `neuraldefend-python/1.0.3`.
- `allow_custom_base_url: bool`: explicit opt-in required for a non-Neural Defend origin.
  That origin receives the API key and uploaded media.
- `allow_http_for_testing: bool`: permits an `http://` origin for a local test server.
  Production traffic must stay on HTTPS. A custom `transport` does not enable this.
- `transport: httpx.BaseTransport | None`: advanced transport injection, for proxies,
  mutual TLS, or tests. Supplying one does not relax HTTPS or the host allowlist,
  because that transport still receives the API key and uploaded media.

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
