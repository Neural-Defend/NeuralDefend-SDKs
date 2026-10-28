# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

### Security

- A caller-supplied `HTTPClient` no longer disables HTTPS, the host allowlist, or the
  no-redirect policy, and the SDK timeout is applied to the copy.
- Multipart filenames are stripped to one path segment and quotes, NUL, CR, and LF are
  percent-encoded so a filename cannot inject headers.
- Response bodies larger than 8 MiB are rejected, and an upload that grows past its
  checked size fails instead of streaming without a limit.

## [1.0.0] - 2026-08-24

### Added

- Initial public Go SDK with streaming multipart uploads for image and video detection.
- Typed `ImageResult` and `VideoResult` models with helper methods.
- Explicit error types for validation, protocol, network, timeout, HTTP, authentication,
  scope, rate limit, and server failures.
- Contract tests against shared JSON fixtures and optional staging smoke tests.
