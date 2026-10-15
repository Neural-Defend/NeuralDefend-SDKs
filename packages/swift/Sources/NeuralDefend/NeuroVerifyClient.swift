import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Client for the NeuroVerify image and video authenticity API.
///
/// A client owns a `URLSession`; create one and reuse it. Results are decision-support signals,
/// not proof of authenticity. Never ship a long-lived production API key inside an app; call
/// the API from your backend, or use short-lived keys issued to the device.
///
/// ```swift
/// let client = try NeuroVerifyClient(apiKey: key)
/// let result = try await client.detectImage(.file(photoURL))
/// switch result.status {
/// case .success: print(result.riskLevel ?? .low)
/// case .rejected: print(result.message)
/// case .unknown: print("Upgrade the SDK")
/// }
/// ```
public final class NeuroVerifyClient: Sendable {
    /// Default production API origin.
    public static let productionURL = URL(string: "https://deepscan.neuraldefend.com")!

    /// Staging API origin, for integration testing with a staging key.
    public static let stagingURL = URL(string: "https://stage.deepscan.neuraldefend.com")!

    /// Client configuration. Every property has a safe default.
    public struct Options: Sendable {
        /// HTTPS origin of the API. A non-Neural Defend origin also requires
        /// ``allowCustomBaseURL``, because it receives the API key and uploaded media.
        public var baseURL: URL

        /// Must be `true` before a non-Neural Defend ``baseURL`` is accepted.
        public var allowCustomBaseURL: Bool

        /// Deadline for each attempt, in seconds, including the upload and reading the response.
        public var timeout: TimeInterval

        /// Retries after the initial request for HTTP 429, 500, and 503 (0 through 3).
        public var maxRetries: Int

        /// Maximum wait honored from a `Retry-After` header, in seconds.
        public var retryAfterCap: TimeInterval

        /// Replaces the default `neuraldefend-swift/<version>` user agent.
        public var userAgent: String?

        /// Receives non-fatal media warnings, such as an undocumented file extension.
        public var onWarning: (@Sendable (ValidationWarning) -> Void)?

        public init(
            baseURL: URL = NeuroVerifyClient.productionURL,
            allowCustomBaseURL: Bool = false,
            timeout: TimeInterval = 120,
            maxRetries: Int = 3,
            retryAfterCap: TimeInterval = 60,
            userAgent: String? = nil,
            onWarning: (@Sendable (ValidationWarning) -> Void)? = nil
        ) {
            self.baseURL = baseURL
            self.allowCustomBaseURL = allowCustomBaseURL
            self.timeout = timeout
            self.maxRetries = maxRetries
            self.retryAfterCap = retryAfterCap
            self.userAgent = userAgent
            self.onWarning = onWarning
        }
    }

    /// Validated API origin.
    public let baseURL: URL

    /// Per-attempt timeout in seconds.
    public let timeout: TimeInterval

    /// Retries after the initial request for HTTP 429, 500, and 503.
    public let maxRetries: Int

    /// Maximum wait honored from a `Retry-After` header, in seconds.
    public let retryAfterCap: TimeInterval

