import Foundation

/// Normalized outcome of a detection request.
public enum ResultStatus: String, Sendable, Codable, CaseIterable {
    /// The media was scored and every returned risk band is recognized.
    case success

    /// The API declined to score the media. This is a normal result, not an error, and it can
    /// be billable.
    case rejected

    /// The API returned an outcome or risk band this SDK version does not recognize. Do not
    /// make policy decisions from it; upgrade the SDK.
    case unknown
}

/// Service-owned risk band. Base decisions on the band rather than on score thresholds, which
/// the service may tune.
public enum RiskLevel: String, Sendable, Codable, CaseIterable {
    case low
    case medium
    case high
}

/// Result of ``NeuroVerifyClient/detectImage(_:onProgress:)``.
///
/// Encoding produces the stable normalized fields and never includes ``raw``.
public struct ImageResult: Sendable, Equatable {
    /// Normalized outcome. Always branch on this before reading scores.
    public let status: ResultStatus

    /// Exact wire `status` value, useful when ``status`` is ``ResultStatus/unknown``.
    public let originalStatus: String

    /// Transaction ID. Every accepted attempt receives a new one; persist it for audit,
    /// billing, and support correlation.
    public let uniqueTrxID: String

    public let filename: String

    /// Content type detected by the service.
    public let contentType: String

    /// Service status code. Unknown values are preserved.
    public let statusCode: Int

    /// Authoritative billing indicator for this transaction. Rejections can be billable.
    public let billable: Bool

    /// Checks reported by the service. The list may evolve; do not build fixed logic around it.
    public let aiThreatSignals: [String]

    /// Risk score from 0.1 through 10.0; higher means more observed risk. `nil` when the image
    /// was not scored.
    public let riskScore: Double?

    /// Recognized risk band, or `nil` when unscored or unrecognized.
    public let riskLevel: RiskLevel?

    /// Exact wire `risk_level` value, preserved for unknown bands.
    public let originalRiskLevel: String?

    /// Service message. Suitable for user guidance; do not branch on its text.
    public let message: String

    /// Redacted wire envelope using the API's field names. Not a stable contract; it may
    /// contain filenames, messages, or future fields, so do not log or persist it routinely.
    public let raw: JSONValue

    /// `true` only for a recognized, scored result.
    public var isScored: Bool { status == .success }

    /// `true` when the API rejected the media without an error.
    public var isRejected: Bool { status == .rejected }

    /// `true` when the recognized risk band is ``RiskLevel/high``.
    public var isHighRisk: Bool { riskLevel == .high }
}

/// Result of ``NeuroVerifyClient/detectVideo(_:maxFrames:sampleRate:onProgress:)``.
///
/// Video and audio are independent modalities and can carry different risk bands. Encoding
/// produces the stable normalized fields and never includes ``raw``.
public struct VideoResult: Sendable, Equatable {
    public let status: ResultStatus
    public let originalStatus: String
    public let uniqueTrxID: String
    public let filename: String
    public let contentType: String
    public let statusCode: Int
    public let billable: Bool
    public let aiThreatSignals: [String]

    public let videoRiskScore: Double?
    public let videoRiskLevel: RiskLevel?
    public let originalVideoRiskLevel: String?
    public let videoMessage: String

    /// `nil` when the video has no audio track or was not scored.
    public let audioRiskScore: Double?
    public let audioRiskLevel: RiskLevel?
    public let originalAudioRiskLevel: String?

    /// For example `"No audio track detected"`; `nil` on rejections.
    public let audioMessage: String?

    /// Redacted wire envelope. See ``ImageResult/raw``.
    public let raw: JSONValue

    public var isScored: Bool { status == .success }
    public var isRejected: Bool { status == .rejected }

    /// `true` when an audio risk score was returned.
    public var hasAudio: Bool { audioRiskScore != nil }

