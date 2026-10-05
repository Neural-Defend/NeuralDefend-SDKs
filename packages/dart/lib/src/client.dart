import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'errors.dart';
import 'media.dart';
import 'models.dart';
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';
import 'version.dart';
import 'wire.dart';

/// Default production API origin.
const String productionUrl = 'https://deepscan.neuraldefend.com';

/// Staging API origin, for integration testing with a staging key.
const String stagingUrl = 'https://stage.deepscan.neuraldefend.com';

/// Receives upload progress for the current attempt. [sentBytes] restarts at
/// zero when an automatic retry begins.
typedef UploadProgressCallback = void Function(int sentBytes, int totalBytes);

const Duration _defaultTimeout = Duration(seconds: 120);
const Duration _defaultRetryAfterCap = Duration(seconds: 60);
const int _maxAllowedRetries = 3;

/// Replaceable timing and randomness used by retry tests.
class ClientRuntime {
  const ClientRuntime({
    this.sleep = _defaultSleep,
    this.random = _defaultRandom,
    this.now = _defaultNow,
  });

  final Future<void> Function(Duration delay) sleep;
  final double Function() random;
  final DateTime Function() now;

  static Future<void> _defaultSleep(Duration delay) => Future.delayed(delay);
  static final math.Random _random = math.Random();
  static double _defaultRandom() => _random.nextDouble();
  static DateTime _defaultNow() => DateTime.now().toUtc();
}

/// Client for the NeuroVerify image and video authenticity API.
///
/// A client owns an HTTP connection pool; call [close] when it is no longer
/// needed. Results are decision-support signals, not proof of authenticity.
class NeuroVerifyClient {
  /// Creates a production client.
  ///
  /// * [apiKey] is sent in the `x-api-key` header. On the Dart VM it falls
  ///   back to `NEURALDEFEND_API_KEY`; Flutter and web apps must pass it
  ///   explicitly. Never ship a long-lived production key inside a mobile or
  ///   web app.
  /// * [baseUrl] is an HTTPS origin. It defaults to `NEURALDEFEND_BASE_URL`
  ///   on the Dart VM, then to [productionUrl].
  /// * [allowCustomBaseUrl] must be `true` before a non-Neural Defend origin
  ///   is accepted, because that origin receives the key and uploaded media.
  /// * [timeout] applies to each attempt, including reading the response.
  /// * [maxRetries] counts retries after the initial request (0 through 3).
  /// * [retryAfterCap] caps the wait honored from a `Retry-After` header.
  /// * [userAgent] overrides `neuraldefend-dart/<version>` where the platform
  ///   allows it; browsers ignore it.
  /// * [httpClient] supplies a custom `package:http` client (for example
  ///   `cupertino_http` or `cronet_http`). A supplied client is not closed by
  ///   [close].
  /// * [onWarning] receives non-fatal media validation warnings.
  factory NeuroVerifyClient({
    String? apiKey,
    String? baseUrl,
    bool allowCustomBaseUrl = false,
    Duration timeout = _defaultTimeout,
    int maxRetries = _maxAllowedRetries,
    Duration retryAfterCap = _defaultRetryAfterCap,
    String? userAgent,
    http.Client? httpClient,
    void Function(ValidationWarning warning)? onWarning,
  }) =>
      NeuroVerifyClient._(
        apiKey: apiKey,
        baseUrl: baseUrl ?? environmentValue('NEURALDEFEND_BASE_URL') ?? productionUrl,
        allowCustomBaseUrl: allowCustomBaseUrl,
        timeout: timeout,
        maxRetries: maxRetries,
        retryAfterCap: retryAfterCap,
        userAgent: userAgent,
        httpClient: httpClient,
        onWarning: onWarning,
        allowInsecureForTesting: false,
        runtime: const ClientRuntime(),
      );

