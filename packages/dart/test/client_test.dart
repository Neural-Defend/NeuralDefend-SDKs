@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:neuraldefend/neuraldefend.dart';
import 'package:neuraldefend/src/client.dart'
    show ClientRuntime, createTestClient;
import 'package:test/test.dart';

import 'support.dart';

final Uint8List _bytes = Uint8List.fromList(utf8.encode('image-bytes'));
MediaInput _jpeg() => MediaInput.bytes(_bytes, filename: 'x.jpg');
MediaInput _mp4() => MediaInput.bytes(_bytes, filename: 'x.mp4');

Map<String, Object?> _withStatus(String fixture, int status) =>
    {...loadCase(fixture), 'http_status': status};

void main() {
  group('retries', () {
    test('HTTP 500 retries three times with 1, 2, 4 second backoff', () async {
      final fake = FakeRuntime();
      final opens = <int>[];
      final transport = fixtureTransport([
        'image/documented/internal-error-500.json',
        'image/documented/internal-error-500.json',
        'image/documented/internal-error-500.json',
        'image/documented/low-risk.json',
      ]);
      final client =
          testClient(transport, maxRetries: 3, runtime: fake.runtime);

      final result = await client.detectImage(MediaInput.openRead(
        () {
          opens.add(opens.length + 1);
          return Stream.value(utf8.encode('streamed-payload'));
        },
        length: 16,
        filename: 'retry.jpg',
      ));

      expect(result.scored, isTrue);
      expect(transport.requests, hasLength(4));
      expect(opens, [1, 2, 3, 4]);
      for (final request in transport.requests) {
        expect(request.bodyText, contains('streamed-payload'));
      }
      expect(fake.sleeps, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
    });

    test('server backoff adds at most 25 percent jitter', () async {
      final fake = FakeRuntime(jitter: 1);
      final transport = fixtureTransport([
        'video/documented/service-unavailable-503.json',
        'video/documented/service-unavailable-503.json',
        'video/documented/both-low.json',
      ]);
      final client =
          testClient(transport, maxRetries: 3, runtime: fake.runtime);
      await client.detectVideo(_mp4());
      expect(fake.sleeps, const [
        Duration(milliseconds: 1250),
        Duration(milliseconds: 2500),
      ]);
    });

    test('exhausted HTTP 503 retries throw ServerError after four attempts',
        () async {
      final fake = FakeRuntime();
      final transport =
          fixtureTransport(['image/documented/service-unavailable-503.json']);
      final client =
          testClient(transport, maxRetries: 3, runtime: fake.runtime);
      await expectLater(
          client.detectImage(_jpeg()), throwsA(isA<ServerError>()));
      expect(transport.requests, hasLength(4));
      expect(fake.sleeps, hasLength(3));
    });

    test('HTTP 429 honors numeric Retry-After, then succeeds', () async {
      final fake = FakeRuntime();
      final transport = fixtureTransport([
        'image/synthetic/rate-limited-429.json',
        'image/documented/low-risk.json',
      ]);
      final client =
          testClient(transport, maxRetries: 1, runtime: fake.runtime);
      final result = await client.detectImage(_jpeg());
      expect(result.scored, isTrue);
      expect(transport.requests, hasLength(2));
      expect(fake.sleeps, const [Duration(seconds: 60)]);
    });

    test('Retry-After is capped by retryAfterCap', () async {
      final fake = FakeRuntime();
      final transport = fixtureTransport([
        'image/synthetic/rate-limited-429.json',
        'image/documented/low-risk.json',
      ]);
      final client = testClient(
        transport,
        maxRetries: 1,
        retryAfterCap: const Duration(seconds: 5),
        runtime: fake.runtime,
      );
      await client.detectImage(_jpeg());
      expect(fake.sleeps, const [Duration(seconds: 5)]);
    });

    test('Retry-After HTTP dates are relative to the clock', () async {
      final fake = FakeRuntime(now: DateTime.utc(2026, 7, 26, 23, 59, 30));
      final limited = loadCase('image/synthetic/rate-limited-429.json');
      final headers = {
        ...(limited['headers']! as Map<String, Object?>),
        'retry-after': 'Sun, 26 Jul 2026 23:59:45 GMT',
      };
      var calls = 0;
      final transport = RecordingClient((call, _) async {
        calls = call;
        return responseFromCase(
          call == 1
              ? {...limited, 'headers': headers}
              : loadCase('image/documented/low-risk.json'),
        );
      });
      final client =
          testClient(transport, maxRetries: 1, runtime: fake.runtime);
      await client.detectImage(_jpeg());
      expect(calls, 2);
      expect(fake.sleeps, const [Duration(seconds: 15)]);
    });

    test('HTTP 429 without Retry-After uses exponential delays', () async {
      final fake = FakeRuntime();
      final limited = loadCase('image/synthetic/rate-limited-429.json');
      final transport = RecordingClient((call, _) async => responseFromCase(
            call < 3
                ? {...limited, 'headers': <String, Object?>{}}
                : loadCase('image/documented/low-risk.json'),
          ));
      final client =
          testClient(transport, maxRetries: 3, runtime: fake.runtime);
      await client.detectImage(_jpeg());
      expect(fake.sleeps, const [Duration(seconds: 1), Duration(seconds: 2)]);
    });

    test('exhausted HTTP 429 throws RateLimitError', () async {
      final fake = FakeRuntime();
      final transport =
          fixtureTransport(['video/synthetic/rate-limited-429.json']);
      final client =
          testClient(transport, maxRetries: 2, runtime: fake.runtime);
      await expectLater(
          client.detectVideo(_mp4()), throwsA(isA<RateLimitError>()));
      expect(transport.requests, hasLength(3));
    });

    for (final fixture in [
      'image/documented/blurry.json',
      'image/synthetic/unauthorized-401.json',
      'image/synthetic/forbidden-403.json',
      'image/documented/low-risk.json',
      'image/documented/no-face.json',
    ]) {
      test('never retries $fixture', () async {
        final fake = FakeRuntime();
        final transport = fixtureTransport([fixture]);
        final client =
            testClient(transport, maxRetries: 3, runtime: fake.runtime);
        try {
          await client.detectImage(_jpeg());
        } on NeuroVerifyError {
          // Expected for 401 and 403.
        }
        expect(transport.requests, hasLength(1));
        expect(fake.sleeps, isEmpty);
      });
    }

    test('maxRetries 0 disables retries', () async {
      final transport =
          fixtureTransport(['image/documented/internal-error-500.json']);
      final client = testClient(transport, maxRetries: 0);
      await expectLater(
          client.detectImage(_jpeg()), throwsA(isA<ServerError>()));
      expect(transport.requests, hasLength(1));
    });
  });

  group('request shape', () {
    test('sends the API key, user agent, and a multipart file part', () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final client = testClient(transport);
      await client.detectImage(MediaInput.bytes(_bytes, filename: 'Photo.JPG'));

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$testBaseUrl/detect/image');
      expect(request.headers['x-api-key'], testApiKey);
      expect(request.headers['user-agent'], 'neuraldefend-dart/$sdkVersion');
      expect(request.headers['accept'], 'application/json');
      expect(request.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      expect(request.bodyText, contains('name="file"; filename="Photo.JPG"'));
      expect(request.bodyText, contains('content-type: image/jpeg'));
      expect(request.bodyText, contains('image-bytes'));
    });

    test('custom user agent is sent', () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final client = testClient(transport, userAgent: 'kyc-app/2.4.0');
      await client.detectImage(_jpeg());
      expect(transport.requests.single.headers['user-agent'], 'kyc-app/2.4.0');
    });

    test('video options are sent as query parameters', () async {
      final transport = fixtureTransport(['video/documented/both-low.json']);
      final client = testClient(transport);
      final result =
          await client.detectVideo(_mp4(), maxFrames: 100, sampleRate: 1);
      expect(result.scored, isTrue);
      expect(transport.requests.single.url.queryParameters, {
        'max_frames': '100',
        'sample_rate': '1',
      });
    });

    test('video query is omitted when options are not set', () async {
      final transport = fixtureTransport(['video/documented/both-low.json']);
      await testClient(transport).detectVideo(_mp4());
      expect(transport.requests.single.url.hasQuery, isFalse);
    });

    for (final (maxFrames, sampleRate, code) in [
      (0, null, ValidationErrorCode.invalidMaxFrames),
      (101, null, ValidationErrorCode.invalidMaxFrames),
      (null, 0, ValidationErrorCode.invalidSampleRate),
    ]) {
      test('rejects maxFrames=$maxFrames sampleRate=$sampleRate locally',
          () async {
        final transport = fixtureTransport(['video/documented/both-low.json']);
        await expectLater(
          testClient(transport).detectVideo(_mp4(),
              maxFrames: maxFrames, sampleRate: sampleRate),
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', code)),
        );
        expect(transport.requests, isEmpty);
      });
    }

    test('progress reports the upload for each attempt', () async {
      final progress = <(int, int)>[];
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      await testClient(transport).detectImage(
        MediaInput.openRead(
          () => Stream.fromIterable([utf8.encode('abc'), utf8.encode('defg')]),
          length: 7,
          filename: 'p.png',
        ),
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(progress, [(0, 7), (3, 7), (7, 7)]);
    });
  });

  group('response classification', () {
    test('HTTP 200 error envelope throws a redacted ServerError', () async {
      final caseData =
          _withStatus('image/documented/internal-error-500.json', 200);
      final body =
          jsonDecode(jsonEncode(caseData['body'])) as Map<String, Object?>;
      final envelope =
          body['unified_face_authenticity_score']! as Map<String, Object?>;
      envelope['message'] = 'failed for $testApiKey';
      envelope['future'] = {
        'echo': ['nested $testApiKey'],
      };
      final transport = RecordingClient(
        (_, __) async => responseFromCase({...caseData, 'body': body}),
      );

      final error = await testClient(transport)
          .detectImage(_jpeg())
          .then<Object>((value) => value, onError: (Object e) => e);
      expect(error, isA<ServerError>());
      final serverError = error as ServerError;
      expect(serverError.statusCode, 200);
      expect(serverError.detail, 'failed for [REDACTED]');
      expect(jsonEncode(serverError.raw), isNot(contains(testApiKey)));
      expect(serverError.toString(), isNot(contains(testApiKey)));
    });

    test('API keys echoed in successful results are redacted from raw',
        () async {
      final caseData = loadCase('image/documented/low-risk.json');
      final body =
          jsonDecode(jsonEncode(caseData['body'])) as Map<String, Object?>;
      (body['unified_face_authenticity_score']!
          as Map<String, Object?>)['echo'] = testApiKey;
      final transport = RecordingClient(
        (_, __) async => responseFromCase({...caseData, 'body': body}),
      );
      final result = await testClient(transport).detectImage(_jpeg());
      expect(result.raw['echo'], '[REDACTED]');
    });

    test('HTTP 400 that is not a rejection throws HttpError', () async {
      final transport = RecordingClient((_, __) async =>
          responseFromCase(_withStatus('image/documented/low-risk.json', 400)));
      await expectLater(
        testClient(transport).detectImage(_jpeg()),
        throwsA(
            isA<HttpError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('unexpected HTTP status throws HttpError with the server detail',
        () async {
      final transport = RecordingClient((_, __) async => http.StreamedResponse(
            Stream.value(utf8.encode('{"detail": "Not Found"}')),
            404,
            headers: {'x-request-id': 'req-404'},
          ));
      await expectLater(
        testClient(transport).detectImage(_jpeg()),
        throwsA(isA<HttpError>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.detail, 'detail', 'Not Found')
            .having((e) => e.requestId, 'requestId', 'req-404')),
      );
    });

    test('non-JSON 401 still throws AuthenticationError', () async {
      final transport = RecordingClient(
        (_, __) async =>
            http.StreamedResponse(Stream.value(utf8.encode('<html>')), 401),
      );
      await expectLater(
        testClient(transport).detectImage(_jpeg()),
        throwsA(isA<AuthenticationError>()
            .having((e) => e.detail, 'detail', 'HTTP 401')),
      );
    });

    test('request id prefers the X-Request-ID header', () async {
      final caseData = loadCase('image/documented/internal-error-500.json');
      final transport = RecordingClient((_, __) async => responseFromCase({
            ...caseData,
            'headers': {'x-request-id': 'req-123'},
          }));
      await expectLater(
        testClient(transport).detectImage(_jpeg()),
        throwsA(isA<ServerError>()
            .having((e) => e.requestId, 'requestId', 'req-123')),
      );
    });

    for (final (field, value) in [
      ('billable', 'yes'),
      ('risk_score', 11.0),
      ('risk_score', 'high'),
      ('status_code', 1.5),
      ('ai_threat_signals', [1]),
    ]) {
      test('invalid $field=$value throws ProtocolError', () async {
        final caseData = loadCase('image/documented/low-risk.json');
        final body =
            jsonDecode(jsonEncode(caseData['body'])) as Map<String, Object?>;
        (body['unified_face_authenticity_score']!
            as Map<String, Object?>)[field] = value;
        final transport = RecordingClient(
          (_, __) async => responseFromCase({...caseData, 'body': body}),
        );
        await expectLater(
          testClient(transport).detectImage(_jpeg()),
          throwsA(isA<ProtocolError>()),
        );
      });
    }

    test('a missing required nullable field throws ProtocolError', () async {
      final caseData = loadCase('video/documented/both-low.json');
      final body =
          jsonDecode(jsonEncode(caseData['body'])) as Map<String, Object?>;
      (body['unified_video_authenticity_score']! as Map<String, Object?>)
          .remove('audio_risk_score');
      final transport = RecordingClient(
        (_, __) async => responseFromCase({...caseData, 'body': body}),
      );
      await expectLater(testClient(transport).detectVideo(_mp4()),
          throwsA(isA<ProtocolError>()));
    });
  });

  group('media validation', () {
    late Directory directory;
    setUp(() =>
        directory = Directory.systemTemp.createTempSync('neuraldefend-test-'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('streams a file path and infers the filename', () async {
      final file = File('${directory.path}/valid.jpg')
        ..writeAsStringSync('path-content');
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final result =
          await testClient(transport).detectImage(MediaInput.file(file.path));
      expect(result.scored, isTrue);
      expect(
          transport.requests.single.bodyText, contains('filename="valid.jpg"'));
      expect(transport.requests.single.bodyText, contains('path-content'));
    });

    test('an explicit filename overrides the path basename', () async {
      final file = File('${directory.path}/upload.bin')..writeAsStringSync('x');
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      await testClient(transport)
          .detectImage(MediaInput.file(file.path, filename: 'selfie.png'));
      expect(transport.requests.single.bodyText,
          contains('filename="selfie.png"'));
      expect(transport.requests.single.bodyText,
          contains('content-type: image/png'));
    });

    test('rejects empty, missing, directory, and symlink paths', () async {
      final empty = File('${directory.path}/empty.jpg')..createSync();
      final folder = Directory('${directory.path}/folder.jpg')..createSync();
      final target = File('${directory.path}/target.jpg')
        ..writeAsStringSync('x');
      final link = Link('${directory.path}/link.jpg')..createSync(target.path);
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final client = testClient(transport);

      final cases = {
        empty.path: ValidationErrorCode.emptyFile,
        '${directory.path}/missing.jpg': ValidationErrorCode.fileNotFound,
        folder.path: ValidationErrorCode.unsupportedInput,
        link.path: ValidationErrorCode.unsupportedInput,
      };
      for (final MapEntry(key: path, value: code) in cases.entries) {
        await expectLater(
          client.detectImage(MediaInput.file(path)),
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', code)),
          reason: path,
        );
      }
      expect(transport.requests, isEmpty);
    });

    test('rejects oversized media before uploading', () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final client = testClient(transport);
      await expectLater(
        client.detectImage(MediaInput.openRead(
          () => const Stream.empty(),
          length: imageMaxBytes + 1,
          filename: 'big.jpg',
        )),
        throwsA(isA<ValidationError>()
            .having((e) => e.code, 'code', ValidationErrorCode.fileTooLarge)),
      );
      await expectLater(
        client.detectVideo(MediaInput.openRead(
          () => const Stream.empty(),
          length: videoMaxBytes + 1,
          filename: 'big.mp4',
        )),
        throwsA(isA<ValidationError>()
            .having((e) => e.code, 'code', ValidationErrorCode.fileTooLarge)),
      );
      expect(transport.requests, isEmpty);
    });

    test('accepts media of exactly the maximum size', () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final exact = Uint8List(imageMaxBytes);
      final result = await testClient(transport)
          .detectImage(MediaInput.bytes(exact, filename: 'max.jpg'));
      expect(result.scored, isTrue);
      expect(transport.requests.single.body.length, greaterThan(imageMaxBytes));
    });

    test('requires a filename for bytes and streams', () async {
      final client =
          testClient(fixtureTransport(['image/documented/low-risk.json']));
      await expectLater(
        client.detectImage(MediaInput.bytes(_bytes, filename: '  ')),
        throwsA(isA<ValidationError>().having(
            (e) => e.code, 'code', ValidationErrorCode.filenameRequired)),
      );
    });

    test('warns about undocumented extensions but still uploads', () async {
      final warnings = <ValidationWarning>[];
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      await testClient(transport, onWarning: warnings.add)
          .detectImage(MediaInput.bytes(_bytes, filename: 'scan.gif'));
      expect(warnings.single.code, 'unsupported_extension');
      expect(warnings.single.filename, 'scan.gif');
      expect(transport.requests.single.bodyText,
          contains('content-type: application/octet-stream'));
    });

    test('single-use streams require maxRetries 0', () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      await expectLater(
        testClient(transport, maxRetries: 1).detectImage(
          MediaInput.stream(Stream.value([1, 2, 3]),
              length: 3, filename: 'x.jpg'),
        ),
        throwsA(isA<ValidationError>().having(
            (e) => e.code, 'code', ValidationErrorCode.streamNotReplayable)),
      );
      final result = await testClient(transport).detectImage(
        MediaInput.stream(Stream.value([1, 2, 3]),
            length: 3, filename: 'x.jpg'),
      );
      expect(result.scored, isTrue);
    });

    test('streams must produce exactly the declared length', () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final client = testClient(transport);
      for (final actual in [2, 4]) {
        await expectLater(
          client.detectImage(MediaInput.openRead(
            () => Stream.value(List.filled(actual, 7)),
            length: 3,
            filename: 'x.jpg',
          )),
          throwsA(isA<ValidationError>()),
          reason: 'emitted $actual bytes for a declared length of 3',
        );
      }
    });

    test('documented formats map to deterministic MIME types', () {
      expect(mimeForFilename('photo.jpg'), 'image/jpeg');
      expect(mimeForFilename('PHOTO.HEIF'), 'image/heif');
      expect(mimeForFilename('clip.mp4'), 'video/mp4');
      expect(mimeForFilename('clip.avi'), 'video/vnd.avi');
      expect(mimeForFilename('clip.ogv'), 'video/ogg');
      expect(mimeForFilename('unknown.xyz'), 'application/octet-stream');
      expect(mimeForFilename('noextension'), 'application/octet-stream');
      expect(imageExtensions, hasLength(9));
      expect(videoExtensions, hasLength(9));
    });
  });

  group('configuration', () {
    test('defaults', () {
      final client = NeuroVerifyClient(apiKey: 'key');
      expect(client.baseUrl, productionUrl);
      expect(client.timeout, const Duration(seconds: 120));
      expect(client.maxRetries, 3);
      expect(client.retryAfterCap, const Duration(seconds: 60));
      client.close();
    });

    test('staging is pinned', () {
      final client = NeuroVerifyClient.staging(apiKey: 'key');
      expect(client.baseUrl, stagingUrl);
      client.close();
    });

    test('custom origins require explicit opt-in', () {
      expect(
        () => NeuroVerifyClient(
            apiKey: 'key', baseUrl: 'https://api.example.com'),
        throwsA(isA<ValidationError>().having((e) => e.code, 'code',
            ValidationErrorCode.customBaseUrlRequiresOptIn)),
      );
      final client = NeuroVerifyClient(
        apiKey: 'key',
        baseUrl: 'https://api.example.com:8443/',
        allowCustomBaseUrl: true,
      );
      expect(client.baseUrl, 'https://api.example.com:8443');
      client.close();
    });

    for (final url in [
      'http://deepscan.neuraldefend.com',
      'https://deepscan.neuraldefend.com/api',
      'https://user:pass@deepscan.neuraldefend.com',
      'https://deepscan.neuraldefend.com?x=1',
      'https://deepscan.neuraldefend.com#frag',
      'not a url',
    ]) {
      test('rejects base URL $url', () {
        expect(
          () => NeuroVerifyClient(
              apiKey: 'key', baseUrl: url, allowCustomBaseUrl: true),
          throwsA(isA<ValidationError>().having(
              (e) => e.code, 'code', ValidationErrorCode.invalidBaseUrl)),
        );
      });
    }

    test('validates the API key, timeout, and retries', () {
      Matcher code(ValidationErrorCode code) =>
          throwsA(isA<ValidationError>().having((e) => e.code, 'code', code));
      expect(() => NeuroVerifyClient(apiKey: '   '),
          code(ValidationErrorCode.apiKeyRequired));
      expect(() => NeuroVerifyClient(apiKey: 'k', timeout: Duration.zero),
          code(ValidationErrorCode.invalidTimeout));
      expect(() => NeuroVerifyClient(apiKey: 'k', maxRetries: -1),
          code(ValidationErrorCode.invalidRetries));
      expect(() => NeuroVerifyClient(apiKey: 'k', maxRetries: 4),
          code(ValidationErrorCode.invalidRetries));
    });

    test('the API key is trimmed and redacted from toString and toJson',
        () async {
      final transport = fixtureTransport(['image/documented/low-risk.json']);
      final client = createTestClient(
        apiKey: '  $testApiKey  ',
        baseUrl: testBaseUrl,
        httpClient: transport,
      );
      expect(client.toString(), isNot(contains(testApiKey)));
      expect(client.toJson()['apiKey'], '[REDACTED]');
      await client.detectImage(_jpeg());
      expect(transport.requests.single.headers['x-api-key'], testApiKey);
    });

    test('Dart VM reads NEURALDEFEND_API_KEY and NEURALDEFEND_BASE_URL',
        () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'test/environment_probe.dart'],
        environment: {
          'NEURALDEFEND_API_KEY': 'environment-key',
          'NEURALDEFEND_BASE_URL': 'https://stage.deepscan.neuraldefend.com',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final lines = const LineSplitter().convert('${result.stdout}'.trim());
      expect(lines.last,
          'https://stage.deepscan.neuraldefend.com|staging-pinned=https://stage.deepscan.neuraldefend.com');
    });

    test('close() closes only an SDK-owned HTTP client', () async {
      final supplied = fixtureTransport(['image/documented/low-risk.json']);
      final client = testClient(supplied)..close();
      expect(supplied.closed, isFalse);
      await expectLater(client.detectImage(_jpeg()), throwsStateError);
    });
  });

  group('real sockets', () {
    late HttpServer server;
    late String origin;
    late Future<void> Function(HttpRequest request) handler;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = 'http://${server.address.host}:${server.port}';
      server.listen((request) => handler(request));
    });
    tearDown(() => server.close(force: true));

    NeuroVerifyClient socketClient({
      Duration timeout = const Duration(seconds: 10),
      int maxRetries = 0,
      ClientRuntime runtime = const ClientRuntime(),
    }) =>
        createTestClient(
          apiKey: testApiKey,
          baseUrl: origin,
          httpClient: http.Client(),
          timeout: timeout,
          maxRetries: maxRetries,
          runtime: runtime,
        );

    Future<void> reply(HttpRequest request, String fixture) async {
      final caseData = loadCase(fixture);
      request.response.statusCode = caseData['http_status']! as int;
      request.response.headers.contentType = ContentType.json;
      request.response.add(fixtureBody(caseData));
      await request.response.close();
    }

    test('streams a large file upload over a real connection', () async {
      final directory =
          Directory.systemTemp.createTempSync('neuraldefend-socket-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/clip.mp4')
        ..writeAsBytesSync(List.generate(5 * 1024 * 1024, (i) => i % 251));
      var received = 0;
      handler = (request) async {
        await for (final chunk in request) {
          received += chunk.length;
        }
        await reply(request, 'video/documented/both-low.json');
      };
      final client = socketClient();
      final result =
          await client.detectVideo(MediaInput.file(file.path), maxFrames: 2);
      expect(result.scored, isTrue);
      expect(received, greaterThan(5 * 1024 * 1024));
      client.close();
    });

    test('a slow server raises TimeoutError and is not retried', () async {
      var calls = 0;
      handler = (request) async {
        calls++;
        await request.drain<void>();
        await Future<void>.delayed(const Duration(seconds: 3));
        await reply(request, 'image/documented/low-risk.json');
      };
      final fake = FakeRuntime();
      final client = socketClient(
        timeout: const Duration(milliseconds: 300),
        maxRetries: 3,
        runtime: fake.runtime,
      );
      final stopwatch = Stopwatch()..start();
      await expectLater(
          client.detectImage(_jpeg()), throwsA(isA<TimeoutError>()));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(calls, 1);
      expect(fake.sleeps, isEmpty);
      client.close();
    });

    test('the abort trigger cancels an in-flight request', () async {
      handler = (request) async {
        await request.drain<void>();
        await Future<void>.delayed(const Duration(seconds: 3));
        await reply(request, 'image/documented/low-risk.json');
      };
      final client = socketClient();
      final abort = Completer<void>();
      final pending = client.detectImage(_jpeg(), abortTrigger: abort.future);
      Timer(const Duration(milliseconds: 200), abort.complete);
      await expectLater(pending, throwsA(isA<AbortError>()));
      client.close();
    });

    test('the abort trigger cancels a retry wait', () async {
      handler = (request) async {
        await request.drain<void>();
        await reply(request, 'image/documented/service-unavailable-503.json');
      };
      final abort = Completer<void>();
      final client = socketClient(
        maxRetries: 3,
        runtime: ClientRuntime(sleep: (_) {
          abort.complete();
          return Completer<void>().future;
        }),
      );
      await expectLater(
        client.detectImage(_jpeg(), abortTrigger: abort.future),
        throwsA(isA<AbortError>()),
      );
      client.close();
    });

    test('redirects are never followed', () async {
      var calls = 0;
      handler = (request) async {
        calls++;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '$origin/elsewhere');
        await request.response.close();
      };
      final client = socketClient();
      await expectLater(
        client.detectImage(_jpeg()),
        throwsA(
            isA<HttpError>().having((e) => e.statusCode, 'statusCode', 302)),
      );
      expect(calls, 1);
      client.close();
    });

    test('a refused connection raises NetworkError without the API key',
        () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final client = createTestClient(
        apiKey: testApiKey,
        baseUrl: 'http://127.0.0.1:$port',
        httpClient: http.Client(),
        maxRetries: 3,
      );
      final error = await client
          .detectImage(_jpeg())
          .then<Object>((value) => value, onError: (Object e) => e);
      expect(error, isA<NetworkError>());
      expect(error.toString(), isNot(contains(testApiKey)));
      client.close();
    });
  });
}
