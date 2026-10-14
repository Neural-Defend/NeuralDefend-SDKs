import Foundation

@testable import NeuralDefend

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

let testAPIKey = "secret-test-key"

/// Repository root, found from this file's location so tests run the same under `swift test`,
/// `xcodebuild test`, and the iOS Simulator (which can read the host file system).
let repositoryRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return url
}()

let fixturesRoot = repositoryRoot.appendingPathComponent("tests/fixtures", isDirectory: true)

/// One shared contract fixture: an HTTP status, headers, and body for an endpoint.
struct FixtureCase {
    let path: String
    let endpoint: String
    let httpStatus: Int
    let headers: [String: String]
    let bodyData: Data
    let json: JSONValue

    var body: JSONValue? { json["body"] }

    var isImage: Bool { endpoint == "/detect/image" }

    /// The wire envelope inside the body.
    var envelope: JSONValue? {
        body?[isImage ? "unified_face_authenticity_score" : "unified_video_authenticity_score"]
    }

    var reply: ServerReply {
        .respond(status: httpStatus, headers: headers, body: bodyData)
    }
}

func loadFixture(_ relativePath: String) throws -> FixtureCase {
    let data = try Data(contentsOf: fixturesRoot.appendingPathComponent(relativePath))
    guard let json = JSONValue.parse(data), case .object(let members) = json else {
        throw FixtureError.invalid(relativePath)
    }
    var headers: [String: String] = [:]
    for (name, value) in members["headers"]?.objectValue ?? [:] {
        headers[name] = value.stringValue
    }
    let bodyData: Data
    if members["body_kind"]?.stringValue == "raw" {
        bodyData = Data((members["body"]?.stringValue ?? "").utf8)
    } else {
        bodyData = try JSONEncoder().encode(members["body"] ?? .null)
    }
    return FixtureCase(
        path: relativePath,
        endpoint: members["endpoint"]?.stringValue ?? "",
        httpStatus: Int(members["http_status"]?.doubleValue ?? 0),
        headers: headers,
        bodyData: bodyData,
        json: json
    )
}

/// Every fixture path relative to `tests/fixtures`, sorted.
func allFixturePaths() -> [String] {
    var paths: [String] = []
    for kind in ["image", "video"] {
        let root = fixturesRoot.appendingPathComponent(kind, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { continue }
        for case let relative as String in enumerator where relative.hasSuffix(".json") {
            paths.append("\(kind)/\(relative)")
        }
    }
    return paths.sorted()
}

enum FixtureError: Error {
    case invalid(String)
}

/// Records every requested retry delay and never actually sleeps.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    let jitter: Double
    let now: Date

    init(jitter: Double = 0, now: Date = Date(timeIntervalSince1970: 1_785_110_340)) {
        self.jitter = jitter
        self.now = now
    }

    var sleeps: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ seconds: TimeInterval) {
        lock.lock()
        recorded.append(seconds)
        lock.unlock()
    }

    var runtime: ClientRuntime {
        ClientRuntime(
            sleep: { [self] seconds in
                record(seconds)
                try Task.checkCancellation()
            },
            random: { [jitter] in jitter },
            now: { [now] in now }
        )
    }
}

/// A client that accepts the plain-HTTP local server.
func makeClient(
    _ server: LocalHTTPServer,
    maxRetries: Int = 0,
    timeout: TimeInterval = 30,
    retryAfterCap: TimeInterval = 60,
    userAgent: String? = nil,
    runtime: ClientRuntime = FakeClock().runtime,
    onWarning: (@Sendable (ValidationWarning) -> Void)? = nil
) throws -> NeuroVerifyClient {
    try NeuroVerifyClient(
        apiKey: testAPIKey,
        options: NeuroVerifyClient.Options(
            baseURL: server.baseURL,
            allowCustomBaseURL: true,
            timeout: timeout,
            maxRetries: maxRetries,
            retryAfterCap: retryAfterCap,
            userAgent: userAgent,
            onWarning: onWarning
        ),
        sessionConfiguration: .ephemeral,
        allowInsecureForTesting: true,
        runtime: runtime
    )
}

/// Starts a server that replies with `fixtures` in order, repeating the last one.
func fixtureServer(_ fixtures: [String]) throws -> LocalHTTPServer {
    let replies = try fixtures.map { try loadFixture($0).reply }
    return try LocalHTTPServer { call, _ in replies[min(call - 1, replies.count - 1)] }
}

/// Runs `body` with a server and always stops it.
func withServer<T>(
    _ server: LocalHTTPServer,
    _ body: (LocalHTTPServer) async throws -> T
) async rethrows -> T {
    defer { server.stop() }
    return try await body(server)
}

let sampleImage = MediaInput.data(Data("image".utf8), filename: "sample.jpg")
let sampleVideo = MediaInput.data(Data("video".utf8), filename: "sample.mp4")

/// Captures the error thrown by `body`, or `nil` when it succeeds.
func captureError(_ body: () async throws -> Void) async -> NeuroVerifyError? {
    do {
        try await body()
        return nil
    } catch let error as NeuroVerifyError {
        return error
    } catch {
        return .network(message: "unexpected error type: \(error)")
    }
}
