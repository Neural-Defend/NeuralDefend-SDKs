import Foundation
import Testing

@testable import NeuralDefend

/// A fixture reply whose envelope was changed by `change`.
private func reply(
    _ fixture: String,
    status: Int? = nil,
    headers: [String: String]? = nil,
    change: (inout [String: JSONValue]) -> Void = { _ in }
) throws -> ServerReply {
    let caseData = try loadFixture(fixture)
    let key = caseData.isImage ? imageEnvelopeKey : videoEnvelopeKey
    var envelope = caseData.envelope?.objectValue ?? [:]
    change(&envelope)
    let body = try JSONEncoder().encode(JSONValue.object([key: .object(envelope)]))
    return .respond(
        status: status ?? caseData.httpStatus,
        headers: headers ?? caseData.headers,
        body: body
    )
}

private func rawReply(_ status: Int, _ body: String, headers: [String: String] = [:]) -> ServerReply {
    .respond(status: status, headers: headers, body: Data(body.utf8))
}

@Suite("Retries")
struct RetryTests {
    @Test("HTTP 500 retries three times with 1, 2, 4 second backoff and replays the body")
    func serverBackoff() async throws {
        let clock = FakeClock()
        let server = try fixtureServer([
            "image/documented/internal-error-500.json",
            "image/documented/internal-error-500.json",
            "image/documented/internal-error-500.json",
            "image/documented/low-risk.json",
        ])
        try await withServer(server) { server in
            let client = try makeClient(server, maxRetries: 3, runtime: clock.runtime)
            let result = try await client.detectImage(
                .data(Data("streamed-payload".utf8), filename: "retry.jpg")
            )
            #expect(result.isScored)
            #expect(server.requests.count == 4)
            for request in server.requests {
                #expect(request.bodyText.contains("streamed-payload"))
            }
            #expect(clock.sleeps == [1, 2, 4])
        }
    }

    @Test("server backoff adds at most 25 percent jitter")
    func jitter() async throws {
        let clock = FakeClock(jitter: 1)
        let server = try fixtureServer([
            "video/documented/service-unavailable-503.json",
            "video/documented/service-unavailable-503.json",
            "video/documented/both-low.json",
        ])
        try await withServer(server) { server in
            _ = try await makeClient(server, maxRetries: 3, runtime: clock.runtime).detectVideo(sampleVideo)
            #expect(clock.sleeps == [1.25, 2.5])
        }
    }

    @Test("exhausted HTTP 503 retries throw a server error after four attempts")
    func exhaustedServer() async throws {
        let clock = FakeClock()
        let server = try fixtureServer(["image/documented/service-unavailable-503.json"])
        try await withServer(server) { server in
            let client = try makeClient(server, maxRetries: 3, runtime: clock.runtime)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            guard case .server(let details, _)? = error else {
                Issue.record("expected a server error, got \(String(describing: error))")
                return
            }
            #expect(details.statusCode == 503)
            #expect(server.requests.count == 4)
            #expect(clock.sleeps.count == 3)
        }
    }

    @Test("HTTP 429 honors a numeric Retry-After, then succeeds")
    func numericRetryAfter() async throws {
        let clock = FakeClock()
        let server = try fixtureServer([
            "image/synthetic/rate-limited-429.json", "image/documented/low-risk.json",
        ])
        try await withServer(server) { server in
            let result = try await makeClient(server, maxRetries: 1, runtime: clock.runtime)
                .detectImage(sampleImage)
            #expect(result.isScored)
            #expect(server.requests.count == 2)
            #expect(clock.sleeps == [60])
        }
    }

    @Test("Retry-After is capped by retryAfterCap")
    func cappedRetryAfter() async throws {
        let clock = FakeClock()
        let server = try fixtureServer([
            "image/synthetic/rate-limited-429.json", "image/documented/low-risk.json",
        ])
        try await withServer(server) { server in
            _ = try await makeClient(server, maxRetries: 1, retryAfterCap: 5, runtime: clock.runtime)
                .detectImage(sampleImage)
            #expect(clock.sleeps == [5])
        }
    }

