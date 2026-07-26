# Unified Video Authenticity Score

### NeuroVerify API — AI-Powered Video Authenticity Detection

#### `POST`

```
https://deepscan.neuraldefend.com/detect/video
```

---

## Overview

The **Unified Video Authenticity Score** is NeuroVerify's combined video verification endpoint. It returns **split modality risk scores** for video and audio independently. Scored responses may also include **`ai_threat_signals`** describing checks applied during analysis; treat this list as informational because it may evolve.

Unlike the image unified endpoint, video analysis exposes **separate** `video_risk_*` and `audio_risk_*` fields rather than a single combined score. Derive overall risk client-side when needed: `max(video_risk_score, audio_risk_score ?? 0)`.

**Key benefits:**

- Single API call replaces separate video and audio detection endpoints
- Opaque per-modality scoring protects proprietary model IP
- Deterministic risk bands for easy integration
- Enterprise-grade security validation on every upload

---

## Endpoint Details

| Property | Value |
|----------|-------|
| **URL** | `/detect/video` |
| **Method** | `POST` |
| **Content-Type** | `multipart/form-data` |
| **Authentication** | API Key required (`x-api-key` header) |
| **Response envelope** | `unified_video_authenticity_score` |
| **Scoring** | Split `video_risk_*` + `audio_risk_*` per modality |

---

## Supported Video Formats

| Format | MIME Type | File Extensions |
|--------|-----------|-----------------|
| MP4 | `video/mp4` | `.mp4` |
| AVI | `video/vnd.avi` | `.avi` |
| MOV | `video/quicktime` | `.mov` |
| MKV | `video/matroska` | `.mkv` |
| WMV | `video/x-ms-wmv` | `.wmv` |
| FLV | `video/x-flv` | `.flv` |
| WebM | `video/webm` | `.webm` |
| OGG / OGV | `video/ogg` | `.ogg`, `.ogv` |

---

## File & Video Requirements

