import Foundation

/// Every error thrown by ``NeuroVerifyClient``.
///
/// The cases match the error classes of the Python, TypeScript, Go, and Dart SDKs. Business
/// rejections such as "no face detected" are not errors; they are returned as results with
/// ``ResultStatus/rejected``.
public enum NeuroVerifyError: Error, Sendable, Equatable {
    /// Local configuration, option, or media validation failed before a request could
    /// complete. Correct the input; do not retry it unchanged.
    case validation(code: ValidationErrorCode, message: String)

    /// An HTTP response that is not otherwise classified, including redirects, which the SDK
    /// never follows.
    case http(ErrorDetails)

    /// HTTP 401: the API key is invalid, expired, or belongs to another environment. Never
    /// retried automatically.
    case authentication(ErrorDetails)

    /// HTTP 403: the API key lacks endpoint or plan access. Never retried automatically.
    case scope(ErrorDetails)

    /// HTTP 429 after the configured retries were exhausted.
    case rateLimit(ErrorDetails, RateLimitInfo)

    /// HTTP 500 or 503 after retries were exhausted, or a response envelope whose `status` is
    /// `"error"`. `raw` is the redacted envelope when one was returned; it is diagnostic data
    /// that may contain filenames or other customer data.
    case server(ErrorDetails, raw: JSONValue?)

    /// The response was malformed or did not satisfy the required envelope. Retrying is not
    /// known to be safe; record the request ID and contact support if it persists.
    case `protocol`(ErrorDetails)

    /// The per-attempt timeout elapsed. Not retried automatically, because the server may
    /// already have accepted a billable request.
    case timeout(message: String)

    /// No response was received (DNS, connectivity, TLS, or similar). Not retried
    /// automatically, because the server may already have accepted the request.
    case network(message: String)

    /// The calling task was cancelled during preparation, a retry wait, the upload, or
    /// response processing.
    case cancelled

    /// HTTP status code when the error was derived from a response.
    public var statusCode: Int? {
        details?.statusCode
    }

    /// `X-Request-ID` or `X-Correlation-ID` header, or the transaction ID of the response
    /// envelope when no header was returned.
    public var requestID: String? {
        details?.requestID
    }

    /// Redacted, human-readable description of the failure.
    public var message: String {
        switch self {
        case .validation(_, let message), .timeout(let message), .network(let message):
            return message
        case .cancelled:
            return "The request was cancelled."
        case .http(let details), .authentication(let details), .scope(let details),
            .rateLimit(let details, _), .server(let details, _), .protocol(let details):
            return details.message
        }
    }

    private var details: ErrorDetails? {
        switch self {
        case .http(let details), .authentication(let details), .scope(let details),
            .rateLimit(let details, _), .server(let details, _), .protocol(let details):
            return details
        case .validation, .timeout, .network, .cancelled:
            return nil
        }
    }

    private var caseName: String {
        switch self {
        case .validation: return "validation"
        case .http: return "http"
        case .authentication: return "authentication"
        case .scope: return "scope"
        case .rateLimit: return "rateLimit"
        case .server: return "server"
        case .protocol: return "protocol"
        case .timeout: return "timeout"
        case .network: return "network"
        case .cancelled: return "cancelled"
        }
    }
}

extension NeuroVerifyError: CustomStringConvertible, LocalizedError {
    public var description: String {
        var parts: [String] = []
        if case .validation(let code, _) = self { parts.append("code: \(code.rawValue)") }
        if let statusCode { parts.append("statusCode: \(statusCode)") }
        if let requestID { parts.append("requestID: \(requestID)") }
        let suffix = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "NeuroVerifyError.\(caseName): \(message)\(suffix)"
    }

    public var errorDescription: String? { message }
}

/// Response details shared by the HTTP-derived error cases.
public struct ErrorDetails: Sendable, Equatable {
    /// Redacted server detail, or a short fallback such as `"HTTP 401"`.
    public let message: String

    /// HTTP status code. `nil` only for a ``NeuroVerifyError/protocol(_:)`` raised before a
    /// status was available.
    public let statusCode: Int?

    /// Request or transaction ID for support correlation.
    public let requestID: String?

    public init(message: String, statusCode: Int?, requestID: String?) {
        self.message = message
        self.statusCode = statusCode
        self.requestID = requestID
    }
}

/// Rate-limit headers returned with HTTP 429.
public struct RateLimitInfo: Sendable, Equatable {
    /// Parsed `Retry-After` value in seconds, capped by ``NeuroVerifyClient/Options/retryAfterCap``.
    public let retryAfter: TimeInterval?

    /// Raw `X-RateLimit-Limit` header value.
    public let limit: String?

    /// Raw `X-RateLimit-Remaining` header value.
    public let remaining: String?

    /// Raw `X-RateLimit-Reset` header value.
    public let reset: String?

    public init(retryAfter: TimeInterval?, limit: String?, remaining: String?, reset: String?) {
        self.retryAfter = retryAfter
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
    }
}

/// Category of a ``NeuroVerifyError/validation(code:message:)`` error.
public enum ValidationErrorCode: String, Sendable, CaseIterable {
    case apiKeyRequired = "api_key_required"
    case customBaseURLRequiresOptIn = "custom_base_url_requires_opt_in"
    case emptyFile = "empty_file"
    case fileNotFound = "file_not_found"
    case fileTooLarge = "file_too_large"
    case filenameRequired = "filename_required"
    case invalidBaseURL = "invalid_base_url"
    case invalidMaxFrames = "invalid_max_frames"
    case invalidRetries = "invalid_retries"
    case invalidSampleRate = "invalid_sample_rate"
    case invalidTimeout = "invalid_timeout"
    case unsupportedInput = "unsupported_input"
}

/// Non-fatal warning about an upload, delivered to ``NeuroVerifyClient/Options/onWarning``.
public struct ValidationWarning: Sendable, Equatable, CustomStringConvertible {
    /// Currently always `"unsupported_extension"`.
    public let code: String
    public let message: String
    public let filename: String

    public var description: String { "ValidationWarning(\(code)): \(message)" }
}