    @Test("Retry-After HTTP dates are relative to the clock")
    func dateRetryAfter() async throws {
        let now = try #require(parseHTTPDate("Sun, 26 Jul 2026 23:59:30 GMT"))
        let clock = FakeClock(now: now)
        let limited = try loadFixture("image/synthetic/rate-limited-429.json")
        var headers = limited.headers
        headers["retry-after"] = "Sun, 26 Jul 2026 23:59:45 GMT"
        let first = ServerReply.respond(status: 429, headers: headers, body: limited.bodyData)
        let second = try loadFixture("image/documented/low-risk.json").reply
        let server = try LocalHTTPServer { call, _ in call == 1 ? first : second }
        try await withServer(server) { server in
            _ = try await makeClient(server, maxRetries: 1, runtime: clock.runtime).detectImage(sampleImage)
            #expect(server.requests.count == 2)
            #expect(clock.sleeps == [15])
        }
    }

    @Test("HTTP 429 without Retry-After uses exponential delays without jitter")
    func rateLimitWithoutHeader() async throws {
        let clock = FakeClock(jitter: 1)
        let limited = try loadFixture("image/synthetic/rate-limited-429.json")
        let first = ServerReply.respond(status: 429, headers: [:], body: limited.bodyData)
        let success = try loadFixture("image/documented/low-risk.json").reply
        let server = try LocalHTTPServer { call, _ in call < 3 ? first : success }
        try await withServer(server) { server in
            _ = try await makeClient(server, maxRetries: 3, runtime: clock.runtime).detectImage(sampleImage)
            #expect(clock.sleeps == [1, 2])
        }
    }

    @Test("exhausted HTTP 429 throws a rate-limit error")
    func exhaustedRateLimit() async throws {
        let server = try fixtureServer(["video/synthetic/rate-limited-429.json"])
        try await withServer(server) { server in
            let client = try makeClient(server, maxRetries: 2)
            let error = await captureError { _ = try await client.detectVideo(sampleVideo) }
            guard case .rateLimit? = error else {
                Issue.record("expected a rate-limit error, got \(String(describing: error))")
                return
            }
            #expect(server.requests.count == 3)
        }
    }

    @Test(
        "never retries non-retryable outcomes",
        arguments: [
            "image/documented/blurry.json",
            "image/synthetic/unauthorized-401.json",
            "image/synthetic/forbidden-403.json",
            "image/documented/low-risk.json",
            "image/documented/no-face.json",
        ]
    )
    func neverRetries(_ fixture: String) async throws {
        let clock = FakeClock()
        let server = try fixtureServer([fixture])
        try await withServer(server) { server in
            let client = try makeClient(server, maxRetries: 3, runtime: clock.runtime)
            _ = await captureError { _ = try await client.detectImage(sampleImage) }
            #expect(server.requests.count == 1)
            #expect(clock.sleeps.isEmpty)
        }
    }

    @Test("maxRetries 0 disables retries")
    func retriesDisabled() async throws {
        let server = try fixtureServer(["image/documented/internal-error-500.json"])
        try await withServer(server) { server in
            let client = try makeClient(server, maxRetries: 0)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            guard case .server? = error else {
                Issue.record("expected a server error")
                return
            }
            #expect(server.requests.count == 1)
        }
    }

    @Test("Retry-After parsing accepts seconds and all three HTTP date formats")
    func retryAfterFormats() throws {
        let now = try #require(parseHTTPDate("Sun, 06 Nov 1994 08:49:30 GMT"))
        #expect(parseRetryAfter("7", cap: 60, now: now) == 7)
        #expect(parseRetryAfter(" 1.5 ", cap: 60, now: now) == 1.5)
        #expect(parseRetryAfter("-3", cap: 60, now: now) == 0)
        #expect(parseRetryAfter("120", cap: 60, now: now) == 60)
        #expect(parseRetryAfter("Sun, 06 Nov 1994 08:49:37 GMT", cap: 60, now: now) == 7)
        #expect(parseRetryAfter("Sunday, 06-Nov-94 08:49:37 GMT", cap: 60, now: now) == 7)
        #expect(parseRetryAfter("Sun Nov  6 08:49:37 1994", cap: 60, now: now) == 7)
        #expect(parseRetryAfter("Sun, 06 Nov 1994 08:49:00 GMT", cap: 60, now: now) == 0)
        #expect(parseRetryAfter("soon", cap: 60, now: now) == nil)
        #expect(parseRetryAfter("", cap: 60, now: now) == nil)
        #expect(parseRetryAfter(nil, cap: 60, now: now) == nil)
    }
}