| Constraint | Value | Notes |
|------------|-------|-------|
| **Maximum file size** | 1.5 GB (1,500,000,000 bytes) | Files exceeding this are rejected |
| **Frame sampling** | **12 frames** (default) | Uniformly distributed; override with `max_frames` (1–100) |
| **Face requirement** | Single face per sampled frame | Multi-face frames are skipped; if no single-face frames remain → `NO_FACE` rejection |
| **Optional parameters** | `sample_rate`, `max_frames` | Query parameters; see [Request Format](#request-format) |

---

## Request Format

### Headers

| Header | Required | Description |
|--------|----------|-------------|
| `x-api-key` | Yes | Your API key (provided at onboarding) |
| `Content-Type` | Automatic | Let the HTTP client generate `multipart/form-data` with its boundary; do not set this header manually |

### Query Parameters

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `max_frames` | int | No | Maximum frames to sample (1–100). **Default: 12** |
| `sample_rate` | int | No | Optional sampling override (must be ≥ 1) |

### Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | File | Yes | Video file to analyze |

### Example Request — cURL

```bash
curl -X POST "https://deepscan.neuraldefend.com/detect/video?max_frames=12" \
  -H "x-api-key: YOUR_API_KEY" \
  -F "file=@/path/to/video.mp4"
```

### Example Request — Python

```python
import requests

url = "https://deepscan.neuraldefend.com/detect/video"
headers = {"x-api-key": "YOUR_API_KEY"}

with open("video.mp4", "rb") as video:
    response = requests.post(
        url,
        headers=headers,
        params={"max_frames": 12},
        files={"file": video},
    )
data = response.json()

result = data["unified_video_authenticity_score"]
if result["status"] == "success":
    print(f"Video: {result['video_risk_level']} ({result['video_risk_score']})")
    print(f"Audio: {result['audio_risk_level']} ({result['audio_risk_score']})")
else:
    print(f"Could not score: {result['video_message']}")
```

## Response Format

All responses are wrapped in the **`unified_video_authenticity_score`** envelope:

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "...",
    "filename": "...",
    "content_type": "...",
    "status": "success | rejected | error",
    "status_code": 1,
    "billable": "Y | N",
    "video_risk_score": 2.4,
    "video_risk_level": "low | medium | high",
    "video_message": "...",
    "audio_risk_score": 2.0,
    "audio_risk_level": "low | medium | high",
    "audio_message": "...",
    "ai_threat_signals": ["..."]
  }
}
```

### Response Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `unique_trx_id` | string | Unique transaction identifier for audit trail |
| `filename` | string | Name of the uploaded file |
| `content_type` | string | Detected MIME type |
| `status` | string | `"success"`, `"rejected"`, or `"error"` |
| `status_code` | integer | Numeric status (see [Status Codes](#status-codes)) |
| `billable` | string | `"Y"` if the request counts toward billing; `"N"` otherwise |
| `video_risk_score` | float \| null | **0.1 – 10.0** (higher = higher AI/manipulation risk); `null` if rejected or error |
| `video_risk_level` | string \| null | `"low"`, `"medium"`, or `"high"` for video modality; `null` if not scored |
| `video_message` | string | Human-readable explanation for the **video** modality (or rejection/error copy) |
| `audio_risk_score` | float \| null | **0.1 – 10.0** (higher = higher AI/manipulation risk) when analysis ran; `null` if no audio, skipped, or failed |
| `audio_risk_level` | string \| null | `"low"`, `"medium"`, or `"high"` for audio modality; `null` if not scored |
| `audio_message` | string \| null | Human-readable explanation for the **audio** modality (or status copy such as `"No audio track detected"`); null on rejected requests |
| `ai_threat_signals` | array \| absent | List of checks applied — **present only on scored success responses** |

---

## Risk Score Bands (per modality)

Each of `video_risk_score` and `audio_risk_score` is mapped independently using the same bands.

| Risk Score | Risk Level | Message | Interpretation |
|------------|------------|---------|----------------|
| 0.1 – 3.9 | `low` | "Not likely to be AI-generated" | Modality appears authentic |
| 4.0 – 6.9 | `medium` | "Less likely to be AI-generated" | Inconclusive — review recommended |
| 7.0 – 10.0 | `high` | "Likely to be AI-generated" | Strong indicators of AI manipulation |

**Optional overall decision (client-side, not returned by API):**

```javascript
const overallScore = Math.max(
  result.video_risk_score,
  result.audio_risk_score ?? 0
);
```

---

## AI Threat Signals (success only)

Scored success responses include the checks applied during analysis:

```json
"ai_threat_signals": [
  "Photometric Liveness Signal",
  "Identity Consistency Analysis",
  "Face Swap Detection",
  "AI Generative Model Analysis",
  "Audio Frequency Analysis",
  "AI Pixel-Level Manipulation",
  "Digital Content Provenance",
  "Frame-Level Visual Analysis"
]
```

Rejections and errors do **not** include `ai_threat_signals`.

---

## Status Codes

| `status_code` | `status` | HTTP | Billable | Meaning |
|---------------|----------|------|----------|---------|
| 1 | `success` | 200 | Yes | Analysis completed — modality scores present |
| 2 | `rejected` | 400 | No | Input validation failed (format, size, security) |
| 5 | `error` | 500 / 503 | No | Server-side failure — retry with backoff |
| 6 | `rejected` | 200 | Yes | No scorable single-face frames in video |

---

## Response Scenarios

### Successful Analysis

`status: "success"` · `status_code: 1` · `billable: "Y"` · `ai_threat_signals` present

---

#### Authentic video — both modalities low risk

**HTTP Status:** `200 OK`

Representative example (scores vary by content):

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_vid001abc234def567",
    "filename": "selfie_video.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 2.4,
    "video_risk_level": "low",
    "video_message": "Not likely to be AI-generated",
    "audio_risk_score": 2.0,
    "audio_risk_level": "low",
    "audio_message": "Not likely to be AI-generated",
    "ai_threat_signals": [
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
}
```

---

#### Face swap detected — video high, audio low

