<div align="center">

# NeuralDefend Dart and Flutter SDK

**Detect deepfakes, AI-generated faces, and spoofed media from Dart and Flutter in a few lines of code.**

[![pub.dev](https://img.shields.io/pub/v/neuraldefend?style=flat-square&logo=dart&logoColor=white&label=pub.dev&color=0175C2)](https://pub.dev/packages/neuraldefend)
[![Dart](https://img.shields.io/badge/dart-3.5%2B-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev/)
[![Flutter](https://img.shields.io/badge/flutter-Android%20%7C%20iOS%20%7C%20web%20%7C%20desktop-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev/)
[![License: MIT](https://img.shields.io/badge/license-MIT-22863A?style=flat-square)](LICENSE)

[Quick start](#quick-start-dart-image) · [Examples](#examples) · [Results](#working-with-results) · [Errors](#errors) · [Troubleshooting](#troubleshooting)

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
| Check a photo of a face | `await client.detectImage(MediaInput.file('photo.jpg'))` | An `ImageResult` with one risk level |
| Check a video | `await client.detectVideo(MediaInput.file('clip.mp4'))` | A `VideoResult` with a video risk and an audio risk |

Think of the risk level as a traffic light:

| Risk level | Meaning | What to do |
|---|---|---|
| `RiskLevel.low` 🟢 | Few signs of manipulation were found | Continue, using your normal process |
| `RiskLevel.medium` 🟡 | The result is unclear | Ask for more evidence or a human review |
| `RiskLevel.high` 🔴 | Strong signs of spoofing or AI generation | Escalate to a human reviewer |

Sometimes the service cannot score a file, for example when there is no face in the
photo. That is a normal answer called a **rejection** (`ResultStatus.rejected`), not a
crash or an exception. The [examples](#examples) show how to handle each case.

## About this SDK

The official Dart and Flutter client for the Neural Defend NeuroVerify image and video
authenticity APIs. Version `1.0.0` provides:

- typed, normalized image and video results;
- one package for Android, iOS, macOS, Windows, Linux, web, and the Dart VM;
- streaming multipart uploads from files, bytes, or `image_picker` files;
- upload progress, cancellation, timeouts, rate-limit handling, and controlled retries; and
- forward-compatible handling of response statuses and risk bands introduced by newer API
  versions.

Risk scores and risk bands are decision-support signals. They are not proof that media is
authentic or manipulated, and they should never be the sole basis for an automatic
acceptance, rejection, or adverse decision. Combine them with other evidence, policy
checks, and human review appropriate to your use case.

## Requirements

- `neuraldefend` version `1.0.0`
- Dart 3.5 or newer (Flutter 3.24 or newer)
- A Neural Defend API key with access to the image and/or video endpoint
- Network access to the HTTPS API origin

Runtime dependencies are limited to `package:http` and `package:http_parser`.

## Installation

In a Flutter app:

```sh
flutter pub add neuraldefend
```

In a Dart server or command-line project:

```sh
dart pub add neuraldefend
```

Then import it:

```dart
import 'package:neuraldefend/neuraldefend.dart';
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

### API key configuration (Dart VM)

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

On the Dart VM, the client reads `NEURALDEFEND_API_KEY` when `apiKey` is not passed and
`NEURALDEFEND_BASE_URL` when `baseUrl` is not passed. An explicit `apiKey` always wins.
Never commit keys to source control, example files, container images, or shell history.

**Flutter and web apps never read environment variables.** They must pass `apiKey`
explicitly, and production apps should send media to your own backend instead of holding
a key at all. See [Choose where the SDK runs](#choose-where-the-sdk-runs).

## Choose where the SDK runs

| Where you call NeuroVerify | Recommended | Key handling |
| --- | --- | --- |
| Dart backend (Shelf, Dart Frog, Serverpod, Cloud Run) | Yes | `NEURALDEFEND_API_KEY` or a secret manager |
| Your backend in another language, called by a Flutter app | Yes | Use the Python, TypeScript, or Go SDK on the server |
| Flutter mobile, desktop, or web app calling NeuroVerify directly | Only with a credential Neural Defend has approved for client use | Pass `apiKey` explicitly; the SDK never reads environment variables in Flutter or web |

## Quick start: Dart image

Save as `bin/main.dart` and run `dart run`:

```dart
import 'dart:convert';

import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final client = NeuroVerifyClient(); // uses NEURALDEFEND_API_KEY
  final result = await client.detectImage(MediaInput.file('selfie.jpg'));
  print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  client.close();
}
```

That's it. You get the full response:

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
  "aiThreatSignals": [
    "Visual Safety Screening",
    "Liveness Verification"
  ],
  "riskScore": 2.2,
  "riskLevel": "low",
  "message": "Not likely to be Spoof or AI-generated",
  "highRisk": false
}
```

The field that matters most is `riskLevel`: `low`, `medium`, or `high`.

## Quick start: Dart video

```dart
import 'dart:convert';

import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final client = NeuroVerifyClient();
  final result = await client.detectVideo(MediaInput.file('clip.mp4'));
  print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  client.close();
}
```

You get the full response, with a separate result for the picture and for the sound:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_video_modalities",
  "filename": "clip.mp4",
  "contentType": "video/mp4",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": [
    "Face Swap Detection",
    "Audio Frequency Analysis"
  ],
  "hasAudio": true,
  "videoRiskScore": 2.2,
  "videoRiskLevel": "low",
  "videoMessage": "Not likely to be AI-generated",
  "audioRiskScore": 8.4,
  "audioRiskLevel": "high",
  "audioMessage": "Likely to be AI-generated",
  "overallRiskScore": 8.4
}
```

`overallRiskScore` is simply the higher of the two scores.

A runnable command-line version of both quick starts is in
[`example/neuraldefend_example.dart`](example/neuraldefend_example.dart).

## Quick start: Flutter

Files from [`image_picker`](https://pub.dev/packages/image_picker) or
[`file_picker`](https://pub.dev/packages/file_picker) are `XFile`s. Pass `XFile.openRead`
so the SDK streams the file instead of loading it into memory, and can reopen it if a
retry is needed:

```dart
import 'package:flutter/foundation.dart';
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

Output in the debug console (representative):

```text
uploaded 0 of 482113 bytes
uploaded 65536 of 482113 bytes
...
uploaded 482113 of 482113 bytes
```

On web, `package:http` buffers the request body before sending it, so uploads are held in
memory and `onProgress` reports reading the file rather than network transfer.

Create one client, keep it for the lifetime of the screen or app, and call `close()` in
`dispose()`. A complete app with progress, cancellation, and error messages is in
[`example/flutter_app`](example/flutter_app). [Example 5](#5-flutter-widget-that-picks-a-photo)
below shows a smaller version.

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
the server ([Example 9](#9-add-a-check-to-a-dart-server) shows one). Your backend can then
enforce user authorization, quotas, audit logging, file limits, and abuse controls:

```dart
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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

## Examples

> **Building for a specific industry?** See the [industry use cases](../../docs/use-cases/README.md):
> eKYC onboarding, KYC re-verification, Video KYC, HR tech, and video conferencing, with
> complete code for this SDK.

Each example is complete. Dart VM examples read `NEURALDEFEND_API_KEY`; Flutter examples
pass `apiKey` explicitly. **The output shown under each example is representative**: your
scores, transaction IDs, byte counts, timings, and messages will differ.

| # | Example | You will learn |
|:-:|---|---|
| 1 | [Check one photo](#1-check-one-photo) | The smallest useful program |
| 2 | [Check a video with sound](#2-check-a-video-with-sound) | Reading the separate video and audio results |
| 3 | [Turn a result into a decision](#3-turn-a-result-into-a-decision) | Mapping low, medium, high, and rejected to actions |
| 4 | [Upload bytes from memory](#4-upload-bytes-from-memory) | Checking a `Uint8List`, such as an `image_picker` result |
| 5 | [Flutter widget that picks a photo](#5-flutter-widget-that-picks-a-photo) | Showing the verdict in a real screen |
| 6 | [Check a whole folder](#6-check-a-whole-folder) | Batch processing with a summary on the Dart VM |
| 7 | [Handle every kind of error](#7-handle-every-kind-of-error) | Telling bad input, bad keys, and outages apart |
| 8 | [Save an audit record](#8-save-an-audit-record) | Keeping transaction IDs for billing and support |
| 9 | [Add a check to a Dart server](#9-add-a-check-to-a-dart-server) | Using the SDK inside a `shelf` endpoint |
| 10 | [Test against staging](#10-test-against-staging) | Using the staging environment safely |
| 11 | [Tune video sampling](#11-tune-video-sampling) | Trading speed for coverage on long videos |

### 1. Check one photo

Print just the answer instead of the whole response.

```dart
import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final client = NeuroVerifyClient();
  final result = await client.detectImage(MediaInput.file('selfie.jpg'));
  print('${result.riskLevel?.name} ${result.message}');
  client.close();
}
```

Output:

```text
low Not likely to be Spoof or AI-generated
```

### 2. Check a video with sound

A video gets **two** answers: one for the picture and one for the sound.

```dart
import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final client = NeuroVerifyClient();
  final result = await client.detectVideo(MediaInput.file('interview.mp4'));
  print('Video: ${result.videoRiskLevel?.name}');
  print('Audio: ${result.audioRiskLevel?.name}');
  client.close();
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
it. Always branch on the **risk level** (`RiskLevel.low`, `medium`, `high`), never on your
own numeric threshold, because the service may tune its scoring bands. Dart's `switch`
makes sure you handle every case.

```dart
import 'package:neuraldefend/neuraldefend.dart';

String decide(ImageResult result) => switch (result.status) {
      ResultStatus.rejected => 'ASK FOR A NEW PHOTO - ${result.message}',
      ResultStatus.unknown =>
        'MANUAL REVIEW - unrecognized status "${result.originalStatus}"',
      ResultStatus.success => switch (result.riskLevel) {
          RiskLevel.low => 'CONTINUE',
          RiskLevel.medium => 'MANUAL REVIEW',
          RiskLevel.high => 'ESCALATE',
          null => 'MANUAL REVIEW',
        },
    };

Future<void> main() async {
  final client = NeuroVerifyClient();
  try {
    for (final path in ['selfie.jpg', 'printed_photo.jpg', 'landscape.jpg']) {
      final result = await client.detectImage(MediaInput.file(path));
      print('${path.padRight(20)} -> ${decide(result)}');
    }
  } finally {
    client.close();
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

Sometimes you already have the file as bytes (`Uint8List`), for example from
`XFile.readAsBytes()`, a download, or a database. Use `MediaInput.bytes` and give it a
`filename` with the real extension; the extension tells the SDK the format.

This snippet uses [`image_picker`](https://pub.dev/packages/image_picker), an **extra
dependency** (`flutter pub add image_picker`):

```dart
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:neuraldefend/neuraldefend.dart';

Future<void> checkPickedPhoto(NeuroVerifyClient client) async {
  final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return; // the user closed the picker

  final Uint8List bytes = await picked.readAsBytes();
  final result = await client.detectImage(
    MediaInput.bytes(bytes, filename: picked.name), // e.g. "IMG_0042.jpg"
  );
  print('${bytes.length} bytes checked -> ${result.riskLevel?.name ?? result.status.name}');
}
```

Output:

```text
482113 bytes checked -> low
```

Bytes are held in memory. For large photos and especially videos, prefer
`MediaInput.openRead(file.openRead, ...)` from the [Flutter quick start](#quick-start-flutter),
which streams the file instead. On the Dart VM you can get bytes with
`File('selfie.jpg').readAsBytes()`.

### 5. Flutter widget that picks a photo

A small screen with one button. It picks a photo, sends it, and shows the traffic-light
answer. Like Example 4, it needs the **extra dependency**
[`image_picker`](https://pub.dev/packages/image_picker).

The key comes from `--dart-define` and the client points at **staging**. This is for
development only: a key compiled into an app can be extracted. In production, send the
photo to your backend (see [credential safety](#flutter-and-web-credential-safety)).

```dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuraldefend/neuraldefend.dart';

// flutter run --dart-define=NEURALDEFEND_API_KEY=replace-with-your-api-key
const _apiKey = String.fromEnvironment('NEURALDEFEND_API_KEY');

void main() => runApp(const MaterialApp(home: SelfieCheckPage()));

class SelfieCheckPage extends StatefulWidget {
  const SelfieCheckPage({super.key});

  @override
  State<SelfieCheckPage> createState() => _SelfieCheckPageState();
}

class _SelfieCheckPageState extends State<SelfieCheckPage> {
  final _client = NeuroVerifyClient.staging(apiKey: _apiKey);
  bool _busy = false;
  String _verdict = 'Pick a photo to check it.';

  @override
  void dispose() {
    _client.close(); // release the connection pool with the screen
    super.dispose();
  }

  Future<void> _pickAndCheck() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final result = await _client.detectImage(MediaInput.openRead(
        file.openRead,
        length: await file.length(),
        filename: file.name,
      ));
      _verdict = switch (result.status) {
        ResultStatus.success => switch (result.riskLevel) {
            RiskLevel.low => '🟢 Low risk: ${result.message}',
            RiskLevel.medium => '🟡 Medium risk: needs a human review',
            RiskLevel.high => '🔴 High risk: escalate for review',
            null => 'Unrecognized risk level; update the package',
          },
        ResultStatus.rejected => 'Please try another photo: ${result.message}',
        ResultStatus.unknown => 'Unrecognized result; update the package',
      };
    } on NeuroVerifyError catch (error) {
      _verdict = 'Could not check the photo: ${error.detail}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Selfie check')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _busy ? null : _pickAndCheck,
                child: const Text('Check a photo'),
              ),
              const SizedBox(height: 24),
              if (_busy) const LinearProgressIndicator() else Text(_verdict),
            ],
          ),
        ),
      );
}
```

Output (text shown on screen after picking a photo):

```text
🟢 Low risk: Not likely to be Spoof or AI-generated
```

If no key was supplied, `NeuroVerifyClient.staging` throws a `ValidationError` with code
`ValidationErrorCode.apiKeyRequired` when the screen is created. The full
[`example/flutter_app`](example/flutter_app) shows how to catch it, plus video, progress,
and cancellation.

### 6. Check a whole folder

Reuse one client for many files; it keeps connections open and is much faster than
creating a client per file. This uses `dart:io`, so it runs on the Dart VM (servers and
command-line tools), not on web.

```dart
import 'dart:io';

import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final files = Directory('uploads')
      .listSync()
      .whereType<File>()
      .where((f) => imageExtensions.contains(f.path.split('.').last.toLowerCase()))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final summary = <String, int>{};
  final client = NeuroVerifyClient();
  try {
    for (final file in files) {
      final result = await client.detectImage(MediaInput.file(file.path));
      final outcome = result.scored ? result.riskLevel!.name : result.status.name;
      summary[outcome] = (summary[outcome] ?? 0) + 1;
      print('${result.filename.padRight(24)} ${outcome.padRight(9)} ${result.message}');
    }
  } finally {
    client.close();
  }
  print('\nSummary: $summary');
}
```

Output:

```text
anna.jpg                 low       Not likely to be Spoof or AI-generated
group_photo.jpg          rejected  Multiple faces detected in the image
id_card_scan.png         medium    Less likely to be Spoof or AI-generated
printed_photo.jpg        high      Likely to be Spoof detected

Summary: {low: 1, rejected: 1, medium: 1, high: 1}
```

`imageExtensions` is exported by the SDK, so you only pick files the image endpoint
documents. Each call is a separate transaction and may be billable. Check your rate limits
before running large batches.

### 7. Handle every kind of error

There are three different situations, and each one needs a different fix:

| Situation | How it shows up | Who fixes it |
|---|---|---|
| The file was checked but could not be scored | A result with `status == ResultStatus.rejected` (no exception) | The end user sends better media |
| Your setup is wrong (missing key, bad path, bad option) | `ValidationError`, `AuthenticationError`, `ScopeError` | You, the developer |
| The service or network had a problem | `RateLimitError`, `ServerError`, `TimeoutError`, `NetworkError` | Try again later |

```dart
import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  NeuroVerifyClient? client;
  try {
    client = NeuroVerifyClient(); // throws ValidationError if no key is found
    final result = await client.detectImage(MediaInput.file('selfie.jpg'));
    if (result.rejected) {
      print('Please upload a different photo: ${result.message}');
    } else {
      print('Risk: ${result.riskLevel?.name}');
    }
  } on ValidationError catch (error) {
    print('Fix the input or configuration (${error.code.name}): ${error.detail}');
  } on AuthenticationError {
    print('The API key is invalid or expired. Check NEURALDEFEND_API_KEY.');
  } on ScopeError {
    print('This key cannot use the image endpoint. Ask Neural Defend to add it.');
  } on RateLimitError catch (error) {
    print('Too many requests. Try again in ${error.retryAfter?.inSeconds} seconds.');
  } on NeuroVerifyError catch (error) {
    print('Service problem (${error.runtimeType}), request id: ${error.requestId}');
  } finally {
    client?.close();
  }
}
```

Output when the key is missing:

```text
Fix the input or configuration (apiKeyRequired): apiKey is required; pass it explicitly or set NEURALDEFEND_API_KEY.
```

Output when the photo has no face:

```text
Please upload a different photo: No face detected in the image
```

The [Errors](#errors) section lists every error class, including `AbortError` for
cancelled requests.

### 8. Save an audit record

Every result has a `uniqueTrxId`. Store it: it is what support and billing will ask for.
`toJson()` gives you a plain map that is safe to pass to `jsonEncode`.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final client = NeuroVerifyClient();
  final ImageResult result;
  try {
    result = await client.detectImage(MediaInput.file('selfie.jpg'));
  } finally {
    client.close();
  }

  final record = {
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'transactionId': result.uniqueTrxId,
    'status': result.status.name,
    'riskLevel': result.riskLevel?.name,
    'billable': result.billable,
  };

  await File('audit.jsonl').writeAsString(
    '${jsonEncode(record)}\n',
    mode: FileMode.append,
  );
  print(const JsonEncoder.withIndent('  ').convert(record));
}
```

Output:

```json
{
  "checkedAt": "2026-10-16T09:41:07.512Z",
  "transactionId": "trx_example_image_low",
  "status": "success",
  "riskLevel": "low",
  "billable": true
}
```

Store only the fields you need. Avoid logging filenames or `result.raw`, which may contain
personal data.

### 9. Add a check to a Dart server

This server accepts a photo and returns the SDK's normalized result. One client is
created at startup and shared by all requests. It uses
[`shelf`](https://pub.dev/packages/shelf), an **extra dependency**
(`dart pub add shelf`).

The photo is sent as the raw request body, and its `Content-Type` header picks the file
extension, because the SDK needs a filename with the real extension.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:neuraldefend/neuraldefend.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _extensions = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'};

final client = NeuroVerifyClient(); // reads NEURALDEFEND_API_KEY

Future<Response> verifySelfie(Request request) async {
  if (request.method != 'POST' || request.url.path != 'verify-selfie') {
    return Response.notFound('Not found');
  }
  final extension = _extensions[request.mimeType];
  if (extension == null) {
    return Response(415, body: 'Send image/jpeg, image/png, or image/webp');
  }

  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
  }

  try {
    final result = await client.detectImage(
      MediaInput.bytes(builder.takeBytes(), filename: 'upload.$extension'),
    );
    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  } on ValidationError catch (error) {
    return Response(422, body: error.detail);
  } on NeuroVerifyError {
    return Response(503, body: 'Verification is temporarily unavailable');
  }
}

Future<void> main() async {
  final server = await shelf_io.serve(verifySelfie, InternetAddress.loopbackIPv4, 8080);
  print('Listening on http://${server.address.host}:${server.port}');
  ProcessSignal.sigint.watch().first.then((_) async {
    await server.close();
    client.close(); // release connections when the server stops
    exit(0);
  });
}
```

Run it with `dart run bin/server.dart`, then call it:

```bash
curl --data-binary @selfie.jpg -H "Content-Type: image/jpeg" http://127.0.0.1:8080/verify-selfie
```

Output:

```json
{"status":"success","scored":true,"rejected":false,"uniqueTrxId":"trx_example_image_low","filename":"upload.jpg","contentType":"image/jpeg","statusCode":1,"billable":true,"aiThreatSignals":["Visual Safety Screening","Liveness Verification"],"riskScore":2.2,"riskLevel":"low","message":"Not likely to be Spoof or AI-generated","highRisk":false}
```

In a real service, authenticate the caller and limit the body size before reading it.

### 10. Test against staging

Neural Defend can issue a separate staging key during onboarding.
`NeuroVerifyClient.staging` always uses the staging server
(`https://stage.deepscan.neuraldefend.com`) and ignores `NEURALDEFEND_BASE_URL`, so a
test can never reach production by mistake.

```dart
import 'dart:io';

import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  final client = NeuroVerifyClient.staging(
    apiKey: Platform.environment['NEURALDEFEND_STAGING_API_KEY'],
    maxRetries: 0, // fail fast in tests
  );
  try {
    final result = await client.detectImage(MediaInput.file('test/fixtures/selfie.jpg'));
    print('staging: ${result.status.name} / ${result.riskLevel?.name}');
  } finally {
    client.close();
  }
}
```

Output:

```text
staging: success / low
```

If `NEURALDEFEND_STAGING_API_KEY` is not set, `apiKey` is `null` and the client falls back
to `NEURALDEFEND_API_KEY`. Make sure that one is also a staging key in test environments.

### 11. Tune video sampling

The service looks at 12 frames by default. Long videos can use more frames for better
coverage; quick checks can use fewer for speed. `maxFrames` accepts 1 to 100, and
`sampleRate` accepts any integer of at least 1.

```dart
import 'package:neuraldefend/neuraldefend.dart';

Future<void> main() async {
  // Allow more time for large uploads; the timeout applies to each attempt.
  final client = NeuroVerifyClient(timeout: const Duration(minutes: 5));
  try {
    for (final frames in [6, 24, 48]) {
      final stopwatch = Stopwatch()..start();
      final result = await client.detectVideo(
        MediaInput.file('webinar.mp4'),
        maxFrames: frames,
      );
      final seconds = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      print('${'$frames'.padLeft(2)} frames -> video ${result.videoRiskLevel?.name} in ${seconds}s');
    }
  } finally {
    client.close();
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

`riskLevel`, `videoRiskLevel`, and `audioRiskLevel` are `RiskLevel?` values
(`RiskLevel.low`, `RiskLevel.medium`, `RiskLevel.high`), or `null` when not scored.

### `toJson()` versus `raw`

`toJson()` returns the normalized fields with camelCase names and excludes `raw`. The
values below are representative; scores, transaction IDs, messages, and threat signals
vary with the submitted media and service evolution.

Representative low-risk image:

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

Representative high-risk image:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_image_high",
  "filename": "printed_photo.jpg",
  "contentType": "image/jpeg",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Visual Safety Screening", "Liveness Verification"],
  "riskScore": 8.7,
  "riskLevel": "high",
  "message": "Likely to be Spoof detected",
  "highRisk": true
}
```

Representative no-face rejection (a normal, billable result, not an exception):

```json
{
  "status": "rejected",
  "scored": false,
  "rejected": true,
  "uniqueTrxId": "trx_example_image_no_face",
  "filename": "landscape.jpg",
  "contentType": "image/jpeg",
  "statusCode": 6,
  "billable": true,
  "aiThreatSignals": [],
  "riskScore": null,
  "riskLevel": null,
  "message": "No face detected in the image",
  "highRisk": false
}
```

Representative video with both modalities:

```json
{
  "status": "success",
  "scored": true,
  "rejected": false,
  "uniqueTrxId": "trx_example_video_modalities",
  "filename": "voice_clone.mp4",
  "contentType": "video/mp4",
  "statusCode": 1,
  "billable": true,
  "aiThreatSignals": ["Face Swap Detection", "Audio Frequency Analysis"],
  "hasAudio": true,
  "videoRiskScore": 2.2,
  "videoRiskLevel": "low",
  "videoMessage": "Not likely to be AI-generated",
  "audioRiskScore": 8.4,
  "audioRiskLevel": "high",
  "audioMessage": "Likely to be AI-generated",
  "overallRiskScore": 8.4
}
```

Do not write policy against example numbers or exact message text. Use the returned band
rather than reconstructing it from score thresholds.

`result.raw` is the redacted, unmodifiable wire envelope, kept for diagnostics and forward
compatibility. It uses the API's field names, is not a stable contract, and may contain
filenames or future personal fields. Do not log or persist it routinely.

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

For a rejection, show the message to the user where appropriate and ask for different
media. Do not retry unchanged media.

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

Handling every concrete error:

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
import 'dart:async';

final cancel = Completer<void>();
final pending = client.detectVideo(MediaInput.file('clip.mp4'), abortTrigger: cancel.future);
cancel.complete();
await pending; // Throws AbortError.
```

Do not confuse a returned rejection with an exception. HTTP 400 quality and security
rejections that carry the documented score envelope are returned as results, so your
application can read the API's message and `billable` value.

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

Report suspected vulnerabilities privately to `support@neuraldefend.com`; do not include
real credentials or customer media in the report.

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

The wire API uses snake_case field names and `"Y"`/`"N"` billing strings. The Dart SDK
normalizes those details in `ImageResult` and `VideoResult`.

## Support

Technical support: [support@neuraldefend.com](mailto:support@neuraldefend.com)

When requesting help, provide the SDK version, endpoint, `requestId` or `uniqueTrxId`, and
a sanitized reproduction. Do not send API keys, raw customer media, or biometric/personal
data.

## License

MIT. See [LICENSE](LICENSE).
