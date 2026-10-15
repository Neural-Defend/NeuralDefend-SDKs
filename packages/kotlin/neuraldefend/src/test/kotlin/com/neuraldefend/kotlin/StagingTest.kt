package com.neuraldefend.kotlin

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Live smoke tests against staging. Run with `./gradlew :neuraldefend:stagingTest`; the
 * scored tests are skipped when `NEURALDEFEND_STAGING_API_KEY` is not configured.
 */
@Tag("staging")
class StagingTest {
    private val apiKey: String? = System.getenv("NEURALDEFEND_STAGING_API_KEY")?.takeIf { it.isNotBlank() }

    private fun fixture(variable: String): File {
        val path = System.getenv(variable) ?: System.getenv("${variable}_DEFAULT")
        val file = File(checkNotNull(path) { "$variable is not set" })
        check(file.isFile) { "$variable does not identify a staging fixture: $path" }
        return file
    }

    private fun assertConsistent(result: DetectionResult) {
        assertTrue(result.originalStatus == "success" || result.originalStatus == "rejected", result.originalStatus)
        assertTrue(result.uniqueTrxId.isNotEmpty())
        assertEquals(result.originalStatus == "success", result.scored)
        assertEquals(result.originalStatus == "rejected", result.rejected)
    }

    @Test
    fun `an invalid key is rejected with AuthenticationError`() {
        val client = NeuroVerifyClient.staging("nv-invalid-key-for-sdk-smoke-test") { maxRetries(0) }
        client.use {
            val error = assertFailsWith<AuthenticationError> {
                runBlocking { it.detectImage(MediaInput.file(fixture("NEURALDEFEND_STAGING_IMAGE"))) }
            }
            assertEquals(401, error.statusCode)
            assertContains(error.detail, "Invalid API key")
            println("staging invalid-key check: $error")
        }
    }

    @Test
    fun `staging image contract`() {
        assumeTrue(apiKey != null, "NEURALDEFEND_STAGING_API_KEY is not configured")
        NeuroVerifyClient.staging(apiKey) { maxRetries(0) }.use { client ->
            val result = runBlocking { client.detectImage(MediaInput.file(fixture("NEURALDEFEND_STAGING_IMAGE"))) }
            assertConsistent(result)
            if (result.scored) {
                assertTrue(result.riskScore!! in 0.1..10.0)
                assertNotNull(result.riskLevel)
            }
        }
    }

    @Test
    fun `staging video contract`() {
        assumeTrue(apiKey != null, "NEURALDEFEND_STAGING_API_KEY is not configured")
        NeuroVerifyClient.staging(apiKey) { maxRetries(0) }.use { client ->
            val result = runBlocking {
                client.detectVideo(MediaInput.file(fixture("NEURALDEFEND_STAGING_VIDEO")), maxFrames = 2)
            }
            assertConsistent(result)
            if (result.scored) {
                assertTrue(result.videoRiskScore!! in 0.1..10.0)
                assertNotNull(result.videoRiskLevel)
            }
        }
    }
}