    private let apiKey: String
    private let userAgent: String
    private let onWarning: (@Sendable (ValidationWarning) -> Void)?
    private let transport: Transport
    private let runtime: ClientRuntime

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - apiKey: Sent in the `x-api-key` header and redacted from every error, result, and
    ///     description. This initializer never reads environment variables; see
    ///     ``fromEnvironment(options:sessionConfiguration:environment:)``.
    ///   - options: Base URL, timeout, retry, and user-agent settings.
    ///   - sessionConfiguration: Copied for the client's private `URLSession`. Defaults to an
    ///     ephemeral configuration, so responses are never cached to disk. Supply one to add
    ///     `protocolClasses` in tests or to adjust connectivity settings.
    /// - Throws: ``NeuroVerifyError/validation(code:message:)`` for an empty key or invalid
    ///   option.
    public convenience init(
        apiKey: String,
        options: Options = Options(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) throws {
        try self.init(
            apiKey: apiKey,
            options: options,
            sessionConfiguration: sessionConfiguration,
            allowInsecureForTesting: false,
            runtime: .live
        )
    }

    /// Creates a client pinned to ``stagingURL``. Use only with a staging credential; any
    /// ``Options/baseURL`` in `options` is ignored.
    public static func staging(
        apiKey: String,
        options: Options = Options(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) throws -> NeuroVerifyClient {
        var pinned = options
        pinned.baseURL = stagingURL
        pinned.allowCustomBaseURL = false
        return try NeuroVerifyClient(apiKey: apiKey, options: pinned, sessionConfiguration: sessionConfiguration)
    }

    /// Creates a client from `NEURALDEFEND_API_KEY` and, when set, `NEURALDEFEND_BASE_URL`.
    /// Intended for command-line tools, servers, and tests; apps should pass a key explicitly.
    public static func fromEnvironment(
        options: Options = Options(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> NeuroVerifyClient {
        var resolved = options
        if let value = environment["NEURALDEFEND_BASE_URL"]?.trimmingCharacters(in: .whitespaces),
            !value.isEmpty
        {
            guard let url = URL(string: value) else {
                throw NeuroVerifyError.validation(
                    code: .invalidBaseURL,
                    message: "NEURALDEFEND_BASE_URL must be a valid HTTPS origin."
                )
            }
            resolved.baseURL = url
        }
        guard let apiKey = environment["NEURALDEFEND_API_KEY"] else {
            throw NeuroVerifyError.validation(
                code: .apiKeyRequired,
                message: "Set NEURALDEFEND_API_KEY or pass apiKey explicitly."
            )
        }
        return try NeuroVerifyClient(apiKey: apiKey, options: resolved, sessionConfiguration: sessionConfiguration)
    }

    init(
        apiKey: String,
        options: Options,
        sessionConfiguration: URLSessionConfiguration,
        allowInsecureForTesting: Bool,
        runtime: ClientRuntime
    ) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw NeuroVerifyError.validation(code: .apiKeyRequired, message: "apiKey is required.")
        }
        guard options.timeout.isFinite, options.timeout > 0 else {
            throw NeuroVerifyError.validation(
                code: .invalidTimeout,
                message: "timeout must be greater than zero."
            )
        }
        guard (0...3).contains(options.maxRetries) else {
            throw NeuroVerifyError.validation(
                code: .invalidRetries,
                message: "maxRetries must be an integer from 0 through 3."
            )
        }
        self.baseURL = try validateBaseURL(
            options.baseURL,
            allowCustom: options.allowCustomBaseURL,
            allowInsecure: allowInsecureForTesting
        )
        self.apiKey = key
        self.timeout = options.timeout
        self.maxRetries = options.maxRetries
        self.retryAfterCap = options.retryAfterCap.isFinite ? max(options.retryAfterCap, 0) : 60
        let customAgent = options.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.userAgent = customAgent.isEmpty ? "neuraldefend-swift/\(Self.sdkVersion)" : customAgent
        self.onWarning = options.onWarning
        self.runtime = runtime

        // Copy, so later changes by the caller do not affect this client.
        let configuration = sessionConfiguration.copy() as! URLSessionConfiguration
        // The SDK's own per-attempt timer is authoritative. URLSession's idle timeout is only a
        // backstop, kept above that deadline and in whole seconds because Linux Foundation
        // truncates fractional values.
        configuration.timeoutIntervalForRequest = options.timeout.rounded(.up) + 1
        configuration.timeoutIntervalForResource = max(options.timeout.rounded(.up) + 1, 7 * 24 * 60 * 60)
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.transport = Transport(configuration: configuration)
    }

    /// Uploads an image to `/detect/image`.
    ///
    /// Business rejections (no face, multiple faces, quality or security failures) are
    /// returned as results with ``ResultStatus/rejected``; branch on ``ImageResult/status``.
    ///
    /// - Throws: ``NeuroVerifyError`` for operational failures. Cancelling the calling task
    ///   throws ``NeuroVerifyError/cancelled``.
    public func detectImage(
        _ media: MediaInput,
        onProgress: UploadProgressHandler? = nil
    ) async throws -> ImageResult {
        let response = try await execute(.image, media: media, query: [], onProgress: onProgress)
        let secret = apiKey
        return try classify(response, kind: .image) { (members, requestID) throws(NeuroVerifyError) in
            try parseImage(members, httpStatus: response.statusCode, requestID: requestID, secret: secret)
        }
    }

    /// Uploads a video to `/detect/video`.
    ///
    /// - Parameters:
    ///   - maxFrames: 1 through 100; the API default is 12.
    ///   - sampleRate: At least 1.
    ///
    /// Video and audio are scored independently; see ``VideoResult``.
    public func detectVideo(
        _ media: MediaInput,
        maxFrames: Int? = nil,
        sampleRate: Int? = nil,
        onProgress: UploadProgressHandler? = nil
    ) async throws -> VideoResult {
        if let maxFrames, !(1...100).contains(maxFrames) {
            throw NeuroVerifyError.validation(
                code: .invalidMaxFrames,
                message: "maxFrames must be an integer from 1 through 100."
            )
        }
        if let sampleRate, sampleRate < 1 {
            throw NeuroVerifyError.validation(
                code: .invalidSampleRate,
                message: "sampleRate must be an integer greater than or equal to 1."
            )
        }
        var query: [URLQueryItem] = []
        if let maxFrames { query.append(URLQueryItem(name: "max_frames", value: String(maxFrames))) }
        if let sampleRate { query.append(URLQueryItem(name: "sample_rate", value: String(sampleRate))) }
        let response = try await execute(.video, media: media, query: query, onProgress: onProgress)
        let secret = apiKey
        return try classify(response, kind: .video) { (members, requestID) throws(NeuroVerifyError) in
            try parseVideo(members, httpStatus: response.statusCode, requestID: requestID, secret: secret)
        }
    }

    private func execute(
        _ kind: DetectionKind,
        media input: MediaInput,
        query: [URLQueryItem],
        onProgress: UploadProgressHandler?
    ) async throws(NeuroVerifyError) -> TransportResponse {
        if Task.isCancelled { throw .cancelled }
        let media = try prepareMedia(input, kind: kind, onWarning: onWarning)
        let body = try MultipartBody.write(media)
        // The temporary body file is deleted when `body` is released.
        defer { withExtendedLifetime(body) {} }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = kind.path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.length), forHTTPHeaderField: "Content-Length")

        var attempt = 0
        while true {
            if Task.isCancelled { throw .cancelled }
            let response = try await transport.upload(
                request,
                bodyFile: body.fileURL,
                totalBytes: body.length,
                timeout: timeout,
                label: kind.rawValue,
                onProgress: onProgress
            )
            guard isRetryable(response.statusCode), attempt < maxRetries else {
                return response
            }
            let delay = retryDelay(
                statusCode: response.statusCode,
                retryAfterHeader: response.header("Retry-After"),
                attempt: attempt,
                retryAfterCap: retryAfterCap,
                runtime: runtime
            )
            do {
                try await runtime.sleep(delay)
            } catch {
                throw .cancelled
            }
            attempt += 1
        }
    }

