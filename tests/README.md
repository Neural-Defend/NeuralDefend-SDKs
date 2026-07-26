# Contract fixture corpus

This directory contains language-neutral HTTP response fixtures for `POST /detect/image`
and `POST /detect/video`. The corpus is checked in and never scraped from documentation
at test runtime.

## Fixture schema

Every fixture is a deterministic UTF-8 JSON document with:

- `case_id`: stable, globally unique case name.
- `endpoint`: `/detect/image` or `/detect/video`.
- `http_status`: HTTP response status.
- `headers`: lowercase response-header names and string values.
- `provenance`: `documented` with source and section, or `synthetic` with its derivation.
- `body_kind`: `json` for a JSON value or `raw` for deliberately malformed JSON text.
- `body`: the response body. Documented JSON bodies preserve the documented field order,
  fields, and values. Synthetic bodies are deterministic and contain no credentials or media.

Consumers should parse the fixture document first. For `body_kind: "json"`, serialize or
consume `body` as JSON. For `body_kind: "raw"`, pass the string directly to the SDK's
response parser.

## Coverage

- 12 documented image fixtures: low/medium/high scores; no face; multiple faces; blur;
  NSFW; security; unsupported format; too large; HTTP 500; HTTP 503.
- 13 documented video fixtures: both modalities low; video-high/audio-low;
  video-low/audio-high; both high; medium without audio; silent video; no face;
  multi-face; unsupported format; too large; security; HTTP 500; HTTP 503.
- 6 synthetic transport fixtures: HTTP 401, 403, and 429 for both endpoints. Rate-limit
  fixtures include `Retry-After` and all documented `X-RateLimit-*` headers.
- 12 synthetic robustness fixtures: unknown extra field, status code, status, and risk
  level plus missing-envelope and malformed-JSON cases for both endpoints.

Total: **43 fixtures**.

## Source inconsistencies

1. Both client guides say all responses use the endpoint envelope, while `spec/public.yaml`
   defines bare `{"detail": "..."}` `ApiError` bodies for HTTP 401, 403, and 429.
2. At fixture extraction time, the video guide listed `max_frames` and `sample_rate` in
   the request body table; the OpenAPI contract declares both as query parameters. The
   copy in this repository has since been corrected to match the contract.
3. At fixture extraction time, the video guide's field reference described
   `audio_message` as a string, but rejection examples set it to `null`; the OpenAPI
   schema marks it nullable. The copy in this repository has since been corrected.
4. The video guide says HTTP 503 has the same JSON body as HTTP 500, but its documented
   examples use different `unique_trx_id` values. Both examples are preserved independently.
5. The sources provide no exact endpoint-specific JSON examples for HTTP 401, 403, or 429.
   Those fixtures therefore use the `ApiError` schema and are marked synthetic.

## Validation

All fixture files must parse as JSON and contain the seven fields listed above. A
`body_kind: "json"` body must be an object. A `body_kind: "raw"` body must be a string
that intentionally fails JSON parsing. Case IDs must be unique and all paths must remain
under `tests/fixtures`.
