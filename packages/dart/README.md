# neuraldefend

The official Dart and Flutter client for the Neural Defend NeuroVerify image and
video authenticity APIs. It provides:

- typed, normalized image and video results;
- one package for Android, iOS, macOS, Windows, Linux, web, and the Dart VM;
- streaming multipart uploads from files, bytes, or `image_picker` files;
- upload progress, cancellation, timeouts, rate-limit handling, and controlled
  retries; and
- forward-compatible handling of response statuses and risk bands introduced by
  newer API versions.

Risk scores and risk bands are decision-support signals. They are not proof that
media is authentic or manipulated, and they should never be the sole basis for an
automatic acceptance, rejection, or adverse decision. Combine them with other
evidence, policy checks, and human review appropriate to your use case.

## Requirements

- `neuraldefend` version `1.0.0`
- Dart 3.5 or newer (Flutter 3.24 or newer)
- A Neural Defend API key with access to the image and/or video endpoint

Runtime dependencies are limited to `package:http` and `package:http_parser`.

## Installation

```sh
dart pub add neuraldefend
# or, in a Flutter app
flutter pub add neuraldefend
```

## Get an API key

NeuroVerify API keys are issued by **Neural Defend** after customer onboarding. There is no
self-service key on pub.dev. Request access from the company first, then configure the SDK.