    private func classify<Parsed>(
        _ response: TransportResponse,
        kind: DetectionKind,
        parse: ([String: JSONValue], String?) throws(NeuroVerifyError) -> Parsed
    ) throws(NeuroVerifyError) -> Parsed {
        let status = response.statusCode
        let headerRequestID = response.header("X-Request-ID") ?? response.header("X-Correlation-ID")
        let json = JSONValue.parse(response.body)?.objectValue

        func details(_ fallback: String) -> ErrorDetails {
            let detail = json?["detail"]?.stringValue.map { redact($0, apiKey) }
            return ErrorDetails(message: detail ?? fallback, statusCode: status, requestID: headerRequestID)
        }

        switch status {
        case 401:
            throw .authentication(details("HTTP 401"))
        case 403:
            throw .scope(details("HTTP 403"))
        case 429:
            throw .rateLimit(
                details("HTTP 429"),
                RateLimitInfo(
                    retryAfter: parseRetryAfter(
                        response.header("Retry-After"),
                        cap: retryAfterCap,
                        now: runtime.now()
                    ),
                    limit: response.header("X-RateLimit-Limit"),
                    remaining: response.header("X-RateLimit-Remaining"),
                    reset: response.header("X-RateLimit-Reset")
                )
            )
        case 200, 400, 500, 503:
            break
        default:
            throw .http(details("Unexpected HTTP \(status)."))
        }

        let envelope = json?[kind.envelopeKey]?.objectValue
        if status == 500 || status == 503 {
            guard let envelope else {
                throw .server(
                    ErrorDetails(message: "HTTP \(status)", statusCode: status, requestID: headerRequestID),
                    raw: nil
                )
            }
            let message = envelope[kind == .image ? "message" : "video_message"]?.stringValue
            throw .server(
                ErrorDetails(
                    message: message.map { redact($0, apiKey) } ?? "HTTP \(status)",
                    statusCode: status,
                    requestID: headerRequestID ?? transactionID(envelope)
                ),
                raw: JSONValue.object(envelope).redacting(apiKey)
            )
        }
        guard json != nil else {
            throw .protocol(
                ErrorDetails(
                    message: "The server returned malformed JSON.",
                    statusCode: status,
                    requestID: headerRequestID
                )
            )
        }
        guard let envelope else {
            throw .protocol(
                ErrorDetails(
                    message: "The response was missing \"\(kind.envelopeKey)\".",
                    statusCode: status,
                    requestID: headerRequestID
                )
            )
        }
        let requestID = headerRequestID ?? transactionID(envelope)
        let result = try parse(envelope, requestID)
        let rejected =
            (result as? ImageResult)?.isRejected ?? (result as? VideoResult)?.isRejected ?? false
        if status == 400 && !rejected {
            throw .http(
                ErrorDetails(
                    message: "HTTP 400 response was not a rejection.",
                    statusCode: 400,
                    requestID: requestID
                )
            )
        }
        return result
    }