  /// Creates a client pinned to [stagingUrl], ignoring
  /// `NEURALDEFEND_BASE_URL`. Use only with a staging credential.
  factory NeuroVerifyClient.staging({
    String? apiKey,
    Duration timeout = _defaultTimeout,
    int maxRetries = _maxAllowedRetries,
    Duration retryAfterCap = _defaultRetryAfterCap,
    String? userAgent,
    http.Client? httpClient,
    void Function(ValidationWarning warning)? onWarning,
  }) =>
      NeuroVerifyClient._(
        apiKey: apiKey,
        baseUrl: stagingUrl,
        allowCustomBaseUrl: false,
        timeout: timeout,
        maxRetries: maxRetries,
        retryAfterCap: retryAfterCap,
        userAgent: userAgent,
        httpClient: httpClient,
        onWarning: onWarning,
        allowInsecureForTesting: false,
        runtime: const ClientRuntime(),
      );

  NeuroVerifyClient._({
    required String? apiKey,
    required String baseUrl,
    required bool allowCustomBaseUrl,
    required Duration timeout,
    required int maxRetries,
    required Duration retryAfterCap,
    required String? userAgent,
    required http.Client? httpClient,
    required void Function(ValidationWarning warning)? onWarning,
    required bool allowInsecureForTesting,
    required ClientRuntime runtime,
  })  : timeout = _checkTimeout(timeout),
        maxRetries = _checkRetries(maxRetries),
        _apiKey = _resolveApiKey(apiKey),
        baseUrl = _validateBaseUrl(
          baseUrl,
          allowInsecure: allowInsecureForTesting,
          allowCustom: allowCustomBaseUrl,
        ),
        retryAfterCap = retryAfterCap.isNegative ? Duration.zero : retryAfterCap,
        _userAgent = canSetUserAgent
            ? (userAgent == null || userAgent.trim().isEmpty
                ? 'neuraldefend-dart/$sdkVersion'
                : userAgent)
            : null,
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _onWarning = onWarning ?? _ignoreWarning,
        _runtime = runtime;

  /// Validated API origin.
  final String baseUrl;

  /// Per-attempt timeout.
  final Duration timeout;

  /// Retries after the initial request for HTTP 429, 500, and 503.
  final int maxRetries;

  /// Maximum wait honored from a `Retry-After` header.
  final Duration retryAfterCap;

  final String _apiKey;
  final String? _userAgent;
  final http.Client _http;
  final bool _ownsHttp;
  final void Function(ValidationWarning warning) _onWarning;
  final ClientRuntime _runtime;
  bool _closed = false;

  /// Uploads an image to `/detect/image`.
  ///
  /// Business rejections (no face, multiple faces, quality or security
  /// failures) are returned as results with [ResultStatus.rejected]; branch on
  /// [ImageResult.status]. Operational failures throw a [NeuroVerifyError].
  ///
  /// Completing [abortTrigger] cancels preparation, retry waits, the upload,
  /// and response processing with an [AbortError].
  Future<ImageResult> detectImage(
    MediaInput media, {
    Future<void>? abortTrigger,
    UploadProgressCallback? onProgress,
  }) async {
    final response = await _execute(
      DetectionKind.image,
      media,
      const {},
      abortTrigger,
      onProgress,
    );
    return _classify(
      response,
      DetectionKind.image,
      (envelope, requestId) => parseImage(
        envelope,
        httpStatus: response.statusCode,
        requestId: requestId,
        secret: _apiKey,
      ),
    );
  }

  /// Uploads a video to `/detect/video`.
  ///
  /// [maxFrames] (1 through 100; API default 12) and [sampleRate] (at least 1)
  /// are sent as query parameters. Video and audio are scored independently.
  Future<VideoResult> detectVideo(
    MediaInput media, {
    int? maxFrames,
    int? sampleRate,
    Future<void>? abortTrigger,
    UploadProgressCallback? onProgress,
  }) async {
    if (maxFrames != null && (maxFrames < 1 || maxFrames > 100)) {
      throw ValidationError(
        ValidationErrorCode.invalidMaxFrames,
        'maxFrames must be an integer from 1 through 100.',
      );
    }
    if (sampleRate != null && sampleRate < 1) {
      throw ValidationError(
        ValidationErrorCode.invalidSampleRate,
        'sampleRate must be an integer greater than or equal to 1.',
      );
    }
    final response = await _execute(
      DetectionKind.video,
      media,
      {
        if (maxFrames != null) 'max_frames': '$maxFrames',
        if (sampleRate != null) 'sample_rate': '$sampleRate',
      },
      abortTrigger,
      onProgress,
    );
    return _classify(
      response,
      DetectionKind.video,
      (envelope, requestId) => parseVideo(
        envelope,
        httpStatus: response.statusCode,
        requestId: requestId,
        secret: _apiKey,
      ),
    );
  }

