@TestOn('vm')
@Tags(['staging'])
library;

import 'dart:io';

import 'package:neuraldefend/neuraldefend.dart';
import 'package:test/test.dart';

final String? _apiKey = Platform.environment['NEURALDEFEND_STAGING_API_KEY'];

String _fixture(String variable, String fallback) {
  final path = Platform.environment[variable] ?? fallback;
  if (!File(path).existsSync()) {
    fail('$variable does not identify a staging fixture: $path');
  }
  return path;
}

void _expectConsistent(String originalStatus, String trxId, bool scored, bool rejected) {
  expect(originalStatus, anyOf('success', 'rejected'));
  expect(trxId, isNotEmpty);
  expect(scored, originalStatus == 'success');
  expect(rejected, originalStatus == 'rejected');
}

void main() {
  final skip = _apiKey == null || _apiKey!.isEmpty
      ? 'NEURALDEFEND_STAGING_API_KEY is not configured'
      : null;

  test('staging image contract', skip: skip, () async {
    final client = NeuroVerifyClient.staging(apiKey: _apiKey, maxRetries: 0);
    try {
      final result = await client.detectImage(MediaInput.file(
        _fixture('NEURALDEFEND_STAGING_IMAGE', '../../tests/fixtures/media/ai-generated.png'),
      ));
      _expectConsistent(result.originalStatus, result.uniqueTrxId, result.scored, result.rejected);
      if (result.scored) {
        expect(result.riskScore, inInclusiveRange(0.1, 10.0));
        expect(result.riskLevel, isNotNull);
      }
    } finally {
      client.close();
    }
  });

  test('staging video contract', skip: skip, () async {
    final client = NeuroVerifyClient.staging(apiKey: _apiKey, maxRetries: 0);
    try {
      final result = await client.detectVideo(
        MediaInput.file(
          _fixture('NEURALDEFEND_STAGING_VIDEO', '../../tests/fixtures/media/fake-video.mp4'),
        ),
        maxFrames: 2,
      );
      _expectConsistent(result.originalStatus, result.uniqueTrxId, result.scored, result.rejected);
      if (result.scored) {
        expect(result.videoRiskScore, inInclusiveRange(0.1, 10.0));
        expect(result.videoRiskLevel, isNotNull);
      }
    } finally {
      client.close();
    }
  });
}
