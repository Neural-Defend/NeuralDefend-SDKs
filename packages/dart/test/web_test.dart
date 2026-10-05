@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuraldefend/neuraldefend.dart';
import 'package:neuraldefend/src/client.dart' show createTestClient;
import 'package:test/test.dart';

const _lowRisk = {
  'unified_face_authenticity_score': {
    'unique_trx_id': 'trx_web',
    'filename': 'selfie.jpg',
    'content_type': 'image/jpeg',
    'status': 'success',
    'status_code': 1,
    'billable': 'Y',
    'risk_score': 2.2,
    'risk_level': 'low',
    'message': 'Not likely to be Spoof or AI-generated',
    'ai_threat_signals': ['Visual Safety Screening'],
  },
};

void main() {
  test('web apps must pass the API key explicitly', () {
    expect(
      () => NeuroVerifyClient(),
      throwsA(isA<ValidationError>()
          .having((e) => e.code, 'code', ValidationErrorCode.apiKeyRequired)
          .having((e) => e.detail, 'detail', contains('web apps'))),
    );
  });

  test('file paths are rejected with a clear validation error', () async {
    final client = NeuroVerifyClient(apiKey: 'key');
    await expectLater(
      client.detectImage(MediaInput.file('selfie.jpg')),
      throwsA(isA<ValidationError>().having((e) => e.code, 'code', ValidationErrorCode.unsupportedInput)),
    );
    client.close();
  });

  test('bytes upload without setting a forbidden User-Agent header', () async {
    late http.BaseRequest seen;
    var body = <int>[];
    final transport = MockClient.streaming((request, stream) async {
      seen = request;
      body = await stream.toBytes();
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(_lowRisk))), 200);
    });
    final client = createTestClient(
      apiKey: 'web-key',
      baseUrl: 'http://sdk.test',
      httpClient: transport,
      userAgent: 'ignored/1.0',
    );

    final result = await client.detectImage(
      MediaInput.bytes(Uint8List.fromList(utf8.encode('pixels')), filename: 'selfie.jpg'),
    );

    expect(result.scored, isTrue);
    expect(result.riskLevel, RiskLevel.low);
    expect(seen.headers.containsKey('user-agent'), isFalse);
    expect(seen.headers['x-api-key'], 'web-key');
    expect(latin1.decode(body), contains('filename="selfie.jpg"'));
  });
}
