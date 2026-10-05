@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:neuraldefend/neuraldefend.dart';
import 'package:test/test.dart';

import 'support.dart';

final Uint8List _image = Uint8List.fromList(utf8.encode('image'));
final Uint8List _video = Uint8List.fromList(utf8.encode('video'));

Future<Object> _detect(String fixture) async {
  final client = testClient(fixtureTransport([fixture]));
  try {
    if (fixture.startsWith('image/')) {
      return await client.detectImage(MediaInput.bytes(_image, filename: 'sample.jpg'));
    }
    return await client.detectVideo(MediaInput.bytes(_video, filename: 'sample.mp4'));
  } catch (error) {
    return error;
  } finally {
    client.close();
  }
}

const _imageResults = [
  'image/documented/low-risk.json',
  'image/documented/medium-risk.json',
  'image/documented/high-risk-spoof.json',
  'image/documented/no-face.json',
  'image/documented/multiple-faces.json',
  'image/documented/nsfw.json',
  'image/documented/blurry.json',
  'image/documented/unsupported-format.json',
  'image/documented/security-rejection.json',
  'image/documented/too-large.json',
];

const _videoResults = [
  'video/documented/both-low.json',
  'video/documented/video-high-audio-low.json',
  'video/documented/both-high.json',
  'video/documented/video-low-audio-high.json',
  'video/documented/medium-no-audio.json',
  'video/documented/silent-no-audio.json',
  'video/documented/no-face.json',
  'video/documented/multiple-faces.json',
  'video/documented/unsupported-format.json',
  'video/documented/security-rejection.json',
  'video/documented/too-large.json',
];

const _serverErrors = [
  'image/documented/internal-error-500.json',
  'image/documented/service-unavailable-503.json',
  'video/documented/internal-error-500.json',
  'video/documented/service-unavailable-503.json',
];

const _unknownValues = [
  'image/robustness/unknown-status-code.json',
  'image/robustness/unknown-status.json',
  'image/robustness/unknown-risk-level.json',
  'video/robustness/unknown-status-code.json',
  'video/robustness/unknown-status.json',
  'video/robustness/unknown-risk-level.json',
];

const _malformed = [
  'image/robustness/missing-envelope.json',
  'image/robustness/malformed-json.json',
  'video/robustness/missing-envelope.json',
  'video/robustness/malformed-json.json',
];

ResultStatus _expectedStatus(String wire) => switch (wire) {
      'success' => ResultStatus.success,
      'rejected' => ResultStatus.rejected,
      _ => ResultStatus.unknown,
    };