    private func transactionID(_ envelope: [String: JSONValue]) -> String? {
        guard let value = envelope["unique_trx_id"]?.stringValue, !value.isEmpty else { return nil }
        return value
    }
}

extension NeuroVerifyClient: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "NeuroVerifyClient(apiKey: [REDACTED], baseURL: \(baseURL.absoluteString), "
            + "timeout: \(timeout), maxRetries: \(maxRetries))"
    }

    public var debugDescription: String { description }

    /// Hides the API key from `dump(_:)`, debuggers, and other reflection.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "apiKey": "[REDACTED]",
                "baseURL": baseURL,
                "timeout": timeout,
                "maxRetries": maxRetries,
            ],
            displayStyle: .class
        )
    }
}

private func validateBaseURL(
    _ url: URL,
    allowCustom: Bool,
    allowInsecure: Bool
) throws(NeuroVerifyError) -> URL {
    let invalid = NeuroVerifyError.validation(
        code: .invalidBaseURL,
        message: "baseURL must be an HTTPS origin without credentials, a path, query, or fragment."
    )
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let scheme = components.scheme?.lowercased(),
        scheme == "https" || (allowInsecure && scheme == "http"),
        let host = components.host, !host.isEmpty,
        components.user == nil, components.password == nil,
        components.query == nil, components.fragment == nil,
        components.path.isEmpty || components.path == "/"
    else { throw invalid }

    var origin = URLComponents()
    origin.scheme = scheme
    origin.host = host.lowercased()
    origin.port = components.port
    if scheme == "https" && origin.port == 443 { origin.port = nil }
    guard let normalized = origin.url else { throw invalid }
    if normalized != NeuroVerifyClient.productionURL && normalized != NeuroVerifyClient.stagingURL
        && !allowCustom
    {
        throw .validation(
            code: .customBaseURLRequiresOptIn,
            message: "A non-Neural Defend baseURL requires allowCustomBaseURL: true because it "
                + "receives the API key and uploaded media."
        )
    }
    return normalized
}