@Suite("Request shape")
struct RequestShapeTests {
    @Test("sends the API key, user agent, and a multipart file part")
    func requestShape() async throws {
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            _ = try await makeClient(server).detectImage(
                .data(Data("image-bytes".utf8), filename: "Photo.JPG")
            )
            let request = try #require(server.requests.first)
            #expect(request.method == "POST")
            #expect(request.target == "/detect/image")
            #expect(request.header("x-api-key") == testAPIKey)
            #expect(request.header("user-agent") == "neuraldefend-swift/\(NeuroVerifyClient.sdkVersion)")
            #expect(request.header("accept") == "application/json")
            let contentType = try #require(request.header("content-type"))
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            #expect(
                request.bodyText
                    == "--\(boundary)\r\n"
                    + "Content-Disposition: form-data; name=\"file\"; filename=\"Photo.JPG\"\r\n"
                    + "Content-Type: image/jpeg\r\n\r\n"
                    + "image-bytes\r\n--\(boundary)--\r\n"
            )
            #expect(request.header("content-length") == String(request.bodyLength))
        }
    }

    @Test("a custom user agent is sent")
    func customUserAgent() async throws {
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            _ = try await makeClient(server, userAgent: "kyc-app/2.4.0").detectImage(sampleImage)
            #expect(server.requests.first?.header("user-agent") == "kyc-app/2.4.0")
        }
    }

    @Test("video options are sent as query parameters")
    func videoQuery() async throws {
        let server = try fixtureServer(["video/documented/both-low.json"])
        try await withServer(server) { server in
            let result = try await makeClient(server).detectVideo(sampleVideo, maxFrames: 100, sampleRate: 1)
            #expect(result.isScored)
            let request = try #require(server.requests.first)
            #expect(request.path == "/detect/video")
            #expect(request.query == ["max_frames": "100", "sample_rate": "1"])
        }
    }

    @Test("the video query is omitted when options are not set")
    func videoWithoutQuery() async throws {
        let server = try fixtureServer(["video/documented/both-low.json"])
        try await withServer(server) { server in
            _ = try await makeClient(server).detectVideo(sampleVideo)
            #expect(server.requests.first?.target == "/detect/video")
        }
    }

    @Test(
        "invalid video options are rejected locally",
        arguments: [
            (0, nil, ValidationErrorCode.invalidMaxFrames),
            (101, nil, ValidationErrorCode.invalidMaxFrames),
            (nil, 0, ValidationErrorCode.invalidSampleRate),
        ] as [(Int?, Int?, ValidationErrorCode)]
    )
    func invalidVideoOptions(maxFrames: Int?, sampleRate: Int?, code: ValidationErrorCode) async throws {
        let server = try fixtureServer(["video/documented/both-low.json"])
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError {
                _ = try await client.detectVideo(sampleVideo, maxFrames: maxFrames, sampleRate: sampleRate)
            }
            guard case .validation(let actual, _)? = error else {
                Issue.record("expected a validation error")
                return
            }
            #expect(actual == code)
            #expect(server.requests.isEmpty)
        }
    }

    @Test("progress starts at zero and ends at the full body for each attempt")
    func progress() async throws {
        let recorder = ProgressRecorder()
        let server = try fixtureServer([
            "image/documented/service-unavailable-503.json", "image/documented/low-risk.json",
        ])
        try await withServer(server) { server in
            _ = try await makeClient(server, maxRetries: 1).detectImage(
                .data(Data(repeating: 7, count: 300_000), filename: "p.png"),
                onProgress: { sent, total in recorder.add(sent, total) }
            )
            let events = recorder.events
            let total = try #require(events.first?.1)
            #expect(events.allSatisfy { $0.1 == total })
            #expect(Int(total) == server.requests.first?.bodyLength)
            #expect(events.filter { $0.0 == 0 }.count == 2)
            #expect(events.last?.0 == total)
            #expect(events.filter { $0.0 == total }.count >= 2)
        }
    }
}

