# ADR 0010: Swift SDK for iOS and Apple platforms with a private generated contract

- Status: Accepted
- Date: 2026-10-14

## Context

iOS, iPadOS, macOS, Mac Catalyst, and visionOS apps, and Swift servers, need the same
contract semantics as the Python, TypeScript, Go, and Dart SDKs (ADR-0004, ADR-0007,
ADR-0008): streaming multipart uploads, bounded retries, normalized results, and
explicit errors.

Several Swift-specific constraints shape the design:

- OpenAPI Generator 7.14.0 `swift5` output is Swift 5 language mode code built on
  global mutable configuration (`OpenAPIClientAPI`), which does not compile cleanly under
  Swift 6 strict concurrency. Its uploads build the whole multipart body in memory.
- The `swift5` generator does not emit the `x-api-key` header name in code; it appears
  only in a generated doc comment (`x-api-key (HEADER)`).
- Swift Package Manager resolves packages from a Git repository whose root contains
  `Package.swift`, using plain semantic version tags (`1.2.3`). Prefixed tags such as
  `swift-v1.2.3` are not seen as versions.
- `URLSession` follows redirects by default, and on Linux, swift-corelibs-foundation
  truncates a fractional `timeoutIntervalForRequest` to whole seconds.
- App binaries are distributed to end users, so any credential compiled into them is
  extractable.

## Decision

Add the Swift package `NeuralDefend` with sources in `packages/swift/`:

- Generate the contract with the pinned OpenAPI Generator image and `generator/swift.json`
  into `packages/swift/generated/core/`. It is not a target in `Package.swift`, so
  consumers cannot import it, and it is used only for drift detection by
  `scripts/check_generated.py`.
- Because the generator omits the header name from code, `scripts/generate.py` checks the
  Swift output for the `x-api-key (HEADER)` doc comment. The facade's request-shape tests
  assert the `x-api-key` header instead.
- Put `Package.swift` at the repository root (tools version 6.0, Swift 6 language mode)
  with one library product, `NeuralDefend`, so `.package(url:from:)` works. Release with
  plain `X.Y.Z` tags through `release-swift.yml`, which verifies the tag and creates a
  GitHub Release with `gh`. A tag ruleset that blocks deleting and moving version tags is
  the real release control, because SwiftPM consumers resolve tags directly.
- Implement a hand-written facade on `URLSession` with no dependencies:
  - `MediaInput.file`, `.data`, and (where PhotosUI exists) `init(photosPickerItem:)`.
    The multipart body is written to a temporary file and sent with
    `uploadTask(with:fromFile:)`, so large videos stream from disk on every platform.
  - retries only for 429, 500, and 503 with the same backoff as the other SDKs, a
    default `retryAfterCap` of 60 seconds, and redirects disabled through the session
    delegate;
  - a 120-second per-attempt timeout enforced by the SDK's own timer, with the
    `URLSession` timeout set slightly longer as a backstop;
  - results normalized to `ResultStatus.success`, `rejected`, or `unknown`, preserving
    the wire values, matching the forward-compatibility model of the other SDKs; and
  - one `NeuroVerifyError` enum whose cases match the other SDKs' error classes.
- Read `NEURALDEFEND_API_KEY` and `NEURALDEFEND_BASE_URL` only through the explicit
  `fromEnvironment` initializer.
  Documentation recommends calling NeuroVerify from a backend and treats direct app calls
  as requiring a credential Neural Defend has approved for client use.
- Test the facade against the shared fixtures with swift-testing and a local socket HTTP
  server, on Linux (oldest supported toolchain 6.0.3 and the latest release) and on macOS
  with both `swift test` and `xcodebuild test` on an iOS Simulator. A SwiftUI example app
  is tested with a mocked `URLProtocol`.
- The repository's Actions policy allows only approved third-party actions, so Linux CI
  installs Swift with `scripts/setup_swift_toolchain.py`, which downloads swift.org
  archives and verifies their GPG signatures with the Swift release key checked in under
  `scripts/keys/`, accepting only pinned primary-key fingerprints. macOS CI uses the Xcode
  installed on the runner.
- Do not publish to CocoaPods; its trunk is read-only. Swift Package Index is the
  discovery channel, configured by `.spi.yml`.

## Consequences

Swift consumers get one dependency-free package for every Apple platform and Linux, with
large uploads streamed from disk. The repository root now contains `Package.swift`, so
SwiftPM fetches the whole repository; this is acceptable because it is small, and moving
the package later would break existing consumers. Plain version tags are reserved for the
Swift package, so other SDKs must keep prefixed tags. The generated core detects contract
changes but has no runtime role, so behavior must be covered by facade tests. Generation
now covers five languages; spec or generator changes must regenerate all private cores
and add equivalent Swift tests. Published tags must never move, so release mistakes
require a new version.