  /// Closes the HTTP client created by this SDK. A caller-supplied
  /// `httpClient` is left open.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsHttp) _http.close();
  }

  /// JSON-compatible configuration with the API key redacted.
  Map<String, Object?> toJson() => {
        'apiKey': '[REDACTED]',
        'baseUrl': baseUrl,
        'timeoutMs': timeout.inMilliseconds,
        'maxRetries': maxRetries,
      };

  @override
  String toString() => 'NeuroVerifyClient(${jsonEncode(toJson())})';

  Future<http.Response> _execute(
    DetectionKind kind,
    MediaInput input,
    Map<String, String> query,
    Future<void>? abortTrigger,
    UploadProgressCallback? onProgress,
  ) async {
    if (_closed) {
      throw StateError('This NeuroVerifyClient has been closed.');
    }
    final caller = _CallerAbort(abortTrigger);
    final media = await caller.guard(prepareMedia(input, kind, _onWarning));
    if (!media.replayable && maxRetries != 0) {
      throw ValidationError(
        ValidationErrorCode.streamNotReplayable,
        'Single-use streams require maxRetries: 0; use MediaInput.file, '
        'MediaInput.bytes, or MediaInput.openRead to allow retries.',
      );
    }
    final uri = Uri.parse('$baseUrl${kind.path}').replace(
      queryParameters: query.isEmpty ? null : query,
    );

    for (var attempt = 0;; attempt++) {
      caller.throwIfAborted();
      final response = await _attempt(kind, uri, media, caller, onProgress);
      final retryable = response.statusCode == 429 ||
          response.statusCode == 500 ||
          response.statusCode == 503;
      if (!retryable || attempt >= maxRetries) return response;
      await caller.guard(_runtime.sleep(_retryDelay(response, attempt)));
    }
  }

  Future<http.Response> _attempt(
    DetectionKind kind,
    Uri uri,
    PreparedMedia media,
    _CallerAbort caller,
    UploadProgressCallback? onProgress,
  ) async {
    final cancel = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!cancel.isCompleted) cancel.complete();
    });
    caller.onAbort(() {
      if (!cancel.isCompleted) cancel.complete();
    });

    Object? uploadFailure;
    final request = http.AbortableMultipartRequest(
      'POST',
      uri,
      abortTrigger: cancel.future,
    )
      ..followRedirects = false
      ..headers['accept'] = 'application/json'
      ..headers['x-api-key'] = _apiKey;
    final userAgent = _userAgent;
    if (userAgent != null) request.headers['user-agent'] = userAgent;

    Stream<List<int>> body() async* {
      var sent = 0;
      onProgress?.call(0, media.length);
      try {
        await for (final chunk in media.open()) {
          sent += chunk.length;
          yield chunk;
          onProgress?.call(sent, media.length);
        }
      } catch (error) {
        uploadFailure = error;
        rethrow;
      }
    }

    request.files.add(http.MultipartFile(
      'file',
      body(),
      media.length,
      filename: media.filename,
      contentType: MediaType.parse(media.contentType),
    ));

    try {
      final work = () async {
        final streamed = await _http.send(request);
        return http.Response.fromStream(streamed);
      }();
      return await _race(work, cancel.future);
    } catch (error) {
      if (caller.aborted) throw AbortError();
      if (timedOut) {
        throw TimeoutError('The ${kind.name} request timed out after '
            '${timeout.inMilliseconds} ms.');
      }
      final failure = uploadFailure;
      if (failure is ValidationError) throw failure;
      if (error is ValidationError) rethrow;
      if (error is http.ClientException || failure != null) {
        throw NetworkError(
          'The ${kind.name} request failed before receiving a response: '
          '${redact(_describe(error), _apiKey)}',
        );
      }
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  Duration _retryDelay(http.Response response, int attempt) {
    final base = math.min(math.pow(2, attempt).toDouble(), 4.0);
    if (response.statusCode == 429) {
      final retryAfter = _parseRetryAfter(response.headers['retry-after']);
      if (retryAfter != null) return retryAfter;
      return _min(_seconds(base), retryAfterCap);
    }
    final jitter = _runtime.random().clamp(0.0, 1.0) * base * 0.25;
    return _seconds(base + jitter);
  }

  Duration? _parseRetryAfter(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final seconds = num.tryParse(trimmed);
    Duration? parsed;
    if (seconds != null) {
      if (!seconds.isFinite) return null;
      parsed = _seconds(seconds.toDouble());
    } else {
      try {
        parsed = parseHttpDate(trimmed).difference(_runtime.now());
      } on FormatException {
        return null;
      }
    }
    if (parsed.isNegative) return Duration.zero;
    return _min(parsed, retryAfterCap);
  }

  T _classify<T>(
    http.Response response,
    DetectionKind kind,
    T Function(Map<String, Object?> envelope, String? requestId) parse,
  ) {
    final status = response.statusCode;
    final headerRequestId =
        response.headers['x-request-id'] ?? response.headers['x-correlation-id'];
    final json = _decodeObject(response);

    String detailOr(String fallback) {
      final detail = json?['detail'];
      return detail is String ? redact(detail, _apiKey) : fallback;
    }

    switch (status) {
      case 401:
        throw AuthenticationError(detailOr('HTTP 401'), requestId: headerRequestId);
      case 403:
        throw ScopeError(detailOr('HTTP 403'), requestId: headerRequestId);
      case 429:
        throw RateLimitError(
          detailOr('HTTP 429'),
          requestId: headerRequestId,
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
          limit: response.headers['x-ratelimit-limit'],
          remaining: response.headers['x-ratelimit-remaining'],
          reset: response.headers['x-ratelimit-reset'],
        );
      case 200 || 400 || 500 || 503:
        break;
      default:
        throw HttpError(
          detailOr('Unexpected HTTP $status.'),
          statusCode: status,
          requestId: headerRequestId,
        );
    }

    final envelopeKey = kind == DetectionKind.image ? imageEnvelope : videoEnvelope;
    final envelope = json?[envelopeKey];
    if (status == 500 || status == 503) {
      if (envelope is! Map<String, Object?>) {
        throw ServerError('HTTP $status', statusCode: status, requestId: headerRequestId);
      }
      final requestId = headerRequestId ?? _transactionId(envelope);
      final message =
          envelope[kind == DetectionKind.image ? 'message' : 'video_message'];
      throw ServerError(
        message is String ? redact(message, _apiKey) : 'HTTP $status',
        statusCode: status,
        requestId: requestId,
        raw: freezeEnvelope(envelope, _apiKey),
      );
    }
    if (json == null) {
      throw ProtocolError(
        'The server returned malformed JSON.',
        statusCode: status,
        requestId: headerRequestId,
      );
    }
    if (envelope is! Map<String, Object?>) {
      throw ProtocolError(
        'The response was missing "$envelopeKey".',
        statusCode: status,
        requestId: headerRequestId,
      );
    }
    final requestId = headerRequestId ?? _transactionId(envelope);
    final result = parse(envelope, requestId);
    final rejected = switch (result) {
      ImageResult(:final rejected) => rejected,
      VideoResult(:final rejected) => rejected,
      _ => false,
    };
    if (status == 400 && !rejected) {
      throw HttpError(
        'HTTP 400 response was not a rejection.',
        statusCode: 400,
        requestId: requestId,
      );
    }
    return result;
  }

  static Map<String, Object?>? _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String? _transactionId(Map<String, Object?> envelope) {
    final value = envelope['unique_trx_id'];
    return value is String && value.isNotEmpty ? value : null;
  }
}