    /// SDK convenience: the maximum available modality score. The API does not return a
    /// combined score, and this does not replace modality-aware policy.
    public var overallRiskScore: Double? {
        switch (videoRiskScore, audioRiskScore) {
        case (let video?, let audio?): return max(video, audio)
        case (let video?, nil): return video
        case (nil, let audio): return audio
        }
    }
}

extension ImageResult: Encodable {
    private enum CodingKeys: String, CodingKey {
        case status, scored, rejected, originalStatus, uniqueTrxId, filename, contentType
        case statusCode, billable, aiThreatSignals, originalRiskLevel, riskScore, riskLevel
        case message, highRisk
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(isScored, forKey: .scored)
        try container.encode(isRejected, forKey: .rejected)
        if status == .unknown {
            try container.encode(originalStatus, forKey: .originalStatus)
            try container.encode(originalRiskLevel, forKey: .originalRiskLevel)
        }
        try container.encode(uniqueTrxID, forKey: .uniqueTrxId)
        try container.encode(filename, forKey: .filename)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(statusCode, forKey: .statusCode)
        try container.encode(billable, forKey: .billable)
        try container.encode(aiThreatSignals, forKey: .aiThreatSignals)
        try container.encode(riskScore, forKey: .riskScore)
        try container.encode(riskLevel, forKey: .riskLevel)
        try container.encode(message, forKey: .message)
        try container.encode(isHighRisk, forKey: .highRisk)
    }
}

extension VideoResult: Encodable {
    private enum CodingKeys: String, CodingKey {
        case status, scored, rejected, originalStatus, uniqueTrxId, filename, contentType
        case statusCode, billable, aiThreatSignals, originalVideoRiskLevel
        case originalAudioRiskLevel, hasAudio, videoRiskScore, videoRiskLevel, videoMessage
        case audioRiskScore, audioRiskLevel, audioMessage, overallRiskScore
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(isScored, forKey: .scored)
        try container.encode(isRejected, forKey: .rejected)
        if status == .unknown {
            try container.encode(originalStatus, forKey: .originalStatus)
            try container.encode(originalVideoRiskLevel, forKey: .originalVideoRiskLevel)
            try container.encode(originalAudioRiskLevel, forKey: .originalAudioRiskLevel)
        }
        try container.encode(uniqueTrxID, forKey: .uniqueTrxId)
        try container.encode(filename, forKey: .filename)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(statusCode, forKey: .statusCode)
        try container.encode(billable, forKey: .billable)
        try container.encode(aiThreatSignals, forKey: .aiThreatSignals)
        try container.encode(hasAudio, forKey: .hasAudio)
        try container.encode(videoRiskScore, forKey: .videoRiskScore)
        try container.encode(videoRiskLevel, forKey: .videoRiskLevel)
        try container.encode(videoMessage, forKey: .videoMessage)
        try container.encode(audioRiskScore, forKey: .audioRiskScore)
        try container.encode(audioRiskLevel, forKey: .audioRiskLevel)
        try container.encode(audioMessage, forKey: .audioMessage)
        try container.encode(overallRiskScore, forKey: .overallRiskScore)
    }
}

extension ImageResult: CustomStringConvertible {
    /// Normalized fields only; ``raw`` is never printed.
    public var description: String {
        "ImageResult(status: \(status.rawValue), uniqueTrxID: \(uniqueTrxID), "
            + "riskLevel: \(riskLevel?.rawValue ?? "nil"), "
            + "riskScore: \(riskScore.map { String($0) } ?? "nil"), billable: \(billable))"
    }
}

extension VideoResult: CustomStringConvertible {
    /// Normalized fields only; ``raw`` is never printed.
    public var description: String {
        "VideoResult(status: \(status.rawValue), uniqueTrxID: \(uniqueTrxID), "
            + "videoRiskLevel: \(videoRiskLevel?.rawValue ?? "nil"), "
            + "audioRiskLevel: \(audioRiskLevel?.rawValue ?? "nil"), billable: \(billable))"
    }
}
