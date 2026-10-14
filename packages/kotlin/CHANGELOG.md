# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

## [1.0.0] - 2026-10-14

### Added

- Initial Kotlin, Java, and Android SDK, published to Maven Central as
  `com.neuraldefend:neuraldefend` (JVM, Java 8 or newer) and
  `com.neuraldefend:neuraldefend-android` (Android 5.0, API 21, or newer).
- Coroutine `detectImage` and `detectVideo` functions, and a `NeuroVerifyCall` API with
  `execute`, `enqueue`, and `cancel` for Java and callback-based code.
- `MediaInput.file`, `MediaInput.bytes`, replayable `MediaInput.stream`, and single-use
  `MediaInput.singleUseStream` inputs with streaming multipart uploads, plus
  `MediaInputs.fromUri` for photo-picker and camera content `Uri`s.
- Typed `ImageResult` and `VideoResult` models with normalized `ResultStatus`, recognized
  `RiskLevel` bands, and preserved original values for forward compatibility.
- A sealed `NeuroVerifyError` hierarchy for validation, protocol, network, timeout, abort,
  HTTP, authentication, scope, rate limit, and server failures.
- Bounded retries for HTTP 429, 500, and 503, `Retry-After` support, per-attempt
  timeouts, coroutine cancellation, upload progress callbacks, and support for a shared
  `OkHttpClient`.
- Contract tests against the shared JSON fixtures, loopback socket tests, Robolectric and
  emulator tests, optional staging smoke tests, and a Jetpack Compose example app.
