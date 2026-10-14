package com.neuraldefend.example

import com.neuraldefend.MediaInput
import com.neuraldefend.NeuroVerifyClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class DetectViewModelTest {
    private val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
    private val server = MockWebServer()
    private lateinit var main: ExecutorCoroutineDispatcher
    private lateinit var http: OkHttpClient
    private lateinit var viewModel: DetectViewModel

    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()) + ByteArray(2048)

    @Before
    fun setUp() {
        main = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        Dispatchers.setMain(main)
        server.useHttps(HandshakeCertificates.Builder().heldCertificate(certificate).build().sslSocketFactory())
        server.start()
        val trust = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        http = OkHttpClient.Builder().sslSocketFactory(trust.sslSocketFactory(), trust.trustManager).build()
        val factory = ClientFactory { apiKey, _ ->
            NeuroVerifyClient.builder()
                .apiKey(apiKey)
                .baseUrl(server.url("/").toString())
                .allowCustomBaseUrl(true)
                .maxRetries(0)
                .okHttpClient(http)
                .build()
        }
        viewModel = DetectViewModel({ factory })
        viewModel.onApiKeyChange("  demo-key  ")
    }

    @After
    fun tearDown() {
        server.close()
        Dispatchers.resetMain()
        main.close()
    }

    private fun enqueueFixture(path: String) {
        val case = Json.parseToJsonElement(File(System.getProperty("neuraldefend.fixtures"), path).readText()).jsonObject
        val headers = case["headers"]?.jsonObject.orEmpty()
        server.enqueue(
            MockResponse.Builder()
                .code(case.getValue("http_status").jsonPrimitive.int)
                .apply { headers.forEach { (name, value) -> addHeader(name, value.jsonPrimitive.content) } }
                .body(bodyOf(case))
                .build(),
        )
    }

    private fun bodyOf(case: JsonObject): String {
        val body = case.getValue("body")
        return if (case["body_kind"]?.jsonPrimitive?.content == "json") body.toString() else body.jsonPrimitive.content
    }

    private fun analyze(kind: MediaKind = MediaKind.IMAGE, name: String = "selfie.jpg"): Phase {
        viewModel.analyze(kind, "Test") { MediaInput.bytes(jpeg, name) }
        return awaitFinished()
    }

    private fun awaitFinished(): Phase = runBlocking {
        withTimeout(10_000) { viewModel.state.first { !it.busy } }.phase
    }

    @Test
    fun showsAScoredImage() {
        enqueueFixture("image/documented/low-risk.json")

        val phase = assertIs<Phase.Done>(analyze())

        assertEquals("Image: low risk (2.2 / 10)", phase.summary.headline)
        assertTrue("Not likely to be Spoof or AI-generated" in phase.summary.details)
        val request = server.takeRequest()
        assertEquals("/detect/image", request.url.encodedPath)
        assertEquals("demo-key", request.headers["x-api-key"])
    }

    @Test
    fun keepsVideoAndAudioVerdictsSeparate() {
        enqueueFixture("video/documented/video-low-audio-high.json")

        val phase = assertIs<Phase.Done>(analyze(MediaKind.VIDEO, "clip.mp4"))

        assertEquals("Video: low risk (2.2 / 10)", phase.summary.headline)
        assertTrue("Audio: high risk (8.4 / 10)" in phase.summary.details)
    }

    @Test
    fun explainsAMissingAudioTrack() {
        enqueueFixture("video/documented/medium-no-audio.json")

        val phase = assertIs<Phase.Done>(analyze(MediaKind.VIDEO, "clip.mp4"))

        assertTrue("Audio: no audio track was scored" in phase.summary.details)
    }

    @Test
    fun rejectionsAreResultsNotErrors() {
        enqueueFixture("image/documented/no-face.json")

        val phase = assertIs<Phase.Done>(analyze())

        assertEquals("Not analyzed", phase.summary.headline)
    }

    @Test
    fun unknownStatusesDoNotCrash() {
        enqueueFixture("image/robustness/unknown-status.json")

        val phase = assertIs<Phase.Done>(analyze())

        assertEquals("Unrecognized status", phase.summary.headline)
    }

    @Test
    fun explainsARejectedKey() {
        enqueueFixture("image/synthetic/unauthorized-401.json")

        val phase = assertIs<Phase.Failed>(analyze())

        assertTrue(phase.message.startsWith("The API key was rejected (401)"), phase.message)
    }

    @Test
    fun explainsRateLimits() {
        enqueueFixture("image/synthetic/rate-limited-429.json")

        val phase = assertIs<Phase.Failed>(analyze())

        assertEquals("Too many requests. Try again in 60 s.", phase.message)
    }

    @Test
    fun aMissingKeyNeverReachesTheNetwork() {
        viewModel.onApiKeyChange(" ")

        val phase = assertIs<Phase.Failed>(analyze())

        assertEquals("Enter an API key first.", phase.message)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun emptyFilesAreRejectedLocally() {
        viewModel.analyze(MediaKind.IMAGE, "Test") { MediaInput.bytes(ByteArray(0), "selfie.jpg") }

        val phase = assertIs<Phase.Failed>(awaitFinished())

        assertTrue(phase.message.startsWith("This file can't be sent"), phase.message)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun cancelStopsTheRequest() {
        server.enqueue(MockResponse.Builder().headersDelay(30, TimeUnit.SECONDS).body("{}").build())
        viewModel.analyze(MediaKind.IMAGE, "Test") { MediaInput.bytes(jpeg, "selfie.jpg") }
        runBlocking {
            withTimeout(10_000) {
                viewModel.state.first { (it.phase as? Phase.Uploading)?.let { p -> p.totalBytes > 0 && p.sentBytes == p.totalBytes } == true }
            }
        }

        viewModel.cancel()

        assertEquals(Phase.Cancelled, awaitFinished())
    }
}