**HTTP Status:** `200 OK`

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_qro0hy17yeyridi0f4yu",
    "filename": "faceswap_2.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 9.0,
    "video_risk_level": "high",
    "video_message": "Likely to be AI-generated",
    "audio_risk_score": 2.2,
    "audio_risk_level": "low",
    "audio_message": "Not likely to be AI-generated",
    "ai_threat_signals": [
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
}
```

---

#### AI-generated video — video high, audio low

**HTTP Status:** `200 OK`

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_kzjyemiphii5m15ua18w",
    "filename": "single_ai_video.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 9.0,
    "video_risk_level": "high",
    "video_message": "Likely to be AI-generated",
    "audio_risk_score": 2.0,
    "audio_risk_level": "low",
    "audio_message": "Not likely to be AI-generated",
    "ai_threat_signals": [
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
}
```

---

#### Audio spoof detected — video low, audio high

**HTTP Status:** `200 OK`

When audio analysis detects spoofing but video frames appear genuine, audio scores high while video stays low.

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_vid_aud456def789abc012",
    "filename": "voice_clone.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 2.2,
    "video_risk_level": "low",
    "video_message": "Not likely to be AI-generated",
    "audio_risk_score": 8.4,
    "audio_risk_level": "high",
    "audio_message": "Likely to be AI-generated",
    "ai_threat_signals": [
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
}
```

---

#### Both modalities suspicious

**HTTP Status:** `200 OK`

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_vid_both789abc012def345",
    "filename": "full_fake.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 8.9,
    "video_risk_level": "high",
    "video_message": "Likely to be AI-generated",
    "audio_risk_score": 7.8,
    "audio_risk_level": "high",
    "audio_message": "Likely to be AI-generated",
    "ai_threat_signals": [
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
}
```

---

#### Medium video risk, no audio track

**HTTP Status:** `200 OK`

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_gehm7hgqgsjsh1xvevh5",
    "filename": "incruiter.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 4.5,
    "video_risk_level": "medium",
    "video_message": "Less likely to be AI-generated",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": "No audio track detected",
    "ai_threat_signals": [
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
}
```

---

#### Silent video — no audio track

**HTTP Status:** `200 OK`

When the video has no audio stream, `audio_risk_score` and `audio_risk_level` are `null` and `audio_message` is `"No audio track detected"`. Video scoring proceeds normally.

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_vid_na123abc456def789",
    "filename": "silent_clip.mp4",
    "content_type": "video/mp4",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "video_risk_score": 2.1,
    "video_risk_level": "low",
    "video_message": "Not likely to be AI-generated",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": "No audio track detected",
    "ai_threat_signals": [
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
}
```

---

### Rejected Requests

`status: "rejected"` · all `*_risk_score` / `*_risk_level` → **`null`** · **no** `ai_threat_signals`

Rejection copy lives on **`video_message`** only. `audio_message` is `null`.

| Scenario | `status_code` | HTTP | `video_message` |
|----------|---------------|------|-------------------|
| No face in sampled frames | 6 | 200 | No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio. |
| Invalid format | 2 | 400 | Unsupported file format |
| File too large (>1.5 GB) | 2 | 400 | File exceeds maximum size limit |
| Security validation failed | 2 | 400 | File failed security validation |

---

#### No face detected

**HTTP Status:** `200 OK` · **Billable:** Yes

Multi-face frames are skipped during sampling. If no single-face frames remain across all sampled frames, the response is `NO_FACE` (status_code 6) — even when multiple faces appear in the video (see multi-face example below).

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_77lgbdbn4kec3ouwbnjt",
    "filename": "non_face_video_2.mp4",
    "content_type": "video/mp4",
    "status": "rejected",
    "status_code": 6,
    "billable": "Y",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

#### Multi-face video (no scorable single-face frames)

**HTTP Status:** `200 OK` · **Billable:** Yes

Videos where every sampled frame contains zero or multiple faces return the same `NO_FACE` rejection shape (status_code 6). Audio is not scored.

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_pzyvd8hlr6f2cvum84qr",
    "filename": "multiple_ai.mp4",
    "content_type": "video/mp4",
    "status": "rejected",
    "status_code": 6,
    "billable": "Y",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

#### Unsupported file format

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_mp0andhgna2uu351stqa",
    "filename": "invalid_upload.txt",
    "content_type": "text/plain",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "Unsupported file format",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

