# Neural Defend NeuroVerify SDK for Kotlin, Java, and Android

The official JVM and Android client for the Neural Defend NeuroVerify image and video
authenticity APIs. It provides:

- typed, normalized image and video results;
- coroutine (`suspend`) APIs for Kotlin and a callback/blocking `NeuroVerifyCall` API for
  Java;
- streaming multipart uploads from files, bytes, replayable streams, and Android content
  `Uri`s from the photo picker or camera;
- upload progress, cancellation, timeouts, rate-limit handling, and controlled retries;
  and
- forward-compatible handling of response statuses and risk bands introduced by newer
  API versions.

Risk scores and risk bands are decision-support signals. They are not proof that media is
authentic or manipulated, and they should never be the sole basis for an automatic
acceptance, rejection, or adverse decision. Combine them with other evidence, policy
checks, and human review appropriate to your use case.

## Requirements

| Artifact | Use it for | Requirements |
| --- | --- | --- |
| `com.neuraldefend:neuraldefend:1.0.0` | JVM servers, CLIs, desktop apps, and Android | Java 8 or newer; Kotlin 2.1 or newer when called from Kotlin |
| `com.neuraldefend:neuraldefend-android:1.0.0` | Android apps that upload content `Uri`s | Android 5.0 (API 21) or newer; includes the JVM artifact |

You also need a Neural Defend API key with access to the image and/or video endpoint.

Runtime dependencies are OkHttp 4.12 or newer (OkHttp 5 also works), kotlinx-coroutines
1.9 or newer, and kotlinx-serialization-json 1.7.3 or newer. These are minimum versions,
so your app can use newer releases. The SDK uses no reflection and needs no R8 or ProGuard
rules.

## Installation

Gradle (Kotlin DSL):

```kotlin
dependencies {
    implementation("com.neuraldefend:neuraldefend:1.0.0")
    // Android apps that upload photo-picker or camera content:
    implementation("com.neuraldefend:neuraldefend-android:1.0.0")
}
```

Maven:

```xml
<dependency>
  <groupId>com.neuraldefend</groupId>
  <artifactId>neuraldefend</artifactId>
  <version>1.0.0</version>
</dependency>
```

Both artifacts are published to Maven Central and signed with the Neural Defend release
key.

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key on Maven Central. Request access from the company first, then configure
the SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media analysis,
   and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key or
   staging credential.
