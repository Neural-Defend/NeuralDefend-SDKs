<div align="center">

# NeuralDefend Java SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Java in a few lines of code.**

[![Version](https://img.shields.io/badge/version-1.0.0-C71A36?style=flat-square&logo=apachemaven&logoColor=white)](CHANGELOG.md)
[![Java](https://img.shields.io/badge/java-17%2B-ED8B00?style=flat-square&logo=openjdk&logoColor=white)](https://openjdk.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start-image) · [Examples](#examples) · [Results](#result-handling) · [Errors](#exceptions) · [Troubleshooting](#troubleshooting)

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
| Check a photo of a face | `client.detectImage(Media.fileMedia("photo.jpg"))` | An `ImageResult` with one risk level |
| Check a video | `client.detectVideo(Media.fileMedia("clip.mp4"), new VideoOptions())` | A `VideoResult` with a video risk and an audio risk |

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `low` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `medium` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `high` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection**, not a crash: you get a result back
with `rejected() == true`, and no exception is thrown. The [examples](#examples) show how
to handle each case.

## About this SDK

The official synchronous Java client for the NeuroVerify image and video authenticity
API. Version `1.0.0` provides typed result objects, streaming multipart uploads, bounded
retries, and explicit exceptions for operational failures.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an exception, including some HTTP 200 responses.
- `billable` is the authoritative billing indicator for each returned transaction.

Risk output is not proof of authenticity and must not be the sole basis for an automated
accept/reject decision. Use the server-provided risk level with other evidence, documented
policy, and human review where appropriate.

Building for Android or writing Kotlin with coroutines? See the
[Kotlin/Android SDK](../kotlin/README.md) instead. The two SDKs use different packages and
can share a classpath.

## Requirements

- Java 17 or newer
- A NeuroVerify API key with access to the image and/or video endpoint
- Network access to the configured HTTPS API origin

This guide documents `com.neuraldefend:neuraldefend-sdk:1.0.0`. The SDK uses
[OkHttp](https://square.github.io/okhttp/) for HTTP; Gradle and Maven download it for you.

## Installation

The coordinates are `com.neuraldefend:neuraldefend-sdk:1.0.0`.

> **Availability:** Maven Central publishing for this package is being rolled out (see the
> `Unreleased` section of the [CHANGELOG](CHANGELOG.md)). If your build cannot resolve the
> artifact yet, contact [support@neuraldefend.com](mailto:support@neuraldefend.com) for
> the recommended distribution channel.

### Gradle (Kotlin DSL)

```kotlin
repositories {
    mavenCentral()
}

dependencies {
    implementation("com.neuraldefend:neuraldefend-sdk:1.0.0")
}
```

### Gradle (Groovy)

```groovy
repositories {
    mavenCentral()
}

dependencies {
    implementation 'com.neuraldefend:neuraldefend-sdk:1.0.0'
}
```

### Maven

```xml
<dependency>
  <groupId>com.neuraldefend</groupId>
  <artifactId>neuraldefend-sdk</artifactId>
  <version>1.0.0</version>
</dependency>
```

Confirm the SDK is on your classpath by printing its version:

```java
System.out.println("neuraldefend-java " + com.neuraldefend.SdkVersion.VERSION);
// neuraldefend-java 1.0.0
```

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key on Maven Central — request access from the company first, then configure
the SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media analysis,
   and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key,
   staging credential, or rate-limit details.
3. Store the key in a secret manager or the `NEURALDEFEND_API_KEY` environment variable
   (see below). Never commit it, embed it in client-side or mobile code, or paste it into
   logs or support tickets.
4. For REST endpoint reference while you wait for a key, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## API-key configuration

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

When `ClientOptions.apiKey` is left empty, the client reads `NEURALDEFEND_API_KEY`:

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.NeuroVerifyClient;

// Requires NEURALDEFEND_API_KEY from https://neuraldefend.com/ onboarding.
NeuroVerifyClient client = NeuroVerifyClient.newClient(new ClientOptions());
```

You can set `apiKey` explicitly when it comes from an application secret provider:

```java
ClientOptions options = new ClientOptions();
options.apiKey = secretProvider.get("neuraldefend-api-key");
NeuroVerifyClient client = NeuroVerifyClient.newClient(options);
```

A non-blank `apiKey` takes precedence over `NEURALDEFEND_API_KEY`. Avoid hard-coding the
key even when setting it explicitly.

## Quick start: image

Save as `QuickStart.java` and run it with the SDK on your classpath:

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;

public class QuickStart {
    public static void main(String[] args) {
        var client = NeuroVerifyClient.newClient(new ClientOptions()); // uses NEURALDEFEND_API_KEY
        var result = client.detectImage(Media.fileMedia("selfie.jpg"));
        System.out.println(result.raw);
    }
}
```

That's it. `result.raw` is the full response exactly as the API sent it:

```text
{risk_level=low, unique_trx_id=trx_example_image_low, filename=selfie.jpg, status_code=1.0, content_type=image/jpeg, risk_score=2.2, ai_threat_signals=[Visual Safety Screening, Liveness Verification], message=Not likely to be Spoof or AI-generated, billable=Y, status=success}
```

The field that matters most is `risk_level`: `low`, `medium`, or `high`. In your code, read
the same values from typed fields such as `result.riskLevel` (see [Examples](#examples)).
`raw` is a plain `Map`, so numbers print as `1.0` and the key order can vary.

## Quick start: video

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.VideoOptions;

public class QuickStartVideo {
    public static void main(String[] args) {
        var client = NeuroVerifyClient.newClient(new ClientOptions());
        var result = client.detectVideo(Media.fileMedia("clip.mp4"), new VideoOptions());
        System.out.println(result.raw);
    }
}
```

You get the full response, with a separate result for the picture and for the sound:

```text
{video_risk_level=low, unique_trx_id=trx_example_video_modalities, status_code=1.0, audio_risk_level=high, audio_message=Likely to be AI-generated, billable=Y, audio_risk_score=8.4, filename=clip.mp4, content_type=video/mp4, ai_threat_signals=[Face Swap Detection, Audio Frequency Analysis], video_message=Not likely to be AI-generated, video_risk_score=2.2, status=success}
```

A combined image-and-video program also lives in
[`examples/DetectMedia.java`](examples/DetectMedia.java).

## Examples

> **Building for a specific industry?** See the [industry use cases](../../docs/use-cases/README.md):
> eKYC onboarding, KYC re-verification, Video KYC, HR tech, and video conferencing, with
> complete code for this SDK.

Each example is a complete class: copy it into a `.java` file, set `NEURALDEFEND_API_KEY`,
and run it with the SDK on your classpath. The output shown under each example is
representative; your scores, transaction IDs, and messages will differ.

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Check one photo](#1-check-one-photo) | The smallest useful program |
| 2 | [Check a video with sound](#2-check-a-video-with-sound) | Reading the separate video and audio results |
| 3 | [Turn a result into a decision](#3-turn-a-result-into-a-decision) | Mapping low, medium, high, and rejected to actions |
| 4 | [Upload bytes from memory](#4-upload-bytes-from-memory) | Checking files that never touch the disk |
| 5 | [Check a whole folder](#5-check-a-whole-folder) | Batch processing with a summary |
| 6 | [Handle every kind of error](#6-handle-every-kind-of-error) | Telling bad input, bad keys, and outages apart |
| 7 | [Save an audit record](#7-save-an-audit-record) | Keeping transaction IDs for billing and support |
| 8 | [Add a check to a web API](#8-add-a-check-to-a-web-api) | Using the SDK inside a Spring Boot endpoint |
| 9 | [Test against staging](#9-test-against-staging) | Using the staging environment safely |
| 10 | [Tune video sampling](#10-tune-video-sampling) | Trading speed for coverage on long videos |

### 1. Check one photo

Print just the answer instead of the whole response.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;

public final class CheckOnePhoto {
    public static void main(String[] args) {
        var client = NeuroVerifyClient.newClient(new ClientOptions());
        var result = client.detectImage(Media.fileMedia("selfie.jpg"));
        System.out.println(result.riskLevel + " " + result.message);
    }
}
```

Output:

```text
low Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** answers: one for the picture and one for the sound.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.VideoOptions;

public final class CheckVideo {
    public static void main(String[] args) {
        var client = NeuroVerifyClient.newClient(new ClientOptions());
        var result = client.detectVideo(Media.fileMedia("interview.mp4"), new VideoOptions());
        System.out.println("Video: " + result.videoRiskLevel);
        System.out.println("Audio: " + result.audioRiskLevel);
    }
}
```

Output:

```text
Video: low
Audio: high
```

Here the face looks real but the voice is likely fake. A video with no sound prints
`Audio: null`.

### 3. Turn a result into a decision

Your application usually needs one of a few actions. Write that mapping once and reuse
it. Always branch on the **risk level**, never on your own numeric threshold, because the
service may tune its scoring bands.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import java.util.List;

public final class Decide {
    static String decide(ImageResult result) {
        if (result.rejected()) {
            return "ASK FOR A NEW PHOTO - " + result.message;
        }
        if (!result.scored()) {
            return "MANUAL REVIEW - unrecognized status " + result.status;
        }
        return switch (result.riskLevel) {
            case "low" -> "CONTINUE";
            case "medium" -> "MANUAL REVIEW";
            case "high" -> "ESCALATE";
            default -> "MANUAL REVIEW";
        };
    }

    public static void main(String[] args) {
        NeuroVerifyClient client = NeuroVerifyClient.newClient(new ClientOptions());

        for (String path : List.of("selfie.jpg", "printed_photo.jpg", "landscape.jpg")) {
            ImageResult result = client.detectImage(Media.fileMedia(path));
            System.out.printf("%-20s -> %s%n", path, decide(result));
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

### 4. Upload bytes from memory

When a file arrives from a web form, a queue, or object storage, you often have bytes
instead of a path. Pass a filename together with the bytes; the filename's extension
tells the SDK the format.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;

public final class UploadBytes {
    public static void main(String[] args) throws Exception {
        byte[] imageBytes = Files.readAllBytes(Path.of("selfie.jpg")); // or bytes from storage

        NeuroVerifyClient client = NeuroVerifyClient.newClient(new ClientOptions());

        // Option A: a byte array.
        ImageResult fromBytes = client.detectImage(Media.bytesMedia("selfie.jpg", imageBytes));
        System.out.printf("%,d bytes checked -> %s%n", imageBytes.length, fromBytes.riskLevel);

        // Option B: an InputStream plus its exact size. ByteArrayInputStream supports
        // mark/reset, so the SDK can safely rewind it if a retry is needed.
        ImageResult fromStream = client.detectImage(
                Media.inputStreamMedia(
                        "selfie.jpg", new ByteArrayInputStream(imageBytes), imageBytes.length));
        System.out.println("stream checked -> " + fromStream.riskLevel);
    }
}
```

Output:

```text
482,113 bytes checked -> low
stream checked -> low
```

Each call above is a separate transaction. See
[Input types](#input-types-and-stream-lifecycle) for streams that cannot be rewound.

### 5. Check a whole folder

Create one client and reuse it for many files; it keeps connections open and is much
faster than creating a client per file.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.Stream;

public final class CheckFolder {
    private static final Set<String> IMAGE_TYPES = Set.of(".jpg", ".jpeg", ".png", ".webp", ".heic");

    public static void main(String[] args) throws Exception {
        NeuroVerifyClient client = NeuroVerifyClient.newClient(new ClientOptions());
        Map<String, Integer> summary = new TreeMap<>();

        List<Path> files;
        try (Stream<Path> listing = Files.list(Path.of("uploads"))) {
            files = listing.filter(Files::isRegularFile).sorted().toList();
        }

        for (Path path : files) {
            String name = path.getFileName().toString();
            int dot = name.lastIndexOf('.');
            String ext = dot < 0 ? "" : name.substring(dot).toLowerCase(Locale.ROOT);
            if (!IMAGE_TYPES.contains(ext)) {
                continue;
            }

            ImageResult result = client.detectImage(Media.fileMedia(path));
            String outcome = result.scored() ? result.riskLevel : "rejected";
            summary.merge(outcome, 1, Integer::sum);
            System.out.printf("%-24s %-9s %s%n", name, outcome, result.message);
        }

        System.out.println();
        System.out.println("Summary: " + summary);
    }
}
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: {high=1, low=1, medium=1, rejected=1}
```

Each call is a separate transaction and may be billable. Check your rate limits before
running large batches.

### 6. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation | How it shows up | Who fixes it |
|---|---|---|
| The file was checked but could not be scored | A result with `rejected() == true` | The end user sends better media |
| Your setup is wrong (missing key, bad path) | `ValidationException`, `AuthenticationException`, `ScopeException` | You, the developer |
| The service or network had a problem | `RateLimitException`, `ServerException`, `TimeoutException`, `NetworkException` | Try again later |

All SDK exceptions are unchecked (`RuntimeException`), so the compiler will not remind you
to catch them. They do **not** share a common SDK base class, so list the ones you care
about explicitly:

```java
import com.neuraldefend.AuthenticationException;
import com.neuraldefend.ClientOptions;
import com.neuraldefend.HttpException;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NetworkException;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.ProtocolException;
import com.neuraldefend.RateLimitException;
import com.neuraldefend.ScopeException;
import com.neuraldefend.ServerException;
import com.neuraldefend.TimeoutException;
import com.neuraldefend.ValidationException;

public final class HandleErrors {
    public static void main(String[] args) {
        ImageResult result;
        try {
            NeuroVerifyClient client = NeuroVerifyClient.newClient(new ClientOptions());
            result = client.detectImage(Media.fileMedia("selfie.jpg"));
        } catch (ValidationException error) {
            System.out.println("Fix the input or configuration: " + error.getDetail());
            return;
        } catch (AuthenticationException error) {
            System.out.println("The API key is invalid or expired. Check NEURALDEFEND_API_KEY.");
            return;
        } catch (ScopeException error) {
            System.out.println("This key cannot use the image endpoint. Ask Neural Defend to add it.");
            return;
        } catch (RateLimitException error) {
            System.out.println("Too many requests. Try again in " + error.getRetryAfter() + " seconds.");
            return;
        } catch (ServerException | TimeoutException | NetworkException
                | ProtocolException | HttpException error) {
            System.out.println("Service problem (" + error.getClass().getSimpleName() + "): "
                    + error.getMessage());
            return;
        }

        if (result.rejected()) {
            System.out.println("Please upload a different photo: " + result.message);
        } else {
            System.out.println("Risk: " + result.riskLevel);
        }
    }
}
```

Output when the key is missing:

```text
Fix the input or configuration: api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

`com.neuraldefend.TimeoutException` has the same simple name as
`java.util.concurrent.TimeoutException`. If a file needs both, import one and write the
other with its full package name. The [Exceptions](#exceptions) section lists every
exception class.

### 7. Save an audit record

Every result has a `uniqueTrxId`. Store it: it is what support and billing will ask for.
This example appends one JSON line per check to `audit.jsonl` using only the JDK; in a real
application you would usually use the JSON library you already have (Jackson, Gson, ...).

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;

public final class AuditRecord {
    private static String json(String value) {
        if (value == null) {
            return "null";
        }
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    public static void main(String[] args) throws Exception {
        NeuroVerifyClient client = NeuroVerifyClient.newClient(new ClientOptions());
        ImageResult result = client.detectImage(Media.fileMedia("selfie.jpg"));

        String record = "{"
                + "\"checked_at\": " + json(Instant.now().toString()) + ", "
                + "\"transaction_id\": " + json(result.uniqueTrxId) + ", "
                + "\"status\": " + json(result.status) + ", "
                + "\"risk_level\": " + json(result.riskLevel) + ", "
                + "\"billable\": " + result.billable
                + "}";

        Files.writeString(
                Path.of("audit.jsonl"),
                record + System.lineSeparator(),
                StandardCharsets.UTF_8,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND);

        System.out.println(record);
    }
}
```

Output:

```json
{"checked_at": "2026-10-16T09:41:07.512310Z", "transaction_id": "trx_example_image_low", "status": "success", "risk_level": "low", "billable": true}
```

Store only the fields you need. Avoid logging filenames or `result.raw`, which may contain
personal data.

### 8. Add a check to a web API

This [Spring Boot](https://spring.io/projects/spring-boot) 3 endpoint accepts an upload
and returns a small JSON summary. One `NeuroVerifyClient` is created as a bean at startup
and shared by all requests. Add the `spring-boot-starter-web` dependency first.

```java
import com.neuraldefend.AuthenticationException;
import com.neuraldefend.ClientOptions;
import com.neuraldefend.HttpException;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NetworkException;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.ProtocolException;
import com.neuraldefend.RateLimitException;
import com.neuraldefend.ScopeException;
import com.neuraldefend.ServerException;
import com.neuraldefend.TimeoutException;
import com.neuraldefend.ValidationException;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@SpringBootApplication
public class VerifyApp {
    public static void main(String[] args) {
        SpringApplication.run(VerifyApp.class, args);
    }

    @Bean
    NeuroVerifyClient neuroVerifyClient() {
        return NeuroVerifyClient.newClient(new ClientOptions()); // reads NEURALDEFEND_API_KEY
    }
}

@RestController
class SelfieController {
    private final NeuroVerifyClient client;

    SelfieController(NeuroVerifyClient client) {
        this.client = client;
    }

    @PostMapping("/verify-selfie")
    Map<String, Object> verifySelfie(@RequestParam("photo") MultipartFile photo) throws IOException {
        String name = photo.getOriginalFilename();
        if (name == null || name.isBlank()) {
            name = "upload.jpg";
        }

        ImageResult result;
        try {
            result = client.detectImage(Media.bytesMedia(name, photo.getBytes()));
        } catch (ValidationException error) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, error.getDetail());
        } catch (AuthenticationException | ScopeException | RateLimitException | ServerException
                | TimeoutException | NetworkException | ProtocolException | HttpException error) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE, "Verification is temporarily unavailable");
        }

        Map<String, Object> body = new LinkedHashMap<>(); // allows null values for rejections
        body.put("unique_trx_id", result.uniqueTrxId);
        body.put("status", result.status);
        body.put("billable", result.billable);
        body.put("risk_score", result.riskScore);
        body.put("risk_level", result.riskLevel);
        body.put("message", result.message);
        body.put("scored", result.scored());
        body.put("rejected", result.rejected());
        return body;
    }
}
```

Spring Boot limits multipart uploads to 1 MB by default. Raise it to the image limit in
`application.properties`:

```properties
spring.servlet.multipart.max-file-size=10MB
spring.servlet.multipart.max-request-size=10MB
```

Start the application, then call it:

```bash
curl -F "photo=@selfie.jpg" http://127.0.0.1:8080/verify-selfie
```

Output:

```json
{"unique_trx_id":"trx_example_image_low","status":"success","billable":true,"risk_score":2.2,"risk_level":"low","message":"Not likely to be Spoof or AI-generated","scored":true,"rejected":false}
```

Spring MVC runs each request on a worker thread, so the blocking SDK call is fine here.

### 9. Test against staging

Neural Defend can issue a separate staging key during onboarding.
`NeuroVerifyClient.staging(...)` always uses the staging server, so a test can never reach
production by mistake.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.ImageResult;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;

public final class StagingCheck {
    public static void main(String[] args) {
        ClientOptions options = new ClientOptions();
        options.apiKey = System.getenv("NEURALDEFEND_STAGING_API_KEY");
        options.maxRetries = 0; // fail fast in tests

        NeuroVerifyClient client = NeuroVerifyClient.staging(options);
        System.out.println("using " + client.getBaseUrl());

        ImageResult result = client.detectImage(Media.fileMedia("src/test/resources/selfie.jpg"));
        System.out.println("staging: " + result.status + " / " + result.riskLevel);
    }
}
```

Output:

```text
using https://stage.deepscan.neuraldefend.com
staging: success / low
```

`staging(...)` copies your options and never modifies the object you pass in.

### 10. Tune video sampling

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `maxFrames` accepts 1 to 100.

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;
import com.neuraldefend.VideoOptions;
import com.neuraldefend.VideoResult;
import java.time.Duration;

public final class TuneSampling {
    public static void main(String[] args) {
        ClientOptions options = new ClientOptions();
        options.timeout = Duration.ofMinutes(5); // allow more time for large uploads
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        for (int frames : new int[] {6, 24, 48}) {
            VideoOptions sampling = new VideoOptions();
            sampling.maxFrames = frames;

            long started = System.nanoTime();
            VideoResult result = client.detectVideo(Media.fileMedia("webinar.mp4"), sampling);
            double seconds = (System.nanoTime() - started) / 1_000_000_000.0;

            System.out.printf("%2d frames -> video %s in %.1fs%n", frames, result.videoRiskLevel, seconds);
        }
    }
}
```

Output:

```text
 6 frames -> video low in 4.8s
24 frames -> video low in 9.3s
48 frames -> video low in 15.6s
```

Each call above is a separate, billable transaction. Pick one setting for production.

## Result handling

Detection methods return `ImageResult` or `VideoResult` instances for both successful
scores and business rejections. Their data is exposed as **public final fields** (for
example `result.riskLevel`, not `getRiskLevel()`), plus a few helper methods:

- `scored()`: `true` only for a recognized successful, scored result.
- `rejected()`: `true` when `status` is `"rejected"`.
- `ImageResult.highRisk()`: `true` when `riskLevel` is `"high"`.
- `VideoResult.hasAudio()`: `true` when an audio risk score is present.
- `VideoResult.overallRiskScore()`: the maximum non-null video/audio score, or `null`.

Do not infer success from HTTP 200. No-face and face-policy outcomes can be HTTP 200
rejections with `null` risk fields and may be billable. Do not create policy from numeric
thresholds: use the API-owned `low`, `medium`, and `high` bands because thresholds may be
tuned.

### `ImageResult` fields

| Field | Type | Meaning |
|---|---|---|
| `uniqueTrxId` | `String` | Transaction ID; keep it for audit, billing, and support |
| `filename` | `String` | Upload name as reported by the service |
| `contentType` | `String` | Content type detected by the service |
| `status` | `String` | `"success"` or `"rejected"` (future values are possible) |
| `statusCode` | `int` | Numeric status from the service, for example `1` (success) or `6` (no face) |
| `billable` | `boolean` | Whether this transaction is billable (wire `"Y"`/`"N"` converted for you) |
| `riskScore` | `Double` | Risk score from 0.1 to 10.0, or `null` when not scored |
| `riskLevel` | `String` | `"low"`, `"medium"`, `"high"`, or `null` when not scored |
| `message` | `String` | Human-readable explanation |
| `aiThreatSignals` | `List<String>` | Names of the checks that ran; empty when none |
| `raw` | `Map<String, Object>` | Sanitized copy of the response score envelope, for diagnostics |

### `VideoResult` fields

| Field | Type | Meaning |
|---|---|---|
| `uniqueTrxId`, `filename`, `contentType`, `status`, `statusCode`, `billable`, `aiThreatSignals`, `raw` | | Same as `ImageResult` |
| `videoRiskScore` | `Double` | Visual risk score, or `null` |
| `videoRiskLevel` | `String` | Visual risk level, or `null` |
| `videoMessage` | `String` | Explanation for the visual result (also used for rejections) |
| `audioRiskScore` | `Double` | Audio risk score, or `null` when there is no scorable audio |
| `audioRiskLevel` | `String` | Audio risk level, or `null` |
| `audioMessage` | `String` | Explanation for the audio result, or `null` |

### About `raw`

`result.raw` holds the response's score envelope with any occurrence of your API key
redacted. It can contain additive fields that this SDK version does not yet map to typed
fields, and it may contain filenames or future personal/customer fields. Numbers in `raw`
are `Double`. Do not log or persist `raw` without justified access, redaction, and
retention controls. The SDK does not include a JSON-serialization helper for results;
build the map or DTO you need from the typed fields, as in examples 7 and 8.

## Representative outputs

The values below are representative examples based on the documented API scenarios.
Scores, transaction IDs, messages, detected content types, and threat signals vary by
media and service evolution. They show the SDK's typed fields, not raw wire envelopes.

### Image outcomes

Low, medium, and high are scored outcomes. Low means lower observed risk, not proof that
an image is authentic. Medium is inconclusive and should receive additional review. High
indicates stronger risk signals and should be escalated under your policy.

A full low-risk `ImageResult`:

```text
uniqueTrxId     = trx_example_image_low
filename        = selfie.jpg
contentType     = image/jpeg
status          = success
statusCode      = 1
billable        = true
riskScore       = 2.2
riskLevel       = low
message         = Not likely to be Spoof or AI-generated
aiThreatSignals = [Visual Safety Screening, Liveness Verification]
scored()        = true
rejected()      = false
highRisk()      = false
```

All image outcomes at a glance:

| Outcome | `status` | `statusCode` | `billable` | `riskScore` | `riskLevel` | `message` |
|---|---|:-:|:-:|:-:|:-:|---|
| Low risk | `success` | 1 | `true` | 2.2 | `low` | Not likely to be Spoof or AI-generated |
| Medium risk | `success` | 1 | `true` | 5.5 | `medium` | Less likely to be Spoof or AI-generated |
| High risk | `success` | 1 | `true` | 8.7 | `high` | Likely to be Spoof detected |
| No face | `rejected` | 6 | `true` | `null` | `null` | No face detected in the image |
| Multiple faces | `rejected` | 7 | `true` | `null` | `null` | Multiple faces detected in the image |
| Quality problem | `rejected` | 2 | `false` | `null` | `null` | Image is too blurry for analysis |
| Security problem | `rejected` | 2 | `false` | `null` | `null` | File failed security validation |

No-face and multiple-face image results are normal, billable rejections even though the
HTTP response is 200. Input-quality and security failures are non-billable rejections,
normally over HTTP 400; they are returned as results, not thrown as
`ValidationException`, because the request reached the API. Rejected results typically
have an empty `aiThreatSignals` list.

For a rejection, show the message to the caller where appropriate and request corrected
media. Do not retry unchanged media.

### Video outcomes

Video and audio are separate modalities. Either modality can have a different risk level.
The API does not return a combined risk score.

Both modalities scored (`trx_example_video_modalities`, `voice_clone.mp4`):

```text
status            = success      statusCode = 1    billable = true
videoRiskScore    = 2.2          videoRiskLevel = low
videoMessage      = Not likely to be AI-generated
audioRiskScore    = 8.4          audioRiskLevel = high
audioMessage      = Likely to be AI-generated
aiThreatSignals   = [Face Swap Detection, Audio Frequency Analysis]
scored() = true   hasAudio() = true   overallRiskScore() = 8.4
```

A video without an audio track can still be successfully scored
(`trx_example_video_silent`, `silent_clip.mp4`):

```text
status            = success      statusCode = 1    billable = true
videoRiskScore    = 2.1          videoRiskLevel = low
videoMessage      = Not likely to be AI-generated
audioRiskScore    = null         audioRiskLevel = null
audioMessage      = No audio track detected
aiThreatSignals   = [Frame-Level Visual Analysis]
scored() = true   hasAudio() = false   overallRiskScore() = 2.1
```

Multi-face sampled frames are skipped. If no sampled frame contains exactly one scorable
face, the response is a no-face rejection and audio is not scored
(`trx_example_video_no_face`, `non_face_video.mp4`):

```text
status            = rejected     statusCode = 6    billable = true
videoRiskScore    = null         videoRiskLevel = null
videoMessage      = No face detected in the video. The video could not be scored, so no risk scores are provided, including for audio.
audioRiskScore    = null         audioRiskLevel = null
audioMessage      = null
aiThreatSignals   = []
scored() = false  hasAudio() = false   overallRiskScore() = null
```

Video format, size, and security failures are similarly returned as non-billable
`statusCode` 2 rejections with `null` modality fields.

## Method reference

### `NeuroVerifyClient.newClient(ClientOptions options)`

```java
ClientOptions options = new ClientOptions();   // every field is optional
options.apiKey = "...";                        // String
options.baseUrl = null;                        // String
options.allowCustomBaseUrl = false;            // boolean
options.timeout = Duration.ofSeconds(120);     // java.time.Duration
options.maxRetries = 3;                        // Integer, 0 through 3
options.userAgent = null;                      // String
options.httpClient = null;                     // okhttp3.OkHttpClient
NeuroVerifyClient client = NeuroVerifyClient.newClient(options);
```

`ClientOptions` is a plain object with public fields. `options` must not be `null`; pass
`new ClientOptions()` to use every default.

| Field | Default | Description |
|---|---|---|
| `apiKey` | `NEURALDEFEND_API_KEY` | API key. Whitespace is stripped and the result must be non-empty. |
| `baseUrl` | `NEURALDEFEND_BASE_URL`, then `https://deepscan.neuraldefend.com` | API origin. |
| `allowCustomBaseUrl` | `false` | Explicit opt-in required for a non-Neural Defend origin. That origin receives the API key and uploaded media. |
| `timeout` | 120 seconds | Positive limit for each complete HTTP call (upload plus response). |
| `maxRetries` | `3` | Retries for HTTP 429, 500, and 503, from `0` through `3`. The default permits four total attempts. |
| `userAgent` | `neuraldefend-java/1.0.0` | Custom `User-Agent` header. |
| `httpClient` | a new OkHttp client | Base OkHttp client to customize, for example with a proxy or connection pool. |

`ClientOptions` also has a few fields intended only for the SDK's own tests:
`allowHttpForTesting` (permits a plain-HTTP origin), and `sleeper`, `random`, and `clock`
(deterministic retry timing). Do not use them in production code.

Rules the client enforces:

- Base URLs must be origin-only URLs with no credentials, path, query, or fragment, and
  must use HTTPS. The production and staging origins are always allowed.
- If you supply `httpClient`, the SDK builds its own copy from it and always disables
  redirects and OkHttp's automatic connection-failure retries, and applies the SDK
  `timeout` as the call timeout. A custom client never bypasses the HTTPS or origin
  checks.
- Invalid configuration throws `ValidationException` from `newClient`, before any request
  is sent.

Configuration precedence is:

1. `apiKey` field, then `NEURALDEFEND_API_KEY`; there is no default key.
2. `baseUrl` field, then `NEURALDEFEND_BASE_URL`, then the production origin.
3. All other fields use only their explicit value or documented default; they have no
   environment-variable fallback.

The origins are also available as constants: `NeuroVerifyClient.PRODUCTION_URL` and
`NeuroVerifyClient.STAGING_URL`. `client.getBaseUrl()` returns the origin a client uses.

### `NeuroVerifyClient.staging(ClientOptions options)`

Creates a client pinned to `https://stage.deepscan.neuraldefend.com`. It ignores both
`options.baseUrl` and `NEURALDEFEND_BASE_URL`, works on a copy so your `options` object is
not changed, and otherwise applies the same rules as `newClient`. Use it only with a
staging credential supplied during onboarding.

### `detectImage(Media media)`

```java
ImageResult detectImage(Media media)
```

Uploads one image to the image endpoint and returns an `ImageResult`. Local validation
failures throw `ValidationException` before a request is sent.

### `detectVideo(Media media, VideoOptions options)`

```java
VideoResult detectVideo(Media media, VideoOptions options)
```

`options` must not be `null`; pass `new VideoOptions()` for the service defaults.

| `VideoOptions` field | Type | Description |
|---|---|---|
| `maxFrames` | `Integer` | Optional maximum number of frames to sample, from `1` through `100`. When `null`, the API default is 12. |
| `sampleRate` | `Integer` | Optional sampling override; must be at least `1`. The SDK and published API contract specify no upper bound. |

### `Media` factories

| Factory | Use it for |
|---|---|
| `Media.fileMedia(String path)` / `Media.fileMedia(Path path)` | A file on disk; the upload name comes from the file name |
| `Media.bytesMedia(String name, byte[] data)` | Bytes already in memory |
| `Media.inputStreamMedia(String name, InputStream stream, long size)` | A stream; pass the exact size, or a negative size when unknown |

`Media.IMAGE_MAX_BYTES` and `Media.VIDEO_MAX_BYTES` expose the upload limits.

### Thread safety and closing

Create **one** client and reuse it for the life of your application. A
`NeuroVerifyClient` stores only its immutable configuration and an OkHttp client, which is
designed to be shared, so one instance can serve many threads (for example as a Spring
bean, as in example 8).

`NeuroVerifyClient` has no `close()` method and is not `AutoCloseable`; there is nothing
to close per client. Each detection call closes its own HTTP response and any file it
opened. If you pass your own `httpClient`, you own that OkHttp client's lifecycle (its
connection pool and dispatcher) and can shut it down as usual for OkHttp when your
application stops.

## Input types and stream lifecycle

### Paths

`Media.fileMedia(...)` files are opened and streamed for each attempt rather than loaded
into memory. The SDK validates that the target is a regular, non-empty file within the
endpoint limit and closes the file after each attempt.

### Bytes

`Media.bytesMedia(name, data)` requires a non-empty `name` with the right extension. Bytes
are held in memory and replayed safely for retries. Empty or oversized arrays are
rejected locally.

### Input streams

`Media.inputStreamMedia(name, stream, size)` requires a non-empty `name`. Caller-owned
streams are **never closed by the SDK**; close them yourself (for example with
try-with-resources) after the call returns.

- **Replayable:** when `stream.markSupported()` is `true` and `size` is zero or more, the
  SDK marks the stream and resets it to that position before every retry. Pass the exact
  number of bytes the stream will produce. `ByteArrayInputStream` and
  `BufferedInputStream` support mark/reset.
- **Non-replayable:** when `size` is negative or the stream does not support mark/reset,
  the stream is consumed once and checked against the byte limit while streaming. Because
  it cannot be replayed, the client must be configured with `maxRetries = 0`, otherwise
  the call throws `ValidationException("non-seekable streams require max_retries=0")`.

The upload name controls the multipart filename and MIME type. Known extensions receive
the MIME types listed below. An unknown extension is sent as `application/octet-stream`
without a warning; the server still inspects the actual content and may reject it.

## Supported media and limits

Image uploads have an exact maximum of 10 MiB (`10,485,760` bytes):

- `.jpg`, `.jpeg` — `image/jpeg`
- `.png` — `image/png`
- `.bmp` — `image/bmp`
- `.tif`, `.tiff` — `image/tiff`
- `.webp` — `image/webp`
- `.heic` — `image/heic`
- `.heif` — `image/heif`

Images must be at least 224 × 224 pixels and contain exactly one face for scoring. EXIF
orientation is handled by the service. No-face and multiple-face images are rejected as
described above.

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

## Exceptions

Every SDK exception lives in the `com.neuraldefend` package and extends
`RuntimeException` directly (unchecked). They do not share an SDK base class, and
`HttpException` is **not** a parent of the other HTTP exceptions, so the order of your
`catch` blocks does not matter. Each exposes `getDetail()`; most also expose
`getStatusCode()` and `getRequestId()`.

| Exception | When | Extra accessors |
|---|---|---|
| `ValidationException` | Invalid local configuration or input, such as a missing key, unreadable path, missing filename, oversized file, or out-of-range option. No HTTP request is made for failures detected locally. | `getDetail()` |
| `AuthenticationException` | HTTP 401; the key is invalid, expired, or inactive. | `getStatusCode()`, `getRequestId()` |
| `ScopeException` | HTTP 403; the key lacks access to the requested endpoint. | `getStatusCode()`, `getRequestId()` |
| `RateLimitException` | Final HTTP 429 after configured retries. | `getRetryAfter()` (`Double` seconds or `null`), `getLimit()`, `getRemaining()`, `getReset()` |
| `ServerException` | An API error envelope, including final HTTP 500/503 responses and an error status inside an HTTP 200 body. | `getStatusCode()`, `getRequestId()`, `getEnvelope()` (sanitized map or `null`) |
| `TimeoutException` | The HTTP call exceeded `timeout`. Not retried automatically. | `getDetail()` |
| `NetworkException` | A non-timeout transport failure. Not retried automatically. | `getDetail()` |
| `ProtocolException` | The response was not valid JSON or did not match the required NeuroVerify envelope. A malformed final HTTP 500/503 response is still a `ServerException`. | `getStatusCode()`, `getRequestId()` |
| `HttpException` | Any other unexpected HTTP status, or an HTTP 400 that is not a rejection. | `getStatusCode()`, `getRequestId()` |

`getRequestId()` returns the `X-Request-ID` response header when present, otherwise the
transaction ID when one is available, otherwise an empty string. Your API key is redacted
from exception details.

Example handling for every exception, with the request ID where one exists:

```java
try {
    ImageResult result = client.detectImage(Media.fileMedia("selfie.jpg"));
    if (result.rejected()) {
        System.out.println("valid request but media was not scored: " + result.message);
    }
} catch (ValidationException error) {
    System.out.println("fix configuration or input: " + error.getDetail());
} catch (AuthenticationException error) {
    System.out.println("verify the API key (request " + error.getRequestId() + ")");
} catch (ScopeException error) {
    System.out.println("request image endpoint access (request " + error.getRequestId() + ")");
} catch (RateLimitException error) {
    System.out.println("rate limited; retry-after=" + error.getRetryAfter()
            + ", request=" + error.getRequestId());
} catch (ServerException error) {
    System.out.println("service error " + error.getStatusCode() + ", request=" + error.getRequestId());
} catch (com.neuraldefend.TimeoutException error) {
    System.out.println("request timed out: " + error.getDetail());
} catch (NetworkException error) {
    System.out.println("network failure: " + error.getDetail());
} catch (ProtocolException error) {
    System.out.println("unexpected API response, request=" + error.getRequestId());
} catch (HttpException error) {
    System.out.println("unexpected HTTP " + error.getStatusCode() + ", request=" + error.getRequestId());
}
```

Do not confuse a returned business rejection with an exception. HTTP 400 validation or
security rejections that have the documented score envelope return a result so your
application can inspect the API's message and `billable` value.

## Retries, billability, and idempotency

The SDK retries only HTTP 429, 500, and 503:

- HTTP 429 honors a valid `Retry-After` duration or HTTP date, capped at 3,600 seconds. If
  the header is absent or invalid, waits are 1, 2, and 4 seconds.
- HTTP 500/503 waits use exponential delays of 1, 2, and 4 seconds plus up to 25% jitter.
- HTTP 400, 401, 403, other HTTP statuses, timeouts, and network failures are not retried.
- `maxRetries = 0` disables retries; `maxRetries = 3` allows up to four total attempts.
- Retries block the calling thread while waiting.

Requests are not idempotent. Every accepted attempt receives a new `uniqueTrxId`, and
retries or manual resubmission may create separate billable transactions. A timeout or
network failure can leave billability unknown because the client may not have received
the server response. Preserve returned transaction IDs for audit, support, and billing
correlation, and avoid adding another retry layer without accounting for the SDK's own
attempts.

`billable` describes the returned transaction only. A successful score is normally
billable; no-face and face-policy rejections can also be billable. Input validation and
security rejections are normally non-billable. Always use the actual returned value.

## Privacy and security

- Upload media only with the data owner's authorization and an appropriate legal basis.
- Treat images, video, audio, filenames, and diagnostics as potentially biometric or
  otherwise sensitive personal data.
- Apply your organization's consent, residency, encryption, retention, deletion,
  access-control, and audit requirements.
- Keep API keys in a secret manager or server-side environment. Never ship a key inside a
  desktop, applet, or mobile build. Rotate a key if exposure is suspected.
- Do not send a production key or customer media to an untrusted `baseUrl`.
  `allowCustomBaseUrl = true` is a deliberate trust decision.
- Redirects are disabled so credentials and media are not forwarded to another origin.
- Minimize production logging. Prefer transaction IDs and status fields over filenames,
  `raw` maps, media bytes, headers, or keys.
- Do not disguise content with a different extension; the server performs format and
  security validation.

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

## Troubleshooting

**`api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)`**

Set `NEURALDEFEND_API_KEY` in the environment of the process that starts the JVM (your
IDE run configuration, service unit, or container), or set a non-empty
`ClientOptions.apiKey` from a secret provider.

**HTTP 401 / `AuthenticationException`**

Verify that the selected key is current and belongs to the intended environment. An
explicit `apiKey` overrides the environment variable.

**HTTP 403 / `ScopeException`**

The key does not have access to the endpoint. Request the required image or video scope
during onboarding.

**`filename is required when uploading bytes` / `filename is required for a nameless file-like object`**

Pass a non-empty name such as `"photo.jpg"` or `"clip.mp4"` to `Media.bytesMedia(...)` or
`Media.inputStreamMedia(...)`.

**`non-seekable streams require max_retries=0`**

Set `options.maxRetries = 0`, pass a stream that supports mark/reset together with its
exact size, or upload from a path or byte array. A non-replayable stream cannot be retried
safely.

**`file path does not exist or is not readable`**

Paths are resolved relative to the JVM's working directory. Check it with
`System.getProperty("user.dir")`, or pass an absolute path.

**`file exceeds the endpoint size limit`**

Images are limited to 10 MiB and videos to 1,500,000,000 bytes. Resize or trim the media
before uploading.

**`a non-Neural Defend base_url requires allow_custom_base_url=true ...`**

`NEURALDEFEND_BASE_URL` or `options.baseUrl` points somewhere other than the production or
staging origin. Remove it, or set `allowCustomBaseUrl = true` only for an origin you trust
with your key and media.

**Upload rejected by Spring Boot before reaching the SDK**

Raise `spring.servlet.multipart.max-file-size` and `max-request-size` (see example 8).

**Unsupported or missing extension**

Use a documented extension matching the real content. Otherwise the upload is sent as
`application/octet-stream`, and the API may reject it after content inspection.

**HTTP 200 but no score**

Inspect `status`, `statusCode`, and the result message. No-face and face-policy outcomes
are expected business rejections, not transport success indicators.

**No audio score**

Check `hasAudio()` and `audioMessage`. `"No audio track detected"` means video scoring
succeeded without an audio modality. A no-face video rejection suppresses both modalities.

**Repeated 429**

Inspect the `RateLimitException` metadata, reduce concurrency, and confirm tenant limits
with your account manager. The SDK has already exhausted its configured retries when the
exception is thrown.

**Timeout or network failure**

Confirm egress, DNS, TLS interception, proxy behavior, and the configured `timeout`
(raise it for large videos). These failures are not retried automatically because the
server may already have accepted a billable request.

**Security or quality rejection**

Do not retry the same media. Correct the format, dimensions, quality, face count, or
security issue indicated by the result message, then submit only if a new request is
appropriate.

## Testing this SDK

From `packages/java`:

```bash
./gradlew test
```

Optional staging smoke tests require `NEURALDEFEND_STAGING_API_KEY`,
`NEURALDEFEND_STAGING_IMAGE`, and `NEURALDEFEND_STAGING_VIDEO`.

## Wire-level API documentation

For the exhaustive HTTP envelopes, status codes, risk-band descriptions, messages,
billability scenarios, and request examples, see:

- [Unified Face Authenticity Score](../../docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](../../docs/client/unified-video-authenticity.md)

The wire API uses an outer endpoint-specific envelope, `snake_case` names, and `"Y"`/`"N"`
billing strings. The Java SDK maps those to the `camelCase` fields and `boolean billable`
of `ImageResult` and `VideoResult`.

## Support

Technical support: `support@neuraldefend.com`

When requesting help, provide the SDK version (`SdkVersion.VERSION`), endpoint,
`getRequestId()` or `uniqueTrxId`, and a sanitized reproduction. Do not send API keys, raw
customer media, or biometric/personal data.

## License

MIT — see [LICENSE](LICENSE).
