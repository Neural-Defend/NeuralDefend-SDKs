# Changelog

All notable changes to this package follow [Keep a Changelog](https://keepachangelog.com/)
and Semantic Versioning.

## [Unreleased]

## [1.0.2] - 2026-07-27

### Changed

- Expanded the published npm guide with complete Node.js and browser onboarding, explicit
  API-key handling, method documentation, normalized response examples, retry and billing
  guidance, privacy controls, and troubleshooting.

## [1.0.1] - 2026-07-27

### Changed

- `JSON.stringify(result)` now emits only normalized public fields; the frozen
  `result.raw` diagnostic payload is still directly accessible but excluded from
  default serialization.
- `originalStatus` is no longer present on success or rejected results; it
  remains on forward-compatible `unknown` results where it is part of the public
  contract.
- Multipart uploads now carry deterministic MIME types derived from the filename
  extension (e.g. `.jpg` -> `image/jpeg`) instead of relying on `openAsBlob`
  platform detection.
- Added `.heif` as a recognized image extension.
- Prefer canonical MIME metadata for recognized extensions even when caller-supplied
  `Blob.type` metadata conflicts, while preserving explicit types for unknown extensions.
- Set the supported Node.js baseline to maintained Node 22 and newer releases.
- Reject non-Neural Defend API origins unless `allowCustomBaseUrl: true` is explicitly
  set, and fail rather than follow HTTP redirects carrying credentials or media.
- Snapshot Node.js path uploads through one validated file handle to prevent path
  replacement and size-check races.
- Reject response scores outside `0.1` through `10.0`, release Node.js streams after
  validation failures, and accept valid cross-realm browser `Blob`/`File` inputs.

### Fixed

- Corrected the trusted-publishing workflow to treat the built tarball as a local file.
  Version `1.0.0` was not uploaded to npm; `1.0.1` is the first usable registry release.

## [1.0.0] - 2026-07-26

### Added

- Initial Node.js and browser SDK facade for image and video authenticity detection.
- Typed success, rejection, and forward-compatible unknown outcomes.
- Local validation, cancellation, timeout handling, and bounded retries.
- Dual ESM/CommonJS package output with browser-specific conditional exports.

Built against public API specification 1.0.0 from source commit
`494fc8c88585e0920efe54b41f3f8d355025c475`.

[Unreleased]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/ts-v1.0.2...HEAD
[1.0.2]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/ts-v1.0.1...ts-v1.0.2
[1.0.1]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/ts-v1.0.0...ts-v1.0.1
[1.0.0]: https://github.com/Neural-Defend/NeuralDefend-SDKs/releases/tag/ts-v1.0.0
