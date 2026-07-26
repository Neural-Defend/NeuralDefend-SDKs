# Unified Face Authenticity Score

### NeuroVerify API — AI-Powered Face Authenticity Detection

#### `POST`

**Endpoint**

```
https://deepscan.neuraldefend.com/detect/image
```

---

## Overview

The **Unified Face Authenticity Score** is NeuroVerify's flagship face verification endpoint. It runs a multi-layered AI detection pipeline — combining **Visual Safety Screening**, **Liveness Verification**, **Face Swap Detection**, **AI Generative Model Analysis**, and **AI Content Compliance** — and returns a single, opaque **risk score** indicating how likely the submitted image is AI-generated or manipulated.

**Key benefits:**

- Single API call replaces multiple detection endpoints
- Opaque scoring protects proprietary model IP
- Deterministic, consistent risk bands for easy integration
- Enterprise-grade security validation on every upload

---

## Endpoint Details

| Property | Value |
|----------|-------|
| **URL** | `/detect/image` |
| **Method** | `POST` |
| **Content-Type** | `multipart/form-data` |
| **Authentication** | API Key required (`x-api-key` header) |
| **Rate Limiting** | Per-key, contact sales for limits |
| **SLA** | 99.9% uptime (production tier) |

---

## Supported Image Formats

| Format | MIME Type | File Extensions | Notes |
|--------|-----------|-----------------|-------|
| JPEG | `image/jpeg` | `.jpg`, `.jpeg` | **Recommended** — best compatibility |
| PNG | `image/png` | `.png` | Supports transparency |
| BMP | `image/bmp` | `.bmp` | Windows bitmap format |
| TIFF | `image/tiff` | `.tiff`, `.tif` | High-quality format |
| WebP | `image/webp` | `.webp` | Modern compressed format |
| HEIC | `image/heic` | `.heic` | Auto-converted to JPEG internally |
| HEIF | `image/heif` | `.heif` | Auto-converted to JPEG internally |

---

## File & Image Requirements

| Constraint | Value | Notes |
|------------|-------|-------|
| **Maximum file size** | 10 MiB (10,485,760 bytes) | Files exceeding this are rejected |
| **Minimum resolution** | 224 × 224 px | Below this, analysis cannot run reliably |
| **Face count** | Exactly 1 | Multi-face or no-face images are rejected |
| **Orientation** | Auto-corrected | EXIF rotation (90°, 180°, 270°) handled |

---

## Request Format

### Headers

| Header | Required | Description |
|--------|----------|-------------|
| `x-api-key` | Yes | Your API key (provided at onboarding) |
| `Content-Type` | Automatic | Let the HTTP client generate `multipart/form-data` with its boundary; do not set this header manually |

### Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | File | Yes | Image file to analyze |

### Example Request — cURL

```bash
curl -X POST "https://deepscan.neuraldefend.com/detect/image" \
  -H "x-api-key: YOUR_API_KEY" \
  -F "file=@/path/to/image.jpg"
```

### Example Request — Python

```python
import requests

url = "https://deepscan.neuraldefend.com/detect/image"
headers = {"x-api-key": "YOUR_API_KEY"}

with open("image.jpg", "rb") as image:
    response = requests.post(url, headers=headers, files={"file": image})
data = response.json()

result = data["unified_face_authenticity_score"]
if result["status"] == "success":
    print(f"Risk Score: {result['risk_score']}")
    print(f"Risk Level: {result['risk_level']}")
else:
    print(f"Could not score: {result['message']}")
```

### Example Request — JavaScript (Node.js)

```javascript
const FormData = require("form-data");
const fs = require("fs");
const axios = require("axios");

const form = new FormData();
form.append("file", fs.createReadStream("image.jpg"));

async function main() {
  const response = await axios.post(
    "https://deepscan.neuraldefend.com/detect/image",
    form,
    {
      headers: {
        "x-api-key": "YOUR_API_KEY",
        ...form.getHeaders(),
      },
    }
  );

  const result = response.data.unified_face_authenticity_score;
  if (result.status === "success") {
    console.log(`Risk Score: ${result.risk_score}`);
  } else {
    console.log(`Could not score: ${result.message}`);
  }
}

main().catch(console.error);
```

