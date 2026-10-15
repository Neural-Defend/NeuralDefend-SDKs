# ADR 0011: Kotlin, Java, and Android SDK on OkHttp with a private generated contract

- Status: Accepted
- Date: 2026-10-14

## Context

Android apps and JVM backends (Kotlin and Java) need the same contract semantics as the
Python, TypeScript, Go, and Dart SDKs (ADR-0004, ADR-0007, ADR-0008): streaming multipart
uploads, bounded retries, normalized results, and explicit errors.

Several JVM- and Android-specific constraints shape the design:

- OpenAPI Generator 7.14.0 `kotlin` output (`jvm-okhttp4`, `kotlinx_serialization`) is a
  full Gradle project with its own infrastructure classes, reflection-free serializers that
  require the serialization compiler plugin, and a public API that does not match the other
  SDKs. Shipping it would add API surface we would have to keep compatible.
- Android media arrives as content `Uri`s from the photo picker and camera, not as files.
  Reading them needs `android.content.ContentResolver`, which a plain JVM jar cannot use.
- Android apps routinely pin OkHttp, kotlinx-coroutines, and kotlinx-serialization to
  whatever their other libraries need. A client that forces newer versions causes
  dependency conflicts.
- Many enterprise JVM services still run Java 8 or 11.
- Android binaries are distributed to end users, so any credential compiled into them is
  extractable.
- Maven Central requires sources and javadoc jars, a complete POM, checksums, and GPG
  signatures for every file, and namespace ownership verified through DNS.

## Decision

Add `packages/kotlin`, a Gradle build that publishes two artifacts to Maven Central:

- `com.neuraldefend:neuraldefend`: a pure JVM jar (package `com.neuraldefend`) built for
  Java 8 bytecode, with `api` dependencies on OkHttp 4.12 and kotlinx-coroutines 1.9 and an
  `implementation` dependency on kotlinx-serialization-json 1.7.3 for its JSON tree. These
  are lower bounds; CI also tests the newest stable releases.
- `com.neuraldefend:neuraldefend-android`: an AAR (minSdk 21, package
  `com.neuraldefend.android`) that adds only `MediaInputs.fromUri` and the `INTERNET`
  permission.

The design follows the other SDKs where the platform allows:

- Generate the contract with the pinned OpenAPI Generator image and `generator/kotlin.json`
  into `packages/kotlin/generated/core/`, outside every Gradle source set. It is never
  compiled or shipped and is used only by `scripts/check_generated.py` for drift detection.
  Unlike the Dart generator, the Kotlin generator emits the `x-api-key` header, so
  `scripts/generate.py` checks for it directly.
- Implement a hand-written facade with the same public names (`NeuroVerifyClient`,
  `detectImage`, `detectVideo`, `ImageResult`, `VideoResult`, and the shared error names).
  Errors form a sealed `NeuroVerifyError` hierarchy, so Kotlin `when` expressions are
  exhaustive.
- Expose coroutine `suspend` functions for Kotlin. Coroutine cancellation surfaces as the
  standard `CancellationException`. Java callers get `NeuroVerifyCall` with `execute`,
  `enqueue`, and `cancel`, modelled on OkHttp's `Call`, where cancelling raises
  `AbortError`.
- Derive the transport from a caller-supplied or SDK-owned `OkHttpClient`, disabling
  redirects and OkHttp's transport retries and applying the per-attempt timeout to connect,
  write, read, and the whole call. Retry rules, `Retry-After` handling, response size
  limits, and redaction match the other SDKs.
- Stream uploads through a custom `RequestBody` that enforces the declared length and
  reopens replayable inputs (files, byte arrays, `StreamSupplier`s, and content `Uri`s) for
  each attempt.
- Read `NEURALDEFEND_API_KEY` and `NEURALDEFEND_BASE_URL` only on non-Android JVMs. Android
  apps must pass an explicit key, and the documentation recommends calling NeuroVerify from
  a backend.
- Track the public ABI with the Kotlin Gradle plugin's built-in ABI validation
  (`neuraldefend/api/neuraldefend.api`) and enable `explicitApi()` and warnings as errors.
- Compile with Kotlin 2.4 but set `languageVersion` and `apiVersion` to 2.2 and depend on
  kotlin-stdlib 2.2.0, so Kotlin consumers need Kotlin 2.1 or newer. Language version 2.0
  is deprecated in Kotlin 2.4, which fails a warnings-as-errors build. Java consumers are
  unaffected.
- Test the facade against the shared fixtures with a loopback HTTP server (not a mock
  library), so the real OkHttp 4.12 transport is exercised, on Java 8, 11, 17, 21, and 25.
  The Android helper runs under Robolectric. A Compose example app shares its screen tests
  between Robolectric and API 23 and API 36 emulators, and its minified release build
  checks that the SDK needs no R8 rules.
- Release with tag `kotlin-vX.Y.Z` through `release-kotlin.yml`. A build job tests and
  verifies an unsigned bundle; the publish job, in the protected `maven-central`
  environment, signs it with the release GPG key, verifies it with
  `scripts/publish_maven_central.py`, attests it, and uploads it through the Central Portal
  API. The repository allows only approved third-party actions, so CI uses
  `actions/setup-java`, the committed Gradle wrapper (checked against gradle.org's
  published checksums), and shell scripts for the emulator and the upload instead of
  community actions.

## Consequences

JVM servers, Java code, and Android apps share one tested implementation with no runtime
dependency beyond OkHttp, coroutines, and serialization, and apps keep control of those
versions. Generation now covers five languages; spec or generator changes must regenerate
all private cores and add equivalent Kotlin tests. Public API changes show up as diffs in
the ABI dump and need `./gradlew updateKotlinAbi`. Android builds need compileSdk 37 and a
Java 21 toolchain to build, but not to consume. Maven Central releases cannot be deleted or
overwritten, so release mistakes require a new version.