/// Creates a client that accepts plain-HTTP origins and deterministic timing.
/// For SDK tests only; not exported from `package:neuraldefend/neuraldefend.dart`.
NeuroVerifyClient createTestClient({
  required String apiKey,
  required String baseUrl,
  required http.Client httpClient,
  Duration timeout = _defaultTimeout,
  int maxRetries = 0,
  Duration retryAfterCap = _defaultRetryAfterCap,
  String? userAgent,
  void Function(ValidationWarning warning)? onWarning,
  ClientRuntime runtime = const ClientRuntime(),
}) =>
    NeuroVerifyClient._(
      apiKey: apiKey,
      baseUrl: baseUrl,
      allowCustomBaseUrl: true,
      timeout: timeout,
      maxRetries: maxRetries,
      retryAfterCap: retryAfterCap,
      userAgent: userAgent,
      httpClient: httpClient,
      onWarning: onWarning,
      allowInsecureForTesting: true,
      runtime: runtime,
    );

Duration _checkTimeout(Duration timeout) {
  if (timeout <= Duration.zero) {
    throw ValidationError(
      ValidationErrorCode.invalidTimeout,
      'timeout must be greater than zero.',
    );
  }
  return timeout;
}

int _checkRetries(int maxRetries) {
  if (maxRetries < 0 || maxRetries > _maxAllowedRetries) {
    throw ValidationError(
      ValidationErrorCode.invalidRetries,
      'maxRetries must be an integer from 0 through 3.',
    );
  }
  return maxRetries;
}