---

## Response Format

All responses are wrapped in the **`unified_face_authenticity_score`** envelope:

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "...",
    "filename": "...",
    "content_type": "...",
    "status": "success | rejected | error",
    "status_code": 1,
    "billable": "Y | N",
    "risk_score": 3.2,
    "risk_level": "low | medium | high",
    "message": "...",
    "ai_threat_signals": [...]
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
| `risk_score` | float \| null | **0.1 – 10.0** (higher = higher AI/manipulation risk); `null` if rejected or error |
| `risk_level` | string \| null | `"low"`, `"medium"`, or `"high"`; `null` if not scored |
| `message` | string | Human-readable explanation of the result |
| `ai_threat_signals` | array \| absent | List of checks performed (present only on scored responses) |

### Risk Score Bands

| Risk Score | Risk Level | Message | Interpretation |
|------------|------------|---------|----------------|
| 0.1 – 3.9 | `low` | "Not likely to be Spoof or AI-generated" | Image appears authentic |
| 4.0 – 6.9 | `medium` | "Less likely to be Spoof or AI-generated" | Inconclusive — review recommended |
| 7.0 – 10.0 | `high` | "Likely to be Spoof detected" or "Likely to be AI-generated" | Spoof uses the spoof-specific message; faceswap and AI-generated use the AI-generated message |



## Status Codes

| `status_code` | `status` | HTTP | Billable | Meaning |
|---------------|----------|------|----------|---------|
| 1 | `success` | 200 | Yes | Analysis completed — `risk_score` present |
| 2 | `rejected` | 400 | No | Input validation failed (quality, format, security) — not billable |
| 5 | `error` | 500/503 | No | Server-side failure — retry with backoff |
| 6 | `rejected` | 200 | Yes | No face detected in image |
| 7 | `rejected` | 200 | Yes | Multiple faces detected — single face required |

---

## Response Scenarios

### Group 1 — Successful Analysis (scored)

`status: "success"` · `status_code: 1` · `risk_score` present · `ai_threat_signals` present

---

#### GENUINE — Low risk (all checks passed)

**HTTP Status:** `200 OK`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_c1r7n6oy69zhunjrkp0p",
    "filename": "selfie.jpg",
    "content_type": "image/jpeg",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "risk_score": 2.2,
    "risk_level": "low",
    "message": "Not likely to be Spoof or AI-generated",
    "ai_threat_signals": [
      "Visual Safety Screening",
      "Liveness Verification",
      "Face Swap Detection",
      "AI Generative Model Analysis",
      "AI Content Compliance"
    ]
  }
}
```

---

#### Medium risk band (inconclusive)

**HTTP Status:** `200 OK`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_med123abc456def789",
    "filename": "portrait.jpg",
    "content_type": "image/jpeg",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "risk_score": 5.5,
    "risk_level": "medium",
    "message": "Less likely to be Spoof or AI-generated",
    "ai_threat_signals": [
      "Visual Safety Screening",
      "Liveness Verification",
      "Face Swap Detection",
      "AI Generative Model Analysis",
      "AI Content Compliance"
    ]
  }
}
```

---

#### SPOOF detected — High risk (presentation attack)

