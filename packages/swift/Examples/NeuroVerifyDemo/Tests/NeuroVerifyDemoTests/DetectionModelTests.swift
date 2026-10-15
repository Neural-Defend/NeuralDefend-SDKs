import Foundation
import NeuralDefend
import Testing

@testable import NeuroVerifyDemo

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Answers every request with a canned response, so the demo runs without a network or key.
final class MockURLProtocol: URLProtocol {
    struct Reply: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: URLRequest] = [:]

    /// Registers `reply` for requests carrying `x-api-key: key`, so parallel tests don't collide.
    static func register(_ reply: Reply, forKey key: String) {
        lock.lock()
        replies[key] = reply
        lock.unlock()
    }

    static func lastRequest(forKey key: String) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return seen[key]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "x-api-key") ?? ""
        Self.lock.lock()
        let reply = Self.replies[key]
        Self.seen[key] = request
        Self.lock.unlock()
        guard let reply, let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: reply.headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // NeuroVerifyDemoTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // NeuroVerifyDemo
    .deletingLastPathComponent()  // Examples
    .deletingLastPathComponent()  // swift
    .deletingLastPathComponent()  // packages
    .deletingLastPathComponent()
    .appendingPathComponent("tests/fixtures")

/// Turns a shared contract fixture into a mocked reply.
private func fixtureReply(_ path: String) throws -> MockURLProtocol.Reply {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(path))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let body = try JSONSerialization.data(withJSONObject: try #require(object["body"]))
    return MockURLProtocol.Reply(
        status: try #require(object["http_status"] as? Int),
        headers: object["headers"] as? [String: String] ?? [:],
        body: body
    )
}

@MainActor
private func model(replying fixture: String) throws -> (DetectionModel, String) {
    let key = "demo-key-\(UUID().uuidString)"
    MockURLProtocol.register(try fixtureReply(fixture), forKey: key)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let client = try NeuroVerifyClient(
        apiKey: key,
        options: .init(maxRetries: 0),
        sessionConfiguration: configuration
    )
    return (DetectionModel(client: client), key)
}

private let photo = MediaInput.data(Data("jpeg-bytes".utf8), filename: "selfie.jpg")
private let clip = MediaInput.data(Data("mp4-bytes".utf8), filename: "clip.mp4")

@MainActor
@Suite("Demo screen model")
struct DetectionModelTests {
    @Test("a scored image shows its risk band and transaction ID")
    func scoredImage() async throws {
        let (model, key) = try model(replying: "image/documented/low-risk.json")
        await model.analyze(photo, isVideo: false)
        guard case .finished(let summary) = model.phase else {
            Issue.record("unexpected phase \(model.phase)")
            return
        }
        #expect(summary.title == "Risk: low")
        #expect(summary.detail.hasPrefix("Score 2.2 of 10."))
        #expect(summary.transactionID == "trx_c1r7n6oy69zhunjrkp0p")
        let request = try #require(MockURLProtocol.lastRequest(forKey: key))
        #expect(request.url?.absoluteString == "https://deepscan.neuraldefend.com/detect/image")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("neuraldefend-swift/") == true)
    }

    @Test("a rejected image is a normal outcome, not an error")
    func rejectedImage() async throws {
        let (model, _) = try model(replying: "image/documented/no-face.json")
        await model.analyze(photo, isVideo: false)
        guard case .finished(let summary) = model.phase else {
            Issue.record("unexpected phase \(model.phase)")
            return
        }
        #expect(summary.title == "Not analyzed")
    }

    @Test("a video shows video and audio separately")
    func video() async throws {
        let (model, key) = try model(replying: "video/documented/silent-no-audio.json")
        await model.analyze(clip, isVideo: true)
        guard case .finished(let summary) = model.phase else {
            Issue.record("unexpected phase \(model.phase)")
            return
        }
        #expect(summary.title.hasPrefix("Video risk: "))
        #expect(summary.detail.hasPrefix("Audio: no audio."))
        #expect(MockURLProtocol.lastRequest(forKey: key)?.url?.query == "max_frames=12")
    }

    @Test("an invalid key shows guidance instead of the server's raw text")
    func invalidKey() async throws {
        let (model, _) = try model(replying: "image/synthetic/unauthorized-401.json")
        await model.analyze(photo, isVideo: false)
        #expect(
            model.phase == .failed("The API key was rejected. Check that it is valid for this environment.")
        )
    }

    @Test("a rate limit shows when to try again")
    func rateLimited() async throws {
        let (model, _) = try model(replying: "image/synthetic/rate-limited-429.json")
        await model.analyze(photo, isVideo: false)
        #expect(model.phase == .failed("Too many requests. Try again in 60 seconds."))
    }

    @Test("local validation errors are shown before any upload")
    func validation() async throws {
        let (model, key) = try model(replying: "image/documented/low-risk.json")
        await model.analyze(.data(Data(), filename: "empty.jpg"), isVideo: false)
        #expect(model.phase == .failed("The upload is empty."))
        #expect(MockURLProtocol.lastRequest(forKey: key) == nil)
    }
}
