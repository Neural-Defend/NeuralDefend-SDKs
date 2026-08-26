# NeuralDefend Java SDK

The official Java client for the NeuroVerify image and video authenticity API. Version
`1.0.0` provides typed result objects, streaming multipart uploads, bounded retries, and
explicit errors for operational failures.

NeuroVerify returns decision-support signals for signs of spoofing, AI generation, or
manipulation:

- Image analysis returns one face-authenticity risk score and risk level.
- Video analysis returns independent video and audio risk scores and risk levels.
- A result can be rejected without being an exception, including some HTTP 200 responses.
- `billable` is the authoritative billing indicator for each returned transaction.

## Requirements

- Java 17 or newer
- A NeuroVerify API key
- Network access to the configured HTTPS API origin

## Installation

Add the dependency from this repository path (until published to Maven Central):

```kotlin
dependencies {
    implementation("com.neuraldefend:neuraldefend-sdk:1.0.0")
}
```

## Quick start

```java
import com.neuraldefend.ClientOptions;
import com.neuraldefend.Media;
import com.neuraldefend.NeuroVerifyClient;

ClientOptions options = new ClientOptions();
options.apiKey = System.getenv("NEURALDEFEND_API_KEY");
NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

var result = client.detectImage(Media.fileMedia("selfie.jpg"));
System.out.printf("status=%s scored=%s risk=%s%n",
        result.status, result.scored(), result.riskScore);
```

See [`examples/DetectMedia.java`](examples/DetectMedia.java) for image and video usage.

## Configuration

| Option | Description |
| --- | --- |
| `apiKey` | API key; falls back to `NEURALDEFEND_API_KEY` |
| `baseUrl` | API origin; defaults to production or `NEURALDEFEND_BASE_URL` |
| `allowCustomBaseUrl` | Required for non-Neural Defend origins |
| `timeout` | Request timeout (default 120s) |
| `maxRetries` | Retries for 429/500/503 (default 3) |
| `httpClient` | Custom OkHttp client |
| `userAgent` | Custom user agent |

Use `NeuroVerifyClient.staging(...)` to pin the client to staging regardless of environment
variables.

## Testing

```bash
./gradlew test
```

Optional staging smoke tests require `NEURALDEFEND_STAGING_API_KEY`,
`NEURALDEFEND_STAGING_IMAGE`, and `NEURALDEFEND_STAGING_VIDEO`.

## License

MIT — see [LICENSE](LICENSE).
