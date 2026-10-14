# NeuralDefend Swift SDK

Official Swift client for the **NeuroVerify Detection API**, which evaluates images and
videos for signs of AI generation, manipulation, spoofing, and related authenticity risks.

- `async`/`await` API with Swift 6 strict concurrency; every public type is `Sendable`.
- No dependencies beyond Foundation.
- Uploads stream from disk with `URLSession`, so a 1.5 GB video is never loaded into memory.
- Bounded retries, a per-attempt timeout, task cancellation, and no redirect following.
- Results normalized to `success`, `rejected`, or `unknown`, with the wire values preserved.
- Works on iOS, iPadOS, macOS, Mac Catalyst, visionOS, and Linux.

## Requirements

| | Minimum |
|---|---|
| Swift | 6.0 (Xcode 16.0 or later) |
| iOS, iPadOS, Mac Catalyst | 15.0 |
| macOS | 12.0 |
| visionOS | 1.0 |
| Linux | Swift 6.0 toolchain (uses `FoundationNetworking`) |

`MediaInput(photosPickerItem:)` needs iOS 16, macOS 13, or visionOS 1. tvOS and watchOS are
not supported.

## Installation

The package lives in the [NeuralDefend-SDKs](https://github.com/Neural-Defend/NeuralDefend-SDKs)
repository and is released with plain version tags such as `1.0.0`.

**Xcode:** choose **File > Add Package Dependencies…**, enter
`https://github.com/Neural-Defend/NeuralDefend-SDKs`, choose **Up to Next Major Version** from
`1.0.0`, and add the `NeuralDefend` library to your app target.

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/Neural-Defend/NeuralDefend-SDKs", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "NeuralDefend", package: "NeuralDefend-SDKs")
    ])
]
```

CocoaPods and Carthage are not supported.

## Get an API key

NeuroVerify API keys are issued by Neural Defend after customer onboarding. Visit
[neuraldefend.com](https://neuraldefend.com/) and choose **Book a Demo**, or contact
[support@neuraldefend.com](mailto:support@neuraldefend.com) for existing accounts and
staging keys.

> **Never ship a long-lived production API key inside an iOS or macOS app.** Anyone who
> installs the app can extract it. Upload media to your authenticated backend and call
> NeuroVerify from there, or use a client credential that Neural Defend has approved for your
> tenant. Use a staging key during development.

## Quick start

```swift
import NeuralDefend

let client = try NeuroVerifyClient(apiKey: apiKey)

let image = try await client.detectImage(.file(photoURL))
switch image.status {
case .success:
    print("Risk \(image.riskLevel!) (score \(image.riskScore!))")
case .rejected:
    print("Not analyzed: \(image.message)")   // for example, no face found
case .unknown:
    print("Unrecognized status \(image.originalStatus); upgrade the SDK")
}

let video = try await client.detectVideo(.file(clipURL), maxFrames: 12)
print(video.videoRiskLevel as Any, video.hasAudio ? video.audioRiskLevel as Any : "no audio")
```

On a server or in a command-line tool, `NeuroVerifyClient.fromEnvironment()` reads
`NEURALDEFEND_API_KEY` (and `NEURALDEFEND_BASE_URL` when set). The other initializers never
read the environment.

### SwiftUI and PhotosPicker

```swift
import NeuralDefend
import PhotosUI
import SwiftUI

struct VerifyView: View {
    let client: NeuroVerifyClient
    @State private var item: PhotosPickerItem?
    @State private var text = ""

    var body: some View {
        VStack {
            PhotosPicker("Choose a photo", selection: $item, matching: .images)
            Text(text)
        }
        .onChange(of: item) { _, item in
            guard let item else { return }
            Task {
                do {
                    let media = try await MediaInput(photosPickerItem: item)
                    let result = try await client.detectImage(media)
                    text = result.isScored ? "Risk: \(result.riskLevel!.rawValue)" : result.message
                } catch let error as NeuroVerifyError {
                    text = error.message
                }
            }
        }
    }
}
```

`MediaInput(photosPickerItem:)` copies the selected photo or video into a private temporary
file, keeps the Photos filename (and so the right content type), and deletes the copy when
the input is released. A complete example with tests is in
[`Examples/NeuroVerifyDemo`](Examples/NeuroVerifyDemo/README.md).

## Method reference

### `NeuroVerifyClient(apiKey:options:sessionConfiguration:)`

Creates a production client. Throws `NeuroVerifyError.validation` for an empty key or an
invalid option. `NeuroVerifyClient.Options`:

| Option | Default | Meaning |
|---|---|---|
| `baseURL` | `https://deepscan.neuraldefend.com` | HTTPS origin, without a path, query, or credentials |
| `allowCustomBaseURL` | `false` | Must be `true` for an origin other than production or staging, because it receives the key and media |
| `timeout` | `120` | Seconds allowed for each attempt, including the upload and the response |
| `maxRetries` | `3` | Retries after the first request for HTTP 429, 500, and 503 (0 through 3) |
| `retryAfterCap` | `60` | Longest `Retry-After` wait honored, in seconds |
| `userAgent` | `neuraldefend-swift/1.0.0` | Replaces the default `User-Agent` |
| `onWarning` | `nil` | Receives non-fatal warnings, such as an undocumented extension |