@Suite("Response classification")
struct ClassificationTests {
    @Test("an HTTP 200 error envelope throws a redacted server error")
    func redactedServerError() async throws {
        let echoing = try reply("image/documented/internal-error-500.json", status: 200) { envelope in
            envelope["message"] = .string("failed for \(testAPIKey)")
            envelope["future"] = .object(["echo": .array([.string("nested \(testAPIKey)")])])
        }
        let server = try LocalHTTPServer { _, _ in echoing }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            guard case .server(let details, let raw)? = error else {
                Issue.record("expected a server error")
                return
            }
            #expect(details.statusCode == 200)
            #expect(details.message == "failed for [REDACTED]")
            let encoded = String(decoding: try JSONEncoder().encode(raw), as: UTF8.self)
            #expect(!encoded.contains(testAPIKey))
            #expect(encoded.contains("[REDACTED]"))
            #expect(!String(describing: error!).contains(testAPIKey))
        }
    }

    @Test("API keys echoed in successful results are redacted from raw")
    func redactedRaw() async throws {
        let echoed = try reply("image/documented/low-risk.json") { $0["echo"] = .string(testAPIKey) }
        let server = try LocalHTTPServer { _, _ in echoed }
        try await withServer(server) { server in
            let result = try await makeClient(server).detectImage(sampleImage)
            #expect(result.raw["echo"] == .string("[REDACTED]"))
        }
    }

    @Test("HTTP 400 that is not a rejection throws an HTTP error")
    func badRequestWithoutRejection() async throws {
        let notRejected = try reply("image/documented/low-risk.json", status: 400)
        let server = try LocalHTTPServer { _, _ in notRejected }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            guard case .http(let details)? = error else {
                Issue.record("expected an HTTP error")
                return
            }
            #expect(details.statusCode == 400)
        }
    }

    @Test("an unexpected HTTP status throws an HTTP error with the server detail")
    func unexpectedStatus() async throws {
        let server = try LocalHTTPServer { _, _ in
            rawReply(404, #"{"detail": "Not Found"}"#, headers: ["X-Request-ID": "req-404"])
        }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            #expect(error == .http(ErrorDetails(message: "Not Found", statusCode: 404, requestID: "req-404")))
        }
    }

    @Test("a non-JSON 401 still throws an authentication error")
    func nonJSONUnauthorized() async throws {
        let server = try LocalHTTPServer { _, _ in rawReply(401, "<html>") }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            #expect(error == .authentication(ErrorDetails(message: "HTTP 401", statusCode: 401, requestID: nil)))
        }
    }

    @Test("the request ID prefers the X-Request-ID header")
    func requestIDHeader() async throws {
        let withHeader = try reply("image/documented/internal-error-500.json", headers: ["X-Request-ID": "req-123"])
        let server = try LocalHTTPServer { _, _ in withHeader }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            #expect(error?.requestID == "req-123")
        }
    }

    @Test(
        "invalid field values throw protocol errors",
        arguments: [
            ("billable", JSONValue.string("yes")),
            ("risk_score", .number(11)),
            ("risk_score", .string("high")),
            ("status_code", .number(1.5)),
            ("ai_threat_signals", .array([.number(1)])),
            ("status", .null),
        ]
    )
    func invalidField(field: String, value: JSONValue) async throws {
        let invalid = try reply("image/documented/low-risk.json") { $0[field] = value }
        let server = try LocalHTTPServer { _, _ in invalid }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            guard case .protocol(let details)? = error else {
                Issue.record("expected a protocol error for \(field)")
                return
            }
            #expect(details.message.contains(field))
        }
    }

    @Test("a missing required nullable field throws a protocol error")
    func missingNullableField() async throws {
        let missing = try reply("video/documented/both-low.json") { $0.removeValue(forKey: "audio_risk_score") }
        let server = try LocalHTTPServer { _, _ in missing }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let error = await captureError { _ = try await client.detectVideo(sampleVideo) }
            guard case .protocol? = error else {
                Issue.record("expected a protocol error")
                return
            }
        }
    }
}

