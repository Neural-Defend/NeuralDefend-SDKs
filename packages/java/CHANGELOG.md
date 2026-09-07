# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

### Added

- Maven Central publishing via `com.vanniktech.maven.publish` and the protected
  `maven-central` release environment.

## [1.0.0] - 2026-08-26

### Added

- Initial public Java SDK with streaming multipart uploads for image and video detection.
- Typed `ImageResult` and `VideoResult` models with helper methods.
- Explicit exception types for validation, protocol, network, timeout, HTTP, authentication,
  scope, rate limit, and server failures.
- Contract tests against shared JSON fixtures and optional staging smoke tests.
