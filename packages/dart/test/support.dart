import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuraldefend/src/client.dart';
import 'package:neuraldefend/src/models.dart';

const String testApiKey = 'secret-test-key';
const String testBaseUrl = 'http://sdk.test';

final Directory fixturesRoot = Directory('../../tests/fixtures');

Map<String, Object?> loadCase(String relativePath) {
  final file = File('${fixturesRoot.path}/$relativePath');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// Every fixture path relative to [fixturesRoot], sorted.
List<String> allFixturePaths() {
  final paths = <String>[];
  for (final kind in ['image', 'video']) {
    final directory = Directory('${fixturesRoot.path}/$kind');
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.json')) {
        paths.add(entity.path.substring(fixturesRoot.path.length + 1).replaceAll(r'\', '/'));
      }
    }
  }
  return paths..sort();
}

Map<String, Object?> wireEnvelope(Map<String, Object?> caseData) {
  final body = caseData['body']! as Map<String, Object?>;
  final key = caseData['endpoint'] == '/detect/image'
      ? 'unified_face_authenticity_score'
      : 'unified_video_authenticity_score';
  return body[key]! as Map<String, Object?>;
}

List<int> fixtureBody(Map<String, Object?> caseData) {
  final body = caseData['body'];
  if (caseData['body_kind'] == 'raw') return utf8.encode(body! as String);
  return utf8.encode(jsonEncode(body));
}

http.StreamedResponse responseFromCase(Map<String, Object?> caseData) {
  final headers = (caseData['headers'] as Map<String, Object?>? ?? const {})
      .map((key, value) => MapEntry(key.toLowerCase(), value! as String));
  final body = fixtureBody(caseData);
  return http.StreamedResponse(
    Stream.value(body),
    caseData['http_status']! as int,
    headers: headers,
    contentLength: body.length,
  );
}

/// A request observed by [RecordingClient].
class RecordedRequest {
  RecordedRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> body;

  String get bodyText => latin1.decode(body);
}

/// Mock transport that fully consumes each streamed upload before replying.
class RecordingClient extends http.BaseClient {
  RecordingClient(this.respond);

  final Future<http.StreamedResponse> Function(int call, RecordedRequest request) respond;
  final List<RecordedRequest> requests = [];
  bool closed = false;

  late final MockClient _mock = MockClient.streaming((request, bodyStream) async {
    final body = await bodyStream.toBytes();
    final recorded = RecordedRequest(
      request.method,
      request.url,
      Map.of(request.headers),
      body,
    );
    requests.add(recorded);
    return respond(requests.length, recorded);
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _mock.send(request);

  @override
  void close() {
    closed = true;
    _mock.close();
  }
}

RecordingClient fixtureTransport(List<String> fixtures) => RecordingClient(
      (call, _) async => responseFromCase(
        loadCase(fixtures[(call - 1).clamp(0, fixtures.length - 1)]),
      ),
    );

/// Deterministic sleep, jitter, and clock that record every requested delay.
class FakeRuntime {
  FakeRuntime({this.jitter = 0, DateTime? now})
      : now = now ?? DateTime.utc(2026, 7, 26, 23, 59);

  final double jitter;
  final DateTime now;
  final List<Duration> sleeps = [];

  ClientRuntime get runtime => ClientRuntime(
        sleep: (delay) async => sleeps.add(delay),
        random: () => jitter,
        now: () => now,
      );
}

NeuroVerifyClient testClient(
  http.Client transport, {
  int maxRetries = 0,
  Duration timeout = const Duration(seconds: 30),
  Duration retryAfterCap = const Duration(seconds: 60),
  String? userAgent,
  ClientRuntime runtime = const ClientRuntime(),
  void Function(ValidationWarning warning)? onWarning,
  String baseUrl = testBaseUrl,
}) =>
    createTestClient(
      apiKey: testApiKey,
      baseUrl: baseUrl,
      httpClient: transport,
      maxRetries: maxRetries,
      timeout: timeout,
      retryAfterCap: retryAfterCap,
      userAgent: userAgent,
      runtime: runtime,
      onWarning: onWarning,
    );