@Suite("Media validation")
struct MediaTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("neuraldefend-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("streams a file URL and infers the filename")
    func fileInput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("valid.jpg")
        try Data("path-content".utf8).write(to: file)
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            let result = try await makeClient(server).detectImage(.file(file))
            #expect(result.isScored)
            let body = server.requests.first?.bodyText ?? ""
            #expect(body.contains("filename=\"valid.jpg\""))
            #expect(body.contains("path-content"))
        }
    }

    @Test("an explicit filename overrides the URL's last path component")
    func explicitFilename() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("upload.bin")
        try Data("x".utf8).write(to: file)
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            _ = try await makeClient(server).detectImage(.file(file, filename: "nested/dir/selfie.webp"))
            let body = server.requests.first?.bodyText ?? ""
            #expect(body.contains("filename=\"selfie.webp\""))
            #expect(body.contains("Content-Type: image/webp"))
        }
    }

    @Test("rejects empty, missing, directory, and non-file inputs before uploading")
    func invalidFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.jpg")
        try Data().write(to: empty)
        let cases: [(MediaInput, ValidationErrorCode)] = [
            (.file(empty), .emptyFile),
            (.file(directory.appendingPathComponent("missing.jpg")), .fileNotFound),
            (.file(directory, filename: "dir.jpg"), .unsupportedInput),
            (.file(URL(string: "https://example.com/a.jpg")!), .unsupportedInput),
            (.data(Data(), filename: "empty.jpg"), .emptyFile),
            (.data(Data("x".utf8), filename: "  "), .filenameRequired),
            (.data(Data("x".utf8), filename: "folder/"), .filenameRequired),
        ]
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            let client = try makeClient(server)
            for (input, code) in cases {
                let error = await captureError { _ = try await client.detectImage(input) }
                guard case .validation(let actual, _)? = error else {
                    Issue.record("expected \(code), got \(String(describing: error))")
                    continue
                }
                #expect(actual == code)
            }
            #expect(server.requests.isEmpty)
        }
    }

    @Test("rejects oversized media before uploading and accepts exactly the limit")
    func sizeLimits() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let atLimit = directory.appendingPathComponent("limit.jpg")
        let overLimit = directory.appendingPathComponent("over.jpg")
        let video = directory.appendingPathComponent("huge.mp4")
        for (url, size) in [
            (atLimit, MediaLimits.imageMaxBytes), (overLimit, MediaLimits.imageMaxBytes + 1),
            (video, MediaLimits.videoMaxBytes + 1),
        ] {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
        }
        let server = try fixtureServer(["image/documented/low-risk.json", "video/documented/both-low.json"])
        try await withServer(server) { server in
            let client = try makeClient(server)
            let tooLarge = await captureError { _ = try await client.detectImage(.file(overLimit)) }
            #expect(tooLarge == .validation(code: .fileTooLarge, message: "The image exceeds the 10 MiB limit."))
            let hugeVideo = await captureError { _ = try await client.detectVideo(.file(video)) }
            #expect(hugeVideo == .validation(code: .fileTooLarge, message: "The video exceeds the 1.5 GB limit."))
            #expect(server.requests.isEmpty)
            let result = try await client.detectImage(.file(atLimit))
            #expect(result.isScored)
            #expect(server.requests.count == 1)
            #expect(server.requests.first.map { $0.bodyLength > MediaLimits.imageMaxBytes } == true)
        }
    }

    @Test("warns about undocumented extensions but still uploads")
    func extensionWarning() async throws {
        let warnings = WarningRecorder()
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            _ = try await makeClient(server, onWarning: { warnings.add($0) })
                .detectImage(.data(Data("x".utf8), filename: "scan.gif"))
            #expect(server.requests.count == 1)
            #expect(server.requests.first?.bodyText.contains("Content-Type: application/octet-stream") == true)
            #expect(warnings.values.map(\.code) == ["unsupported_extension"])
            #expect(warnings.values.first?.filename == "scan.gif")
        }
    }

    @Test("documented formats map to deterministic content types")
    func contentTypes() {
        let expected = [
            "a.jpg": "image/jpeg", "a.JPEG": "image/jpeg", "a.png": "image/png", "a.bmp": "image/bmp",
            "a.tif": "image/tiff", "a.tiff": "image/tiff", "a.webp": "image/webp", "a.heic": "image/heic",
            "a.heif": "image/heif", "a.mp4": "video/mp4", "a.avi": "video/vnd.avi",
            "a.mov": "video/quicktime", "a.mkv": "video/matroska", "a.wmv": "video/x-ms-wmv",
            "a.flv": "video/x-flv", "a.webm": "video/webm", "a.ogg": "video/ogg", "a.ogv": "video/ogg",
            "a.gif": "application/octet-stream", "noext": "application/octet-stream",
            "trailing.": "application/octet-stream",
        ]
        for (filename, contentType) in expected {
            #expect(MediaLimits.contentType(forFilename: filename) == contentType, "\(filename)")
        }
        #expect(MediaLimits.imageExtensions.count == 9)
        #expect(MediaLimits.videoExtensions.count == 9)
    }

    @Test("quotes and line breaks in filenames are percent-encoded in the multipart header")
    func filenameEscaping() async throws {
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            _ = try await makeClient(server).detectImage(.data(Data("x".utf8), filename: "a\"b\r\nc.jpg"))
            #expect(server.requests.first?.bodyText.contains("filename=\"a%22b%0D%0Ac.jpg\"") == true)
        }
    }

    @Test("the temporary multipart body is deleted when it is released")
    func temporaryFileCleanup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = try prepareMedia(sampleImage, kind: .image, onWarning: nil)
        var body: MultipartBody? = try MultipartBody.write(media, directory: directory)
        let url = try #require(body?.fileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(body?.length == Int64((try? Data(contentsOf: url))?.count ?? -1))
        body = nil
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("Configuration")
struct ConfigurationTests {
    @Test("defaults")
    func defaults() throws {
        let client = try NeuroVerifyClient(apiKey: "key")
        #expect(client.baseURL == NeuroVerifyClient.productionURL)
        #expect(client.baseURL.absoluteString == "https://deepscan.neuraldefend.com")
        #expect(client.timeout == 120)
        #expect(client.maxRetries == 3)
        #expect(client.retryAfterCap == 60)
    }