String _resolveApiKey(String? explicit) {
  final value = (explicit ?? environmentValue('NEURALDEFEND_API_KEY'))?.trim() ?? '';
  if (value.isEmpty) {
    throw ValidationError(
      ValidationErrorCode.apiKeyRequired,
      platformLabel == 'dart-vm'
          ? 'apiKey is required; pass it explicitly or set NEURALDEFEND_API_KEY.'
          : 'apiKey is required in $platformLabel apps; pass it explicitly.',
    );
  }
  return value;
}

String _validateBaseUrl(
  String value, {
  required bool allowInsecure,
  required bool allowCustom,
}) {
  final Uri uri;
  try {
    uri = Uri.parse(value.trim());
  } on FormatException {
    throw ValidationError(
      ValidationErrorCode.invalidBaseUrl,
      'baseUrl must be a valid HTTPS origin.',
    );
  }
  final schemeAllowed =
      uri.scheme == 'https' || (allowInsecure && uri.scheme == 'http');
  if (!schemeAllowed ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw ValidationError(
      ValidationErrorCode.invalidBaseUrl,
      'baseUrl must be an HTTPS origin without credentials, a path, query, '
      'or fragment.',
    );
  }
  final origin = uri.replace(path: '').origin;
  if (origin != productionUrl && origin != stagingUrl && !allowCustom) {
    throw ValidationError(
      ValidationErrorCode.customBaseUrlRequiresOptIn,
      'A non-Neural Defend baseUrl requires allowCustomBaseUrl: true because '
      'it receives the API key and uploaded media.',
    );
  }
  return origin;
}

void _ignoreWarning(ValidationWarning warning) {}

Duration _seconds(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

Duration _min(Duration a, Duration b) => a < b ? a : b;

String _describe(Object error) =>
    error is http.ClientException ? error.message : error.runtimeType.toString();

/// Completes [work] unless [cancel] completes first, in which case the
/// returned future fails and any later outcome of [work] is ignored.
Future<T> _race<T>(Future<T> work, Future<void> cancel) {
  final result = Completer<T>();
  work.then(
    (value) {
      if (!result.isCompleted) result.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  cancel.then((_) {
    if (!result.isCompleted) {
      result.completeError(const _Cancelled(), StackTrace.current);
    }
  });
  return result.future;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Tracks the caller's abort trigger across preparation, attempts, and retry
/// waits.
class _CallerAbort {
  _CallerAbort(Future<void>? trigger) {
    trigger?.then(
      (_) => _fire(),
      onError: (Object _) => _fire(),
    );
  }

  final Completer<void> _aborted = Completer<void>();
  final List<void Function()> _listeners = [];

  bool get aborted => _aborted.isCompleted;

  void _fire() {
    if (_aborted.isCompleted) return;
    _aborted.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void onAbort(void Function() listener) {
    if (aborted) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void throwIfAborted() {
    if (aborted) throw AbortError();
  }

  Future<T> guard<T>(Future<T> work) async {
    throwIfAborted();
    try {
      return await _race(work, _aborted.future);
    } on _Cancelled {
      throw AbortError();
    }
  }
}
