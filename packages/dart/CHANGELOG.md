# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

## [1.0.0] - 2026-10-05

### Added

- Initial Dart and Flutter SDK for image and video detection on Android, iOS, macOS,
  Windows, Linux, web (dart2js and dart2wasm), and the Dart VM.
- `MediaInput.file`, `MediaInput.bytes`, `MediaInput.openRead` (for example
  `XFile.openRead` from `image_picker`), and single-use `MediaInput.stream` inputs, with
  streaming multipart uploads.
- Typed `ImageResult` and `VideoResult` models with normalized `ResultStatus`, recognized
  `RiskLevel` bands, and preserved original values for forward compatibility.
- Explicit error types for validation, protocol, network, timeout, abort, HTTP,
  authentication, scope, rate limit, and server failures.
- Bounded retries for HTTP 429, 500, and 503, `Retry-After` support, per-attempt
  timeouts, `abortTrigger` cancellation, and upload progress callbacks.
- Contract tests against the shared JSON fixtures, browser tests, optional staging smoke
  tests, and a Flutter example app.
