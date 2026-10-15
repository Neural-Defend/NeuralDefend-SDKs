import Foundation
import Testing

@testable import NeuralDefend

private let imageResults = [
    "image/documented/low-risk.json",
    "image/documented/medium-risk.json",
    "image/documented/high-risk-spoof.json",
    "image/documented/no-face.json",
    "image/documented/multiple-faces.json",
    "image/documented/nsfw.json",
    "image/documented/blurry.json",
    "image/documented/unsupported-format.json",
    "image/documented/security-rejection.json",
    "image/documented/too-large.json",
]

private let videoResults = [
    "video/documented/both-low.json",
    "video/documented/video-high-audio-low.json",
    "video/documented/both-high.json",
    "video/documented/video-low-audio-high.json",
    "video/documented/medium-no-audio.json",
    "video/documented/silent-no-audio.json",
    "video/documented/no-face.json",
    "video/documented/multiple-faces.json",
    "video/documented/unsupported-format.json",
    "video/documented/security-rejection.json",
    "video/documented/too-large.json",
]

private let serverErrors = [
    "image/documented/internal-error-500.json",
    "image/documented/service-unavailable-503.json",
    "video/documented/internal-error-500.json",
    "video/documented/service-unavailable-503.json",
]

private let unknownValues = [
    "image/robustness/unknown-status-code.json",
    "image/robustness/unknown-status.json",
    "image/robustness/unknown-risk-level.json",
    "video/robustness/unknown-status-code.json",
    "video/robustness/unknown-status.json",
    "video/robustness/unknown-risk-level.json",
]

private let malformed = [
    "image/robustness/missing-envelope.json",
    "image/robustness/malformed-json.json",
    "video/robustness/missing-envelope.json",
    "video/robustness/malformed-json.json",
]

private let extraFields = [
    "image/robustness/unknown-extra-field.json",
    "video/robustness/unknown-extra-field.json",
]

private let unauthorized = ["image/synthetic/unauthorized-401.json", "video/synthetic/unauthorized-401.json"]
private let forbidden = ["image/synthetic/forbidden-403.json", "video/synthetic/forbidden-403.json"]
private let rateLimited = ["image/synthetic/rate-limited-429.json", "video/synthetic/rate-limited-429.json"]

private enum Outcome {
    case image(ImageResult)
    case video(VideoResult)
    case failure(NeuroVerifyError)

    var error: NeuroVerifyError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

private func detect(_ fixture: String) async throws -> Outcome {
    let server = try fixtureServer([fixture])
    return try await withServer(server) { server in
        let client = try makeClient(server)
        do {
            if fixture.hasPrefix("image/") {
                return .image(try await client.detectImage(sampleImage))
            }
            return .video(try await client.detectVideo(sampleVideo))
        } catch let error as NeuroVerifyError {
            return .failure(error)
        }
    }
}

private func expectedStatus(_ wire: String?) -> ResultStatus {
    switch wire {
    case "success": return .success
    case "rejected": return .rejected
    default: return .unknown
    }
}

@Suite("Shared contract fixtures")
struct ContractTests {
    @Test("the shared corpus contains the documented 43 fixtures")
    func corpusSize() {
        #expect(allFixturePaths().count == 43)
    }

    @Test("every fixture is covered by exactly one contract group")
    func coverage() {
        let covered =
            imageResults + videoResults + serverErrors + unknownValues + malformed + extraFields
            + unauthorized + forbidden + rateLimited
        #expect(Set(covered).count == covered.count)
        #expect(Set(covered) == Set(allFixturePaths()))
    }