**HTTP Status:** `200 OK`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_k8mdf2ab1xpqr7w3e9t6",
    "filename": "printed_photo.jpg",
    "content_type": "image/jpeg",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "risk_score": 8.7,
    "risk_level": "high",
    "message": "Likely to be Spoof detected",
    "ai_threat_signals": [
      "Visual Safety Screening",
      "Liveness Verification",
      "Face Swap Detection",
      "AI Generative Model Analysis",
      "AI Content Compliance"
    ]
  }
}
```

---

#### FACESWAP detected — High risk (face manipulation)

**HTTP Status:** `200 OK`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_m3nqw8yz5abcdef12gh4",
    "filename": "swapped.jpg",
    "content_type": "image/jpeg",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "risk_score": 8.4,
    "risk_level": "high",
    "message": "Likely to be AI-generated",
    "ai_threat_signals": [
      "Visual Safety Screening",
      "Liveness Verification",
      "Face Swap Detection",
      "AI Generative Model Analysis",
      "AI Content Compliance"
    ]
  }
}
```

---

#### AI_GENERATED detected — High risk (synthetic face)

**HTTP Status:** `200 OK`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_p9rst4uv6wxyz78klm01",
    "filename": "ai_generated.png",
    "content_type": "image/png",
    "status": "success",
    "status_code": 1,
    "billable": "Y",
    "risk_score": 8.4,
    "risk_level": "high",
    "message": "Likely to be AI-generated",
    "ai_threat_signals": [
      "Visual Safety Screening",
      "Liveness Verification",
      "Face Swap Detection",
      "AI Generative Model Analysis",
      "AI Content Compliance"
    ]
  }
}
```

---

### Group 2 — Rejected (not scored)

`status: "rejected"` · `risk_score: null` · `risk_level: null` · no `ai_threat_signals`

The image did not pass pre-analysis validation. No AI detection models were run.

---

#### No face detected

**HTTP Status:** `200 OK` · **Billable:** Yes

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_nf123abc456def789",
    "filename": "landscape.jpg",
    "content_type": "image/jpeg",
    "status": "rejected",
    "status_code": 6,
    "billable": "Y",
    "risk_score": null,
    "risk_level": null,
    "message": "No face detected in the image"
  }
}
```

---

#### Multiple faces detected

**HTTP Status:** `200 OK` · **Billable:** Yes

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_mf456def789abc012",
    "filename": "group_photo.jpg",
    "content_type": "image/jpeg",
    "status": "rejected",
    "status_code": 7,
    "billable": "Y",
    "risk_score": null,
    "risk_level": null,
    "message": "Multiple faces detected in the image"
  }
}
```

---

#### Image quality error (blur, brightness, contrast, dimensions)

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_qe789abc012def345",
    "filename": "blurry.jpg",
    "content_type": "image/jpeg",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "Image is too blurry for analysis"
  }
}
```

Other quality messages you may receive:

| Message | Cause |
|---------|-------|
| "Image is too blurry for analysis" | Image fails blur quality gate |
| "Image brightness is outside acceptable range" | Too dark or overexposed |
| "Image contrast is outside acceptable range" | Insufficient contrast |
| "Image dimensions are outside acceptable range" | Below minimum resolution |
| "Image dimensions exceed maximum limit" | Above maximum resolution |
| "Image quality is insufficient for analysis" | Generic quality failure |
| "Failed to process the image" | Image conversion or processing failed |

---

#### NSFW content detected

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_nsfw012abc345def67",
    "filename": "flagged.jpg",
    "content_type": "image/jpeg",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "Image contains inappropriate content"
  }
}
```

---

#### Security rejection

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_sec345def678abc901",
    "filename": "suspicious.jpg.php",
    "content_type": "application/octet-stream",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "File failed security validation"
  }
}
```

---

#### Unsupported file format

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_fmt678abc901def234",
    "filename": "document.pdf",
    "content_type": "application/pdf",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "Unsupported file format"
  }
}
```

---

#### File too large

**HTTP Status:** `400 Bad Request` · **Billable:** No

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_big901def234abc567",
    "filename": "huge_image.jpg",
    "content_type": "image/jpeg",
    "status": "rejected",
    "status_code": 2,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "File exceeds maximum size limit"
  }
}
```

---

### Group 3 — Server Errors

`status: "error"` · `status_code: 5` · not billable

