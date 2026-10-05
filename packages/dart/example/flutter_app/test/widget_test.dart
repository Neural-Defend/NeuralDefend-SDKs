import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuraldefend/neuraldefend.dart';
import 'package:neuraldefend_flutter_example/main.dart';

const _imageSuccess = {
  'unified_face_authenticity_score': {
    'unique_trx_id': 'trx_example_low',
    'filename': 'selfie.jpg',
    'content_type': 'image/jpeg',
    'status': 'success',
    'status_code': 1,
    'billable': 'Y',
    'risk_score': 2.2,
    'risk_level': 'low',
    'message': 'Not likely to be Spoof or AI-generated',
    'ai_threat_signals': ['Liveness Verification'],
  },
};

const _videoNoFace = {
  'unified_video_authenticity_score': {
    'unique_trx_id': 'trx_example_video_no_face',
    'filename': 'clip.mp4',
    'content_type': 'video/mp4',
    'status': 'rejected',
    'status_code': 6,
    'billable': 'Y',
    'video_risk_score': null,
    'video_risk_level': null,
    'video_message': 'No face detected in the video.',
    'audio_risk_score': null,
    'audio_risk_level': null,
    'audio_message': null,
  },
};

XFile _file(String name) =>
    XFile.fromData(Uint8List.fromList(List.filled(256, 7)),
        path: name, name: name);

NeuroVerifyClient Function() _clientReturning(
  int status,
  Object body, {
  List<http.BaseRequest>? requests,
}) =>
    () => NeuroVerifyClient.staging(
          apiKey: 'test-key',
          maxRetries: 0,
          httpClient: MockClient((request) async {
            requests?.add(request);
            return http.Response(
              jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

void main() {
  testWidgets('uploads a picked photo and shows its risk band', (tester) async {
    final requests = <http.BaseRequest>[];
    await tester.pumpWidget(NeuroVerifyExampleApp(
      clientFactory: _clientReturning(200, _imageSuccess, requests: requests),
      picker: (kind) async =>
          kind == MediaKind.image ? _file('selfie.jpg') : null,
    ));

    await tester.tap(find.text('Check a photo'));
    await tester.pumpAndSettle();

    expect(find.text('Low risk'), findsOneWidget);
    expect(find.text('Not likely to be Spoof or AI-generated'), findsOneWidget);
    expect(find.text('Transaction trx_example_low'), findsOneWidget);
    expect(requests.single.url.path, '/detect/image');
    expect(requests.single.headers['x-api-key'], 'test-key');
  });

  testWidgets('shows a rejected video as not scored', (tester) async {
    await tester.pumpWidget(NeuroVerifyExampleApp(
      clientFactory: _clientReturning(200, _videoNoFace),
      picker: (_) async => _file('clip.mp4'),
    ));

    await tester.tap(find.text('Check a video'));
    await tester.pumpAndSettle();

    expect(find.text('Not scored'), findsOneWidget);
    expect(find.text('No face detected in the video.'), findsOneWidget);
    expect(find.text('Billable: yes'), findsOneWidget);
  });

  testWidgets('maps a 401 to an actionable message', (tester) async {
    await tester.pumpWidget(NeuroVerifyExampleApp(
      clientFactory: _clientReturning(401, {'detail': 'Invalid API key'}),
      picker: (_) async => _file('selfie.jpg'),
    ));

    await tester.tap(find.text('Check a photo'));
    await tester.pumpAndSettle();

    expect(find.text('API key rejected'), findsOneWidget);
  });

  testWidgets('explains a missing API key instead of crashing', (tester) async {
    await tester.pumpWidget(NeuroVerifyExampleApp(
      clientFactory: () => NeuroVerifyClient.staging(apiKey: ''),
    ));

    expect(find.text('Configuration needed'), findsOneWidget);
    expect(find.text('Check a photo'), findsNothing);
  });

  testWidgets('ignores a cancelled picker', (tester) async {
    var calls = 0;
    await tester.pumpWidget(NeuroVerifyExampleApp(
      clientFactory: _clientReturning(200, _imageSuccess),
      picker: (_) async {
        calls++;
        return null;
      },
    ));

    await tester.tap(find.text('Check a photo'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(OutcomeCard), findsNothing);
  });
}