#### File too large

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_big901def234abc567",
    "filename": "huge_video.mp4",
    "content_type": "video/mp4",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "File exceeds maximum size limit",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

#### Security rejection

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_sec345def678abc901",
    "filename": "suspicious.mp4.exe",
    "content_type": "application/octet-stream",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "File failed security validation",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

### Server Errors

`status: "error"` · `status_code: 5` · `billable: "N"` · not scored

A server-side issue prevented analysis. Retry with exponential backoff.

---

#### Service unavailable (503)

Returned when required detectors are not initialized. Same JSON body as 500; HTTP status is **503**.

**HTTP Status:** `503 Service Unavailable`

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_vid_err456def789abc012",
    "filename": "video.mp4",
    "content_type": "video/mp4",
    "status": "error",
    "status_code": 5,
    "billable": "N",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "Internal server error during video detection",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

#### Internal server error (500)

**HTTP Status:** `500 Internal Server Error`

```json
{
  "unified_video_authenticity_score": {
    "unique_trx_id": "trx_500def789abc012345",
    "filename": "video.mp4",
    "content_type": "video/mp4",
    "status": "error",
    "status_code": 5,
    "billable": "N",
    "video_risk_score": null,
    "video_risk_level": null,
    "video_message": "Internal server error during video detection",
    "audio_risk_score": null,
    "audio_risk_level": null,
    "audio_message": null
  }
}
```

---

## Integration Guide

### Recommended Client Logic

```
1. POST video to /detect/video
2. Check HTTP status code:
   - 401 → Invalid API key
   - 200 / 400 / 500 / 503 → Parse JSON response
3. Read response.unified_video_authenticity_score.status:
   - "success" → Read video_risk_* and audio_risk_* fields
   - "rejected" → Show video_message; prompt re-upload
   - "error" → Record the transaction and follow the HTTP-status retry policy below
4. Treat each modality as decision-support evidence:
   - "low" → Lower observed risk; not proof of authenticity
   - "medium" → Review with additional evidence
   - "high" → Escalate for human review; do not auto-reject from this result alone
```

### Retry Strategy

| Scenario | Recommended action |
|----------|-------------------|
| HTTP 500 / 503 | Retry up to 3 times after the initial request with exponential backoff (1s, 2s, 4s) |
| HTTP 429 (rate limit) | Wait for `Retry-After` header value, then retry |
| HTTP 400 | Do NOT retry — fix the input |
| HTTP 401 | Do NOT retry — check API key |

### Frame Sampling

By default, the pipeline samples **12 frames** uniformly across the video duration. Override with the `max_frames` query parameter (1–100) when you need deeper temporal coverage at the cost of latency.

### Idempotency

Each request generates a new `unique_trx_id`. Requests are not idempotent: re-submitting
the same video creates a separate transaction and may be billable again. Store the
transaction ID for audit and billing correlation.

---

## Error Handling Summary

| HTTP Code | Meaning | Client Action |
|-----------|---------|---------------|
| 200 | Analysis completed or face-policy rejection | Parse `status` field for outcome |
| 400 | Input validation failed | Fix input per `video_message`, do not retry |
| 401 | Unauthorized | Verify API key is valid and active |
| 403 | Forbidden | Endpoint not included in your plan |
| 429 | Rate limit exceeded | Wait per `Retry-After`, then retry |
| 500 | Internal server error | Retry with backoff (max 3 attempts) |
| 503 | Service unavailable (detectors not ready) | Retry with backoff (max 3 attempts) |

---

## Best Practices

### Recommended

- Use **MP4 (H.264)** for best compatibility and fastest processing
- Ensure a **single, clearly visible face** in most frames
- Keep file size reasonable for latency (1.5 GB max)
- Store `unique_trx_id` for dispute resolution and audit trails
- Use **`video_risk_level`** / **`audio_risk_level`** (not raw scores) for business decisions — band thresholds may be tuned

### Avoid

- Videos with **only multi-face or no-face frames** — use a single-subject clip
- **Non-video files** disguised with video extensions (security rejection)
- Retrying on HTTP 400 without fixing the input

---

## Support

| Channel | Details |
|---------|---------|
| Technical support | support@neuraldefend.com |

---

*Last updated: June 2026*