3. On a server, store the key in a secret manager or `NEURALDEFEND_API_KEY`. In Android
   apps, read [Android credential safety](#android-credential-safety) first.
4. For REST endpoint reference, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## Choose where the SDK runs

| Where you call NeuroVerify | Recommended | Key handling |
| --- | --- | --- |
| JVM backend (Ktor, Spring, Micronaut, Quarkus, Cloud Run) | Yes | `NEURALDEFEND_API_KEY` or a secret manager |
| Your backend, called by an Android app | Yes | Use this SDK (or the Python, TypeScript, Go, or Dart SDK) on the server |
| Android app calling NeuroVerify directly | Only with a credential Neural Defend has approved for client use | Pass `apiKey` explicitly; the SDK never reads environment variables on Android |

## Quick start (Kotlin on a server)

```kotlin
import com.neuraldefend.MediaInput
import com.neuraldefend.NeuroVerifyClient
import com.neuraldefend.ResultStatus
import java.io.File

suspend fun main() {
    // Reads NEURALDEFEND_API_KEY when apiKey is omitted.
    NeuroVerifyClient().use { client ->
        val image = client.detectImage(MediaInput.file(File("selfie.jpg")))
        when (image.status) {
            ResultStatus.SUCCESS -> println("${image.riskLevel} risk (${image.riskScore}): ${image.message}")
            ResultStatus.REJECTED -> println("Not scored (billable: ${image.billable}): ${image.message}")
            ResultStatus.UNKNOWN -> println("Unrecognized outcome \"${image.originalStatus}\"; upgrade the SDK.")
        }

        val video = client.detectVideo(MediaInput.file(File("clip.mp4")), maxFrames = 24)
        if (video.scored) {
            val audio = if (video.hasAudio) video.audioRiskLevel.toString() else "none"
            println("video: ${video.videoRiskLevel}, audio: $audio")
        }
    }
}
```

Create one client and reuse it: it holds a connection pool. `close()` releases it.

## Quick start (Java)

```java
import com.neuraldefend.ImageResult;
import com.neuraldefend.MediaInput;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.NeuroVerifyError;
import java.io.File;
import java.util.concurrent.TimeUnit;

try (NeuroVerifyClient client = NeuroVerifyClient.builder()
        .apiKey(System.getenv("NEURALDEFEND_API_KEY"))
        .timeout(60, TimeUnit.SECONDS)
        .build()) {
    ImageResult image = client.newImageCall(MediaInput.file(new File("selfie.jpg"))).execute();
    if (image.isScored()) {
        System.out.println(image.getRiskLevel() + " " + image.getRiskScore());
    }
} catch (NeuroVerifyError error) {
    System.err.println(error); // The API key is never included.
}
```

`execute()` blocks the calling thread. To stay asynchronous, use `enqueue`:

```java
NeuroVerifyCall<VideoResult> call = client.newVideoCall(MediaInput.file(new File("clip.mp4")));
call.enqueue(new NeuroVerifyCallback<VideoResult>() {
    @Override public void onResult(NeuroVerifyCall<VideoResult> call, VideoResult result) { /* ... */ }
    @Override public void onFailure(NeuroVerifyCall<VideoResult> call, NeuroVerifyError error) { /* ... */ }
});
// Later, if the user gives up:
call.cancel(); // onFailure receives AbortError.
```

Callbacks run on a background thread. Each call can run once.

## Android quick start

The photo picker, `GetContent`, `OpenDocument`, and the camera's `TakePicture` and
`CaptureVideo` all return content `Uri`s. `MediaInputs.fromUri` reads the display name and
size from the content provider and streams the content, reopening it for each retry, so
large videos are never loaded into memory:

```kotlin
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import com.neuraldefend.android.MediaInputs

class CheckViewModel(private val client: NeuroVerifyClient) : ViewModel() {
    fun check(context: Context, uri: Uri) {
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                client.detectImage(MediaInputs.fromUri(context, uri)) { sent, total ->
                    // Upload progress for the current attempt.
                }
            }
            // Show result.status, result.riskLevel, and result.message.
        }
    }
}

// In a composable:
val picker = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
    if (uri != null) viewModel.check(context, uri)
}
picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly))
```

Cancelling the coroutine (for example, when `viewModelScope` is cleared) cancels the
upload and any retry wait. The `neuraldefend-android` artifact declares the `INTERNET`
permission for you.

A complete Compose app with the photo picker, progress, cancellation, and error messages
is in [`example`](example).

To share your app's HTTP stack (connection pool, interceptors, certificate pinning), pass
it to the builder. The SDK derives its own settings from it and does not shut it down:

```kotlin
val client = NeuroVerifyClient(apiKey = key) { okHttpClient(appOkHttpClient) }
```

## Android credential safety

> **Never ship a long-lived production API key in an Android app, `BuildConfig` field,
> resource, asset, native library, or remote config. Anyone who installs the app can
> extract it.**

Android apps require an explicit `apiKey`. The SDK never reads environment variables on
Android. The public API contract does not define a credential-issuance endpoint for client
apps, so do not invent a client-side key exchange based on this README.

For normal apps, upload media to your authenticated backend and call NeuroVerify from the
server. Your backend can then enforce user authorization, quotas, audit logging, file
limits, and abuse controls:

```kotlin
// In the app: stream the picked file to your own backend with your user's session.
val body = object : RequestBody() {
    override fun contentType() = context.contentResolver.getType(uri)?.toMediaTypeOrNull()
    override fun writeTo(sink: BufferedSink) {
        context.contentResolver.openInputStream(uri)!!.source().use { sink.writeAll(it) }
    }
}
val request = Request.Builder()
    .url("https://api.example.com/media-authenticity/image")
    .header("authorization", "Bearer $sessionToken")
    .post(MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("file", name, body).build())
    .build()

// On the server (Ktor, Spring, ...): call NeuroVerify with the key from your secret store.
val result = client.detectImage(MediaInput.stream(length, filename) { upload.openStream() })
```

Call the SDK directly from an app only when Neural Defend has explicitly approved a
client-exposable credential for your tenant, or during development with a staging key.

## API key configuration (JVM)

```sh
# macOS/Linux
export NEURALDEFEND_API_KEY="your-api-key"
```

```powershell
# PowerShell
$env:NEURALDEFEND_API_KEY = "your-api-key"
```

On a JVM (not on Android), the client reads `NEURALDEFEND_API_KEY` when no `apiKey` is set
and `NEURALDEFEND_BASE_URL` when no `baseUrl` is set. Never commit keys to source control,
example files, container images, or shell history.

## Method reference

### Creating a client

```kotlin
val client = NeuroVerifyClient(apiKey = key) {      // Kotlin
    timeout(60.seconds)
    maxRetries(1)
}
NeuroVerifyClient client = NeuroVerifyClient.builder().apiKey(key).build();  // Java
```

| Builder option | Default | Description |
| --- | --- | --- |
| `apiKey` | `NEURALDEFEND_API_KEY` (JVM only) | Sent in the `x-api-key` header; redacted from errors, `toString()`, and diagnostics |
| `baseUrl` | `NEURALDEFEND_BASE_URL` (JVM only), then `https://deepscan.neuraldefend.com` | HTTPS origin without a path, query, fragment, or credentials |
| `allowCustomBaseUrl` | `false` | Required for any origin other than the production or staging API, because it receives the key and media |
| `timeout` | 120 seconds | Applies to each attempt: connecting, uploading, and reading the response |
| `maxRetries` | `3` | Retries after the first attempt for HTTP 429, 500, and 503 (`0` through `3`) |
| `retryAfterCap` | 60 seconds | Longest `Retry-After` wait the SDK honors |
| `userAgent` | `neuraldefend-kotlin/1.0.0` | Sent as `User-Agent` |
| `okHttpClient` | SDK-owned client | Shared `OkHttpClient`; redirects and transport retries are always disabled |
| `onWarning` | ignored | Receives non-fatal `ValidationWarning`s such as `unsupported_extension` |

Invalid configuration throws `ValidationError` from `build()`.

### Staging

`NeuroVerifyClient.staging(apiKey)`, or `builder().staging()`, pins the client to
`https://stage.deepscan.neuraldefend.com` and ignores `NEURALDEFEND_BASE_URL`. Use it only
with a staging credential.

### `detectImage(media, onProgress)`

`suspend` function. Uploads one image to `/detect/image` and returns `ImageResult`. Java
code uses `newImageCall(media, onProgress)`.

### `detectVideo(media, maxFrames, sampleRate, onProgress)`

`suspend` function. Uploads one video to `/detect/video` and returns `VideoResult`.
`maxFrames` is an integer from 1 through 100 (API default 12); `sampleRate` is an integer
of at least 1. Java code uses `newVideoCall(...)`.

`onProgress(sentBytes, totalBytes)` reports upload progress for the current attempt. It
restarts at zero if an automatic retry begins, and runs on an OkHttp thread.

### `NeuroVerifyCall`

| Method | Description |
| --- | --- |
| `execute()` | Blocks until the result is ready. Never call it on the Android main thread |
| `enqueue(callback)` | Runs in the background and calls `onResult` or `onFailure` exactly once |
| `cancel()` | Cancels preparation, the upload, retry waits, and response processing. The call fails with `AbortError` |
| `isCanceled()` | Whether `cancel()` was called |

### `close()`

Releases the SDK-owned connection pool and threads. Later calls throw
`IllegalStateException`. A caller-supplied `OkHttpClient` is left open.

### Media inputs

| Input | Retries | Notes |
| --- | --- | --- |
| `MediaInput.file(file, filename?)` | Yes | Symbolic links and non-regular files are rejected |
| `MediaInput.bytes(bytes, filename)` | Yes | The array is not copied; do not change it during the upload |
| `MediaInput.stream(length, filename) { open() }` | Yes | The supplier is called once per attempt and must return the same bytes |
| `MediaInput.singleUseStream(stream, length, filename)` | No | Requires `maxRetries(0)` |
| `MediaInputs.fromUri(context, uri, filename?)` (Android artifact) | Yes | Content and `file://` Uris; call it off the main thread |

`filename` must include the real extension, because the API uses it for format checks.
`length` must equal the number of bytes the stream produces, or the upload fails with a
`ValidationError`.

## Working with results

### Normalized fields

Every `ImageResult` and `VideoResult` has:

| Field | Meaning |
| --- | --- |
| `status` | `ResultStatus.SUCCESS`, `REJECTED`, or `UNKNOWN`. Always branch on this first |
| `scored` / `rejected` | Convenience booleans for the first two statuses (`isScored()` / `isRejected()` in Java) |
| `originalStatus` | Exact wire `status`, useful for `UNKNOWN` results |
| `uniqueTrxId` | Transaction ID. Persist it for audit, billing, and support |
| `billable` | Authoritative billing indicator. Rejections can be billable |
| `filename`, `contentType`, `statusCode` | Echoed by the service; unknown `statusCode` values are preserved |
| `aiThreatSignals` | Checks the service reports. The list may evolve |
| `raw` | Redacted, unmodifiable wire envelope for diagnostics. Not a stable contract |

`ImageResult` adds `riskScore`, `riskLevel`, `originalRiskLevel`, `message`, and
`highRisk`.

`VideoResult` adds `videoRiskScore`, `videoRiskLevel`, `videoMessage`, `audioRiskScore`,
`audioRiskLevel`, `audioMessage`, `hasAudio`, `overallRiskScore`, and the matching
`original*RiskLevel` fields. Video and audio are independent modalities.
`overallRiskScore` is an SDK convenience (the higher available score); the API does not
return a combined score.

`riskLevel` is `RiskLevel.LOW`, `MEDIUM`, or `HIGH`, or `null` when the result is not
scored or the band is new to this SDK version.

`toJson()` returns the normalized fields with camelCase names and excludes `raw`:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_low",
  "filename": "selfie.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "riskScore": 2.2,
  "riskLevel": "low",
  "message": "Not likely to be Spoof or AI-generated",
  "highRisk": false
}
```

Scores and messages vary with submitted media and service evolution. Do not write policy
against example numbers or exact message text. Use the returned band rather than
reconstructing it from score thresholds.

### Outcomes

- **Low, medium, or high**: `status` is `SUCCESS`. Interpret low as lower observed risk,
  not proof of authenticity. Treat medium as inconclusive. Treat high as a reason to
  escalate or review, not as sufficient evidence for automatic rejection.
- **No face or multiple faces**: a billable HTTP 200 rejection (`status` is `REJECTED`).
- **Quality, format, size, or security failures**: normally a non-billable HTTP 400
  rejection. These are results, not exceptions.
- **Video with no audio track**: can still be scored; `hasAudio` is `false` and
  `audioMessage` explains why.
- **Video with no scorable single-face frame**: a no-face rejection; audio is not scored.
- **Unknown status or risk band from a newer API**: `status` is `UNKNOWN`, with the wire
  values in `originalStatus` and `original*RiskLevel`. Do not make a policy decision from
  it. Record the transaction ID and upgrade the SDK.

## Errors

All SDK errors extend the sealed class `NeuroVerifyError` (an `Exception`) and expose
`detail`. HTTP-derived errors can also expose `statusCode` and `requestId`.

- `ValidationError`: local configuration, option, filename, input, empty-file, or size
  validation failed. Its `code` is a `ValidationErrorCode`. Correct the input; do not retry
  it unchanged.
- `AuthenticationError`: HTTP 401. Check that the key is active and belongs to the selected
  environment. Not retried.
- `ScopeError`: HTTP 403. The key lacks endpoint or plan access. Not retried.
- `RateLimitError`: HTTP 429 after retries are exhausted. Exposes `retryAfterMillis` plus
  string `limit`, `remaining`, and `reset` metadata.
- `TimeoutError`: the per-attempt timeout elapsed. Not retried.
- `NetworkError`: no response was received (DNS, connectivity, TLS). Not retried.
- `ServerError`: HTTP 500/503 after retries are exhausted, or a wire result with
  `status: "error"`. May expose a redacted `raw` envelope.
- `ProtocolError`: the response was malformed or missing required fields. Retain the
  request or transaction ID and contact support if it persists.
- `AbortError`: `NeuroVerifyCall.cancel()` was called. Coroutine cancellation instead
  throws the standard `CancellationException`, as Kotlin expects.
- `HttpError`: another unexpected HTTP status. The specific HTTP errors extend it.

```kotlin
try {
    val result = client.detectImage(MediaInput.file(File("selfie.jpg")))
    // Handle result.status here.
} catch (error: NeuroVerifyError) {
    when (error) {
        is ValidationError -> println("Fix the request: ${error.code} ${error.detail}")
        is AuthenticationError -> println("Check the API key.")
        is ScopeError -> println("Request image endpoint access.")
        is RateLimitError -> println("Rate limit exhausted. Retry after ${error.retryAfterMillis} ms.")
        is ServerError -> println("Service error ${error.statusCode}, request ${error.requestId}.")
        is HttpError -> println("Unexpected HTTP ${error.statusCode}.")
        is TimeoutError -> println("The request timed out.")
        is NetworkError -> println("No response was received.")
        is ProtocolError -> println("Unexpected response contract, request ${error.requestId}.")
        is AbortError -> println("Cancelled by the caller.")
    }
}
```

## Retries, billing, and idempotency

By default, the SDK makes the initial request and up to three retries:

- HTTP 500 and 503 wait about 1, 2, and 4 seconds, with up to 25% jitter.
- HTTP 429 honors a numeric or HTTP-date `Retry-After` value up to `retryAfterCap`;
  without a valid header it waits 1, 2, and 4 seconds.
- HTTP 400, 401, 403, other statuses, timeouts, protocol failures, cancellations, and
  network failures are not retried.

Set `maxRetries(0)` to disable automatic retries.

Requests are not idempotent. Every accepted attempt can receive a new `uniqueTrxId`, and
resubmitting the same media, including automatic retries, may create separate
transactions with separate billing. `billable` is authoritative for the returned
transaction. Persist `uniqueTrxId` with your audit record and avoid application-level
retries unless you have accounted for duplicate processing and billing.

The SDK never follows redirects, so the API key and media are only sent to the configured
origin.

## Media formats and limits

Image uploads:

- Extensions: `.jpg`, `.jpeg`, `.png`, `.bmp`, `.tif`, `.tiff`, `.webp`, `.heic`, `.heif`
- Exact maximum: 10 MiB (`10,485,760` bytes)
- API minimum resolution: 224 by 224 pixels
- Face policy: exactly one face

Video uploads:

- Extensions: `.mp4`, `.avi`, `.mov`, `.mkv`, `.wmv`, `.flv`, `.webm`, `.ogg`, `.ogv`
- Exact maximum: `1,500,000,000` bytes
- Default frame sample maximum: `12`
- Face policy: sampled frames with multiple faces are skipped; at least one scorable
  single-face frame is required

The SDK rejects empty and oversized input locally. It warns through `onWarning`, but does
not reject, an undocumented extension, because the server performs content and security
validation. Known extensions select deterministic MIME types; unknown extensions use
`application/octet-stream`. `MediaInput.IMAGE_EXTENSIONS`, `VIDEO_EXTENSIONS`,
`IMAGE_MAX_BYTES`, `VIDEO_MAX_BYTES`, and `MediaInput.mimeTypeFor(filename)` are public for
validating input before upload.

Camera apps and the photo picker may hand you HEIC photos or transcoded videos. Keep the
provider's display name so the extension matches the content.

## Security and privacy

- Upload media only with the data owner's authorization and an appropriate legal basis.
- Treat images, video, audio, filenames, transaction IDs, and diagnostics as potentially
  sensitive data. Face media may be biometric personal data.
- Apply your organization's consent, purpose limitation, retention, deletion, residency,
  encryption, access-control, and incident-response requirements.
- Keep production API keys in a managed secret store, rotate them, scope them to required
  endpoints and environments, and never expose them to an untrusted client.
- Authenticate and authorize users before accepting uploads through your backend.
- Avoid routine logging of `result.raw`, server messages, local paths, or filenames.
- Do not enable `allowCustomBaseUrl` unless the destination is trusted to receive both
  credentials and media.
- Do not use low risk as proof, or high risk as the sole reason for an adverse action.
  Design a review and appeal path for consequential decisions.

## Troubleshooting

**`ValidationErrorCode.API_KEY_REQUIRED`**

On a JVM, set `NEURALDEFEND_API_KEY` before creating the client or call `apiKey(...)`.
Android apps always require an explicit key.

**`ValidationErrorCode.FILENAME_REQUIRED`**

Pass a filename with the real extension, such as `"photo.jpg"`.

**`ValidationErrorCode.FILE_TOO_LARGE` or `EMPTY_FILE`**

Check the byte limits before upload.

**`ValidationErrorCode.FILE_NOT_FOUND` from `MediaInputs.fromUri`**

The Uri no longer exists or the app lost permission to read it. Photo-picker grants are
temporary; upload while the grant is valid, or copy the content into app storage first.

**`ValidationErrorCode.UNSUPPORTED_INPUT` from `MediaInputs.fromUri`**

The provider did not report a size. Copy the content to a file in `cacheDir` and use
`MediaInput.file`.

**`ValidationErrorCode.STREAM_NOT_REPLAYABLE`**

`MediaInput.singleUseStream` can be read only once. Use `MediaInput.stream`,
`MediaInput.bytes`, or `MediaInput.file` to allow retries, or set `maxRetries(0)`.

**`NetworkOnMainThreadException` or a frozen UI**

Call `suspend` functions from a coroutine and `execute()` only from a background thread.

**Image returns no face or multiple faces**

Use a well-lit, in-focus image at least 224 by 224 pixels with one clearly visible subject.

**401 or 403**

Confirm the key's environment, validity, endpoint scope, and plan access. Production and
staging keys may not be interchangeable.

**429**

The SDK already retries up to `maxRetries` and honors `Retry-After` up to the configured
cap. After `RateLimitError`, reduce concurrency instead of retrying in a loop.

**Timeout or network error**

Check connectivity. For large videos on mobile networks, choose a realistic `timeout`. The
SDK does not retry these failures because the server may already have accepted the media.

**`ProtocolError` or `ResultStatus.UNKNOWN`**

Upgrade the SDK. If the issue persists, give support the SDK version and the request or
transaction ID.

## Development

The build needs JDK 21 to run Gradle and an Android SDK with platform 37 for the Android
modules. Set `ANDROID_HOME` or write `sdk.dir=...` to `local.properties`.

```sh
./gradlew check                                  # JVM, Robolectric, lint, and ABI checks
./gradlew -Pneuraldefend.jvmOnly=true :neuraldefend:check   # no Android SDK needed
./gradlew :example:connectedDebugAndroidTest     # instrumented tests on a device or emulator
./gradlew centralBundle                          # unsigned Maven Central bundle in build/central
```

Run the JVM tests on another JDK with
`-Pneuraldefend.testJavaVersion=8 -Porg.gradle.java.installations.paths=/path/to/jdk8`, and
against the newest OkHttp, coroutines, and serialization releases with
`-Pneuraldefend.latestDependencies=true`.

The public API is tracked in `neuraldefend/api/neuraldefend.api`. After an intentional API
change, run `./gradlew updateKotlinAbi` and commit the result.

Staging smoke tests run their scored cases only when `NEURALDEFEND_STAGING_API_KEY` is set:

```sh
NEURALDEFEND_STAGING_API_KEY=... ./gradlew -Pneuraldefend.jvmOnly=true :neuraldefend:stagingTest
```

The private generated contract under `generated/core/` is produced by
`scripts/generate.py` and must never be edited by hand. It is used only to detect contract
drift and is not compiled into the published artifacts.

## Wire-level API documentation

For exhaustive response scenarios, wire field names, status codes, and current messages,
see:

- [Unified Face Authenticity Score](https://github.com/Neural-Defend/NeuralDefend-SDKs/blob/main/docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](https://github.com/Neural-Defend/NeuralDefend-SDKs/blob/main/docs/client/unified-video-authenticity.md)

## License

MIT. See [LICENSE](LICENSE).