`sessionConfiguration` is copied into the client's own `URLSession` and defaults to
`.ephemeral`, so responses are never cached to disk. Pass a configuration to add
`protocolClasses` in tests or to adjust connectivity settings.

### `NeuroVerifyClient.staging(apiKey:options:sessionConfiguration:)`

Creates a client pinned to `https://stage.deepscan.neuraldefend.com`. Use only with a
staging key; `options.baseURL` is ignored.

### `NeuroVerifyClient.fromEnvironment(options:sessionConfiguration:environment:)`

Reads `NEURALDEFEND_API_KEY` and, when set, `NEURALDEFEND_BASE_URL` (which still needs
`allowCustomBaseURL` for a non-Neural Defend origin).

### `detectImage(_:onProgress:)`

Uploads to `/detect/image` and returns an `ImageResult`.

### `detectVideo(_:maxFrames:sampleRate:onProgress:)`

Uploads to `/detect/video` and returns a `VideoResult`. `maxFrames` is 1 through 100 (the
API default is 12) and `sampleRate` is at least 1; other values throw
`.validation(code: .invalidMaxFrames)` or `.invalidSampleRate` before any upload.

`onProgress` receives `(sentBytes, totalBytes)` of the multipart request body. It may be
called on any thread, starts at zero for every attempt, and restarts on an automatic retry.

### Media inputs

| Input | Use |
|---|---|
| `.file(url, filename: nil)` | A local file, streamed from disk. The filename defaults to the URL's last path component. Security-scoped URLs from a document picker are accessed for each upload. |
| `.data(data, filename:)` | In-memory bytes. The filename is required because its extension selects the content type. |
| `MediaInput(photosPickerItem:)` | A photo or video from SwiftUI's `PhotosPicker`. |

Every input can be replayed, so automatic retries resend identical bytes.

### Cancellation

Cancel the calling `Task` to stop preparation, a retry wait, or an upload in flight. The
call then throws `NeuroVerifyError.cancelled`. In SwiftUI, work started in `.task { }` is
cancelled automatically when the view disappears.

## Working with results

Always branch on `status` before reading scores.

| `status` | Meaning |
|---|---|
| `.success` | Scored, and every returned risk band is recognized |
| `.rejected` | The API declined to score the media (no face, several faces, quality, format, or security checks). This is a normal result, not an error, and it can be billable. |
| `.unknown` | A status or risk band this SDK version does not recognize. `originalStatus` and the `original…RiskLevel` fields keep the wire values. Do not make decisions from it; upgrade the SDK. |

`ImageResult` fields: `status`, `originalStatus`, `uniqueTrxID`, `filename`, `contentType`,
`statusCode`, `billable`, `aiThreatSignals`, `riskScore` (0.1 through 10.0), `riskLevel`
(`.low`, `.medium`, `.high`), `originalRiskLevel`, `message`, and the convenience properties
`isScored`, `isRejected`, and `isHighRisk`.

`VideoResult` scores video and audio independently: `videoRiskScore`, `videoRiskLevel`,
`videoMessage`, `audioRiskScore`, `audioRiskLevel`, `audioMessage`, `hasAudio`, and
`overallRiskScore` (the higher of the two, an SDK convenience that does not replace
modality-aware policy).

Base decisions on the risk band, not on score thresholds, which the service may tune.
`raw` holds the redacted wire envelope with the API's field names. It is not a stable
contract and may contain filenames or future fields, so do not log or persist it routinely.
Results are `Encodable`; encoding writes the normalized fields and never `raw`.

## Errors

Every operational failure throws `NeuroVerifyError`:

