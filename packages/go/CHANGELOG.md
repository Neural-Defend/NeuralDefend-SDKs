# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

## [1.0.0] - 2026-08-24

### Added

- Initial public Go SDK with streaming multipart uploads for image and video detection.
- Typed `ImageResult` and `VideoResult` models with helper methods.
- Explicit error types for validation, protocol, network, timeout, HTTP, authentication,
  scope, rate limit, and server failures.
- Contract tests against shared JSON fixtures and optional staging smoke tests.
