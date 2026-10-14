package com.neuraldefend.example

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.neuraldefend.NeuroVerifyClient
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals

private const val LOW_RISK_IMAGE = """{"unified_face_authenticity_score": {"unique_trx_id": "trx_c1r7n6oy69zhunjrkp0p",
"filename": "ai-generated.png", "content_type": "image/png", "status": "success", "status_code": 1, "billable": "Y",
"risk_score": 2.2, "risk_level": "low", "message": "Not likely to be Spoof or AI-generated", "ai_threat_signals": []}}"""

private const val HIGH_RISK_VIDEO = """{"unified_video_authenticity_score": {"unique_trx_id": "trx_qro0hy17yeyridi0f4yu",
"filename": "fake-video.mp4", "content_type": "video/mp4", "status": "success", "status_code": 1, "billable": "Y",
"video_risk_score": 9.0, "video_risk_level": "high", "video_message": "Likely to be AI-generated",
"audio_risk_score": null, "audio_risk_level": null, "audio_message": "No audio track detected", "ai_threat_signals": []}}"""

@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class DetectScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    private val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
    private val server = MockWebServer()
    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as ExampleApplication
    private lateinit var original: ClientFactory

    @Before
    fun setUp() {
        server.useHttps(HandshakeCertificates.Builder().heldCertificate(certificate).build().sslSocketFactory())
        server.start()
        val trust = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val http = OkHttpClient.Builder().sslSocketFactory(trust.sslSocketFactory(), trust.trustManager).build()
        original = app.clientFactory
        app.clientFactory = ClientFactory { apiKey, _ ->
            NeuroVerifyClient.builder()
                .apiKey(apiKey)
                .baseUrl(server.url("/").toString())
                .allowCustomBaseUrl(true)
                .maxRetries(0)
                .okHttpClient(http)
                .build()
        }
    }

    @After
    fun tearDown() {
        app.clientFactory = original
        server.close()
    }

    private fun enqueue(code: Int, body: String) {
        server.enqueue(MockResponse.Builder().code(code).addHeader("content-type", "application/json").body(body).build())
    }

    /** Saves the screen when running under Robolectric, which sets the output directory. */
    private fun screenshot(name: String) {
        val directory = System.getProperty("neuraldefend.screenshots") ?: return
        compose.waitForIdle()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        File(directory).mkdirs()
        File(directory, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun submit(tag: String) {
        compose.onNodeWithTag("apiKey").performTextInput("demo-key")
        compose.onNodeWithTag(tag).performScrollTo().performClick()
    }

    @Test
    fun cancelsAnUpload() {
        server.enqueue(MockResponse.Builder().headersDelay(30, TimeUnit.SECONDS).body("{}").build())

        submit("sampleImage")

        compose.waitUntilAtLeastOneExists(hasText("Sample image: waiting for the analysis…"), timeoutMillis = 15_000)
        screenshot("uploading")
        compose.onNodeWithTag("cancel").performClick()
        compose.waitUntilAtLeastOneExists(hasTestTag("cancelled"), timeoutMillis = 15_000)
    }

    @Test
    fun analyzesTheSampleImage() {
        enqueue(200, LOW_RISK_IMAGE)

        submit("sampleImage")

        compose.waitUntilAtLeastOneExists(hasTestTag("result"), timeoutMillis = 15_000)
        compose.onNodeWithText("Image: low risk (2.2 / 10)").assertExists()
        screenshot("image-result")
        val request = server.takeRequest()
        assertEquals("/detect/image", request.url.encodedPath)
        assertEquals("demo-key", request.headers["x-api-key"])
    }

    @Test
    fun analyzesTheSampleVideo() {
        enqueue(200, HIGH_RISK_VIDEO)

        submit("sampleVideo")

        compose.waitUntilAtLeastOneExists(hasTestTag("result"), timeoutMillis = 30_000)
        compose.onNodeWithText("Video: high risk (9.0 / 10)").assertExists()
        compose.onNodeWithText("Audio: no audio track was scored").assertExists()
        screenshot("video-result")
        assertEquals("/detect/video", server.takeRequest().url.encodedPath)
    }

    @Test
    fun explainsARejectedKey() {
        enqueue(401, """{"detail":"Invalid API key"}""")

        submit("sampleImage")

        compose.waitUntilAtLeastOneExists(hasTestTag("error"), timeoutMillis = 15_000)
        compose.onNodeWithText("The API key was rejected (401): Invalid API key").assertExists()
        screenshot("invalid-key")
    }
}