    @Test("documented image results", arguments: imageResults)
    func imageResult(_ fixture: String) async throws {
        let wire = try #require(try loadFixture(fixture).envelope)
        guard case .image(let result) = try await detect(fixture) else {
            Issue.record("expected an image result")
            return
        }
        #expect(result.status == expectedStatus(wire["status"]?.stringValue))
        #expect(result.originalStatus == wire["status"]?.stringValue)
        #expect(result.uniqueTrxID == wire["unique_trx_id"]?.stringValue)
        #expect(result.filename == wire["filename"]?.stringValue)
        #expect(result.contentType == wire["content_type"]?.stringValue)
        #expect(Double(result.statusCode) == wire["status_code"]?.doubleValue)
        #expect(result.billable == (wire["billable"]?.stringValue == "Y"))
        #expect(result.riskScore == wire["risk_score"]?.doubleValue)
        #expect(result.riskLevel?.rawValue == wire["risk_level"]?.stringValue)
        #expect(result.message == wire["message"]?.stringValue)
        #expect(result.aiThreatSignals == (wire["ai_threat_signals"]?.arrayValue ?? []).compactMap(\.stringValue))
        #expect(result.isScored == (wire["status"]?.stringValue == "success"))
        #expect(result.isRejected == (wire["status"]?.stringValue == "rejected"))
        #expect(result.isHighRisk == (wire["risk_level"]?.stringValue == "high"))
        #expect(result.raw == wire)
    }

    @Test("documented video results", arguments: videoResults)
    func videoResult(_ fixture: String) async throws {
        let wire = try #require(try loadFixture(fixture).envelope)
        guard case .video(let result) = try await detect(fixture) else {
            Issue.record("expected a video result")
            return
        }
        #expect(result.status == expectedStatus(wire["status"]?.stringValue))
        #expect(Double(result.statusCode) == wire["status_code"]?.doubleValue)
        #expect(result.billable == (wire["billable"]?.stringValue == "Y"))
        #expect(result.videoRiskScore == wire["video_risk_score"]?.doubleValue)
        #expect(result.videoRiskLevel?.rawValue == wire["video_risk_level"]?.stringValue)
        #expect(result.videoMessage == wire["video_message"]?.stringValue)
        #expect(result.audioRiskScore == wire["audio_risk_score"]?.doubleValue)
        #expect(result.audioRiskLevel?.rawValue == wire["audio_risk_level"]?.stringValue)
        #expect(result.audioMessage == wire["audio_message"]?.stringValue)
        #expect(result.hasAudio == (wire["audio_risk_score"]?.doubleValue != nil))
        let scores = [wire["video_risk_score"]?.doubleValue, wire["audio_risk_score"]?.doubleValue]
            .compactMap { $0 }
        #expect(result.overallRiskScore == scores.max())
        #expect(result.raw == wire)
    }

    @Test("server error envelopes throw server errors", arguments: serverErrors)
    func serverError(_ fixture: String) async throws {
        let caseData = try loadFixture(fixture)
        guard case .server(let details, let raw)? = try await detect(fixture).error else {
            Issue.record("expected a server error")
            return
        }
        #expect(details.statusCode == caseData.httpStatus)
        #expect(raw == caseData.envelope)
        #expect(details.requestID == caseData.envelope?["unique_trx_id"]?.stringValue)
    }

    @Test("HTTP 401 throws an authentication error", arguments: unauthorized)
    func authentication(_ fixture: String) async throws {
        let caseData = try loadFixture(fixture)
        guard case .authentication(let details)? = try await detect(fixture).error else {
            Issue.record("expected an authentication error")
            return
        }
        #expect(details.message == caseData.body?["detail"]?.stringValue)
        #expect(details.statusCode == 401)
    }

    @Test("HTTP 403 throws a scope error", arguments: forbidden)
    func scope(_ fixture: String) async throws {
        let caseData = try loadFixture(fixture)
        guard case .scope(let details)? = try await detect(fixture).error else {
            Issue.record("expected a scope error")
            return
        }
        #expect(details.message == caseData.body?["detail"]?.stringValue)
        #expect(details.statusCode == 403)
    }

    @Test("rate-limit errors expose every documented header", arguments: rateLimited)
    func rateLimit(_ fixture: String) async throws {
        guard case .rateLimit(let details, let info)? = try await detect(fixture).error else {
            Issue.record("expected a rate-limit error")
            return
        }
        #expect(details.statusCode == 429)
        #expect(details.message == "Rate limit exceeded")
        #expect(info.retryAfter == 60)
        #expect(info.limit == "1000")
        #expect(info.remaining == "0")
        #expect(info.reset == "2026-07-27T00:00:00Z")
    }

