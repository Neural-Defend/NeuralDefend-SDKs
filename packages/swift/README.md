<div align="center">

# NeuralDefend Swift SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Swift with a few lines of `async` code.**

[![Swift](https://img.shields.io/badge/swift-6.0%2B-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org/)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20Mac%20Catalyst%20%7C%20visionOS%20%7C%20Linux-555555?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-F05138?style=flat-square&logo=swift&logoColor=white)](#installation)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start-image) · [Examples](#examples) · [Results](#working-with-results) · [Errors](#errors) · [Troubleshooting](#troubleshooting)

</div>

---

## In plain words

You give the SDK a photo or a video. It sends the file to Neural Defend's **NeuroVerify**
service and gives you back an answer like this:

> "This face has a **low** / **medium** / **high** risk of being fake."

That is the whole idea. You do not need to know anything about machine learning, HTTP, or
multipart uploads; the SDK handles all of that for you.

| You want to... | Call | You get back |
|---|---|---|
| Check a photo of a face | `try await client.detectImage(.file(photoURL))` | An `ImageResult` with one risk level |
| Check a video | `try await client.detectVideo(.file(clipURL))` | A `VideoResult` with a video risk and an audio risk |

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `.low` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `.medium` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `.high` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection** (`status == .rejected`), not a thrown
error. The [examples](#examples) show how to handle each case.

## About this SDK

The official Swift client for the NeuroVerify image and video authenticity API. Version
`1.0.0` provides:

- An `async`/`await` API built for Swift 6 strict concurrency; every public type is
  `Sendable`, so one client can be shared across tasks.
- No dependencies beyond Foundation.
- Uploads streamed from disk with `URLSession`, so a 1.5 GB video is never loaded into memory.
- Bounded retries, a per-attempt timeout, task cancellation, upload progress, and no
  redirect following.
- Results normalized to `.success`, `.rejected`, or `.unknown`, with the wire values preserved.
- Support for iOS, iPadOS, macOS, Mac Catalyst, visionOS, and Linux.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without throwing, including some HTTP 200 responses.
- `billable` is the authoritative billing indicator for each returned transaction.

Risk output is not proof of authenticity and must not be the sole basis for an automated
accept/reject decision. Use the server-provided risk level with other evidence, documented
policy, and human review where appropriate.

## Requirements

| | Minimum |
|---|---|
| Swift | 6.0 (Xcode 16.0 or later) |
| iOS, iPadOS, Mac Catalyst | 15.0 |
| macOS | 12.0 |
| visionOS | 1.0 |
| Linux | Swift 6.0 toolchain (uses `FoundationNetworking`) |

You also need:

- A NeuroVerify API key with access to the image and/or video endpoint
  ([how to get one](#get-an-api-key)).
- Network access to the HTTPS API origin.

`MediaInput(photosPickerItem:)` needs iOS 16, macOS 13, Mac Catalyst 16, or visionOS 1.
tvOS and watchOS are not supported. This guide documents release `1.0.0`.

## Installation

The package lives in the [NeuralDefend-SDKs](https://github.com/Neural-Defend/NeuralDefend-SDKs)
repository and is released with plain version tags such as `1.0.0`. It is installed with
Swift Package Manager; CocoaPods and Carthage are not supported.

### In Xcode

1. Open your project and choose **File > Add Package Dependencies…**
2. Paste `https://github.com/Neural-Defend/NeuralDefend-SDKs` into the search field.
3. Set **Dependency Rule** to **Up to Next Major Version** starting at `1.0.0`.
4. Click **Add Package**, tick the **NeuralDefend** library, choose your app target, and
   click **Add Package** again.
5. Write `import NeuralDefend` at the top of any Swift file that uses the SDK.

### In `Package.swift`

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

Your package must declare platforms at least as new as the [requirements](#requirements),
for example `platforms: [.iOS(.v15), .macOS(.v12)]`.

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key in the package — request access from the company first, then configure
the SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media analysis,
   and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key,
   staging credential, or rate-limit details.
3. Store the key in a secret manager, your server's environment
   (`NEURALDEFEND_API_KEY`), or your backend's configuration. Never commit it, and never
   paste it into logs or support tickets.
4. For REST endpoint reference while you wait for a key, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

> [!WARNING]
> **Never ship a long-lived production API key inside an iOS, macOS, or visionOS app.**
> Anyone who installs the app can extract it. Upload media to your own authenticated
> backend and call NeuroVerify from there, or use a short-lived client credential that
> Neural Defend has approved for your tenant. Use a staging key during development.

### Where the key comes from

| Where your code runs | How to create the client |
|---|---|
| Server, command-line tool, CI | `try NeuroVerifyClient.fromEnvironment()` reads `NEURALDEFEND_API_KEY` |
| App with an approved short-lived credential | `try NeuroVerifyClient(apiKey: credentialFromYourBackend)` |
| Integration tests | `try NeuroVerifyClient.staging(apiKey: stagingKey)` |

Set the variable before starting a server or command-line tool.

macOS/Linux:

```bash
# Request a key at https://neuraldefend.com/ (Book a Demo), then export it:
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
```

PowerShell:

```powershell
# Request a key at https://neuraldefend.com/ (Book a Demo), then set it:
$env:NEURALDEFEND_API_KEY = "replace-with-your-api-key"
```

Only `fromEnvironment()` reads environment variables. `NeuroVerifyClient(apiKey:)` and
`staging(apiKey:)` never do, so an app never picks up a key by accident.

## Quick start: image

```swift
import Foundation
import NeuralDefend

let client = try NeuroVerifyClient.fromEnvironment() // uses NEURALDEFEND_API_KEY
let result = try await client.detectImage(.file(URL(fileURLWithPath: "selfie.jpg")))

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
print(String(decoding: try encoder.encode(result), as: UTF8.self))
```

That's it. You get the full response:

```json
{
  "aiThreatSignals" : [
    "Visual Safety Screening",
    "Liveness Verification"
  ],
  "billable" : true,
  "contentType" : "image/jpeg",
  "filename" : "selfie.jpg",
  "highRisk" : false,
  "message" : "Not likely to be Spoof or AI-generated",
  "rejected" : false,
  "riskLevel" : "low",
  "riskScore" : 2.2,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_image_low"
}
```

The field that matters most is `riskLevel`: `low`, `medium`, or `high`. In an iOS or macOS
app, create the client with `NeuroVerifyClient(apiKey:)` instead (see
[Get an API key](#get-an-api-key)).

<details>
<summary><b>First time with Swift Package Manager?</b> Create a command-line project to run this.</summary>

Create this layout, put the snippet above in `main.swift`, then run `swift run` from the
`DetectMedia` folder:

```text
DetectMedia/
├── Package.swift
└── Sources/
    └── DetectMedia/
        └── main.swift
```

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DetectMedia",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/Neural-Defend/NeuralDefend-SDKs", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DetectMedia",
            dependencies: [.product(name: "NeuralDefend", package: "NeuralDefend-SDKs")]
        )
    ]
)
```

</details>

## Quick start: video

```swift
import Foundation
import NeuralDefend

let client = try NeuroVerifyClient.fromEnvironment()
let result = try await client.detectVideo(.file(URL(fileURLWithPath: "clip.mp4")))

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
print(String(decoding: try encoder.encode(result), as: UTF8.self))
```

You get the full response, with a separate result for the picture and for the sound:

```json
{
  "aiThreatSignals" : [
    "Face Swap Detection",
    "Audio Frequency Analysis"
  ],
  "audioMessage" : "Likely to be AI-generated",
  "audioRiskLevel" : "high",
  "audioRiskScore" : 8.4,
  "billable" : true,
  "contentType" : "video/mp4",
  "filename" : "clip.mp4",
  "hasAudio" : true,
  "overallRiskScore" : 8.4,
  "rejected" : false,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_video_modalities",
  "videoMessage" : "Not likely to be AI-generated",
  "videoRiskLevel" : "low",
  "videoRiskScore" : 2.2
}
```

`overallRiskScore` is simply the higher of the two scores.

## Examples

> **Building for a specific industry?** See the [industry use cases](../../docs/use-cases/README.md):
> eKYC onboarding, KYC re-verification, Video KYC, HR tech, and video conferencing, with
> complete code for this SDK.

Unless an example says otherwise, it is a complete command-line program: paste it into
`Sources/DetectMedia/main.swift` from the [quick start](#quick-start-image), set
`NEURALDEFEND_API_KEY`, and run `swift run DetectMedia`. Example 5 is a SwiftUI view for an
app. The output shown under each example is representative; your scores, transaction IDs,
and messages will differ.

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Check one photo](#1-check-one-photo) | The smallest useful program |
| 2 | [Check a video with sound](#2-check-a-video-with-sound) | Reading the separate video and audio results |
| 3 | [Turn a result into a decision](#3-turn-a-result-into-a-decision) | Mapping low, medium, high, and rejected to actions |
| 4 | [Upload `Data` from memory](#4-upload-data-from-memory) | Checking bytes that are not in a file, such as a `UIImage` |
| 5 | [Pick a photo in SwiftUI](#5-pick-a-photo-in-swiftui) | Checking a photo the user picks with `PhotosPicker` |
| 6 | [Check many files at once](#6-check-many-files-at-once) | Sharing one client across a `TaskGroup` |
| 7 | [Handle every kind of error](#7-handle-every-kind-of-error) | Telling bad input, bad keys, and outages apart |
| 8 | [Save an audit record](#8-save-an-audit-record) | Keeping transaction IDs for billing and support |
| 9 | [Run on a server or Linux, and test against staging](#9-run-on-a-server-or-linux-and-test-against-staging) | Server-side Swift and safe testing |
| 10 | [Tune video sampling and show progress](#10-tune-video-sampling-and-show-progress) | Trading speed for coverage on long videos |

### 1. Check one photo

Print just the answer instead of the whole response.

```swift
import Foundation
import NeuralDefend

let client = try NeuroVerifyClient.fromEnvironment()
let result = try await client.detectImage(.file(URL(fileURLWithPath: "selfie.jpg")))
print(result.riskLevel?.rawValue ?? "none", result.message)
```

Output:

```text
low Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** answers: one for the picture and one for the sound.

```swift
import Foundation
import NeuralDefend

let client = try NeuroVerifyClient.fromEnvironment()
let result = try await client.detectVideo(.file(URL(fileURLWithPath: "interview.mp4")))
print("Video:", result.videoRiskLevel?.rawValue ?? "none")
print("Audio:", result.audioRiskLevel?.rawValue ?? "none")
```

Output:

```text
Video: low
Audio: high
```

Here the face looks real but the voice is likely fake. A video with no sound prints
`Audio: none`.

### 3. Turn a result into a decision

Your application usually needs one of a few actions. Write that mapping once and reuse
it. Always switch on the **risk level**, never on your own numeric threshold, because the
service may tune its scoring bands. Swift's `switch` makes sure every case is handled.

```swift
import Foundation
import NeuralDefend

enum Decision: CustomStringConvertible {
    case proceed, manualReview, escalate
    case askForNewPhoto(String)

    var description: String {
        switch self {
        case .proceed: "CONTINUE"
        case .manualReview: "MANUAL REVIEW"
        case .escalate: "ESCALATE"
        case .askForNewPhoto(let reason): "ASK FOR A NEW PHOTO - \(reason)"
        }
    }
}

func decide(_ result: ImageResult) -> Decision {
    switch result.status {
    case .rejected:
        return .askForNewPhoto(result.message)
    case .unknown:
        return .manualReview                        // never decide from an unrecognized outcome
    case .success:
        switch result.riskLevel {
        case .low: return .proceed
        case .medium: return .manualReview
        case .high: return .escalate
        case nil: return .manualReview
        }
    }
}

let client = try NeuroVerifyClient.fromEnvironment()
for name in ["selfie.jpg", "printed_photo.jpg", "landscape.jpg"] {
    let result = try await client.detectImage(.file(URL(fileURLWithPath: name)))
    print(name.padding(toLength: 20, withPad: " ", startingAt: 0), "->", decide(result))
}
```

Output:

```text
selfie.jpg           -> CONTINUE
printed_photo.jpg    -> ESCALATE
landscape.jpg        -> ASK FOR A NEW PHOTO - No face detected in the image
```

### 4. Upload `Data` from memory

When media arrives from the camera, a `UIImage`, a network download, or object storage,
you often have `Data` instead of a file. Use `.data(_:filename:)`. The filename is
required because its extension tells the SDK the format.

```swift
import Foundation
import NeuralDefend

// Stand-in for bytes from your storage service or a download.
let imageData = try Data(contentsOf: URL(fileURLWithPath: "selfie.jpg"))

let client = try NeuroVerifyClient.fromEnvironment()
let result = try await client.detectImage(.data(imageData, filename: "selfie.jpg"))

print("\(imageData.count) bytes checked -> \(result.riskLevel?.rawValue ?? result.message)")
```

Output:

```text
482113 bytes checked -> low
```

In an iOS or visionOS app, a `UIImage` works the same way once you turn it into JPEG data:

```swift
import NeuralDefend
import UIKit

func check(_ image: UIImage, with client: NeuroVerifyClient) async throws -> ImageResult {
    guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
        throw NeuroVerifyError.validation(code: .unsupportedInput, message: "The image has no bitmap data.")
    }
    return try await client.detectImage(.data(jpeg, filename: "photo.jpg"))
}
```

`Data` is held in memory and resent unchanged on an automatic retry. For large videos,
prefer `.file(_:)`, which streams from disk.

### 5. Pick a photo in SwiftUI

This view lets the user pick a photo with `PhotosPicker` and shows the verdict.
`MediaInput(photosPickerItem:)` copies the picked item into a private temporary file that
is deleted automatically, and keeps the Photos filename so the content type is right.
`.task(id:)` starts a check each time the selection changes and cancels the previous one.
Requires iOS 16, macOS 13, or visionOS 1.

```swift
import NeuralDefend
import PhotosUI
import SwiftUI

struct VerifyPhotoView: View {
    // Create the client once, with a key or approved credential from your backend.
    let client: NeuroVerifyClient

    @State private var item: PhotosPickerItem?
    @State private var verdict = "Choose a photo of one face."

    var body: some View {
        VStack(spacing: 16) {
            PhotosPicker("Choose a photo", selection: $item, matching: .images)
            Text(verdict)
                .multilineTextAlignment(.center)
        }
        .padding()
        .task(id: item) {
            guard let item else { return }
            verdict = "Checking…"
            do {
                let media = try await MediaInput(photosPickerItem: item)
                let result = try await client.detectImage(media)
                switch result.status {
                case .success:
                    verdict = "Risk: \(result.riskLevel?.rawValue ?? "unknown")"
                case .rejected:
                    verdict = "Please choose another photo: \(result.message)"
                case .unknown:
                    verdict = "Unrecognized result. Please update the app."
                }
            } catch NeuroVerifyError.cancelled {
                // The user picked another photo or left the screen.
            } catch let error as NeuroVerifyError {
                verdict = "Could not check the photo: \(error.message)"
            } catch {
                verdict = "Could not check the photo."
            }
        }
    }
}
```

Output (text shown on screen):

```text
Risk: low
```

or, for a photo without a face:

```text
Please choose another photo: No face detected in the image
```

A complete demo app with progress reporting and tests is in
[`Examples/NeuroVerifyDemo`](Examples/NeuroVerifyDemo/README.md).

### 6. Check many files at once

`NeuroVerifyClient` is `Sendable`, so a single client can safely be shared by many tasks.
Reuse it instead of creating a client per file. This program checks every image in a folder
in parallel with a `TaskGroup` and prints a summary.

```swift
import Foundation
import NeuralDefend

let client = try NeuroVerifyClient.fromEnvironment()
let folder = URL(fileURLWithPath: "uploads", isDirectory: true)
let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { MediaLimits.imageExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

let rows = await withTaskGroup(of: (String, String, String).self) { group in
    for file in files {
        group.addTask {
            do {
                let result = try await client.detectImage(.file(file))
                let outcome = result.isScored ? (result.riskLevel?.rawValue ?? "unknown") : "rejected"
                return (file.lastPathComponent, outcome, result.message)
            } catch let error as NeuroVerifyError {
                return (file.lastPathComponent, "error", error.message)
            } catch {
                return (file.lastPathComponent, "error", "\(error)")
            }
        }
    }
    var collected: [(String, String, String)] = []
    for await row in group { collected.append(row) }
    return collected.sorted { $0.0 < $1.0 }
}

var summary: [String: Int] = [:]
for (name, outcome, message) in rows {
    summary[outcome, default: 0] += 1
    print(name.padding(toLength: 24, withPad: " ", startingAt: 0),
          outcome.padding(toLength: 9, withPad: " ", startingAt: 0), message)
}
print("\nSummary:", summary.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: high=1, low=1, medium=1, rejected=1
```

Each call is a separate transaction and may be billable. For large folders, limit how many
uploads run at once and check your rate limits; the SDK retries HTTP 429 a few times, then
throws `.rateLimit`.

### 7. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation | How it shows up | Who fixes it |
|---|---|---|
| The file was checked but could not be scored | A result with `status == .rejected` | The end user sends better media |
| Your setup is wrong (missing key, bad path, bad option) | `.validation`, `.authentication`, `.scope` | You, the developer |
| The service or network had a problem | `.rateLimit`, `.server`, `.timeout`, `.network` | Try again later |

```swift
import Foundation
import NeuralDefend

do {
    let client = try NeuroVerifyClient.fromEnvironment()
    let result = try await client.detectImage(.file(URL(fileURLWithPath: "selfie.jpg")))
    if result.isRejected {
        print("Please upload a different photo: \(result.message)")
    } else {
        print("Risk: \(result.riskLevel?.rawValue ?? "unknown")")
    }
} catch let error as NeuroVerifyError {
    switch error {
    case .validation(let code, let message):
        print("Fix the input or configuration (\(code.rawValue)): \(message)")
    case .authentication:
        print("The API key is invalid or expired. Check NEURALDEFEND_API_KEY.")
    case .scope:
        print("This key cannot use the image endpoint. Ask Neural Defend to add it.")
    case .rateLimit(_, let info):
        print("Too many requests. Try again in \(Int(info.retryAfter ?? 60)) seconds.")
    case .server, .http, .protocol:
        print("Service problem, request id: \(error.requestID ?? "-")")
    case .timeout, .network:
        print("Could not reach the service: \(error.message)")
    case .cancelled:
        print("Cancelled.")
    }
}
```

Output when the key is missing:

```text
Fix the input or configuration (api_key_required): Set NEURALDEFEND_API_KEY or pass apiKey explicitly.
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

The [Errors](#errors) section lists every case.

### 8. Save an audit record

Every result has a `uniqueTrxID`. Store it: it is what support and billing will ask for.
A small `Codable` struct keeps only the fields you need.

```swift
import Foundation
import NeuralDefend

struct AuditRecord: Codable {
    let checkedAt: Date
    let transactionID: String
    let status: ResultStatus
    let riskLevel: RiskLevel?
    let billable: Bool
}

let client = try NeuroVerifyClient.fromEnvironment()
let result = try await client.detectImage(.file(URL(fileURLWithPath: "selfie.jpg")))

let record = AuditRecord(
    checkedAt: Date(),
    transactionID: result.uniqueTrxID,
    status: result.status,
    riskLevel: result.riskLevel,
    billable: result.billable
)

// Append one JSON line per check to audit.jsonl.
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
let line = try encoder.encode(record) + Data("\n".utf8)
let log = URL(fileURLWithPath: "audit.jsonl")
if FileManager.default.fileExists(atPath: log.path) {
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
} else {
    try line.write(to: log)
}

encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
print(String(decoding: try encoder.encode(record), as: UTF8.self))
```

Output:

```json
{
  "billable" : true,
  "checkedAt" : "2026-10-16T09:41:07Z",
  "riskLevel" : "low",
  "status" : "success",
  "transactionID" : "trx_example_image_low"
}
```

Store only the fields you need. Avoid logging filenames or `result.raw`, which may contain
personal data. If you need the whole normalized result, `ImageResult` and `VideoResult` are
`Encodable` too, and encoding them never includes `raw`.

### 9. Run on a server or Linux, and test against staging

The SDK runs on Linux with the Swift 6 toolchain, so you can call NeuroVerify from a
server-side Swift app or a command-line job. This is the recommended place to keep a
production key. On a server, create **one** client at startup and share it between
requests.

```swift
import Foundation
import NeuralDefend

// The same code runs on macOS and Linux. Import FoundationNetworking yourself only if
// your own Linux code uses URLSession types such as URLSessionConfiguration.
let client = try NeuroVerifyClient.fromEnvironment()   // NEURALDEFEND_API_KEY from your secret store
print(client)                                            // the key is always redacted

let result = try await client.detectImage(.file(URL(fileURLWithPath: "selfie.jpg")))
print("production: \(result.status.rawValue) / \(result.riskLevel?.rawValue ?? "-")")
```

Run it in the official Swift container:

```bash
docker run --rm -it -v "$PWD:/app" -w /app \
  -e NEURALDEFEND_API_KEY \
  swift:6.0 swift run DetectMedia
```

Output:

```text
NeuroVerifyClient(apiKey: [REDACTED], baseURL: https://deepscan.neuraldefend.com, timeout: 120.0, maxRetries: 3)
production: success / low
```

Neural Defend can also issue a separate **staging** key during onboarding. `staging()`
always uses the staging server and ignores any `baseURL`, so a test can never reach
production by mistake:

```swift
import Foundation
import NeuralDefend

let stagingKey = ProcessInfo.processInfo.environment["NEURALDEFEND_STAGING_API_KEY"] ?? ""
let client = try NeuroVerifyClient.staging(
    apiKey: stagingKey,
    options: .init(maxRetries: 0)          // fail fast in tests
)
let result = try await client.detectImage(.file(URL(fileURLWithPath: "Tests/Fixtures/selfie.jpg")))
print("staging: \(result.status.rawValue) / \(result.riskLevel?.rawValue ?? "-")")
```

Output:

```text
staging: success / low
```

### 10. Tune video sampling and show progress

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `maxFrames` accepts 1 to 100. The
`onProgress` callback reports how many bytes of the upload have been sent.

```swift
import Foundation
import NeuralDefend

// Allow more time per attempt for large uploads on slow networks.
let client = try NeuroVerifyClient.fromEnvironment(options: .init(timeout: 300))
let clip = URL(fileURLWithPath: "webinar.mp4")

for frames in [6, 24, 48] {
    let started = Date()
    let result = try await client.detectVideo(.file(clip), maxFrames: frames) { sent, total in
        if sent == total { print("  uploaded \(total) bytes") }
    }
    let seconds = Date().timeIntervalSince(started)
    print("\(frames) frames -> video \(result.videoRiskLevel?.rawValue ?? "-") in \(String(format: "%.1f", seconds))s")
}
```

Output:

```text
  uploaded 48211934 bytes
6 frames -> video low in 4.8s
  uploaded 48211934 bytes
24 frames -> video low in 9.3s
  uploaded 48211934 bytes
48 frames -> video low in 15.6s
```

Each call above is a separate, billable transaction. Pick one setting for production.
`onProgress` may be called on any thread; in an app, hop to the main actor before updating
the UI.

## Working with results

Detection methods return `ImageResult` or `VideoResult` values for both successful scores
and business rejections. They are immutable `Sendable` structs. Always branch on `status`
before reading scores.

| `status` | Meaning |
|---|---|
| `.success` | Scored, and every returned risk band is recognized |
| `.rejected` | The API declined to score the media (no face, several faces, quality, format, or security checks). This is a normal result, not an error, and it can be billable. |
| `.unknown` | A status or risk band this SDK version does not recognize. `originalStatus` and the `original…RiskLevel` fields keep the wire values. Do not make decisions from it; upgrade the SDK. |

`RiskLevel` has three cases: `.low`, `.medium`, and `.high`. `ResultStatus` and `RiskLevel`
are `String`-backed, `Codable`, and `CaseIterable`.

### `ImageResult`

| Property | Type | Meaning |
|---|---|---|
| `status` | `ResultStatus` | Normalized outcome |
| `originalStatus` | `String` | Exact wire status |
| `uniqueTrxID` | `String` | Transaction ID; persist it for audit, billing, and support |
| `filename` | `String` | Upload name |
| `contentType` | `String` | Content type detected by the service |
| `statusCode` | `Int` | Service status code; unknown values are preserved |
| `billable` | `Bool` | Authoritative billing indicator for this transaction |
| `aiThreatSignals` | `[String]` | Checks reported by the service; the list may evolve |
| `riskScore` | `Double?` | 0.1 through 10.0; `nil` when not scored |
| `riskLevel` | `RiskLevel?` | Recognized band; `nil` when not scored or unrecognized |
| `originalRiskLevel` | `String?` | Exact wire risk level |
| `message` | `String` | Service message, suitable for user guidance; do not branch on its text |
| `raw` | `JSONValue` | Redacted wire envelope (see below) |
| `isScored` | `Bool` | `true` only when `status == .success` |
| `isRejected` | `Bool` | `true` when `status == .rejected` |
| `isHighRisk` | `Bool` | `true` when `riskLevel == .high` |

### `VideoResult`

`VideoResult` has the same `status`, `originalStatus`, `uniqueTrxID`, `filename`,
`contentType`, `statusCode`, `billable`, `aiThreatSignals`, `raw`, `isScored`, and
`isRejected` properties, and scores video and audio independently:

| Property | Type | Meaning |
|---|---|---|
| `videoRiskScore` / `videoRiskLevel` | `Double?` / `RiskLevel?` | Video modality score and band |
| `originalVideoRiskLevel` | `String?` | Exact wire video risk level |
| `videoMessage` | `String` | Video message; also explains a rejection |
| `audioRiskScore` / `audioRiskLevel` | `Double?` / `RiskLevel?` | Audio modality; `nil` when there is no audio track or the video was not scored |
| `originalAudioRiskLevel` | `String?` | Exact wire audio risk level |
| `audioMessage` | `String?` | For example `"No audio track detected"`; `nil` on rejections |
| `hasAudio` | `Bool` | `true` when an audio risk score was returned |
| `overallRiskScore` | `Double?` | SDK convenience: the higher available modality score |

Do not infer success from HTTP 200. No-face and face-policy outcomes can be HTTP 200
rejections with `nil` risk fields and may be billable. Do not create policy from numeric
thresholds: use the API-owned `.low`, `.medium`, and `.high` bands because thresholds may
be tuned.

### Encoding versus `raw`

Results are `Encodable`. Encoding writes the stable normalized fields with camelCase keys
(`uniqueTrxId`, `riskLevel`, …), wire `"Y"`/`"N"` billing values as booleans, and the
derived `scored`, `rejected`, `highRisk`, `hasAudio`, and `overallRiskScore` values. The
`original…` fields are written only when `status` is `.unknown`. Encoding never writes
`raw`. Set `keyEncodingStrategy = .convertToSnakeCase` on your `JSONEncoder` if you prefer
snake_case keys.

`raw` is the redacted wire envelope as a `JSONValue`, using the API's field names. It is
kept for diagnostics and forward compatibility, is not a stable contract, and may contain
filenames or future personal or customer fields. Do not log or persist it routinely.

`print(result)` shows a short summary of normalized fields and never prints `raw`.

## Representative outputs

The values below are representative examples based on the documented API scenarios.
Scores, transaction IDs, messages, detected content types, and threat signals vary by
media and service evolution. They show the normalized shape that `JSONEncoder` writes with
`[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` (arrays are shown on one line for
brevity), not raw wire envelopes.

### Image outcomes

Low, medium, and high are scored outcomes. Low means lower observed risk, not proof that
an image is authentic. Medium is inconclusive and should receive additional review. High
indicates stronger risk signals and should be escalated under your policy.

Representative low-risk result:

```json
{
  "aiThreatSignals" : [ "Visual Safety Screening", "Liveness Verification" ],
  "billable" : true,
  "contentType" : "image/jpeg",
  "filename" : "selfie.jpg",
  "highRisk" : false,
  "message" : "Not likely to be Spoof or AI-generated",
  "rejected" : false,
  "riskLevel" : "low",
  "riskScore" : 2.2,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_image_low"
}
```

Representative medium-risk result:

```json
{
  "aiThreatSignals" : [ "Visual Safety Screening", "Liveness Verification" ],
  "billable" : true,
  "contentType" : "image/jpeg",
  "filename" : "portrait.jpg",
  "highRisk" : false,
  "message" : "Less likely to be Spoof or AI-generated",
  "rejected" : false,
  "riskLevel" : "medium",
  "riskScore" : 5.5,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_image_medium"
}
```

Representative high-risk result:

```json
{
  "aiThreatSignals" : [ "Visual Safety Screening", "Liveness Verification" ],
  "billable" : true,
  "contentType" : "image/jpeg",
  "filename" : "printed_photo.jpg",
  "highRisk" : true,
  "message" : "Likely to be Spoof detected",
  "rejected" : false,
  "riskLevel" : "high",
  "riskScore" : 8.7,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_image_high"
}
```

No-face and multiple-face image results are normal, billable rejections even though the
HTTP response is 200:

```json
{
  "aiThreatSignals" : [ ],
  "billable" : true,
  "contentType" : "image/jpeg",
  "filename" : "landscape.jpg",
  "highRisk" : false,
  "message" : "No face detected in the image",
  "rejected" : true,
  "riskLevel" : null,
  "riskScore" : null,
  "scored" : false,
  "status" : "rejected",
  "statusCode" : 6,
  "uniqueTrxId" : "trx_example_image_no_face"
}
```

```json
{
  "aiThreatSignals" : [ ],
  "billable" : true,
  "contentType" : "image/jpeg",
  "filename" : "group_photo.jpg",
  "highRisk" : false,
  "message" : "Multiple faces detected in the image",
  "rejected" : true,
  "riskLevel" : null,
  "riskScore" : null,
  "scored" : false,
  "status" : "rejected",
  "statusCode" : 7,
  "uniqueTrxId" : "trx_example_image_multiple_faces"
}
```

Input-quality and security failures are returned as non-billable business rejections,
normally over HTTP 400. They are returned as results, not thrown as `.validation`,
because the request reached the API:

```json
{
  "aiThreatSignals" : [ ],
  "billable" : false,
  "contentType" : "image/jpeg",
  "filename" : "blurry.jpg",
  "highRisk" : false,
  "message" : "Image is too blurry for analysis",
  "rejected" : true,
  "riskLevel" : null,
  "riskScore" : null,
  "scored" : false,
  "status" : "rejected",
  "statusCode" : 2,
  "uniqueTrxId" : "trx_example_image_quality"
}
```

For a rejection, show the message to the user where appropriate and request corrected
media. Do not retry unchanged media.

### Video outcomes

Video and audio are separate modalities. Either modality can have a different risk level.
The API does not return a combined risk score.

Representative result with both modalities:

```json
{
  "aiThreatSignals" : [ "Face Swap Detection", "Audio Frequency Analysis" ],
  "audioMessage" : "Likely to be AI-generated",
  "audioRiskLevel" : "high",
  "audioRiskScore" : 8.4,
  "billable" : true,
  "contentType" : "video/mp4",
  "filename" : "voice_clone.mp4",
  "hasAudio" : true,
  "overallRiskScore" : 8.4,
  "rejected" : false,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_video_modalities",
  "videoMessage" : "Not likely to be AI-generated",
  "videoRiskLevel" : "low",
  "videoRiskScore" : 2.2
}
```

A video without an audio track can still be successfully scored:

```json
{
  "aiThreatSignals" : [ "Frame-Level Visual Analysis" ],
  "audioMessage" : "No audio track detected",
  "audioRiskLevel" : null,
  "audioRiskScore" : null,
  "billable" : true,
  "contentType" : "video/mp4",
  "filename" : "silent_clip.mp4",
  "hasAudio" : false,
  "overallRiskScore" : 2.1,
  "rejected" : false,
  "scored" : true,
  "status" : "success",
  "statusCode" : 1,
  "uniqueTrxId" : "trx_example_video_silent",
  "videoMessage" : "Not likely to be AI-generated",
  "videoRiskLevel" : "low",
  "videoRiskScore" : 2.1
}
```

Multi-face sampled frames are skipped. If no sampled frame contains exactly one scorable
face, the response uses the same no-face rejection shape and audio is not scored:

```json
{
  "aiThreatSignals" : [ ],
  "audioMessage" : null,
  "audioRiskLevel" : null,
  "audioRiskScore" : null,
  "billable" : true,
  "contentType" : "video/mp4",
  "filename" : "non_face_video.mp4",
  "hasAudio" : false,
  "overallRiskScore" : null,
  "rejected" : true,
  "scored" : false,
  "status" : "rejected",
  "statusCode" : 6,
  "uniqueTrxId" : "trx_example_video_no_face",
  "videoMessage" : "No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.",
  "videoRiskLevel" : null,
  "videoRiskScore" : null
}
```

Video format, size, and security failures are similarly returned as non-billable
`statusCode: 2` rejections with `nil` modality fields.

## Method reference

### `NeuroVerifyClient(apiKey:options:sessionConfiguration:)`

```swift
public convenience init(
    apiKey: String,
    options: NeuroVerifyClient.Options = Options(),
    sessionConfiguration: URLSessionConfiguration = .ephemeral
) throws
```

Creates a production client. The key is trimmed and must be non-empty; it is sent in the
`x-api-key` header and never read from the environment by this initializer. Throws
`NeuroVerifyError.validation` for an empty key or an invalid option.

`NeuroVerifyClient.Options` (every property has a default):

| Option | Default | Meaning |
|---|---|---|
| `baseURL` | `https://deepscan.neuraldefend.com` | HTTPS origin, without a path, query, fragment, or credentials |
| `allowCustomBaseURL` | `false` | Must be `true` for an origin other than production or staging, because it receives the key and media |
| `timeout` | `120` | Seconds allowed for each attempt, including the upload and the response; must be greater than zero |
| `maxRetries` | `3` | Retries after the first request for HTTP 429, 500, and 503 (0 through 3) |
| `retryAfterCap` | `60` | Longest `Retry-After` wait honored, in seconds |
| `userAgent` | `nil` → `neuraldefend-swift/1.0.0` | Replaces the default `User-Agent` |
| `onWarning` | `nil` | `@Sendable (ValidationWarning) -> Void`; receives non-fatal warnings, such as an undocumented extension |

```swift
let client = try NeuroVerifyClient(
    apiKey: credentialFromYourBackend,
    options: .init(timeout: 300, maxRetries: 1, onWarning: { print($0) })
)
```

`sessionConfiguration` is copied into the client's own `URLSession` and defaults to
`.ephemeral`, so responses are never cached to disk and cookies are not stored. Pass a
configuration to add `protocolClasses` in tests or to adjust connectivity settings.

The client also exposes `baseURL`, `timeout`, `maxRetries`, and `retryAfterCap` as
read-only properties, plus the constants `NeuroVerifyClient.productionURL`,
`NeuroVerifyClient.stagingURL`, and `NeuroVerifyClient.sdkVersion`. Its `description`,
`debugDescription`, and `dump` output always show the key as `[REDACTED]`.

### `NeuroVerifyClient.staging(apiKey:options:sessionConfiguration:)`

Creates a client pinned to `https://stage.deepscan.neuraldefend.com`. Use only with a
staging key; `options.baseURL` and `options.allowCustomBaseURL` are ignored.

### `NeuroVerifyClient.fromEnvironment(options:sessionConfiguration:environment:)`

Reads `NEURALDEFEND_API_KEY` and, when set, `NEURALDEFEND_BASE_URL` (which still needs
`allowCustomBaseURL: true` for a non-Neural Defend origin). Intended for servers,
command-line tools, and tests; apps should pass a key explicitly. The `environment`
parameter defaults to `ProcessInfo.processInfo.environment` and can be replaced in tests.

Configuration precedence:

1. The key: `apiKey` argument for the initializers, `NEURALDEFEND_API_KEY` for
   `fromEnvironment()`. There is no default key.
2. The origin: `staging()` always uses staging; `fromEnvironment()` uses
   `NEURALDEFEND_BASE_URL` when set, then `options.baseURL`; the initializer uses
   `options.baseURL` (production by default).
3. All other options use only their explicit value or documented default.

### `detectImage(_:onProgress:)`

```swift
public func detectImage(
    _ media: MediaInput,
    onProgress: UploadProgressHandler? = nil
) async throws -> ImageResult
```

Uploads to `/detect/image` and returns an `ImageResult`. Local validation failures throw
`.validation` before any request is sent.

### `detectVideo(_:maxFrames:sampleRate:onProgress:)`

```swift
public func detectVideo(
    _ media: MediaInput,
    maxFrames: Int? = nil,
    sampleRate: Int? = nil,
    onProgress: UploadProgressHandler? = nil
) async throws -> VideoResult
```

Uploads to `/detect/video` and returns a `VideoResult`.

- `maxFrames`: 1 through 100. When omitted, the API default is 12. Other values throw
  `.validation(code: .invalidMaxFrames, …)` before any upload.
- `sampleRate`: at least 1. Smaller values throw `.validation(code: .invalidSampleRate, …)`.

### Upload progress

`UploadProgressHandler` is `@Sendable (_ sentBytes: Int64, _ totalBytes: Int64) -> Void`.
It reports the bytes of the multipart request body, may be called on any thread, starts at
zero for every attempt, and restarts on an automatic retry.

### Cancellation

Cancel the calling `Task` to stop preparation, a retry wait, or an upload in flight. The
call then throws `NeuroVerifyError.cancelled`. In SwiftUI, work started in `.task { }` or
`.task(id:)` is cancelled automatically when the view disappears or the id changes.

## Media inputs

| Input | Use |
|---|---|
| `.file(url, filename: nil)` | A local file URL, streamed from disk. The filename defaults to the URL's last path component. Security-scoped URLs from a document picker are accessed for each upload. |
| `.data(data, filename:)` | In-memory bytes. The filename is required because its extension selects the content type. |
| `MediaInput(photosPickerItem:)` | A photo or video from SwiftUI's `PhotosPicker` (`async throws`). Copied to a private temporary file that is deleted when the input is released. |

Every input can be replayed, so automatic retries resend identical bytes. `.file` requires
a `file://` URL; a remote URL throws `.validation(code: .unsupportedInput, …)`. A path must
be a readable regular file.

Each upload is first written as a complete multipart body to a temporary file, which
`URLSession` streams and every retry reuses. The file is deleted when the call returns.
Make sure the device has free space for one copy of the largest video you upload.

## Supported media and limits

Image uploads have an exact maximum of 10 MiB (`10,485,760` bytes):

- `.jpg`, `.jpeg` — `image/jpeg`
- `.png` — `image/png`
- `.bmp` — `image/bmp`
- `.tif`, `.tiff` — `image/tiff`
- `.webp` — `image/webp`
- `.heic` — `image/heic`
- `.heif` — `image/heif`

Images must be at least 224 × 224 pixels and contain exactly one face for scoring.
No-face and multiple-face images are rejected as described above.

Video uploads have an exact maximum of `1,500,000,000` bytes:

- `.mp4` — `video/mp4`
- `.avi` — `video/vnd.avi`
- `.mov` — `video/quicktime`
- `.mkv` — `video/matroska`
- `.wmv` — `video/x-ms-wmv`
- `.flv` — `video/x-flv`
- `.webm` — `video/webm`
- `.ogg`, `.ogv` — `video/ogg`

The service samples 12 frames by default. A sampled frame must contain one face to be
scorable; multi-face frames are skipped. If no scorable single-face frame remains, the
entire request is rejected and audio is not scored.

Empty and oversized input is rejected locally with `.emptyFile` or `.fileTooLarge`. An
undocumented extension produces a `ValidationWarning` through `onWarning` but is still
uploaded as `application/octet-stream`, because the server inspects the content.
`MediaLimits` exposes `imageMaxBytes`, `videoMaxBytes`, `imageExtensions`,
`videoExtensions`, and `contentType(forFilename:)`.

## Errors

Every operational failure throws `NeuroVerifyError`, a `Sendable`, `Equatable` enum:

| Case | When | Retried automatically |
|---|---|---|
| `.validation(code:message:)` | Invalid key, option, or media, detected before upload | No |
| `.authentication(ErrorDetails)` | HTTP 401: key invalid, expired, or for another environment | No |
| `.scope(ErrorDetails)` | HTTP 403: key lacks access to the endpoint | No |
| `.rateLimit(ErrorDetails, RateLimitInfo)` | HTTP 429 after retries; `RateLimitInfo` has `retryAfter`, `limit`, `remaining`, `reset` | Yes |
| `.server(ErrorDetails, raw: JSONValue?)` | HTTP 500 or 503 after retries, or an envelope with `status: "error"` | Yes (500, 503) |
| `.http(ErrorDetails)` | Any other status, including redirects, which are never followed | No |
| `.protocol(ErrorDetails)` | Malformed JSON or an envelope that breaks the contract | No |
| `.timeout(message:)` | The per-attempt timeout elapsed | No |
| `.network(message:)` | No response: DNS, connectivity, TLS, or a refused connection | No |
| `.cancelled` | The calling task was cancelled | No |

Every case exposes `error.message`; `error.statusCode` and `error.requestID` are set when
the error came from an HTTP response. `ErrorDetails` holds `message`, `statusCode`, and
`requestID`. The API key is redacted from every message, `raw` value, and description.

`ValidationErrorCode` values: `apiKeyRequired`, `customBaseURLRequiresOptIn`, `emptyFile`,
`fileNotFound`, `fileTooLarge`, `filenameRequired`, `invalidBaseURL`, `invalidMaxFrames`,
`invalidRetries`, `invalidSampleRate`, `invalidTimeout`, and `unsupportedInput`.

```swift
do {
    let result = try await client.detectImage(media)
    // inspect result.status
} catch let error as NeuroVerifyError {
    switch error {
    case .rateLimit(_, let info): scheduleRetry(after: info.retryAfter ?? 60)
    case .authentication, .scope: showConfigurationProblem()
    case .cancelled: break
    default: log("NeuroVerify failed: \(error) [\(error.requestID ?? "-")]")
    }
}
```

Do not confuse a returned business rejection with a thrown error. HTTP 400 validation or
security rejections that have the documented score envelope are returned as results so
your application can inspect the API's message and `billable` value.

## Retries, billing, and idempotency

By default the SDK makes the first request and up to three retries, only for HTTP 429,
500, and 503:

- HTTP 500 and 503 wait about 1, 2, and 4 seconds, plus up to 25% jitter.
- HTTP 429 honors a `Retry-After` value in seconds or as an HTTP date, up to
  `retryAfterCap` (60 seconds by default); without one it waits 1, 2, and 4 seconds.
- Other statuses, timeouts, protocol errors, cancellation, and network errors are not
  retried, because the server may already have accepted a billable request.
- `maxRetries: 0` disables retries; `maxRetries: 3` allows up to four total attempts.

Requests are not idempotent. Every accepted attempt can receive a new `uniqueTrxID` and be
billed separately. A timeout or network failure can leave billability unknown because the
client may not have received the server response. Persist `uniqueTrxID` with your audit
record, and avoid adding another retry layer without accounting for the SDK's own attempts.

`billable` describes the returned transaction only. A successful score is normally
billable; no-face and face-policy rejections can also be billable. Input validation and
security rejections are normally non-billable. Always use the actual returned value.

## Privacy and security

- Upload media only with the data owner's authorization and an appropriate legal basis.
  Face media may be biometric personal data.
- **Keep production keys out of apps.** Call NeuroVerify from your backend, or use a
  short-lived credential approved by Neural Defend. On a server, keep keys in a secret
  store and rotate them if exposure is suspected.
- Apply your organization's consent, residency, encryption, retention, deletion,
  access-control, and audit requirements.
- Do not enable `allowCustomBaseURL` unless the origin is trusted with both keys and media.
- Redirects are never followed, so credentials and media are not forwarded to another
  origin.
- The default ephemeral `URLSession` never caches responses to disk.
- Minimize production logging. Prefer transaction IDs and normalized status fields over
  `raw`, server messages, file paths, filenames, or media bytes.
- Do not treat low risk as proof, or high risk as the only reason for an adverse decision.

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

**`.validation(code: .apiKeyRequired)`**

`fromEnvironment()` could not find `NEURALDEFEND_API_KEY`, or the key passed to the
initializer is empty. Set the variable in the same environment that starts the process
(in Xcode: **Product > Scheme > Edit Scheme > Run > Arguments**), or pass the key
explicitly.

**`.authentication` with "Invalid API key"**

The key is wrong, expired, or for the other environment. Staging keys work only with
`NeuroVerifyClient.staging`.

**`.scope`**

The key does not have access to the endpoint. Request the required image or video scope
during onboarding.

**`.validation(code: .filenameRequired)`**

Pass a filename with the real extension, for example `.data(bytes, filename: "photo.jpg")`.

**`.validation(code: .customBaseURLRequiresOptIn)`**

Set `allowCustomBaseURL: true` only for a proxy or mock server you trust.

**HTTP 200 but no score**

Inspect `status`, `statusCode`, and the result message. No-face and face-policy outcomes
are expected business rejections, not transport success indicators.

**No audio score**

Check `hasAudio` and `audioMessage`. `"No audio track detected"` means video scoring
succeeded without an audio modality. A no-face video rejection suppresses both modalities.

**Repeated `.rateLimit`**

Inspect `RateLimitInfo`, reduce concurrency, and confirm tenant limits with your account
manager. The SDK has already used its configured retries when the error is thrown.

**`.timeout` on large videos over slow networks**

Raise `timeout`. It applies to each attempt, not to the whole call. Timeouts are not
retried automatically because the server may already have accepted a billable request.

**Uploads stop when the app goes to the background**

The client uses a foreground `URLSession`. Keep the app active, or upload from your backend.

**Linux build or runtime errors about networking**

Install the Swift toolchain's Foundation dependencies (`libcurl` and `libxml2`), or use the
official `swift:6.0` container image.

**Security or quality rejection**

Do not retry the same media. Correct the format, dimensions, quality, face count, or
security issue indicated by the result message, then submit only if a new request is
appropriate.

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

For the exhaustive HTTP envelopes, status codes, risk-band descriptions, messages,
billability scenarios, and request examples, see:

- [Unified Face Authenticity Score](../../docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](../../docs/client/unified-video-authenticity.md)
- [OpenAPI contract](../../spec/public.yaml)

The wire API uses an outer endpoint-specific envelope, snake_case field names, and
`"Y"`/`"N"` billing strings. The Swift SDK intentionally normalizes those details in
`ImageResult` and `VideoResult`.

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the SDK version (`NeuroVerifyClient.sdkVersion`), endpoint,
`requestID` or `uniqueTrxID`, and a sanitized reproduction. Do not send API keys, raw
customer media, or biometric/personal data.

## License

MIT. See [LICENSE](LICENSE).
