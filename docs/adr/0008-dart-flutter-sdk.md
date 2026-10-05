# ADR 0008: Dart and Flutter SDK with a private generated contract

- Status: Accepted
- Date: 2026-10-05

## Context

Customers building Flutter mobile, desktop, and web apps, and Dart backends, need the same
contract semantics as the Python, TypeScript, and Go SDKs (ADR-0004, ADR-0007):
streaming multipart uploads, bounded retries, normalized results, and explicit errors.

Several Dart-specific constraints shape the design:

- OpenAPI Generator 7.14.0 `dart` output imports `dart:io`, `package:intl`,
  `package:collection`, and `package:meta`. Shipping it would make the package
  incompatible with web and add dependencies the facade does not need.
- The `dart` generator does not apply the spec's `x-api-key` security scheme to the
  operations. It emits the generic `ApiKeyAuth` class but not the header name.
- `package:cross_file` (the `XFile` type returned by `image_picker` and `file_picker`)
  0.4.x depends on the Flutter SDK, so depending on it would exclude pure Dart servers.
- Flutter and web binaries are distributed to end users, so any credential compiled into
  them is extractable.

## Decision

Add `packages/dart` as the public pub.dev package `neuraldefend`:

- Generate the contract with the pinned OpenAPI Generator image and `generator/dart.json`
  into `packages/dart/generated/core/`, **outside `lib/`**. It is not importable by
  consumers, is excluded from analysis and from the published archive (`.pubignore`), and
  is used only for drift detection by `scripts/check_generated.py`.
- Because the generator omits the header name, `scripts/generate.py` checks the Dart
  output for `ApiKeyAuth` rather than `x-api-key`. The facade's request-shape tests
  assert the `x-api-key` header instead.
- Implement a hand-written facade on `package:http` (`AbortableMultipartRequest`) with
  runtime dependencies limited to `http` and `http_parser`:
  - `MediaInput.file`, `.bytes`, `.openRead`, and `.stream`. `openRead` accepts any
    `Stream<List<int>> Function()`, including `XFile.openRead`, which gives Flutter
    pickers a replayable, streaming input without depending on `cross_file`;
  - retries only for 429, 500, and 503 with the same backoff as the other SDKs, a
    default `retryAfterCap` of 60 seconds, and redirects disabled;
  - results normalized to `ResultStatus.success`, `rejected`, or `unknown`, preserving
    the wire values in `originalStatus` and `original*RiskLevel`, matching the TypeScript
    SDK's forward-compatibility model; and
  - errors with the same class names as the other SDKs, implementing `Exception`.
- Select platform behavior with conditional imports on `dart.library.io`. The Dart VM
  reads `NEURALDEFEND_API_KEY` and `NEURALDEFEND_BASE_URL`; Flutter apps (detected with
  `dart.library.ui`) and web builds never read the environment and require an explicit
  `apiKey`. Documentation recommends calling NeuroVerify from a backend and treats direct
  client-app calls as requiring a credential Neural Defend has approved for client use.
- Test the facade against the shared fixtures on the Dart VM, in Chrome with dart2js and
  dart2wasm, and with a Flutter example app whose widget tests inject the HTTP client.
- Release with tag `dart-vX.Y.Z` through `release-dart.yml`, publishing to pub.dev with
  GitHub OIDC automated publishing from the protected `pub-dev` environment.

## Consequences

Flutter and Dart consumers get one package for every platform with no Flutter dependency,
so it also works in Dart servers and CLIs. Large uploads stream on native platforms; on
web, `package:http` buffers the request body. The generated core detects contract changes
but has no runtime role, so behavior must be covered by facade tests. Generation now
covers four languages; spec or generator changes must regenerate all private cores and add
equivalent Dart tests. pub.dev versions cannot be deleted, so release mistakes require a
new version or retraction.
