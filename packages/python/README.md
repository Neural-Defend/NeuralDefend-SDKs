# NeuralDefend Python SDK

Typed Python 3.9+ client for the NeuroVerify image and video authenticity API.

## Install

```bash
pip install neuraldefend
```

Set `NEURALDEFEND_API_KEY`, then use the synchronous client:

```python
import json

from neuraldefend import NeuroVerifyClient

with NeuroVerifyClient() as client:
    result = client.detect_image("selfie.jpg")

print(json.dumps(result.to_dict(), indent=2))

if result.scored:
    print(result.risk_level, result.risk_score)
elif result.rejected:
    print("Could not score:", result.message)
```

Business rejections are normal results, including HTTP 400 validation rejections. Use
`status` and `risk_level` for decisions. Do not infer authenticity from HTTP 200 or define
business rules from numeric score thresholds. `billable` is authoritative for the
transaction; a face-policy rejection can still be billable.

`result.to_dict()` returns only stable normalized fields and derived convenience flags as
JSON-serializable data. The sanitized immutable wire payload remains available separately
as `result.raw` for explicit diagnostics and is never serialized automatically. Raw
diagnostics are unstable and may contain filenames or future personal/customer fields;
do not log or persist them without appropriate access and retention controls.

Video analysis returns independent modalities:

```python
with NeuroVerifyClient() as client:
    result = client.detect_video("clip.mp4", max_frames=24)

print(result.video_risk_level, result.audio_risk_level)
print(result.overall_risk_score)  # client-side convenience, not an API field
```

Paths, `bytes`, and binary file-like objects are accepted. `filename=` is required for
bytes and nameless streams so the SDK can send deterministic media metadata. Caller-owned
streams are never closed. Seekable
streams are rewound to the beginning for safe retries; non-seekable streams require
`max_retries=0`.

Supported image extensions are `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`,
`.webp`, `.heic`, and `.heif` (10 MiB maximum). Supported video extensions are `.mp4`,
`.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`, `.ogg`, and `.ogv`
(1,500,000,000-byte maximum). Known extensions use deterministic MIME types; unknown
extensions are warned about and sent as `application/octet-stream`.

## Configuration

Explicit arguments take precedence over environment variables:

- `api_key` then `NEURALDEFEND_API_KEY`
- `base_url` then `NEURALDEFEND_BASE_URL` then production
- `allow_custom_base_url=False`
- `timeout=120`
- `max_retries=3`

`NeuroVerifyClient.staging()` always selects staging, regardless of
`NEURALDEFEND_BASE_URL`. Production and staging use TLS. A non-TLS URL is accepted only
when an injected transport is supplied for isolated tests. Non-Neural Defend origins are
rejected by default. If a trusted private deployment requires one, set
`allow_custom_base_url=True` explicitly; that origin receives the API key and uploaded
media. Redirects are never followed.

Only HTTP 429, 500, and 503 are retried. Network errors, timeouts, and other HTTP statuses
are not retried because request billability may be ambiguous. `max_retries=3` means up to
four total HTTP attempts. Every accepted attempt receives a new transaction ID and may
have separate billing implications.

Upload media only with the data owner's authorization and an appropriate legal basis.
Media can contain biometric personal data; apply your organization's retention, deletion,
residency, logging, and access-control requirements.

## Errors

All SDK exceptions derive from `NeuroVerifyError`:

- `ValidationError` for local validation
- `AuthenticationError` for HTTP 401
- `ScopeError` for HTTP 403
- `RateLimitError` for final HTTP 429
- `ServerError` for server error envelopes and final HTTP 500/503
- `TimeoutError` and `NetworkError` for transport failures
- `ProtocolError` for malformed API responses
- `HttpError` for unclassified HTTP responses

Errors carry `status_code`, `detail`, and `request_id` when available. Rate-limit errors
also carry the documented rate-limit header values.

## Architecture decision note

OpenAPI Generator 7.14.0 buffers multipart files in memory in its Python transport. That
is unsafe for the API's large video limit. The package therefore ships the generated
`_core` privately for contract tracking but deliberately does not use it at runtime.
The stable facade uses a hand-written `httpx` multipart transport so paths and streams
remain streaming. Responses are decoded from raw JSON rather than generated models so
additive fields and future enum values do not break installed clients.
