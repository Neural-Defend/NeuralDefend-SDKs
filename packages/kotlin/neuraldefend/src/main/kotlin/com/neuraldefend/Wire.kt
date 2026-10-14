package com.neuraldefend

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.Collections

internal const val REDACTED = "[REDACTED]"

/** Replaces every occurrence of [secret] in [value]. */
internal fun redact(value: String, secret: String): String =
    if (secret.isEmpty()) value else value.replace(secret, REDACTED)

/** Parses UTF-8 JSON text into an object tree, or returns `null` when it is not a JSON object. */
internal fun decodeObject(text: String): Map<String, Any?>? {
    val element = try {
        Json.parseToJsonElement(text)
    } catch (_: SerializationException) {
        return null
    } catch (_: IllegalArgumentException) {
        return null
    }
    @Suppress("UNCHECKED_CAST")
    return toValue(element, secret = "") as? Map<String, Any?>
}

private fun toValue(element: JsonElement, secret: String): Any? = when (element) {
    is JsonNull -> null
    is JsonObject -> Collections.unmodifiableMap(
        LinkedHashMap<String, Any?>(element.size).apply {
            for ((key, value) in element) put(key, toValue(value, secret))
        },
    )
    is JsonArray -> Collections.unmodifiableList(element.map { toValue(it, secret) })
    is JsonPrimitive -> when {
        element.isString -> redact(element.content, secret)
        element.content == "true" -> true
        element.content == "false" -> false
        else -> parseNumber(element.content)
    }
}

private fun parseNumber(content: String): Any {
    if (content.none { it == '.' || it == 'e' || it == 'E' }) {
        content.toLongOrNull()?.let { return it }
    }
    return content.toDouble()
}

/** Deep, redacted, unmodifiable copy of a decoded JSON value. */
internal fun freeze(value: Any?, secret: String): Any? = when (value) {
    is String -> redact(value, secret)
    is Map<*, *> -> Collections.unmodifiableMap(
        LinkedHashMap<String, Any?>(value.size).apply {
            for ((key, nested) in value) put(key.toString(), freeze(nested, secret))
        },
    )
    is List<*> -> Collections.unmodifiableList(value.map { freeze(it, secret) })
    else -> value
}

@Suppress("UNCHECKED_CAST")
internal fun freezeEnvelope(value: Map<String, Any?>, secret: String): Map<String, Any?> =
    freeze(value, secret) as Map<String, Any?>

private class Context(val httpStatus: Int, val requestId: String?) {
    fun invalid(field: String, expectation: String = "was missing or invalid"): ProtocolError =
        ProtocolError("The response field \"$field\" $expectation.", httpStatus, requestId)
}

private fun Map<String, Any?>.requiredString(field: String, context: Context): String =
    this[field] as? String ?: throw context.invalid(field)

private fun Map<String, Any?>.requiredInt(field: String, context: Context): Int {
    when (val candidate = this[field]) {
        is Long -> if (candidate in Int.MIN_VALUE..Int.MAX_VALUE) return candidate.toInt()
        is Double -> if (candidate.isFinite() && candidate == Math.floor(candidate) &&
            candidate >= Int.MIN_VALUE && candidate <= Int.MAX_VALUE
        ) {
            return candidate.toInt()
        }
    }
    throw context.invalid(field, "must be an integer")
}

private fun Map<String, Any?>.nullableScore(field: String, context: Context): Double? {
    if (!containsKey(field)) throw context.invalid(field, "was missing")
    val candidate = this[field] ?: return null
    val score = (candidate as? Number)?.toDouble()
    if (score == null || !score.isFinite() || score < 0.1 || score > 10.0) {
        throw context.invalid(field, "must be from 0.1 through 10.0 or null")
    }
    return score
}

private fun Map<String, Any?>.nullableString(field: String, context: Context): String? {
    if (!containsKey(field)) throw context.invalid(field, "was missing")
    val candidate = this[field] ?: return null
    return candidate as? String ?: throw context.invalid(field, "must be a string or null")
}

private fun Map<String, Any?>.billable(context: Context): Boolean = when (this["billable"]) {
    "Y" -> true
    "N" -> false
    else -> throw context.invalid("billable", "must be exactly \"Y\" or \"N\"")
}

private fun Map<String, Any?>.signals(context: Context): List<String> {
    val candidate = this["ai_threat_signals"] ?: return emptyList()
    if (candidate !is List<*> || candidate.any { it !is String }) {
        throw context.invalid("ai_threat_signals", "must be an array of strings")
    }
    return Collections.unmodifiableList(candidate.map { it as String })
}

