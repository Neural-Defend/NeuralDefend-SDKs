import Foundation
import Testing

@testable import NeuralDefend

private let stagingKey = ProcessInfo.processInfo.environment["NEURALDEFEND_STAGING_API_KEY"] ?? ""

private func stagingMedia(_ variable: String, _ fallback: String) throws -> URL {
    let path = ProcessInfo.processInfo.environment[variable] ?? fixturesRoot.appendingPathComponent(fallback).path
    guard FileManager.default.fileExists(atPath: path) else {
        throw FixtureError.invalid("\(variable) does not identify a staging fixture: \(path)")
    }
    return URL(fileURLWithPath: path)
}

private func expectConsistent(_ originalStatus: String, _ trxID: String, _ scored: Bool, _ rejected: Bool) {
    #expect(["success", "rejected"].contains(originalStatus))
    #expect(!trxID.isEmpty)
    #expect(scored == (originalStatus == "success"))
    #expect(rejected == (originalStatus == "rejected"))
}

/// Live staging checks. They run only when `NEURALDEFEND_STAGING_API_KEY` is set, as in the
/// protected `staging-smoke.yml` workflow; `swift test --filter Staging` selects them.
@Suite(
    "Staging",
    .enabled(if: !stagingKey.isEmpty, "NEURALDEFEND_STAGING_API_KEY is not configured"),
    .serialized
)
struct StagingTests {
    @Test("staging image contract")
    func image() async throws {
        let client = try NeuroVerifyClient.staging(apiKey: stagingKey, options: .init(maxRetries: 0))
        let result = try await client.detectImage(
            .file(try stagingMedia("NEURALDEFEND_STAGING_IMAGE", "media/ai-generated.png"))
        )
        expectConsistent(result.originalStatus, result.uniqueTrxID, result.isScored, result.isRejected)
        if result.isScored {
            #expect((0.1...10.0).contains(result.riskScore ?? -1))
            #expect(result.riskLevel != nil)
        }
    }

    @Test("staging video contract")
    func video() async throws {
        let client = try NeuroVerifyClient.staging(apiKey: stagingKey, options: .init(maxRetries: 0))
        let result = try await client.detectVideo(
            .file(try stagingMedia("NEURALDEFEND_STAGING_VIDEO", "media/fake-video.mp4")),
            maxFrames: 2
        )
        expectConsistent(result.originalStatus, result.uniqueTrxID, result.isScored, result.isRejected)
        if result.isScored {
            #expect((0.1...10.0).contains(result.videoRiskScore ?? -1))
            #expect(result.videoRiskLevel != nil)
        }
    }
}