    @Test("staging is pinned even when another base URL is supplied")
    func staging() throws {
        let options = NeuroVerifyClient.Options(
            baseURL: URL(string: "https://example.com")!,
            allowCustomBaseURL: true
        )
        let client = try NeuroVerifyClient.staging(apiKey: "key", options: options)
        #expect(client.baseURL.absoluteString == "https://stage.deepscan.neuraldefend.com")
    }

    @Test("custom origins require explicit opt-in")
    func customOrigin() throws {
        let custom = URL(string: "https://proxy.example.com:8443/")!
        #expect(throws: NeuroVerifyError.self) {
            try NeuroVerifyClient(apiKey: "key", options: .init(baseURL: custom))
        }
        do {
            _ = try NeuroVerifyClient(apiKey: "key", options: .init(baseURL: custom))
        } catch let error as NeuroVerifyError {
            guard case .validation(.customBaseURLRequiresOptIn, _) = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
        let client = try NeuroVerifyClient(
            apiKey: "key",
            options: .init(baseURL: custom, allowCustomBaseURL: true)
        )
        #expect(client.baseURL.absoluteString == "https://proxy.example.com:8443")
        let normalized = try NeuroVerifyClient(
            apiKey: "key",
            options: .init(baseURL: URL(string: "HTTPS://DeepScan.NeuralDefend.com:443/")!)
        )
        #expect(normalized.baseURL == NeuroVerifyClient.productionURL)
    }

