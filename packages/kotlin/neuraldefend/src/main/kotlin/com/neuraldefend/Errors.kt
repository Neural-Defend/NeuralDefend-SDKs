package com.neuraldefend

/**
 * Base class for every exception thrown by the NeuroVerify SDK.
 *
 * The class names match the Python, TypeScript, Go, and Dart SDKs. Business rejections
 * (no face, blurry image, and so on) are **not** errors: they are returned as results with
 * [ResultStatus.REJECTED].
 *
 * Coroutine cancellation is reported with the standard
 * [kotlin.coroutines.cancellation.CancellationException], never with a subclass of this
 * type, so structured concurrency keeps working. [AbortError] is used by the Java-friendly
 * [NeuroVerifyCall] API.
 */
public sealed class NeuroVerifyError(
    /** Redacted, human-readable description of the failure. */
    public val detail: String,
    /** HTTP status code when the failure was derived from a response. */
    public val statusCode: Int?,
    /**
     * `X-Request-ID`/`X-Correlation-ID` header, or the transaction ID of the response
     * envelope when no header was returned.
     */
    public val requestId: String?,
) : Exception(detail) {
    override fun toString(): String {
        val parts = listOfNotNull(
            statusCode?.let { "statusCode: $it" },
            requestId?.let { "requestId: $it" },
        )
        val suffix = if (parts.isEmpty()) "" else " (${parts.joinToString(", ")})"
        return "${javaClass.simpleName}: $detail$suffix"
    }
}

/** Category of a local [ValidationError]. */
public enum class ValidationErrorCode {
    API_KEY_REQUIRED,
    CUSTOM_BASE_URL_REQUIRES_OPT_IN,
    EMPTY_FILE,
    FILE_NOT_FOUND,
    FILE_TOO_LARGE,
    FILENAME_REQUIRED,
    INVALID_BASE_URL,
    INVALID_MAX_FRAMES,
    INVALID_RETRIES,
    INVALID_SAMPLE_RATE,
    INVALID_TIMEOUT,
    STREAM_NOT_REPLAYABLE,
    UNSUPPORTED_INPUT,
}

/**
 * Local configuration, option, or media validation failed before a request could
 * complete. Correct the input; do not retry it unchanged.
 */
public class ValidationError(
    public val code: ValidationErrorCode,
    detail: String,
) : NeuroVerifyError(detail, null, null)

/**
 * An HTTP response that is not otherwise classified. The more specific HTTP errors extend
 * this class, so catch it last.
 */
public open class HttpError @JvmOverloads constructor(
    detail: String,
    statusCode: Int,
    requestId: String? = null,
) : NeuroVerifyError(detail, statusCode, requestId)

/**
 * HTTP 401: the API key is invalid, expired, or belongs to another environment. Never
 * retried automatically.
 */
public class AuthenticationError @JvmOverloads constructor(
    detail: String,
    requestId: String? = null,
) : HttpError(detail, 401, requestId)

/** HTTP 403: the API key lacks endpoint or plan access. Never retried automatically. */
public class ScopeError @JvmOverloads constructor(
    detail: String,
    requestId: String? = null,
) : HttpError(detail, 403, requestId)

/** HTTP 429 after the configured retries were exhausted. */
public class RateLimitError @JvmOverloads constructor(
    detail: String,
    requestId: String? = null,
    /** Parsed `Retry-After` value in milliseconds, capped by the client's `retryAfterCap`. */
    public val retryAfterMillis: Long? = null,
    /** Raw `X-RateLimit-Limit` header value. */
    public val limit: String? = null,
    /** Raw `X-RateLimit-Remaining` header value. */
    public val remaining: String? = null,
    /** Raw `X-RateLimit-Reset` header value. */
    public val reset: String? = null,
) : HttpError(detail, 429, requestId)

/**
 * HTTP 500/503 after retries were exhausted, or a response envelope whose `status` is
 * `"error"`.
 */
public class ServerError @JvmOverloads constructor(
    detail: String,
    statusCode: Int,
    requestId: String? = null,
    /**
     * Redacted, unmodifiable wire envelope when one was returned. Diagnostic data only; it
     * may contain filenames or other customer data.
     */
    public val raw: Map<String, Any?>? = null,
) : HttpError(detail, statusCode, requestId)

/**
 * The response was malformed or did not satisfy the required envelope. Retrying is not
 * known to be safe; record the request ID and contact support if it persists.
 */
public class ProtocolError @JvmOverloads constructor(
    detail: String,
    statusCode: Int? = null,
    requestId: String? = null,
) : NeuroVerifyError(detail, statusCode, requestId)

/**
 * The configured per-attempt timeout elapsed. Not retried automatically, because the
 * server may already have accepted a billable request.
 */
public class TimeoutError(detail: String) : NeuroVerifyError(detail, null, null)

/**
 * No response was received (DNS, connectivity, TLS, or similar). Not retried
 * automatically, because the server may already have accepted the request.
 */
public class NetworkError(detail: String) : NeuroVerifyError(detail, null, null)

/** [NeuroVerifyCall.cancel] was called before the call completed. */
public class AbortError @JvmOverloads constructor(detail: String = "The request was aborted.") : NeuroVerifyError(detail, null, null)
