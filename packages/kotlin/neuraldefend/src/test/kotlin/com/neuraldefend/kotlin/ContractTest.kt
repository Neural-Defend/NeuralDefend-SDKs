package com.neuraldefend.kotlin

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull

/** Runs every shared fixture in tests/fixtures through the public client over a real socket. */
class ContractTest {
    private fun detect(fixture: String): Any = fixtureServer(fixture).use { server ->
        val client = testClient(server)
        try {
            runBlocking {
                if (fixture.startsWith("image/")) {
                    client.detectImage(MediaInput.bytes("image".toByteArray(), "sample.jpg"))
                } else {
                    client.detectVideo(MediaInput.bytes("video".toByteArray(), "sample.mp4"))
                }
            }
        } catch (error: NeuroVerifyError) {
            error
        } finally {
            client.close()
        }
    }

    private fun expectedStatus(wire: Any?): ResultStatus = when (wire) {
        "success" -> ResultStatus.SUCCESS
        "rejected" -> ResultStatus.REJECTED
        else -> ResultStatus.UNKNOWN
    }

    private fun Any?.asDouble(): Double? = (this as Number?)?.toDouble()

    @Test
    fun `the shared corpus contains the documented 43 fixtures`() {
        assertEquals(43, allFixturePaths().size)
    }

    @Test
    fun `every fixture is covered by exactly one contract group`() {
        val covered = IMAGE_RESULTS + VIDEO_RESULTS + SERVER_ERRORS + UNKNOWN_VALUES + MALFORMED + listOf(
            "image/robustness/unknown-extra-field.json",
            "video/robustness/unknown-extra-field.json",
            "image/synthetic/unauthorized-401.json",
            "video/synthetic/unauthorized-401.json",
            "image/synthetic/forbidden-403.json",
            "video/synthetic/forbidden-403.json",
            "image/synthetic/rate-limited-429.json",
            "video/synthetic/rate-limited-429.json",
        )
        assertEquals(covered.size, covered.toSet().size)
        assertEquals(allFixturePaths().toSet(), covered.toSet())
    }

    @TestFactory
    fun `documented image results`(): List<DynamicTest> = IMAGE_RESULTS.map { fixture ->
        DynamicTest.dynamicTest(fixture) {
            val wire = wireEnvelope(loadCase(fixture))
            val result = assertIs<ImageResult>(detect(fixture))
            assertEquals(expectedStatus(wire["status"]), result.status)
            assertEquals(wire["status"], result.originalStatus)
            assertEquals(wire["unique_trx_id"], result.uniqueTrxId)
            assertEquals(wire["filename"], result.filename)
            assertEquals(wire["content_type"], result.contentType)
            assertEquals((wire["status_code"] as Number).toInt(), result.statusCode)
            assertEquals(wire["billable"] == "Y", result.billable)
            assertEquals(wire["risk_score"].asDouble(), result.riskScore)
            assertEquals(wire["risk_level"], result.riskLevel?.wireValue)
            assertEquals(wire["message"], result.message)
            assertEquals(wire["ai_threat_signals"] ?: emptyList<String>(), result.aiThreatSignals)
            assertEquals(wire["status"] == "success", result.scored)
            assertEquals(wire["status"] == "rejected", result.rejected)
            assertEquals(wire["risk_level"] == "high", result.highRisk)
            assertEquals(wire, result.raw)
        }
    }

    @TestFactory
    fun `documented video results`(): List<DynamicTest> = VIDEO_RESULTS.map { fixture ->
        DynamicTest.dynamicTest(fixture) {
            val wire = wireEnvelope(loadCase(fixture))
            val result = assertIs<VideoResult>(detect(fixture))
            assertEquals(expectedStatus(wire["status"]), result.status)
            assertEquals((wire["status_code"] as Number).toInt(), result.statusCode)
            assertEquals(wire["billable"] == "Y", result.billable)
            assertEquals(wire["video_risk_score"].asDouble(), result.videoRiskScore)
            assertEquals(wire["video_risk_level"], result.videoRiskLevel?.wireValue)
            assertEquals(wire["video_message"], result.videoMessage)
            assertEquals(wire["audio_risk_score"].asDouble(), result.audioRiskScore)
            assertEquals(wire["audio_risk_level"], result.audioRiskLevel?.wireValue)
            assertEquals(wire["audio_message"], result.audioMessage)
            assertEquals(wire["audio_risk_score"] != null, result.hasAudio)
            val scores = listOfNotNull(wire["video_risk_score"].asDouble(), wire["audio_risk_score"].asDouble())
            assertEquals(scores.maxOrNull(), result.overallRiskScore)
            assertEquals(wire, result.raw)
        }
    }

    @TestFactory
    fun `server error envelopes throw ServerError`(): List<DynamicTest> = SERVER_ERRORS.map { fixture ->
        DynamicTest.dynamicTest(fixture) {
            val case = loadCase(fixture)
            val error = assertIs<ServerError>(detect(fixture))
            assertEquals(case["http_status"]!!.jsonPrimitive.int, error.statusCode)
            assertEquals(wireEnvelope(case), error.raw)
            assertEquals(wireEnvelope(case)["unique_trx_id"], error.requestId)
        }
    }

    @TestFactory
    fun `authentication and scope errors`(): List<DynamicTest> = listOf("image", "video").flatMap { kind ->
        listOf(
            DynamicTest.dynamicTest("$kind 401") {
                val fixture = "$kind/synthetic/unauthorized-401.json"
                val detail = loadCase(fixture)["body"]!!.jsonObject["detail"]!!.jsonPrimitive.content
                val error = assertIs<AuthenticationError>(detect(fixture))
                assertEquals(detail, error.detail)
                assertEquals(401, error.statusCode)
            },
            DynamicTest.dynamicTest("$kind 403") {
                val fixture = "$kind/synthetic/forbidden-403.json"
                val detail = loadCase(fixture)["body"]!!.jsonObject["detail"]!!.jsonPrimitive.content
                val error = assertIs<ScopeError>(detect(fixture))
                assertEquals(detail, error.detail)
                assertEquals(403, error.statusCode)
            },
        )
    }