void main() {
  test('the shared corpus contains the documented 43 fixtures', () {
    expect(allFixturePaths(), hasLength(43));
  });

  test('every fixture is covered by exactly one contract group', () {
    final covered = [
      ..._imageResults,
      ..._videoResults,
      ..._serverErrors,
      ..._unknownValues,
      ..._malformed,
      'image/robustness/unknown-extra-field.json',
      'video/robustness/unknown-extra-field.json',
      'image/synthetic/unauthorized-401.json',
      'video/synthetic/unauthorized-401.json',
      'image/synthetic/forbidden-403.json',
      'video/synthetic/forbidden-403.json',
      'image/synthetic/rate-limited-429.json',
      'video/synthetic/rate-limited-429.json',
    ];
    expect(covered.toSet(), hasLength(covered.length));
    expect(covered.toSet(), equals(allFixturePaths().toSet()));
  });

  group('documented image results', () {
    for (final fixture in _imageResults) {
      test(fixture, () async {
        final caseData = loadCase(fixture);
        final wire = wireEnvelope(caseData);
        final result = await _detect(fixture) as ImageResult;

        expect(result.status, _expectedStatus(wire['status']! as String));
        expect(result.originalStatus, wire['status']);
        expect(result.uniqueTrxId, wire['unique_trx_id']);
        expect(result.filename, wire['filename']);
        expect(result.contentType, wire['content_type']);
        expect(result.statusCode, wire['status_code']);
        expect(result.billable, wire['billable'] == 'Y');
        expect(result.riskScore, (wire['risk_score'] as num?)?.toDouble());
        expect(result.riskLevel?.name, wire['risk_level']);
        expect(result.message, wire['message']);
        expect(result.aiThreatSignals, wire['ai_threat_signals'] ?? const <String>[]);
        expect(result.scored, wire['status'] == 'success');
        expect(result.rejected, wire['status'] == 'rejected');
        expect(result.highRisk, wire['risk_level'] == 'high');
        expect(result.raw, equals(wire));
      });
    }
  });

  group('documented video results', () {
    for (final fixture in _videoResults) {
      test(fixture, () async {
        final caseData = loadCase(fixture);
        final wire = wireEnvelope(caseData);
        final result = await _detect(fixture) as VideoResult;

        expect(result.status, _expectedStatus(wire['status']! as String));
        expect(result.statusCode, wire['status_code']);
        expect(result.billable, wire['billable'] == 'Y');
        expect(result.videoRiskScore, (wire['video_risk_score'] as num?)?.toDouble());
        expect(result.videoRiskLevel?.name, wire['video_risk_level']);
        expect(result.videoMessage, wire['video_message']);
        expect(result.audioRiskScore, (wire['audio_risk_score'] as num?)?.toDouble());
        expect(result.audioRiskLevel?.name, wire['audio_risk_level']);
        expect(result.audioMessage, wire['audio_message']);
        expect(result.hasAudio, wire['audio_risk_score'] != null);

        final scores = [wire['video_risk_score'], wire['audio_risk_score']]
            .whereType<num>()
            .map((score) => score.toDouble());
        expect(
          result.overallRiskScore,
          scores.isEmpty ? isNull : scores.reduce((a, b) => a > b ? a : b),
        );
        expect(result.raw, equals(wire));
      });
    }
  });

  group('server error envelopes throw ServerError', () {
    for (final fixture in _serverErrors) {
      test(fixture, () async {
        final caseData = loadCase(fixture);
        final error = await _detect(fixture);
        expect(error, isA<ServerError>());
        final serverError = error as ServerError;
        expect(serverError.statusCode, caseData['http_status']);
        expect(serverError.raw, equals(wireEnvelope(caseData)));
        expect(serverError.requestId, wireEnvelope(caseData)['unique_trx_id']);
      });
    }
  });

  group('authentication and scope errors', () {
    for (final kind in ['image', 'video']) {
      test('$kind 401', () async {
        final fixture = '$kind/synthetic/unauthorized-401.json';
        final body = loadCase(fixture)['body']! as Map<String, Object?>;
        final error = await _detect(fixture);
        expect(error, isA<AuthenticationError>());
        expect((error as AuthenticationError).detail, body['detail']);
        expect(error.statusCode, 401);
      });

      test('$kind 403', () async {
        final fixture = '$kind/synthetic/forbidden-403.json';
        final body = loadCase(fixture)['body']! as Map<String, Object?>;
        final error = await _detect(fixture);
        expect(error, isA<ScopeError>());
        expect((error as ScopeError).detail, body['detail']);
        expect(error.statusCode, 403);
      });
    }
  });

  group('rate-limit errors expose every documented header', () {
    for (final kind in ['image', 'video']) {
      test(kind, () async {
        final error = await _detect('$kind/synthetic/rate-limited-429.json');
        expect(error, isA<RateLimitError>());
        final rateLimit = error as RateLimitError;
        expect(rateLimit.statusCode, 429);
        expect(rateLimit.detail, 'Rate limit exceeded');
        expect(rateLimit.retryAfter, const Duration(seconds: 60));
        expect(rateLimit.limit, '1000');
        expect(rateLimit.remaining, '0');
        expect(rateLimit.reset, '2026-07-27T00:00:00Z');
      });
    }
  });

  group('malformed responses throw ProtocolError', () {
    for (final fixture in _malformed) {
      test(fixture, () async {
        final error = await _detect(fixture);
        expect(error, isA<ProtocolError>());
        expect((error as ProtocolError).statusCode, loadCase(fixture)['http_status']);
      });
    }
  });

  group('unknown wire values are preserved without breaking', () {
    for (final fixture in _unknownValues) {
      test(fixture, () async {
        final wire = wireEnvelope(loadCase(fixture));
        final result = await _detect(fixture);
        expect(result, isNot(isA<Error>()));
        expect(result, isNot(isA<NeuroVerifyError>()));

        if (result is ImageResult) {
          expect(result.originalStatus, wire['status']);
          expect(result.statusCode, wire['status_code']);
          expect(result.originalRiskLevel, wire['risk_level']);
          final known = wire['status'] == 'success' && wire['risk_level'] != 'critical';
          expect(result.status, known ? ResultStatus.success : ResultStatus.unknown);
          expect(result.scored, known);
          if (!known) {
            expect(result.toJson()['originalStatus'], wire['status']);
          }
        } else {
          final video = result as VideoResult;
          expect(video.originalStatus, wire['status']);
          expect(video.statusCode, wire['status_code']);
          expect(video.originalVideoRiskLevel, wire['video_risk_level']);
          final known = wire['status'] == 'success' &&
              RiskLevel.tryParse(wire['video_risk_level'] as String?) != null;
          expect(video.status, known ? ResultStatus.success : ResultStatus.unknown);
          expect(video.scored, known);
        }
      });
    }
  });

  group('unknown extra fields stay in raw and out of toJson', () {
    for (final kind in ['image', 'video']) {
      test(kind, () async {
        final result = await _detect('$kind/robustness/unknown-extra-field.json');
        final raw = switch (result) {
          ImageResult(:final raw) => raw,
          VideoResult(:final raw) => raw,
          _ => fail('expected a result, got $result'),
        };
        final future = raw['future_signal']! as Map<String, Object?>;
        expect(future['confidence'], 0.42);
        expect(() => raw['x'] = 1, throwsUnsupportedError);
        final json = switch (result) {
          ImageResult() => result.toJson(),
          VideoResult() => result.toJson(),
          _ => fail('expected a result, got $result'),
        };
        expect(json.containsKey('raw'), isFalse);
        expect(json.containsKey('future_signal'), isFalse);
        expect(jsonDecode(jsonEncode(json)), equals(json));
      });
    }
  });

  test('normalized image JSON matches the documented shape', () async {
    final result = await _detect('image/documented/low-risk.json') as ImageResult;
    expect(result.toJson(), {
      'status': 'success',
      'scored': true,
      'rejected': false,
      'uniqueTrxId': result.uniqueTrxId,
      'filename': 'selfie.jpg',
      'contentType': 'image/jpeg',
      'statusCode': 1,
      'billable': true,
      'aiThreatSignals': result.aiThreatSignals,
      'riskScore': result.riskScore,
      'riskLevel': 'low',
      'message': result.message,
      'highRisk': false,
    });
  });

  test('normalized video JSON keeps modalities independent', () async {
    final result = await _detect('video/documented/silent-no-audio.json') as VideoResult;
    final json = result.toJson();
    expect(json['hasAudio'], isFalse);
    expect(json['audioRiskScore'], isNull);
    expect(json['audioRiskLevel'], isNull);
    expect(json['overallRiskScore'], result.videoRiskScore);
  });
}