private fun normalizedStatus(wire: String): ResultStatus = when (wire) {
    "success" -> ResultStatus.SUCCESS
    "rejected" -> ResultStatus.REJECTED
    else -> ResultStatus.UNKNOWN
}

private fun envelopeError(
    message: String,
    envelope: Map<String, Any?>,
    secret: String,
    context: Context,
): ServerError = ServerError(
    redact(message, secret),
    context.httpStatus,
    context.requestId,
    freezeEnvelope(envelope, secret),
)

/** Parses an image envelope. Throws [ServerError] for `status: "error"` and [ProtocolError] for contract violations. */
internal fun parseImage(envelope: Map<String, Any?>, httpStatus: Int, requestId: String?, secret: String): ImageResult {
    val context = Context(httpStatus, requestId)
    val originalStatus = envelope.requiredString("status", context)
    val uniqueTrxId = envelope.requiredString("unique_trx_id", context)
    val filename = envelope.requiredString("filename", context)
    val contentType = envelope.requiredString("content_type", context)
    val statusCode = envelope.requiredInt("status_code", context)
    val billable = envelope.billable(context)
    val signals = envelope.signals(context)
    val message = envelope.requiredString("message", context)
    val score = envelope.nullableScore("risk_score", context)
    val originalLevel = envelope.nullableString("risk_level", context)
    val level = RiskLevel.fromWire(originalLevel)

    if (originalStatus == "error") throw envelopeError(message, envelope, secret, context)
    var status = normalizedStatus(originalStatus)
    if (status == ResultStatus.SUCCESS && (score == null || level == null)) status = ResultStatus.UNKNOWN
    return ImageResult(
        status = status,
        originalStatus = originalStatus,
        uniqueTrxId = uniqueTrxId,
        filename = filename,
        contentType = contentType,
        statusCode = statusCode,
        billable = billable,
        aiThreatSignals = signals,
        raw = freezeEnvelope(envelope, secret),
        riskScore = score,
        riskLevel = level,
        originalRiskLevel = originalLevel,
        message = message,
    )
}

/** Parses a video envelope. Throws [ServerError] for `status: "error"` and [ProtocolError] for contract violations. */
internal fun parseVideo(envelope: Map<String, Any?>, httpStatus: Int, requestId: String?, secret: String): VideoResult {
    val context = Context(httpStatus, requestId)
    val originalStatus = envelope.requiredString("status", context)
    val uniqueTrxId = envelope.requiredString("unique_trx_id", context)
    val filename = envelope.requiredString("filename", context)
    val contentType = envelope.requiredString("content_type", context)
    val statusCode = envelope.requiredInt("status_code", context)
    val billable = envelope.billable(context)
    val signals = envelope.signals(context)
    val videoMessage = envelope.requiredString("video_message", context)
    val audioMessage = envelope.nullableString("audio_message", context)
    val videoScore = envelope.nullableScore("video_risk_score", context)
    val originalVideoLevel = envelope.nullableString("video_risk_level", context)
    val videoLevel = RiskLevel.fromWire(originalVideoLevel)
    val audioScore = envelope.nullableScore("audio_risk_score", context)
    val originalAudioLevel = envelope.nullableString("audio_risk_level", context)
    val audioLevel = RiskLevel.fromWire(originalAudioLevel)

    if (originalStatus == "error") throw envelopeError(videoMessage, envelope, secret, context)
    var status = normalizedStatus(originalStatus)
    if (status == ResultStatus.SUCCESS) {
        val videoScored = videoScore != null && videoLevel != null
        val audioConsistent = (audioScore == null && originalAudioLevel == null) ||
            (audioScore != null && audioLevel != null)
        if (!videoScored || !audioConsistent) status = ResultStatus.UNKNOWN
    }
    return VideoResult(
        status = status,
        originalStatus = originalStatus,
        uniqueTrxId = uniqueTrxId,
        filename = filename,
        contentType = contentType,
        statusCode = statusCode,
        billable = billable,
        aiThreatSignals = signals,
        raw = freezeEnvelope(envelope, secret),
        videoRiskScore = videoScore,
        videoRiskLevel = videoLevel,
        originalVideoRiskLevel = originalVideoLevel,
        videoMessage = videoMessage,
        audioRiskScore = audioScore,
        audioRiskLevel = audioLevel,
        originalAudioRiskLevel = originalAudioLevel,
        audioMessage = audioMessage,
    )
}
