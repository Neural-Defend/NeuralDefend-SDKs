<div align="center">

# NeuralDefend Kotlin and Android SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Kotlin, Java, and Android in a few lines of code.**

[![Maven Central](https://img.shields.io/maven-central/v/com.neuraldefend/neuraldefend-kotlin?style=flat-square&logo=apachemaven&logoColor=white&label=Maven%20Central&color=C71A36)](https://central.sonatype.com/artifact/com.neuraldefend/neuraldefend-kotlin)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.1%2B-7F52FF?style=flat-square&logo=kotlin&logoColor=white)](https://kotlinlang.org/)
[![Android](https://img.shields.io/badge/Android-API%2021%2B-34A853?style=flat-square&logo=android&logoColor=white)](https://developer.android.com/)
[![JVM](https://img.shields.io/badge/JVM-Java%208%2B-007396?style=flat-square&logo=openjdk&logoColor=white)](https://openjdk.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start-jvm-image) · [Examples](#examples) · [Results](#working-with-results) · [Errors](#errors) · [Troubleshooting](#troubleshooting)

</div>

---

## In plain words

You give the SDK a photo or a video. It sends the file to Neural Defend's **NeuroVerify**
service and gives you back an answer like this:

> "This face has a **low** / **medium** / **high** risk of being fake."

That is the whole idea. You do not need to know anything about machine learning, HTTP, or
file uploads; the SDK handles all of that for you.

| You want to... | Call | You get back |
|---|---|---|
| Check a photo of a face | `client.detectImage(MediaInput.file(File("photo.jpg")))` | An `ImageResult` with one risk level |
| Check a video | `client.detectVideo(MediaInput.file(File("clip.mp4")))` | A `VideoResult` with a video risk and an audio risk |
| Check a photo the user picked on Android | `client.detectImage(MediaInputs.fromUri(context, uri))` | An `ImageResult` with one risk level |

Both `detectImage` and `detectVideo` are `suspend` functions, so you call them from a
coroutine. Java code (or any code that cannot use coroutines) uses `newImageCall(...)` and
`newVideoCall(...)` instead; see [Quick start: Java](#quick-start-java).

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `RiskLevel.LOW` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `RiskLevel.MEDIUM` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `RiskLevel.HIGH` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection** (`ResultStatus.REJECTED`), not a
crash. The [examples](#examples) show how to handle each case.

## About this SDK

The official Kotlin and Android client for the Neural Defend NeuroVerify image and video
authenticity APIs. Java-first projects should use the
[Java SDK](../java/README.md) (`com.neuraldefend:neuraldefend-sdk`) instead. The two SDKs
use different packages (`com.neuraldefend.kotlin` and `com.neuraldefend`), so they can
share a classpath. Version `1.0.0` provides:

- typed, normalized image and video results;
- coroutine (`suspend`) APIs for Kotlin and a callback/blocking `NeuroVerifyCall` API for
  Java;
- streaming multipart uploads from files, bytes, replayable streams, and Android content
  `Uri`s from the photo picker or camera;
- upload progress, cancellation, timeouts, rate-limit handling, and controlled retries;
  and
- forward-compatible handling of response statuses and risk bands introduced by newer
  API versions.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an exception, including some HTTP 200 responses.
- `billable` is the authoritative billing indicator for each returned transaction.

Risk scores and risk bands are not proof that media is authentic or manipulated, and they
should never be the sole basis for an automatic acceptance, rejection, or adverse
decision. Combine them with other evidence, policy checks, and human review appropriate to
your use case.

## Requirements

| Artifact | Use it for | Requirements |
| --- | --- | --- |
| `com.neuraldefend:neuraldefend-kotlin:1.0.0` | JVM servers, CLIs, desktop apps, and Android | Java 8 or newer; Kotlin 2.1 or newer when called from Kotlin |
| `com.neuraldefend:neuraldefend-android:1.0.0` | Android apps that upload content `Uri`s | Android 5.0 (API 21) or newer; includes the JVM artifact |

You also need a Neural Defend API key with access to the image and/or video endpoint, and
network access to the HTTPS API origin.

Runtime dependencies are OkHttp 4.12 or newer (OkHttp 5 also works), kotlinx-coroutines
1.9 or newer, and kotlinx-serialization-json 1.7.3 or newer. These are minimum versions,
so your app can use newer releases. The SDK uses no reflection and needs no R8 or ProGuard
rules.

## Installation

Gradle (Kotlin DSL), for a JVM server, CLI, or desktop app:

```kotlin
dependencies {
    implementation("com.neuraldefend:neuraldefend-kotlin:1.0.0")
}
```

Gradle (Groovy DSL):

```groovy
dependencies {
    implementation 'com.neuraldefend:neuraldefend-kotlin:1.0.0'
}
```

Maven:

```xml
<dependency>
  <groupId>com.neuraldefend</groupId>
  <artifactId>neuraldefend-kotlin</artifactId>
  <version>1.0.0</version>
</dependency>
```

Android app module (`app/build.gradle.kts`). The Android artifact already includes
`neuraldefend-kotlin` and adds `MediaInputs.fromUri` for photo-picker and camera content:

```kotlin
dependencies {
    implementation("com.neuraldefend:neuraldefend-android:1.0.0")
}
```

Both artifacts are published to Maven Central and signed with the Neural Defend release
key. Make sure `mavenCentral()` is listed in your repositories.

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
3. On a server, store the key in a secret manager or the `NEURALDEFEND_API_KEY`
   environment variable. In Android apps, read
   [Android credential safety](#android-credential-safety) first.
4. For REST endpoint reference, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## API key configuration (JVM)

macOS/Linux:

```sh
# Request a key at https://neuraldefend.com/ (Book a Demo), then export it:
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
```

PowerShell:

```powershell
# Request a key at https://neuraldefend.com/ (Book a Demo), then set it:
$env:NEURALDEFEND_API_KEY = "replace-with-your-api-key"
```

On a JVM (not on Android), the client reads `NEURALDEFEND_API_KEY` when no `apiKey` is set
and `NEURALDEFEND_BASE_URL` when no `baseUrl` is set. An explicit `apiKey` always takes
precedence. Never commit keys to source control, example files, container images, or
shell history.

## Choose where the SDK runs

| Where you call NeuroVerify | Recommended | Key handling |
| --- | --- | --- |
| JVM backend (Ktor, Spring, Micronaut, Quarkus, Cloud Run) | Yes | `NEURALDEFEND_API_KEY` or a secret manager |
| Your backend, called by an Android app | Yes | Use this SDK (or the Python, TypeScript, Go, or Dart SDK) on the server |
| Android app calling NeuroVerify directly | Only with a credential Neural Defend has approved for client use | Pass `apiKey` explicitly; the SDK never reads environment variables on Android |

## Quick start: JVM image

Save this as `DetectImage.kt`, set `NEURALDEFEND_API_KEY`, and run it with the image path
as the first argument.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import com.neuraldefend.kotlin.ResultStatus
import java.io.File

suspend fun main(args: Array<String>) {
    require(args.size == 1) { "usage: DetectImage IMAGE_PATH" }

    // Reads NEURALDEFEND_API_KEY when apiKey is omitted.
    // Get a key from https://neuraldefend.com/ (Book a Demo).
    NeuroVerifyClient().use { client ->
        val image = client.detectImage(MediaInput.file(File(args[0])))

        println(image.toJson())   // normalized fields; never includes the API key or raw envelope

        when (image.status) {
            ResultStatus.SUCCESS -> println("image risk: ${image.riskLevel} (${image.riskScore})")
            ResultStatus.REJECTED -> println("image was not scored (billable: ${image.billable}): ${image.message}")
            ResultStatus.UNKNOWN -> println("unrecognized outcome \"${image.originalStatus}\"; upgrade the SDK")
        }
    }
}
```

Output:

```text
{status=success, scored=true, rejected=false, uniqueTrxId=trx_example_image_low, filename=selfie.jpg, contentType=image/jpeg, statusCode=1, billable=true, aiThreatSignals=[Visual Safety Screening, Liveness Verification], riskScore=2.2, riskLevel=low, message=Not likely to be Spoof or AI-generated, highRisk=false}
image risk: LOW (2.2)
```

Create one client and reuse it: it holds a connection pool. `use { }` (or `close()`)
releases it.

## Quick start: JVM video

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File

suspend fun main(args: Array<String>) {
    require(args.size == 1) { "usage: DetectVideo VIDEO_PATH" }

    NeuroVerifyClient().use { client ->
        val video = client.detectVideo(MediaInput.file(File(args[0])), maxFrames = 24, sampleRate = 2)

        if (video.scored) {
            println("video risk: ${video.videoRiskLevel} (${video.videoRiskScore})")
            if (video.hasAudio) {
                println("audio risk: ${video.audioRiskLevel} (${video.audioRiskScore})")
            } else {
                println("audio not scored: ${video.audioMessage}")
            }
            println("maximum modality score: ${video.overallRiskScore}")
        } else if (video.rejected) {
            println("video was not scored: ${video.videoMessage}")
        } else {
            println("unrecognized outcome \"${video.originalStatus}\"; upgrade the SDK")
        }
    }
}
```

Output:

```text
video risk: LOW (2.2)
audio risk: HIGH (8.4)
maximum modality score: 8.4
```

`overallRiskScore` is a client-side convenience equal to the higher available modality
score. It is not a combined score returned by the API and does not replace
modality-aware policy.

## Quick start: Java

```java
import com.neuraldefend.kotlin.ImageResult;
import com.neuraldefend.kotlin.MediaInput;
import com.neuraldefend.kotlin.NeuroVerifyClient;
import com.neuraldefend.kotlin.NeuroVerifyError;
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

Output:

```text
LOW 2.2
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

## Quick start: Android

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
permission for you. [Example 8](#8-android-photo-picker-to-verdict) is a complete,
runnable version with screen state and error messages, and a full Compose app with
progress and cancellation is in [`example`](example).

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

[Example 9](#9-add-a-check-to-a-spring-boot-endpoint) shows a complete server endpoint.
Call the SDK directly from an app only when Neural Defend has explicitly approved a
client-exposable credential for your tenant, or during development with a staging key.

## Examples

Each example is complete: copy it into your project, set `NEURALDEFEND_API_KEY` (JVM
examples), and run it. The output shown under each example is representative; your
scores, transaction IDs, and messages will differ. Printing a `RiskLevel` shows the enum
name (`LOW`); use `riskLevel?.wireValue` when you want the lower-case API value (`low`).

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Check one photo](#1-check-one-photo) | The smallest useful program |
| 2 | [Check a video with sound](#2-check-a-video-with-sound) | Reading the separate video and audio results |
| 3 | [Turn a result into a decision](#3-turn-a-result-into-a-decision) | Mapping low, medium, high, and rejected to actions |
| 4 | [Upload a ByteArray from memory](#4-upload-a-bytearray-from-memory) | Checking files that never touch the disk |
| 5 | [Check a whole folder](#5-check-a-whole-folder) | Batch processing with a summary |
| 6 | [Handle every kind of error](#6-handle-every-kind-of-error) | Telling bad input, bad keys, and outages apart |
| 7 | [Save an audit record](#7-save-an-audit-record) | Keeping transaction IDs for billing and support |
| 8 | [Android photo picker to verdict](#8-android-photo-picker-to-verdict) | A ViewModel and Compose screen that checks a picked photo |
| 9 | [Add a check to a Spring Boot endpoint](#9-add-a-check-to-a-spring-boot-endpoint) | Using the SDK inside a server API |
| 10 | [Test against staging](#10-test-against-staging) | Using the staging environment safely |
| 11 | [Tune video sampling](#11-tune-video-sampling) | Trading speed for coverage on long videos |

### 1. Check one photo

The shortest possible program. `use { }` closes the client for you, even if something
goes wrong.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File

suspend fun main() {
    val result = NeuroVerifyClient().use { client ->          // reads NEURALDEFEND_API_KEY
        client.detectImage(MediaInput.file(File("selfie.jpg")))
    }

    println("${result.status} ${result.riskLevel} ${result.riskScore}")
    println(result.message)
}
```

Output:

```text
SUCCESS LOW 2.2
Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** separate answers: one for the picture and one for the audio. A clip
without sound is still scored; only the audio fields are empty.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File

suspend fun main() {
    val result = NeuroVerifyClient().use { client ->
        client.detectVideo(MediaInput.file(File("interview.mp4")))
    }

    if (result.scored) {
        println("Video: ${result.videoRiskLevel} (${result.videoRiskScore})")
        if (result.hasAudio) {
            println("Audio: ${result.audioRiskLevel} (${result.audioRiskScore})")
        } else {
            println("Audio: not scored (${result.audioMessage})")
        }
    } else {
        println("Not scored: ${result.videoMessage}")
    }
}
```

Output:

```text
Video: LOW (2.2)
Audio: HIGH (8.4)
```

Here the face looks real but the voice is likely synthetic, which is why the two
modalities are reported separately.

### 3. Turn a result into a decision

Your application usually needs one of a few actions. Write that mapping once and reuse
it. Always branch on the **risk level**, never on your own numeric threshold, because the
service may tune its scoring bands. Kotlin's `when` makes sure you handle every case.

```kotlin
import com.neuraldefend.kotlin.ImageResult
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import com.neuraldefend.kotlin.ResultStatus
import com.neuraldefend.kotlin.RiskLevel
import java.io.File

fun decide(result: ImageResult): String = when (result.status) {
    ResultStatus.REJECTED -> "ASK FOR A NEW PHOTO - ${result.message}"
    ResultStatus.UNKNOWN -> "MANUAL REVIEW - unrecognized status \"${result.originalStatus}\""
    ResultStatus.SUCCESS -> when (result.riskLevel) {
        RiskLevel.LOW -> "CONTINUE"
        RiskLevel.MEDIUM -> "MANUAL REVIEW"
        RiskLevel.HIGH -> "ESCALATE"
        null -> "MANUAL REVIEW"
    }
}

suspend fun main() {
    NeuroVerifyClient().use { client ->
        for (path in listOf("selfie.jpg", "printed_photo.jpg", "landscape.jpg")) {
            val result = client.detectImage(MediaInput.file(File(path)))
            println("${path.padEnd(20)} -> ${decide(result)}")
        }
    }
}
```

Output:

```text
selfie.jpg           -> CONTINUE
printed_photo.jpg    -> ESCALATE
landscape.jpg        -> ASK FOR A NEW PHOTO - No face detected in the image
```

### 4. Upload a ByteArray from memory

When a file arrives from a message queue, a database, or object storage, you often have
bytes instead of a file. Pass the bytes and a `filename`; the filename's extension tells
the SDK the format.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File

suspend fun main() {
    val imageBytes: ByteArray = File("selfie.jpg").readBytes()   // or bytes from your storage service

    val result = NeuroVerifyClient().use { client ->
        client.detectImage(MediaInput.bytes(imageBytes, "selfie.jpg"))
    }

    println("%,d bytes checked -> %s".format(imageBytes.size, result.riskLevel))
}
```

Output:

```text
482,113 bytes checked -> LOW
```

The array is not copied, so do not change it while the upload runs. For large files,
prefer `MediaInput.file` or `MediaInput.stream`, which stream from disk instead of holding
everything in memory. See [Media inputs](#media-inputs).

### 5. Check a whole folder

Reuse one client for many files; it keeps the connection open and is much faster than
creating a client per file. `MediaInput.IMAGE_EXTENSIONS` lists the supported image
extensions (lower case, without the dot).

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File

suspend fun main() {
    val images = File("uploads").listFiles().orEmpty()
        .filter { it.isFile && it.extension.lowercase() in MediaInput.IMAGE_EXTENSIONS }
        .sortedBy { it.name }
    val summary = mutableMapOf<String, Int>()

    NeuroVerifyClient().use { client ->
        for (file in images) {
            val result = client.detectImage(MediaInput.file(file))
            val outcome = if (result.scored) result.riskLevel?.wireValue ?: "unknown" else result.status.wireValue
            summary.merge(outcome, 1, Int::plus)
            println("${file.name.padEnd(24)} ${outcome.padEnd(9)} ${result.message}")
        }
    }

    println()
    println("Summary: $summary")
}
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: {low=1, rejected=1, medium=1, high=1}
```

Each call is a separate transaction and may be billable. Check your rate limits before
running large batches.

### 6. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation | How it shows up | Who fixes it |
|---|---|---|
| The file was checked but could not be scored | A result with `status == ResultStatus.REJECTED` | The end user sends better media |
| Your setup is wrong (missing key, bad path, no access) | `ValidationError`, `AuthenticationError`, `ScopeError` | You, the developer |
| The service or network had a problem | `RateLimitError`, `ServerError`, `TimeoutError`, `NetworkError` | Try again later |

```kotlin
import com.neuraldefend.kotlin.AuthenticationError
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import com.neuraldefend.kotlin.NeuroVerifyError
import com.neuraldefend.kotlin.RateLimitError
import com.neuraldefend.kotlin.ScopeError
import com.neuraldefend.kotlin.ValidationError
import java.io.File

suspend fun main() {
    try {
        val result = NeuroVerifyClient().use { client ->
            client.detectImage(MediaInput.file(File("selfie.jpg")))
        }
        if (result.rejected) {
            println("Please upload a different photo: ${result.message}")
        } else {
            println("Risk: ${result.riskLevel}")
        }
    } catch (error: NeuroVerifyError) {
        when (error) {
            is ValidationError -> println("Fix the input or configuration: ${error.detail}")
            is AuthenticationError -> println("The API key is invalid or expired. Check NEURALDEFEND_API_KEY.")
            is ScopeError -> println("This key cannot use the image endpoint. Ask Neural Defend to add it.")
            is RateLimitError -> println("Too many requests. Try again in ${error.retryAfterMillis} ms.")
            else -> println("Service problem (${error.javaClass.simpleName}), request id: ${error.requestId}")
        }
    }
}
```

Output when the key is missing:

```text
Fix the input or configuration: apiKey is required; pass it explicitly or set NEURALDEFEND_API_KEY.
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

Because `NeuroVerifyError` is a sealed class, you can also write a `when` with one branch
per error type and no `else`; the [Errors](#errors) section shows that version and lists
every error class.

### 7. Save an audit record

Every result has a `uniqueTrxId`. Store it: it is what support and billing will ask for.
This example writes one JSON line per check using
[kotlinx-serialization-json](https://github.com/Kotlin/kotlinx.serialization); add
`implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")` (or newer) to
your own dependencies to use it.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.time.Instant

suspend fun main() {
    val result = NeuroVerifyClient().use { client ->
        client.detectImage(MediaInput.file(File("selfie.jpg")))
    }

    val record = buildJsonObject {
        put("checkedAt", Instant.now().toString())
        put("transactionId", result.uniqueTrxId)
        put("status", result.status.wireValue)
        put("riskLevel", result.riskLevel?.wireValue)
        put("billable", result.billable)
    }

    File("audit.jsonl").appendText("$record\n")
    println(record)
}
```

Output:

```json
{"checkedAt":"2026-10-16T09:41:07.512310Z","transactionId":"trx_example_image_low","status":"success","riskLevel":"low","billable":true}
```

Store only the fields you need. Avoid logging filenames or `result.raw`, which may contain
personal data.

### 8. Android photo picker to verdict

This is a complete screen: the user taps a button, picks a photo, and sees a verdict.
`detectImage` is a `suspend` function, so the ViewModel calls it from `viewModelScope`.
`MediaInputs.fromUri` and the upload run on `Dispatchers.IO` because content providers can
do disk or network I/O. It needs `neuraldefend-android` plus the usual Compose and
Lifecycle dependencies.

```kotlin
import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.neuraldefend.android.MediaInputs
import com.neuraldefend.kotlin.ImageResult
import com.neuraldefend.kotlin.NetworkError
import com.neuraldefend.kotlin.NeuroVerifyClient
import com.neuraldefend.kotlin.NeuroVerifyError
import com.neuraldefend.kotlin.ResultStatus
import com.neuraldefend.kotlin.RiskLevel
import com.neuraldefend.kotlin.ValidationError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class VerifyPhotoViewModel(private val client: NeuroVerifyClient) : ViewModel() {
    private val _verdict = MutableStateFlow("Pick a photo to check.")
    val verdict: StateFlow<String> = _verdict

    fun check(context: Context, uri: Uri) {
        _verdict.value = "Checking..."
        viewModelScope.launch {
            _verdict.value = try {
                val result = withContext(Dispatchers.IO) {
                    client.detectImage(MediaInputs.fromUri(context, uri))
                }
                describe(result)
            } catch (error: ValidationError) {
                "This file can't be sent: ${error.detail}"
            } catch (error: NetworkError) {
                "Couldn't reach NeuroVerify. Check your connection."
            } catch (error: NeuroVerifyError) {
                "Verification failed. Please try again later."
            }
        }
    }

    private fun describe(result: ImageResult): String = when (result.status) {
        ResultStatus.REJECTED -> "Not analyzed: ${result.message}"
        ResultStatus.UNKNOWN -> "Unrecognized result. Please update the app."
        ResultStatus.SUCCESS -> when (result.riskLevel) {
            RiskLevel.LOW -> "Low risk: ${result.message}"
            RiskLevel.MEDIUM -> "Unclear: sent for review"
            RiskLevel.HIGH -> "High risk: sent for review"
            null -> "Unrecognized result. Please update the app."
        }
    }

    override fun onCleared() {
        client.close()   // only if this ViewModel owns the client
    }
}

@Composable
fun VerifyPhotoScreen(viewModel: VerifyPhotoViewModel) {
    val context = LocalContext.current
    val verdict by viewModel.verdict.collectAsStateWithLifecycle()
    val picker = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
        if (uri != null) viewModel.check(context, uri)
    }

    Column {
        Button(onClick = { picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) }) {
            Text("Choose a photo")
        }
        Text(verdict)
    }
}
```

Create the client once (for example in your `Application` or dependency-injection setup)
and pass it to the ViewModel. Read [Android credential safety](#android-credential-safety)
before deciding which key the app may use:

```kotlin
val client = NeuroVerifyClient.staging(apiKey = stagingKey)   // development only
```

Output (text shown on screen):

```text
Low risk: Not likely to be Spoof or AI-generated
```

If the user picks a photo without a face, the screen shows
`Not analyzed: No face detected in the image`. Leaving the screen clears `viewModelScope`,
which cancels the upload and any retry wait.

### 9. Add a check to a Spring Boot endpoint

This [Spring Boot](https://spring.io/projects/spring-boot) controller accepts an upload
and returns the SDK's normalized result. One client is created as a bean and shared by all
requests; Spring calls its `close()` when the application stops. Spring MVC handles each
request on its own thread, so the blocking `newImageCall(...).execute()` API fits naturally.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import com.neuraldefend.kotlin.NeuroVerifyError
import com.neuraldefend.kotlin.ValidationError
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile
import org.springframework.web.server.ResponseStatusException

@Configuration
class NeuroVerifyConfig {
    @Bean
    fun neuroVerifyClient(): NeuroVerifyClient = NeuroVerifyClient()   // reads NEURALDEFEND_API_KEY
}

@RestController
class VerifySelfieController(private val client: NeuroVerifyClient) {
    @PostMapping("/verify-selfie")
    fun verifySelfie(@RequestPart("photo") photo: MultipartFile): Map<String, Any?> {
        val filename = photo.originalFilename ?: "upload.jpg"
        // MediaInput.stream reopens the upload for each retry, so retries stay safe.
        val media = MediaInput.stream(photo.size, filename) { photo.inputStream }
        return try {
            client.newImageCall(media).execute().toJson()
        } catch (error: ValidationError) {
            throw ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, error.detail)
        } catch (error: NeuroVerifyError) {
            throw ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Verification is temporarily unavailable")
        }
    }
}
```

Call it:

```bash
curl -F "photo=@selfie.jpg" http://localhost:8080/verify-selfie
```

Output:

```json
{"status":"success","scored":true,"rejected":false,"uniqueTrxId":"trx_example_image_low","filename":"selfie.jpg","contentType":"image/jpeg","statusCode":1,"billable":true,"aiThreatSignals":["Visual Safety Screening","Liveness Verification"],"riskScore":2.2,"riskLevel":"low","message":"Not likely to be Spoof or AI-generated","highRisk":false}
```

In a coroutine-based server such as Ktor, call the `suspend` function
`client.detectImage(media)` directly from the route handler instead of `execute()`.

### 10. Test against staging

Neural Defend can issue a separate staging key during onboarding. `staging(...)` always
uses the staging server and ignores `NEURALDEFEND_BASE_URL`, so a test can never reach
production by mistake.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File

suspend fun main() {
    val client = NeuroVerifyClient.staging(System.getenv("NEURALDEFEND_STAGING_API_KEY")) {
        maxRetries(0)                 // fail fast in tests
    }

    val result = client.use { it.detectImage(MediaInput.file(File("src/test/resources/selfie.jpg"))) }
    println("staging (${client.baseUrl}): ${result.status} / ${result.riskLevel}")
}
```

Output:

```text
staging (https://stage.deepscan.neuraldefend.com): SUCCESS / LOW
```

### 11. Tune video sampling

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `maxFrames` accepts 1 to 100.

```kotlin
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NeuroVerifyClient
import java.io.File
import kotlin.system.measureTimeMillis
import kotlin.time.Duration.Companion.minutes

suspend fun main() {
    // Allow more time per attempt for large uploads.
    NeuroVerifyClient { timeout(5.minutes) }.use { client ->
        for (frames in listOf(6, 24, 48)) {
            var level: Any? = null
            val millis = measureTimeMillis {
                level = client.detectVideo(MediaInput.file(File("webinar.mp4")), maxFrames = frames).videoRiskLevel
            }
            println("%2d frames -> video %s in %.1fs".format(frames, level, millis / 1000.0))
        }
    }
}
```

Output:

```text
 6 frames -> video LOW in 4.8s
24 frames -> video LOW in 9.3s
48 frames -> video LOW in 15.6s
```

Each call above is a separate, billable transaction. Pick one setting for production.

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

`timeout` and `retryAfterCap` accept a Kotlin `Duration` or a `(value, TimeUnit)` pair.
Invalid configuration throws `ValidationError` from `build()` (or from the
`NeuroVerifyClient(...)` factory).

### Staging

`NeuroVerifyClient.staging(apiKey)`, `NeuroVerifyClient.staging(apiKey) { ... }`, or
`builder().staging()` pins the client to `https://stage.deepscan.neuraldefend.com` and
ignores `NEURALDEFEND_BASE_URL`. Use it only with a staging credential.

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
scored or the band is new to this SDK version. `RiskLevel.wireValue` and
`ResultStatus.wireValue` give the lower-case API values (`"low"`, `"success"`).

`toJson()` returns the normalized fields as a JSON-compatible `Map` with camelCase names
and excludes `raw`. Serialized with any JSON library, it looks like this:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_image_low",
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

A no-face rejection has the same shape with `"status": "rejected"`, `"statusCode": 6`,
null `riskScore` and `riskLevel`, and a message such as `"No face detected in the image"`.
A high-risk image has, for example, `"riskScore": 8.7`, `"riskLevel": "high"`, and
`"highRisk": true`.

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

For a rejection, show the message to the user where appropriate and ask for different
media. Do not retry unchanged media.

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
- `HttpError`: another unexpected HTTP status. The specific HTTP errors extend it, so
  check it after them.

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

Do not confuse a returned business rejection with an exception. HTTP 400 validation or
security rejections that have the documented score envelope return a result, so your
application can inspect the API's message and `billable` value.

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

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

**`ValidationErrorCode.API_KEY_REQUIRED`**

On a JVM, set `NEURALDEFEND_API_KEY` in the environment that starts the JVM, or call
`apiKey(...)`. Android apps always require an explicit key.

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

**HTTP 200 but no score**

Check `status`, `statusCode`, and the result message. No-face and face-policy outcomes are
expected business rejections, not transport success indicators.

**Image returns no face or multiple faces**

Use a well-lit, in-focus image at least 224 by 224 pixels with one clearly visible subject.

**No audio score**

Check `hasAudio` and `audioMessage`. `"No audio track detected"` means video scoring
succeeded without an audio modality. A no-face video rejection suppresses both modalities.

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

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the SDK version, endpoint, `requestId` or `uniqueTrxId`, and
a sanitized reproduction. Do not send API keys, raw customer media, or biometric/personal
data.

## License

MIT. See [LICENSE](LICENSE).