| Case | When | Retried automatically |
|---|---|---|
| `.validation(code:message:)` | Invalid option or media, detected before upload | No |
| `.authentication(_)` | HTTP 401: key invalid, expired, or for another environment | No |
| `.scope(_)` | HTTP 403: key lacks access to the endpoint | No |
| `.rateLimit(_, info)` | HTTP 429 after retries; `info` has `retryAfter`, `limit`, `remaining`, `reset` | Yes |
| `.server(_, raw:)` | HTTP 500 or 503 after retries, or an envelope with `status: "error"` | Yes (500, 503) |
| `.http(_)` | Any other status, including redirects, which are never followed | No |
| `.protocol(_)` | Malformed JSON or an envelope that breaks the contract | No |
| `.timeout(message:)` | The per-attempt timeout elapsed | No |
| `.network(message:)` | No response: DNS, connectivity, TLS, or a refused connection | No |
| `.cancelled` | The calling task was cancelled | No |

`error.statusCode`, `error.requestID`, and `error.message` are available on every case. The
API key is redacted from every message, `raw` value, and description, and the client's
`description`, `debugDescription`, and `dump` output never contain it.

```swift
do {
    let result = try await client.detectImage(media)
} catch let error as NeuroVerifyError {
    switch error {
    case .rateLimit(_, let info): scheduleRetry(after: info.retryAfter ?? 60)
    case .authentication, .scope: showConfigurationProblem()
    case .cancelled: break
    default: log("NeuroVerify failed: \(error) [\(error.requestID ?? "-")]")
    }
}
```

## Retries, billing, and idempotency

By default the SDK makes the first request and up to three retries:

- HTTP 500 and 503 wait about 1, 2, and 4 seconds, plus up to 25% jitter.
- HTTP 429 honors a `Retry-After` value in seconds or as an HTTP date, up to
  `retryAfterCap`; without one it waits 1, 2, and 4 seconds.
- Other statuses, timeouts, protocol errors, cancellation, and network errors are not
  retried, because the server may already have accepted a billable request.

Set `maxRetries: 0` to disable retries. Requests are not idempotent: every accepted attempt
can receive a new `uniqueTrxID` and be billed separately. `billable` is authoritative for
the returned transaction; persist `uniqueTrxID` with your audit record.

## Media formats and limits

- Images: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`, `.webp`, `.heic`, `.heif`;
  at most 10 MiB (10,485,760 bytes); at least 224 by 224 pixels; exactly one face.
- Videos: `.mp4`, `.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`, `.ogg`, `.ogv`; at most
  1,500,000,000 bytes.

Empty and oversized input is rejected locally. An undocumented extension produces a warning
through `onWarning` but is still uploaded, because the server inspects the content. Known
extensions map to fixed content types (`MediaLimits.contentType(forFilename:)`); others use
`application/octet-stream`. `MediaLimits` also exposes the extension sets and size limits.

Each upload is first written as a complete multipart body to a temporary file, which
`URLSession` streams and every retry reuses. The file is deleted when the call returns.
Make sure the device has free space for one copy of the largest video you upload.

## Security and privacy

- Upload media only with the data owner's authorization and an appropriate legal basis.
  Face media may be biometric personal data.
- Keep production keys out of apps. On a server, keep them in a secret store and rotate them.
- Avoid routine logging of `raw`, server messages, file paths, or filenames.
- Do not enable `allowCustomBaseURL` unless the origin is trusted with both keys and media.
- Do not treat low risk as proof, or high risk as the only reason for an adverse decision.

## Troubleshooting

- **`.authentication` with "Invalid API key":** the key is wrong, expired, or for the other
  environment. Staging keys work only with `NeuroVerifyClient.staging`.
- **`.validation(code: .customBaseURLRequiresOptIn)`:** set `allowCustomBaseURL: true` for a
  proxy or mock server you trust.
- **`.timeout` on large videos over slow networks:** raise `timeout`. It applies to each
  attempt, not to the whole call.
- **Uploads stop when the app goes to the background:** the client uses a foreground
  `URLSession`. Keep the app active, or upload from your backend.
- **Linux:** install the Swift toolchain's Foundation dependencies (`libcurl` and `libxml2`).

## Development

```sh
swift test                                   # from the repository root
swift format lint --strict -r Package.swift packages/swift
(cd packages/swift/Examples/NeuroVerifyDemo && swift test)
```

Tests run against the repository's shared fixtures (`tests/fixtures`) through a local HTTP
server, so they exercise the real `URLSession` transport. Live staging tests run only when
`NEURALDEFEND_STAGING_API_KEY` is set: `swift test --filter Staging`.

`generated/core` holds the OpenAPI Generator `swift5` output. It is not compiled; CI only
regenerates it to detect contract drift.

## Wire-level API documentation

- [Image endpoint and response scenarios](../../docs/client/unified-face-authenticity.md)
- [Video endpoint and response scenarios](../../docs/client/unified-video-authenticity.md)
- [OpenAPI contract](../../spec/public.yaml)

## License

MIT. See [LICENSE](LICENSE).
