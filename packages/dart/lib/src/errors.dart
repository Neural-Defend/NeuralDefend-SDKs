/// Base class for every exception thrown by the NeuroVerify SDK.
///
/// The class names match the Python, TypeScript, and Go SDKs. They implement
/// [Exception] rather than extending [Error] because they describe runtime
/// conditions an application is expected to handle.
abstract class NeuroVerifyError implements Exception {
  NeuroVerifyError(this.detail, {this.statusCode, this.requestId});

  /// Redacted, human-readable description of the failure.
  final String detail;

  /// HTTP status code when the failure was derived from a response.
  final int? statusCode;

  /// `X-Request-ID`/`X-Correlation-ID` header, or the transaction ID of the
  /// response envelope when no header was returned.
  final String? requestId;

  @override
  String toString() {
    final parts = <String>[
      if (statusCode != null) 'statusCode: $statusCode',
      if (requestId != null) 'requestId: $requestId',
    ];
    final suffix = parts.isEmpty ? '' : ' (${parts.join(', ')})';
    return '$runtimeType: $detail$suffix';
  }
}

/// Category of a local [ValidationError].
enum ValidationErrorCode {
  apiKeyRequired,
  customBaseUrlRequiresOptIn,
  emptyFile,
  fileNotFound,
  fileTooLarge,
  filenameRequired,
  invalidBaseUrl,
  invalidMaxFrames,
  invalidRetries,
  invalidSampleRate,
  invalidTimeout,
  streamNotReplayable,
  unsupportedInput,
}

/// Local configuration, option, or media validation failed before a request
/// could complete. Correct the input; do not retry it unchanged.
class ValidationError extends NeuroVerifyError {
  ValidationError(this.code, super.detail);

  final ValidationErrorCode code;
}

/// An HTTP response that is not otherwise classified. The more specific HTTP
/// errors extend this class, so catch it last.
class HttpError extends NeuroVerifyError {
  HttpError(super.detail, {required int super.statusCode, super.requestId});
}

/// HTTP 401: the API key is invalid, expired, or belongs to another
/// environment. Never retried automatically.
class AuthenticationError extends HttpError {
  AuthenticationError(super.detail, {super.requestId}) : super(statusCode: 401);
}

/// HTTP 403: the API key lacks endpoint or plan access. Never retried
/// automatically.
class ScopeError extends HttpError {
  ScopeError(super.detail, {super.requestId}) : super(statusCode: 403);
}

/// HTTP 429 after the configured retries were exhausted.
class RateLimitError extends HttpError {
  RateLimitError(
    super.detail, {
    super.requestId,
    this.retryAfter,
    this.limit,
    this.remaining,
    this.reset,
  }) : super(statusCode: 429);

  /// Parsed `Retry-After` value, capped by the client's `retryAfterCap`.
  final Duration? retryAfter;

  /// Raw `X-RateLimit-Limit` header value.
  final String? limit;

  /// Raw `X-RateLimit-Remaining` header value.
  final String? remaining;

  /// Raw `X-RateLimit-Reset` header value.
  final String? reset;
}

/// HTTP 500/503 after retries were exhausted, or a response envelope whose
/// `status` is `"error"`.
class ServerError extends HttpError {
  ServerError(
    super.detail, {
    required super.statusCode,
    super.requestId,
    this.raw,
  });

  /// Redacted, unmodifiable wire envelope when one was returned. Diagnostic
  /// data only; it may contain filenames or other customer data.
  final Map<String, Object?>? raw;
}

/// The response was malformed or did not satisfy the required envelope.
/// Retrying is not known to be safe; record the request ID and contact support
/// if it persists.
class ProtocolError extends NeuroVerifyError {
  ProtocolError(super.detail, {super.statusCode, super.requestId});
}

/// The configured per-attempt timeout elapsed. Not retried automatically,
/// because the server may already have accepted a billable request.
class TimeoutError extends NeuroVerifyError {
  TimeoutError(super.detail);
}

/// No response was received (DNS, connectivity, TLS, or similar). Not retried
/// automatically, because the server may already have accepted the request.
class NetworkError extends NeuroVerifyError {
  NetworkError(super.detail);
}

/// The caller's abort trigger completed during preparation, a retry wait, the
/// upload, or response processing.
class AbortError extends NeuroVerifyError {
  AbortError([super.detail = 'The request was aborted.']);
}
