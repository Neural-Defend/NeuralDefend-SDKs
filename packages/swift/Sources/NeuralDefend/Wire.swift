import Foundation

let imageEnvelopeKey = "unified_face_authenticity_score"
let videoEnvelopeKey = "unified_video_authenticity_score"

/// Strict reader for one response envelope. Every failure is a protocol error.
struct EnvelopeReader {
    let members: [String: JSONValue]
    let httpStatus: Int
    let requestID: String?

    func invalid(_ field: String, _ expectation: String = "was missing or invalid")
        -> NeuroVerifyError
    {
        .protocol(
            ErrorDetails(
                message: "The response field \"\(field)\" \(expectation).",
                statusCode: httpStatus,
                requestID: requestID
            )
        )
    }

    func string(_ field: String) throws(NeuroVerifyError) -> String {
        guard case .string(let value)? = members[field] else { throw invalid(field) }
        return value
    }

    func integer(_ field: String) throws(NeuroVerifyError) -> Int {
        guard case .number(let value)? = members[field], value.isFinite,
            value == value.rounded(.towardZero), abs(value) <= 9_007_199_254_740_992
        else { throw invalid(field, "must be an integer") }
        return Int(value)
    }

    func nullableScore(_ field: String) throws(NeuroVerifyError) -> Double? {
        guard let value = members[field] else { throw invalid(field, "was missing") }
        switch value {
        case .null:
            return nil
        case .number(let score) where score.isFinite && score >= 0.1 && score <= 10.0:
            return score
        default:
            throw invalid(field, "must be from 0.1 through 10.0 or null")
        }
    }

    func nullableString(_ field: String) throws(NeuroVerifyError) -> String? {
        guard let value = members[field] else { throw invalid(field, "was missing") }
        switch value {
        case .null: return nil
        case .string(let text): return text
        default: throw invalid(field, "must be a string or null")
        }
    }

    func billable() throws(NeuroVerifyError) -> Bool {
        switch members["billable"] {
        case .string("Y")?: return true
        case .string("N")?: return false
        default: throw invalid("billable", "must be exactly \"Y\" or \"N\"")
        }
    }

    func signals() throws(NeuroVerifyError) -> [String] {
        switch members["ai_threat_signals"] {
        case nil, .null?:
            return []
        case .array(let items)?:
            var signals: [String] = []
            for item in items {
                guard case .string(let signal) = item else {
                    throw invalid("ai_threat_signals", "must be an array of strings")
                }
                signals.append(signal)
            }
            return signals
        default:
            throw invalid("ai_threat_signals", "must be an array of strings")
        }
    }
}

func normalizedStatus(_ wire: String) -> ResultStatus {
    switch wire {
    case "success": return .success
    case "rejected": return .rejected
    default: return .unknown
    }
}

func riskLevel(_ wire: String?) -> RiskLevel? {
    wire.flatMap(RiskLevel.init(rawValue:))
}

/// Parses an image envelope. Throws ``NeuroVerifyError/server(_:raw:)`` for
/// `status: "error"` and ``NeuroVerifyError/protocol(_:)`` for contract violations.
func parseImage(
    _ members: [String: JSONValue],
    httpStatus: Int,
    requestID: String?,
    secret: String
) throws(NeuroVerifyError) -> ImageResult {
    let reader = EnvelopeReader(members: members, httpStatus: httpStatus, requestID: requestID)
    let originalStatus = try reader.string("status")
    let uniqueTrxID = try reader.string("unique_trx_id")
    let filename = try reader.string("filename")
    let contentType = try reader.string("content_type")
    let statusCode = try reader.integer("status_code")
    let billable = try reader.billable()
    let signals = try reader.signals()
    let message = try reader.string("message")
    let score = try reader.nullableScore("risk_score")
    let originalLevel = try reader.nullableString("risk_level")
    let level = riskLevel(originalLevel)
    let raw = JSONValue.object(members).redacting(secret)

    if originalStatus == "error" {
        throw .server(
            ErrorDetails(
                message: redact(message, secret),
                statusCode: httpStatus,
                requestID: requestID
            ),
            raw: raw
        )
    }
    var status = normalizedStatus(originalStatus)
    if status == .success && (score == nil || level == nil) {
        status = .unknown
    }
    return ImageResult(
        status: status,
        originalStatus: originalStatus,
        uniqueTrxID: uniqueTrxID,
        filename: filename,
        contentType: contentType,
        statusCode: statusCode,
        billable: billable,
        aiThreatSignals: signals,
        riskScore: score,
        riskLevel: level,
        originalRiskLevel: originalLevel,
        message: message,
        raw: raw
    )
}

/// Parses a video envelope. Throws ``NeuroVerifyError/server(_:raw:)`` for
/// `status: "error"` and ``NeuroVerifyError/protocol(_:)`` for contract violations.
func parseVideo(
    _ members: [String: JSONValue],
    httpStatus: Int,
    requestID: String?,
    secret: String
) throws(NeuroVerifyError) -> VideoResult {
    let reader = EnvelopeReader(members: members, httpStatus: httpStatus, requestID: requestID)
    let originalStatus = try reader.string("status")
    let uniqueTrxID = try reader.string("unique_trx_id")
    let filename = try reader.string("filename")
    let contentType = try reader.string("content_type")
    let statusCode = try reader.integer("status_code")
    let billable = try reader.billable()
    let signals = try reader.signals()
    let videoMessage = try reader.string("video_message")
    let audioMessage = try reader.nullableString("audio_message")
    let videoScore = try reader.nullableScore("video_risk_score")
    let originalVideoLevel = try reader.nullableString("video_risk_level")
    let videoLevel = riskLevel(originalVideoLevel)
    let audioScore = try reader.nullableScore("audio_risk_score")
    let originalAudioLevel = try reader.nullableString("audio_risk_level")
    let audioLevel = riskLevel(originalAudioLevel)
    let raw = JSONValue.object(members).redacting(secret)

    if originalStatus == "error" {
        throw .server(
            ErrorDetails(
                message: redact(videoMessage, secret),
                statusCode: httpStatus,
                requestID: requestID
            ),
            raw: raw
        )
    }
    var status = normalizedStatus(originalStatus)
    if status == .success {
        let videoScored = videoScore != nil && videoLevel != nil
        let audioConsistent =
            (audioScore == nil && originalAudioLevel == nil)
            || (audioScore != nil && audioLevel != nil)
        if !videoScored || !audioConsistent { status = .unknown }
    }
    return VideoResult(
        status: status,
        originalStatus: originalStatus,
        uniqueTrxID: uniqueTrxID,
        filename: filename,
        contentType: contentType,
        statusCode: statusCode,
        billable: billable,
        aiThreatSignals: signals,
        videoRiskScore: videoScore,
        videoRiskLevel: videoLevel,
        originalVideoRiskLevel: originalVideoLevel,
        videoMessage: videoMessage,
        audioRiskScore: audioScore,
        audioRiskLevel: audioLevel,
        originalAudioRiskLevel: originalAudioLevel,
        audioMessage: audioMessage,
        raw: raw
    )
}
