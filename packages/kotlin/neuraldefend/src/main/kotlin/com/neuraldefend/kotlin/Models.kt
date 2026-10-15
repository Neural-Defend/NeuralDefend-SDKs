package com.neuraldefend.kotlin

/**
 * Service-owned risk band. Base decisions on the band rather than on score thresholds,
 * which the service may tune.
 */
public enum class RiskLevel(
    /** Exact wire value. */
    public val wireValue: String,
) {
    LOW("low"),
    MEDIUM("medium"),
    HIGH("high"),
    ;

    public companion object {
        /** Returns the band for a wire value, or `null` when absent or not recognized. */
        @JvmStatic
        public fun fromWire(value: String?): RiskLevel? = entries.firstOrNull { it.wireValue == value }
    }
}

/** Normalized outcome of a detection request. */
public enum class ResultStatus(
    /** Lower-case name used by [DetectionResult.toJson]. */
    public val wireValue: String,
) {
    /** The media was scored and every returned risk band is recognized. */
    SUCCESS("success"),

    /** The API declined to score the media. A normal result, not an exception; it can be billable. */
    REJECTED("rejected"),

    /**
     * The API returned an outcome or risk band this SDK version does not recognize. Do not
     * make policy decisions from it; upgrade the SDK.
     */
    UNKNOWN("unknown"),
}

/** Non-fatal media warning that does not prevent the upload. */
public class ValidationWarning(
    /** Currently always `unsupported_extension`. */
    public val code: String,
    public val message: String,
    public val filename: String,
) {
    override fun toString(): String = "ValidationWarning($code): $message"
}

/** Fields shared by [ImageResult] and [VideoResult]. */
public sealed class DetectionResult(
    /** Normalized outcome. Always branch on this before reading scores. */
    public val status: ResultStatus,
    /** Exact wire `status` value, useful when [status] is [ResultStatus.UNKNOWN]. */
    public val originalStatus: String,
    /**
     * Transaction ID. Every accepted attempt receives a new one; persist it for audit,
     * billing, and support correlation.
     */
    public val uniqueTrxId: String,
    public val filename: String,
    /** Content type detected by the service. */
    public val contentType: String,
    /** Service status code. Unknown values are preserved. */
    public val statusCode: Int,
    /** Authoritative billing indicator for this transaction. Rejections can be billable. */
    public val billable: Boolean,
    /** Checks reported by the service. The list may evolve; do not build fixed logic around it. */
    public val aiThreatSignals: List<String>,
    /**
     * Redacted, unmodifiable wire envelope using the API's field names.
     *
     * Not a stable contract and excluded from [toJson]. It may contain filenames, messages,
     * future fields, or other customer data; do not log or persist it routinely.
     */
    public val raw: Map<String, Any?>,
) {
    /** `true` only for a recognized, scored result. */
    @get:JvmName("isScored")
    public val scored: Boolean get() = status == ResultStatus.SUCCESS

    /** `true` when the API rejected the media without an exception. */
    @get:JvmName("isRejected")
    public val rejected: Boolean get() = status == ResultStatus.REJECTED

    /** Stable normalized fields as a JSON-compatible map. Excludes [raw]. */
    public abstract fun toJson(): Map<String, Any?>

    internal fun baseJson(): LinkedHashMap<String, Any?> = linkedMapOf<String, Any?>().apply {
        put("status", status.wireValue)
        put("scored", scored)
        put("rejected", rejected)
        if (status == ResultStatus.UNKNOWN) put("originalStatus", originalStatus)
        put("uniqueTrxId", uniqueTrxId)
        put("filename", filename)
        put("contentType", contentType)
        put("statusCode", statusCode)
        put("billable", billable)
        put("aiThreatSignals", aiThreatSignals)
    }
}

/** Result of [NeuroVerifyClient.detectImage]. */
public class ImageResult internal constructor(
    status: ResultStatus,
    originalStatus: String,
    uniqueTrxId: String,
    filename: String,
    contentType: String,
    statusCode: Int,
    billable: Boolean,
    aiThreatSignals: List<String>,
    raw: Map<String, Any?>,
    /** Risk score from 0.1 through 10.0; higher means more observed risk. `null` when unscored. */
    public val riskScore: Double?,
    /** Recognized risk band, or `null` when unscored or unrecognized. */
    public val riskLevel: RiskLevel?,
    /** Exact wire `risk_level` value, preserved for unknown bands. */
    public val originalRiskLevel: String?,
    /** Service message. Suitable for user guidance; do not branch on its text. */
    public val message: String,
) : DetectionResult(
    status, originalStatus, uniqueTrxId, filename, contentType, statusCode, billable, aiThreatSignals, raw,
) {
    /** `true` when the recognized risk band is [RiskLevel.HIGH]. */
    @get:JvmName("isHighRisk")
    public val highRisk: Boolean get() = riskLevel == RiskLevel.HIGH

    override fun toJson(): Map<String, Any?> = baseJson().apply {
        if (status == ResultStatus.UNKNOWN) put("originalRiskLevel", originalRiskLevel)
        put("riskScore", riskScore)
        put("riskLevel", riskLevel?.wireValue)
        put("message", message)
        put("highRisk", highRisk)
    }

    override fun toString(): String = "ImageResult(${toJson()})"
}

/**
 * Result of [NeuroVerifyClient.detectVideo]. Video and audio are independent modalities and
 * can carry different risk bands.
 */
public class VideoResult internal constructor(
    status: ResultStatus,
    originalStatus: String,
    uniqueTrxId: String,
    filename: String,
    contentType: String,
    statusCode: Int,
    billable: Boolean,
    aiThreatSignals: List<String>,
    raw: Map<String, Any?>,
    public val videoRiskScore: Double?,
    public val videoRiskLevel: RiskLevel?,
    public val originalVideoRiskLevel: String?,
    public val videoMessage: String,
    /** `null` when the video has no audio track or was not scored. */
    public val audioRiskScore: Double?,
    public val audioRiskLevel: RiskLevel?,
    public val originalAudioRiskLevel: String?,
    /** For example `"No audio track detected"`; `null` on rejections. */
    public val audioMessage: String?,
) : DetectionResult(
    status, originalStatus, uniqueTrxId, filename, contentType, statusCode, billable, aiThreatSignals, raw,
) {
    /** `true` when an audio risk score was returned. */
    @get:JvmName("hasAudio")
    public val hasAudio: Boolean get() = audioRiskScore != null

    /**
     * SDK convenience: the maximum available modality score. The API does not return a
     * combined score, and this does not replace modality-aware policy.
     */
    public val overallRiskScore: Double?
        get() {
            val video = videoRiskScore ?: return audioRiskScore
            val audio = audioRiskScore ?: return video
            return maxOf(video, audio)
        }

    override fun toJson(): Map<String, Any?> = baseJson().apply {
        if (status == ResultStatus.UNKNOWN) {
            put("originalVideoRiskLevel", originalVideoRiskLevel)
            put("originalAudioRiskLevel", originalAudioRiskLevel)
        }
        put("hasAudio", hasAudio)
        put("videoRiskScore", videoRiskScore)
        put("videoRiskLevel", videoRiskLevel?.wireValue)
        put("videoMessage", videoMessage)
        put("audioRiskScore", audioRiskScore)
        put("audioRiskLevel", audioRiskLevel?.wireValue)
        put("audioMessage", audioMessage)
        put("overallRiskScore", overallRiskScore)
    }

    override fun toString(): String = "VideoResult(${toJson()})"
}
