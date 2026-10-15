import Foundation
import Testing

@testable import NeuralDefend

/// Behavior that depends on real sockets: deadlines, cancellation, redirects, refused
/// connections, and large streaming uploads.
@Suite("Real sockets")
struct TransportTests {
    @Test("streams a large file upload over a real connection")
    func largeUpload() async throws {
        let size = 64 << 20
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("neuraldefend-large-\(UUID().uuidString).mp4")
        _ = FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file)
        let chunk = Data((0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0) })
        for _ in 0..<(size >> 20) { try handle.write(contentsOf: chunk) }
        try handle.close()

        let recorder = ProgressRecorder()
        let server = try fixtureServer(["video/documented/both-low.json"])
        try await withServer(server) { server in
            let result = try await makeClient(server).detectVideo(
                .file(file),
                onProgress: { sent, total in recorder.add(sent, total) }
            )
            #expect(result.isScored)
            let request = try #require(server.requests.first)
            #expect(request.bodyLength > size)
            #expect(request.bodyLength < size + 1024)
            #expect(request.header("content-length") == String(request.bodyLength))
            // URLSession may coalesce loopback progress into a single callback.
            let sent = recorder.events.map(\.0)
            #expect(sent.first == 0)
            #expect(sent == sent.sorted())
            #expect(recorder.events.last.map { $0.0 == $0.1 && Int($0.1) == request.bodyLength } == true)
        }
    }

    @Test("a slow server raises a timeout and is not retried")
    func timeout() async throws {
        let server = try LocalHTTPServer { _, _ in .hang }
        try await withServer(server) { server in
            let client = try makeClient(server, maxRetries: 3, timeout: 0.5)
            let started = Date()
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            guard case .timeout(let message)? = error else {
                Issue.record("expected a timeout, got \(String(describing: error))")
                return
            }
            #expect(message == "The image request timed out after 500 ms.")
            let elapsed = Date().timeIntervalSince(started)
            #expect(elapsed >= 0.45, "the SDK deadline, not URLSession's, must end the attempt")
            #expect(elapsed < 5)
            // A slow simulator can hit the deadline before the server logs the request, so
            // zero is fine; a retry would make it two or more.
            #expect(server.requests.count <= 1)
        }
    }

    @Test("cancelling the task cancels an in-flight request")
    func cancelInFlight() async throws {
        let server = try LocalHTTPServer { _, _ in .hang }
        try await withServer(server) { server in
            let client = try makeClient(server)
            let task = Task { await captureError { _ = try await client.detectImage(sampleImage) } }
            while server.requests.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
            task.cancel()
            #expect(await task.value == .cancelled)
        }
    }

    @Test("cancelling the task cancels a retry wait")
    func cancelRetryWait() async throws {
        let server = try fixtureServer(["image/documented/service-unavailable-503.json"])
        try await withServer(server) { server in
            let client = try NeuroVerifyClient(
                apiKey: testAPIKey,
                options: .init(baseURL: server.baseURL, allowCustomBaseURL: true, maxRetries: 3),
                sessionConfiguration: .ephemeral,
                allowInsecureForTesting: true,
                runtime: .live
            )
            let task = Task { await captureError { _ = try await client.detectImage(sampleImage) } }
            while server.requests.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
            try await Task.sleep(nanoseconds: 100_000_000)
            task.cancel()
            #expect(await task.value == .cancelled)
            #expect(server.requests.count == 1)
        }
    }

    @Test("a task cancelled before the call never sends a request")
    func cancelledBeforeStart() async throws {
        let server = try fixtureServer(["image/documented/low-risk.json"])
        try await withServer(server) { server in
            let client = try makeClient(server)
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await captureError { _ = try await client.detectImage(sampleImage) }
            }
            #expect(await task.value == .cancelled)
            #expect(server.requests.isEmpty)
        }
    }

    @Test("redirects are never followed")
    func redirect() async throws {
        let target = try fixtureServer(["image/documented/low-risk.json"])
        let location = target.baseURL.appendingPathComponent("detect/image").absoluteString
        let server = try LocalHTTPServer { _, _ in
            .respond(status: 302, headers: ["Location": location], body: Data())
        }
        try await withServer(server) { server in
            defer { target.stop() }
            let client = try makeClient(server, maxRetries: 3)
            let error = await captureError { _ = try await client.detectImage(sampleImage) }
            #expect(error?.statusCode == 302)
            guard case .http? = error else {
                Issue.record("expected an HTTP error, got \(String(describing: error))")
                return
            }
            #expect(server.requests.count == 1)
            #expect(target.requests.isEmpty)
        }
    }

    @Test("a refused connection raises a network error without the API key")
    func refusedConnection() async throws {
        let port = try LocalHTTPServer.closedPort()
        let client = try NeuroVerifyClient(
            apiKey: testAPIKey,
            options: .init(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                allowCustomBaseURL: true,
                maxRetries: 3
            ),
            sessionConfiguration: .ephemeral,
            allowInsecureForTesting: true,
            runtime: FakeClock().runtime
        )
        let error = await captureError { _ = try await client.detectImage(sampleImage) }
        guard case .network(let message)? = error else {
            Issue.record("expected a network error, got \(String(describing: error))")
            return
        }
        #expect(message.hasPrefix("The image request failed before receiving a response"))
        #expect(!String(describing: error!).contains(testAPIKey))
    }
}