A server-side issue prevented analysis. Retry with exponential backoff.

---

#### Service unavailable (503)

**HTTP Status:** `503 Service Unavailable`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_503abc123def456789",
    "filename": "photo.jpg",
    "content_type": "image/jpeg",
    "status": "error",
    "status_code": 5,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "Internal server error during unified detection"
  }
}
```

---

#### Internal server error (500)

**HTTP Status:** `500 Internal Server Error`

```json
{
  "unified_face_authenticity_score": {
    "unique_trx_id": "trx_500def789abc012345",
    "filename": "photo.jpg",
    "content_type": "image/jpeg",
    "status": "error",
    "status_code": 5,
    "billable": "N",
    "risk_score": null,
    "risk_level": null,
    "message": "Internal server error during unified detection"
  }
}
```

---

## Integration Guide

### Recommended Client Logic

```
1. POST image to /detect/image
2. Check HTTP status code:
   - 401 → Invalid API key
   - 200/400/500/503 → Parse JSON response
3. Read response.unified_face_authenticity_score.status:
   - "success" → Read risk_score, risk_level, message
   - "rejected" → Show message to user, prompt re-upload
   - "error" → Record the transaction and follow the HTTP-status retry policy below
4. Treat risk_level as decision-support evidence:
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

### Idempotency

Each request generates a unique `unique_trx_id`. Requests are **not** idempotent — re-submitting the same image produces a new transaction. Store the `unique_trx_id` if you need audit trail correlation.

---

## Best Practices

### Recommended

- Use **JPEG format** for best compatibility and fastest processing
- Ensure the subject's face is **clearly visible, frontal, and well-lit**
- Keep file size **under 5 MB** for optimal latency (10 MB max)
- Store `unique_trx_id` for dispute resolution and audit trails
- Implement proper error handling for all three response statuses
- Use `risk_level` as one decision-support signal; never use it as the sole basis for acceptance or rejection

### Avoid

- Submitting images with **multiple faces** — crop to a single subject first
- Sending **extremely low resolution** images (below 224×224)
- Images with **poor lighting** (overexposed, underexposed, or washed out)
- **Blurry or out-of-focus** captures
- **Non-image files** disguised with image extensions (security rejection)
- Retrying on HTTP 400 without fixing the input

---

## Error Handling Summary

| HTTP Code | Meaning | Client Action |
|-----------|---------|---------------|
| 200 | Analysis completed or face policy rejection | Parse `status` field for outcome |
| 400 | Input validation failed | Fix input per `message`, do not retry |
| 401 | Unauthorized | Verify API key is valid and active |
| 403 | Forbidden | Endpoint not included in your plan |
| 429 | Rate limit exceeded | Wait per `Retry-After`, then retry |
| 500 | Internal server error | Retry with backoff (max 3 attempts) |
| 503 | Service unavailable | Retry with backoff (max 3 attempts) |

---

## SDKs & Libraries

| Integration | Install | Documentation | Registry |
|-------------|---------|---------------|----------|
| Python 3.9+ | `pip install neuraldefend` | [Python SDK guide](../../packages/python/README.md) | [`neuraldefend` on PyPI](https://pypi.org/project/neuraldefend/) |
| Node.js 22+ / browser | `npm install @neuraldefend/sdk` | [TypeScript SDK guide](../../packages/typescript/README.md) | [`@neuraldefend/sdk` on npm](https://www.npmjs.com/package/@neuraldefend/sdk) |
| MCP (Python 3.10+) | `pip install neuraldefend-mcp` | [MCP server guide](../../packages/mcp/README.md) | [`neuraldefend-mcp` on PyPI](https://pypi.org/project/neuraldefend-mcp/) |

The SDK guides provide typed image and video examples and explain normalized outcomes,
retry behavior, and credential handling.

---

## Support

| Channel | Details |
|---------|---------|
| Technical support | support@neuraldefend.com |

---

*Last updated: July 2026*
