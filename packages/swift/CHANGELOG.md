# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning. Swift
Package Manager releases use plain tags such as `1.0.0`.

## [Unreleased]

### Security

- Response bodies larger than 8 MiB are rejected before JSON parsing.

## [1.0.0] - 2026-10-14

### Added

- Initial Swift SDK for image and video detection on iOS 15+, macOS 12+, Mac Catalyst,
  visionOS, and Linux, with Swift 6 strict concurrency and no dependencies.
- `NeuroVerifyClient` with `detectImage` and `detectVideo` (`maxFrames`, `sampleRate`),
  production, `staging`, and `fromEnvironment` initializers, and upload progress.
- `MediaInput.file`, `MediaInput.data`, and `MediaInput(photosPickerItem:)` inputs, streamed
  from disk through `URLSession` upload tasks.
- `NeuroVerifyError` cases matching the other SDKs: validation, HTTP, authentication,
  scope, rate limit, server, protocol, timeout, network, and cancelled.
- Retries for HTTP 429, 500, and 503 (up to 3, with 1, 2, and 4 second backoff and jitter,
  and `Retry-After` capped at 60 seconds), a 120-second per-attempt timeout, task
  cancellation, no redirect following, and API key redaction.
- A SwiftUI example with tests that use a mocked `URLProtocol`.