    @TestFactory
    fun `rate-limit errors expose every documented header`(): List<DynamicTest> = listOf("image", "video").map { kind ->
        DynamicTest.dynamicTest(kind) {
            val error = assertIs<RateLimitError>(detect("$kind/synthetic/rate-limited-429.json"))
            assertEquals(429, error.statusCode)
            assertEquals("Rate limit exceeded", error.detail)
            assertEquals(60_000L, error.retryAfterMillis)
            assertEquals("1000", error.limit)
            assertEquals("0", error.remaining)
            assertEquals("2026-07-27T00:00:00Z", error.reset)
        }
    }

    @TestFactory
    fun `malformed responses throw ProtocolError`(): List<DynamicTest> = MALFORMED.map { fixture ->
        DynamicTest.dynamicTest(fixture) {
            val error = assertIs<ProtocolError>(detect(fixture))
            assertEquals(loadCase(fixture)["http_status"]!!.jsonPrimitive.int, error.statusCode)
        }
    }

    @TestFactory
    fun `unknown wire values are preserved without breaking`(): List<DynamicTest> = UNKNOWN_VALUES.map { fixture ->
        DynamicTest.dynamicTest(fixture) {
            val wire = wireEnvelope(loadCase(fixture))
            when (val result = detect(fixture)) {
                is ImageResult -> {
                    assertEquals(wire["status"], result.originalStatus)
                    assertEquals((wire["status_code"] as Number).toInt(), result.statusCode)
                    assertEquals(wire["risk_level"], result.originalRiskLevel)
                    val known = wire["status"] == "success" && wire["risk_level"] != "critical"
                    assertEquals(if (known) ResultStatus.SUCCESS else ResultStatus.UNKNOWN, result.status)
                    assertEquals(known, result.scored)
                    if (!known) assertEquals(wire["status"], result.toJson()["originalStatus"])
                }
                is VideoResult -> {
                    assertEquals(wire["status"], result.originalStatus)
                    assertEquals((wire["status_code"] as Number).toInt(), result.statusCode)
                    assertEquals(wire["video_risk_level"], result.originalVideoRiskLevel)
                    val known = wire["status"] == "success" &&
                        RiskLevel.fromWire(wire["video_risk_level"] as String?) != null
                    assertEquals(if (known) ResultStatus.SUCCESS else ResultStatus.UNKNOWN, result.status)
                    assertEquals(known, result.scored)
                }
                else -> throw AssertionError("expected a result, got $result")
            }
        }
    }

    @TestFactory
    fun `unknown extra fields stay in raw and out of toJson`(): List<DynamicTest> = listOf("image", "video").map { kind ->
        DynamicTest.dynamicTest(kind) {
            val result = assertIs<DetectionResult>(detect("$kind/robustness/unknown-extra-field.json"))
            @Suppress("UNCHECKED_CAST")
            val future = result.raw["future_signal"] as Map<String, Any?>
            assertEquals(0.42, future["confidence"])
            kotlin.test.assertFailsWith<UnsupportedOperationException> {
                @Suppress("UNCHECKED_CAST")
                (result.raw as MutableMap<String, Any?>)["x"] = 1
            }
            val json = result.toJson()
            assertFalse(json.containsKey("raw"))
            assertFalse(json.containsKey("future_signal"))
        }
    }

    @Test
    fun `normalized image JSON matches the documented shape`() {
        val result = assertIs<ImageResult>(detect("image/documented/low-risk.json"))
        assertEquals(
            mapOf(
                "status" to "success",
                "scored" to true,
                "rejected" to false,
                "uniqueTrxId" to result.uniqueTrxId,
                "filename" to "selfie.jpg",
                "contentType" to "image/jpeg",
                "statusCode" to 1,
                "billable" to true,
                "aiThreatSignals" to result.aiThreatSignals,
                "riskScore" to result.riskScore,
                "riskLevel" to "low",
                "message" to result.message,
                "highRisk" to false,
            ),
            result.toJson(),
        )
        assertEquals(result.toJson().keys.toList().first(), "status")
    }

    @Test
    fun `normalized video JSON keeps modalities independent`() {
        val result = assertIs<VideoResult>(detect("video/documented/silent-no-audio.json"))
        val json = result.toJson()
        assertEquals(false, json["hasAudio"])
        assertNull(json["audioRiskScore"])
        assertNull(json["audioRiskLevel"])
        assertEquals(result.videoRiskScore, json["overallRiskScore"])
    }

    private companion object {
        val IMAGE_RESULTS = listOf(
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
        )
        val VIDEO_RESULTS = listOf(
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
        )
        val SERVER_ERRORS = listOf(
            "image/documented/internal-error-500.json",
            "image/documented/service-unavailable-503.json",
            "video/documented/internal-error-500.json",
            "video/documented/service-unavailable-503.json",
        )
        val UNKNOWN_VALUES = listOf(
            "image/robustness/unknown-status-code.json",
            "image/robustness/unknown-status.json",
            "image/robustness/unknown-risk-level.json",
            "video/robustness/unknown-status-code.json",
            "video/robustness/unknown-status.json",
            "video/robustness/unknown-risk-level.json",
        )
        val MALFORMED = listOf(
            "image/robustness/missing-envelope.json",
            "image/robustness/malformed-json.json",
            "video/robustness/missing-envelope.json",
            "video/robustness/malformed-json.json",
        )
    }
}
