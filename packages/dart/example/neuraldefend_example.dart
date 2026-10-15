// Detects an image and, optionally, a video from the command line.
//
//   export NEURALDEFEND_API_KEY="your-api-key"
//   dart run example/neuraldefend_example.dart selfie.jpg [clip.mp4]
//
// Run this on a server or developer machine. In a Flutter app, call your own
// backend instead of shipping a production API key; see the package README.
import 'dart:io';

import 'package:neuraldefend/neuraldefend.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln('Usage: dart run example/neuraldefend_example.dart '
        '<image> [video]');
    exitCode = 64;
    return;
  }

  final NeuroVerifyClient client;
  try {
    client = NeuroVerifyClient(
      onWarning: (warning) => stderr.writeln(warning.message),
    );
  } on ValidationError catch (error) {
    stderr.writeln(error.detail);
    exitCode = 78;
    return;
  }

  try {
    final image = await client.detectImage(MediaInput.file(arguments[0]));
    switch (image.status) {
      case ResultStatus.success:
        stdout.writeln('Image ${image.uniqueTrxId}: ${image.riskLevel?.name} '
            'risk (${image.riskScore}). ${image.message}');
      case ResultStatus.rejected:
        stdout.writeln('Image rejected (billable: ${image.billable}): '
            '${image.message}');
      case ResultStatus.unknown:
        stdout.writeln('Unrecognized image outcome '
            '"${image.originalStatus}"; upgrade the SDK.');
    }

    if (arguments.length == 2) {
      final video = await client.detectVideo(
        MediaInput.file(arguments[1]),
        maxFrames: 12,
        onProgress: (sent, total) {
          if (sent == total) stderr.writeln('Uploaded $total bytes.');
        },
      );
      if (video.scored) {
        stdout.writeln('Video ${video.uniqueTrxId}: '
            'video ${video.videoRiskLevel?.name} (${video.videoRiskScore}), '
            'audio ${video.hasAudio ? video.audioRiskLevel?.name : 'none'}.');
      } else {
        stdout.writeln('Video ${video.status.name}: ${video.videoMessage}');
      }
    }
  } on RateLimitError catch (error) {
    stderr.writeln('Rate limited; retry after ${error.retryAfter}.');
    exitCode = 75;
  } on NeuroVerifyError catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    client.close();
  }
}
