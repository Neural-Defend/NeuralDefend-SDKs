import 'dart:typed_data';

import 'package:neuraldefend/neuraldefend.dart';

/// Compiled with `dart compile js` in CI to prove the public library has no
/// `dart:io` dependency on web targets.
Future<void> main() async {
  final client = NeuroVerifyClient(apiKey: 'compile-check-only');
  final media = MediaInput.bytes(Uint8List(1), filename: 'compile.jpg');
  try {
    await client.detectImage(media, abortTrigger: Future<void>.value());
  } on AbortError {
    // Expected: the request is aborted before any network traffic.
  } finally {
    client.close();
  }
}