    @Test("malformed responses throw protocol errors", arguments: malformed)
    func malformedResponse(_ fixture: String) async throws {
        let caseData = try loadFixture(fixture)
        guard case .protocol(let details)? = try await detect(fixture).error else {
            Issue.record("expected a protocol error")
            return
        }
        #expect(details.statusCode == caseData.httpStatus)
    }

    @Test("unknown wire values are preserved without breaking", arguments: unknownValues)
    func unknownValue(_ fixture: String) async throws {
        let wire = try #require(try loadFixture(fixture).envelope)
        switch try await detect(fixture) {
        case .image(let result):
            #expect(result.originalStatus == wire["status"]?.stringValue)
            #expect(Double(result.statusCode) == wire["status_code"]?.doubleValue)
            #expect(result.originalRiskLevel == wire["risk_level"]?.stringValue)
            let known =
                wire["status"]?.stringValue == "success"
                && RiskLevel(rawValue: wire["risk_level"]?.stringValue ?? "") != nil
            #expect(result.status == (known ? .success : .unknown))
            #expect(result.isScored == known)
            if !known {
                let json = try JSONValue.parse(JSONEncoder().encode(result))
                #expect(json?["originalStatus"]?.stringValue == wire["status"]?.stringValue)
            }
        case .video(let result):
            #expect(result.originalStatus == wire["status"]?.stringValue)
            #expect(Double(result.statusCode) == wire["status_code"]?.doubleValue)
            #expect(result.originalVideoRiskLevel == wire["video_risk_level"]?.stringValue)
            let known =
                wire["status"]?.stringValue == "success"
                && RiskLevel(rawValue: wire["video_risk_level"]?.stringValue ?? "") != nil
            #expect(result.status == (known ? .success : .unknown))
            #expect(result.isScored == known)
        case .failure(let error):
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("unknown extra fields stay in raw and out of the encoded result", arguments: extraFields)
    func extraField(_ fixture: String) async throws {
        let encoded: Data
        let raw: JSONValue
        switch try await detect(fixture) {
        case .image(let result):
            raw = result.raw
            encoded = try JSONEncoder().encode(result)
        case .video(let result):
            raw = result.raw
            encoded = try JSONEncoder().encode(result)
        case .failure(let error):
            Issue.record("unexpected error \(error)")
            return
        }
        #expect(raw["future_signal"]?["confidence"]?.doubleValue == 0.42)
        let json = try #require(JSONValue.parse(encoded)?.objectValue)
        #expect(json["raw"] == nil)
        #expect(json["future_signal"] == nil)
    }

    @Test("normalized image JSON matches the documented shape")
    func imageShape() async throws {
        guard case .image(let result) = try await detect("image/documented/low-risk.json") else {
            Issue.record("expected an image result")
            return
        }
        let json = try #require(JSONValue.parse(JSONEncoder().encode(result))?.objectValue)
        #expect(
            Set(json.keys) == [
                "status", "scored", "rejected", "uniqueTrxId", "filename", "contentType",
                "statusCode", "billable", "aiThreatSignals", "riskScore", "riskLevel", "message",
                "highRisk",
            ]
        )
        #expect(json["status"] == .string("success"))
        #expect(json["filename"] == .string("selfie.jpg"))
        #expect(json["contentType"] == .string("image/jpeg"))
        #expect(json["statusCode"] == .number(1))
        #expect(json["billable"] == .bool(true))
        #expect(json["riskLevel"] == .string("low"))
        #expect(json["highRisk"] == .bool(false))
    }

    @Test("normalized video JSON keeps modalities independent")
    func videoShape() async throws {
        guard case .video(let result) = try await detect("video/documented/silent-no-audio.json") else {
            Issue.record("expected a video result")
            return
        }
        let json = try #require(JSONValue.parse(JSONEncoder().encode(result))?.objectValue)
        #expect(json["hasAudio"] == .bool(false))
        #expect(json["audioRiskScore"] == .null)
        #expect(json["audioRiskLevel"] == .null)
        #expect(json["overallRiskScore"] == result.videoRiskScore.map(JSONValue.number))
    }
}