1. Visit **[neuraldefend.com](https://neuraldefend.com/)** and choose **Book a Demo** to
   talk with the Neural Defend team about deepfake detection, AI-generated media analysis,
   and API access for your use case.
2. After onboarding, Neural Defend provides an API key scoped to the image and/or video
   endpoints you need. Existing customers can also ask their account manager for a key or
   staging credential.
3. On a server, store the key in a secret manager or `NEURALDEFEND_API_KEY`. In Flutter
   and web apps, read [Flutter and web credential safety](#flutter-and-web-credential-safety)
   first.
4. For REST endpoint reference, see the
   [Neural Defend API documentation](https://neuraldefend.gitbook.io/neural-defend).

**Contact:** [support@neuraldefend.com](mailto:support@neuraldefend.com)

## Choose where the SDK runs

| Where you call NeuroVerify | Recommended | Key handling |
| --- | --- | --- |
| Dart backend (Shelf, Dart Frog, Serverpod, Cloud Run) | Yes | `NEURALDEFEND_API_KEY` or a secret manager |
| Your backend in another language, called by a Flutter app | Yes | Use the Python, TypeScript, or Go SDK on the server |
| Flutter mobile, desktop, or web app calling NeuroVerify directly | Only with a credential Neural Defend has approved for client use | Pass `apiKey` explicitly; the SDK never reads environment variables in Flutter or web |

## Quick start (Dart server or CLI)

```dart
import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  // Reads NEURALDEFEND_API_KEY when apiKey is omitted.
  final client = NeuroVerifyClient();
  try {
    final image = await client.detectImage(MediaInput.file('selfie.jpg'));
    switch (image.status) {
      case ResultStatus.success:
        print('${image.riskLevel?.name} risk (${image.riskScore}): ${image.message}');
      case ResultStatus.rejected:
        print('Not scored (billable: ${image.billable}): ${image.message}');
      case ResultStatus.unknown:
        print('Unrecognized outcome "${image.originalStatus}"; upgrade the SDK.');
    }

    final video = await client.detectVideo(
      MediaInput.file('clip.mp4'),
      maxFrames: 24,
    );
    if (video.scored) {
      print('video: ${video.videoRiskLevel?.name}, '
          'audio: ${video.hasAudio ? video.audioRiskLevel?.name : 'none'}');
    }
  } finally {
    client.close();
  }
}
```

A runnable version is in [`example/neuraldefend_example.dart`](example/neuraldefend_example.dart).

## Flutter quick start

Files from [`image_picker`](https://pub.dev/packages/image_picker) or
[`file_picker`](https://pub.dev/packages/file_picker) are `XFile`s. Pass `XFile.openRead`
so the SDK streams the file instead of loading it into memory, and can reopen it if a
retry is needed:

```dart
import 'package:image_picker/image_picker.dart';
import 'package:neuraldefend/neuraldefend.dart';

Future<ImageResult?> checkSelfie(NeuroVerifyClient client) async {
  final file = await ImagePicker().pickImage(source: ImageSource.camera);
  if (file == null) return null;
  return client.detectImage(
    MediaInput.openRead(
      file.openRead,
      length: await file.length(),
      filename: file.name,
    ),
    onProgress: (sent, total) => debugPrint('uploaded $sent of $total bytes'),
  );
}
```

On web, `package:http` buffers the request body before sending it, so uploads are held in
memory and `onProgress` reports reading the file rather than network transfer.

Create one client, keep it for the lifetime of the screen or app, and call `close()` in
`dispose()`. A complete app with progress, cancellation, and error messages is in
[`example/flutter_app`](example/flutter_app).

To use the platform HTTP stacks, pass any `package:http` client, such as
[`cupertino_http`](https://pub.dev/packages/cupertino_http) on iOS/macOS or
[`cronet_http`](https://pub.dev/packages/cronet_http) on Android:

```dart
final client = NeuroVerifyClient(apiKey: apiKey, httpClient: CupertinoClient.defaultSessionConfiguration());
```

## Flutter and web credential safety

> **Never ship a long-lived production API key in a Flutter app, web bundle,
> `--dart-define`, asset, or remote config. Anyone who installs or loads the app can
> extract it.**

Flutter and web clients require an explicit `apiKey`. The SDK never reads environment
variables there. The public API contract does not define a credential-issuance endpoint
for client apps, so do not invent a client-side key exchange based on this README.

For normal apps, upload media to your authenticated backend and call NeuroVerify from
the server. Your backend can then enforce user authorization, quotas, audit logging, file
limits, and abuse controls:

```dart
import 'package:http/http.dart' as http;

Future<http.StreamedResponse> uploadToBackend(XFile file, String sessionToken) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.example.com/media-authenticity/image'),
  )
    ..headers['authorization'] = 'Bearer $sessionToken'
    ..files.add(http.MultipartFile(
      'file',
      file.openRead(),
      await file.length(),
      filename: file.name,
    ));
  return request.send();
}
```

Call the SDK directly from a client app only when Neural Defend has explicitly approved a
client-exposable credential for your tenant, or during development with a staging key.

## API key configuration (Dart VM)

```sh
# macOS/Linux
export NEURALDEFEND_API_KEY="your-api-key"
```

```powershell
# PowerShell
$env:NEURALDEFEND_API_KEY = "your-api-key"
```

On the Dart VM, the client reads `NEURALDEFEND_API_KEY` when `apiKey` is not passed and
`NEURALDEFEND_BASE_URL` when `baseUrl` is not passed. Never commit keys to source control,
example files, container images, or shell history.

## Method reference

### `NeuroVerifyClient({...})`

| Parameter | Default | Description |
| --- | --- | --- |
| `apiKey` | `NEURALDEFEND_API_KEY` (Dart VM only) | Sent in the `x-api-key` header; redacted from errors, `toString()`, and diagnostics |
| `baseUrl` | `NEURALDEFEND_BASE_URL` (Dart VM only), then `https://deepscan.neuraldefend.com` | HTTPS origin without a path, query, fragment, or credentials |
| `allowCustomBaseUrl` | `false` | Required for any origin other than the production or staging API, because it receives the key and media |
| `timeout` | 120 seconds | Applies to each attempt, including upload and reading the response |
| `maxRetries` | `3` | Retries after the first attempt for HTTP 429, 500, and 503 (`0` through `3`) |
| `retryAfterCap` | 60 seconds | Longest `Retry-After` wait the SDK honors |
| `userAgent` | `neuraldefend-dart/1.0.0` | Ignored in browsers, which control this header |
| `httpClient` | SDK-owned `http.Client` | Custom `package:http` client; the SDK does not close a client you supply |
| `onWarning` | ignored | Receives non-fatal `ValidationWarning`s such as `unsupported_extension` |

Invalid configuration throws `ValidationError` from the constructor.

### `NeuroVerifyClient.staging({...})`

Pins the client to `https://stage.deepscan.neuraldefend.com` and ignores
`NEURALDEFEND_BASE_URL`. Use it only with a staging credential. It accepts the same options
except `baseUrl` and `allowCustomBaseUrl`.

### `client.detectImage(media, {abortTrigger, onProgress})`

Uploads one image to `/detect/image` and returns `Future<ImageResult>`.

### `client.detectVideo(media, {maxFrames, sampleRate, abortTrigger, onProgress})`

Uploads one video to `/detect/video` and returns `Future<VideoResult>`. `maxFrames` is an
integer from 1 through 100 (API default 12); `sampleRate` is an integer of at least 1.

Both methods accept:

- `abortTrigger`: complete this future to cancel preparation, a retry wait, the upload, or
  response processing. The call then fails with `AbortError`.
- `onProgress(sentBytes, totalBytes)`: upload progress for the current attempt. It restarts
  at zero if an automatic retry begins.

### `client.close()`

Closes the SDK-owned HTTP client. Later calls throw `StateError`.

### Media inputs

| Input | Platforms | Retries |
| --- | --- | --- |
| `MediaInput.file(path, {filename})` | Dart VM, Flutter mobile and desktop | Yes; symbolic links and non-regular files are rejected |
| `MediaInput.bytes(bytes, filename: ...)` | All | Yes |
| `MediaInput.openRead(open, length: ..., filename: ...)` | All, including `XFile.openRead` on web | Yes; `open` is called once per attempt |
| `MediaInput.stream(stream, length: ..., filename: ...)` | All | No; requires `maxRetries: 0` |

`filename` must include the real extension, because the API uses it for format checks.
`length` must equal the number of bytes the stream produces, or the upload fails with a
`ValidationError`.

## Working with results

### Normalized fields

Every `ImageResult` and `VideoResult` has:

| Field | Meaning |
| --- | --- |
| `status` | `ResultStatus.success`, `rejected`, or `unknown`. Always branch on this first |
| `scored` / `rejected` | Convenience booleans for the first two statuses |
| `originalStatus` | Exact wire `status`, useful for `unknown` results |
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

- **Low, medium, or high**: `status` is `success`. Interpret `low` as lower observed risk,
  not proof of authenticity. Treat `medium` as inconclusive. Treat `high` as a reason to
  escalate or review, not as sufficient evidence for automatic rejection.
- **No face or multiple faces**: a billable HTTP 200 rejection (`status` is `rejected`).
- **Quality, format, size, or security failures**: normally a non-billable HTTP 400
  rejection. These are results, not exceptions.
- **Video with no audio track**: can still be scored; `hasAudio` is `false` and
  `audioMessage` explains why.
- **Video with no scorable single-face frame**: a no-face rejection; audio is not scored.
- **Unknown status or risk band from a newer API**: `status` is `unknown`, with the wire
  values in `originalStatus` and `original*RiskLevel`. Do not make a policy decision from
  it. Record the transaction ID and upgrade the SDK.

## Errors

All SDK errors extend `NeuroVerifyError`, implement `Exception`, and expose `detail`.
HTTP-derived errors can also expose `statusCode` and `requestId`.

- `ValidationError`: local configuration, option, filename, input, empty-file, or size
  validation failed. Its `code` is a `ValidationErrorCode`. Correct the input; do not retry
  it unchanged.
- `AuthenticationError`: HTTP 401. Check that the key is active and belongs to the selected
  environment. Not retried.
- `ScopeError`: HTTP 403. The key lacks endpoint or plan access. Not retried.
- `RateLimitError`: HTTP 429 after retries are exhausted. Exposes `retryAfter` as a
  `Duration` plus string `limit`, `remaining`, and `reset` metadata.
- `TimeoutError`: the per-attempt timeout elapsed. Not retried.
- `NetworkError`: no response was received (DNS, connectivity, TLS). Not retried.
- `ServerError`: HTTP 500/503 after retries are exhausted, or a wire result with
  `status: "error"`. May expose a redacted `raw` envelope.
- `ProtocolError`: the response was malformed or missing required fields. Retain the
  request or transaction ID and contact support if it persists.
- `AbortError`: your `abortTrigger` completed. Distinct from a timeout.
- `HttpError`: another unexpected HTTP status. The specific HTTP errors extend it, so catch
  it last.

```dart
try {
  final result = await client.detectImage(MediaInput.file('selfie.jpg'));
  // Handle result.status here.
} on ValidationError catch (error) {
  print('Fix the request: ${error.code.name} ${error.detail}');
} on AuthenticationError {
  print('Check the API key.');
} on ScopeError {
  print('Request image endpoint access.');
} on RateLimitError catch (error) {
  print('Rate limit exhausted. Retry after ${error.retryAfter}.');
} on TimeoutError {
  print('The request timed out.');
} on NetworkError {
  print('No response was received.');
} on ServerError catch (error) {
  print('Service error ${error.statusCode}, request ${error.requestId}.');
} on ProtocolError catch (error) {
  print('Unexpected response contract, request ${error.requestId}.');
} on AbortError {
  print('Cancelled by the caller.');
} on HttpError catch (error) {
  print('Unexpected HTTP ${error.statusCode}.');
}
```

To cancel a request:

```dart
final cancel = Completer<void>();
final pending = client.detectVideo(MediaInput.file('clip.mp4'), abortTrigger: cancel.future);
cancel.complete();
await pending; // Throws AbortError.
```

## Retries, billing, and idempotency

By default, the SDK makes the initial request and up to three retries:

- HTTP 500 and 503 wait about 1, 2, and 4 seconds, with up to 25% jitter.
- HTTP 429 honors a numeric or HTTP-date `Retry-After` value up to `retryAfterCap`;
  without a valid header it waits 1, 2, and 4 seconds.
- HTTP 400, 401, 403, other statuses, timeouts, protocol failures, aborts, and network
  failures are not retried.

Set `maxRetries: 0` to disable automatic retries.

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
`application/octet-stream`. The constants `imageExtensions`, `videoExtensions`,
`imageMaxBytes`, and `videoMaxBytes` and the function `mimeForFilename` are exported for
validating input before upload.

`image_picker` may re-encode photos (for example, HEIC to JPEG on iOS) and returns a
filename with the matching extension. Avoid `imageQuality`, `maxWidth`, or `maxHeight`
values that shrink a face below the 224-pixel minimum.

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

**`ValidationErrorCode.apiKeyRequired`**

On the Dart VM, set `NEURALDEFEND_API_KEY` before creating the client or pass `apiKey`.
Flutter and web apps always require an explicit `apiKey`.

**`ValidationErrorCode.filenameRequired`**

Pass a filename with the real extension, such as `filename: 'photo.jpg'`. On native
platforms, `XFile.fromData` derives `name` from `path`, so set `path` as well.

**`ValidationErrorCode.fileTooLarge` or `emptyFile`**

Check the byte limits before upload. Picker files report their size through
`XFile.length()`.

**`ValidationErrorCode.streamNotReplayable`**

`MediaInput.stream` can be read only once. Use `MediaInput.openRead`, `MediaInput.bytes`,
or `MediaInput.file` to allow retries, or set `maxRetries: 0`.

**`ValidationErrorCode.unsupportedInput` on web**

Browsers have no file system access. Use `MediaInput.openRead` with an `XFile` or
`MediaInput.bytes`.

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

**Android release builds cannot connect**

Add `<uses-permission android:name="android.permission.INTERNET" />` to
`android/app/src/main/AndroidManifest.xml`. macOS apps also need the
`com.apple.security.network.client` entitlement.

**`ProtocolError` or `ResultStatus.unknown`**

Upgrade `neuraldefend`. If the issue persists, give support the SDK version and the
request or transaction ID.

## Development

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test                 # Dart VM, including the shared contract fixtures
dart test -p chrome       # dart2js
dart test -p chrome -c dart2wasm
```

Staging smoke tests run only when `NEURALDEFEND_STAGING_API_KEY` is set:

```sh
NEURALDEFEND_STAGING_API_KEY=... dart test --tags staging
```

The private generated contract under `generated/core/` is produced by
`scripts/generate.py` and must never be edited by hand. It is excluded from the published
package.

## Wire-level API documentation

For exhaustive response scenarios, wire field names, status codes, and current messages,
see:

- [Unified Face Authenticity Score](https://github.com/Neural-Defend/NeuralDefend-SDKs/blob/main/docs/client/unified-face-authenticity.md)
- [Unified Video Authenticity Score](https://github.com/Neural-Defend/NeuralDefend-SDKs/blob/main/docs/client/unified-video-authenticity.md)

## License

MIT. See [LICENSE](LICENSE).