    @Test(
        "rejects invalid base URLs",
        arguments: [
            "http://deepscan.neuraldefend.com",
            "ftp://deepscan.neuraldefend.com",
            "https://user:pass@deepscan.neuraldefend.com",
            "https://deepscan.neuraldefend.com/v1",
            "https://deepscan.neuraldefend.com?x=1",
            "https://deepscan.neuraldefend.com#frag",
            "deepscan.neuraldefend.com",
        ]
    )
    func invalidBaseURL(_ value: String) throws {
        let url = try #require(URL(string: value))
        do {
            _ = try NeuroVerifyClient(apiKey: "key", options: .init(baseURL: url, allowCustomBaseURL: true))
            Issue.record("accepted \(value)")
        } catch let error as NeuroVerifyError {
            guard case .validation(.invalidBaseURL, _) = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
    }

    @Test("validates the API key, timeout, and retries")
    func validation() {
        let cases: [(String, NeuroVerifyClient.Options, ValidationErrorCode)] = [
            ("", .init(), .apiKeyRequired),
            ("  \n", .init(), .apiKeyRequired),
            ("key", .init(timeout: 0), .invalidTimeout),
            ("key", .init(timeout: -1), .invalidTimeout),
            ("key", .init(timeout: .infinity), .invalidTimeout),
            ("key", .init(maxRetries: -1), .invalidRetries),
            ("key", .init(maxRetries: 4), .invalidRetries),
        ]
        for (key, options, code) in cases {
            do {
                _ = try NeuroVerifyClient(apiKey: key, options: options)
                Issue.record("accepted \(code)")
            } catch let error as NeuroVerifyError {
                guard case .validation(let actual, _) = error else {
                    Issue.record("unexpected \(error)")
                    continue
                }
                #expect(actual == code)
            } catch {
                Issue.record("unexpected \(error)")
            }
        }
    }

    @Test("the API key is redacted from descriptions and reflection")
    func redaction() throws {
        let client = try NeuroVerifyClient(apiKey: "  super-secret-key  ")
        #expect(!client.description.contains("super-secret-key"))
        #expect(!String(reflecting: client).contains("super-secret-key"))
        var dumped = ""
        dump(client, to: &dumped)
        #expect(!dumped.contains("super-secret-key"))
        #expect(dumped.contains("[REDACTED]"))
    }

    @Test("fromEnvironment reads NEURALDEFEND_API_KEY and NEURALDEFEND_BASE_URL")
    func environment() throws {
        let client = try NeuroVerifyClient.fromEnvironment(
            environment: [
                "NEURALDEFEND_API_KEY": "env-key",
                "NEURALDEFEND_BASE_URL": "https://stage.deepscan.neuraldefend.com",
            ]
        )
        #expect(client.baseURL == NeuroVerifyClient.stagingURL)
        #expect(throws: NeuroVerifyError.self) {
            try NeuroVerifyClient.fromEnvironment(environment: [:])
        }
        #expect(throws: NeuroVerifyError.self) {
            try NeuroVerifyClient.fromEnvironment(
                environment: ["NEURALDEFEND_API_KEY": "k", "NEURALDEFEND_BASE_URL": "https://evil.example"]
            )
        }
    }

    @Test("errors describe themselves without leaking response bodies")
    func errorDescriptions() {
        let error = NeuroVerifyError.rateLimit(
            ErrorDetails(message: "Rate limit exceeded", statusCode: 429, requestID: "req-1"),
            RateLimitInfo(retryAfter: 60, limit: "1000", remaining: "0", reset: nil)
        )
        #expect(
            error.description == "NeuroVerifyError.rateLimit: Rate limit exceeded (statusCode: 429, requestID: req-1)")
        #expect(error.localizedDescription == "Rate limit exceeded")
        #expect(NeuroVerifyError.cancelled.statusCode == nil)
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(Int64, Int64)] = []

    func add(_ sent: Int64, _ total: Int64) {
        lock.lock()
        recorded.append((sent, total))
        lock.unlock()
    }

    var events: [(Int64, Int64)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ValidationWarning] = []

    func add(_ warning: ValidationWarning) {
        lock.lock()
        recorded.append(warning)
        lock.unlock()
    }

    var values: [ValidationWarning] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
