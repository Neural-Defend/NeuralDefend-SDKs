package com.neuraldefend

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ClientTest {
    private fun <T> withServer(server: TestServer, block: suspend (TestServer) -> T): T =
        server.use { runBlocking { block(it) } }

    private inline fun <reified E : Throwable> failsWith(noinline block: suspend () -> Unit): E =
        assertFailsWith<E> { runBlocking { block() } }

    @Nested
    inner class Retries {
        @Test
        fun `HTTP 500 retries three times with 1, 2, 4 second backoff`() {
            val fake = FakeRuntime()
            val opens = AtomicInteger()
            val server = fixtureServer(
                "image/documented/internal-error-500.json",
                "image/documented/internal-error-500.json",
                "image/documented/internal-error-500.json",
                "image/documented/low-risk.json",
            )
            withServer(server) {
                val client = testClient(it, maxRetries = 3, runtime = fake.runtime)
                val result = client.detectImage(
                    MediaInput.stream(16, "retry.jpg") {
                        opens.incrementAndGet()
                        ByteArrayInputStream("streamed-payload".toByteArray())
                    },
                )
                assertTrue(result.scored)
            }
            assertEquals(4, server.requests.size)
            assertEquals(4, opens.get())
            server.requests.forEach { assertContains(it.bodyText, "streamed-payload") }
            assertEquals(listOf(1000L, 2000L, 4000L), fake.sleeps)
        }

        @Test
        fun `server backoff adds at most 25 percent jitter`() {
            val fake = FakeRuntime(jitter = 1.0)
            val server = fixtureServer(
                "video/documented/service-unavailable-503.json",
                "video/documented/service-unavailable-503.json",
                "video/documented/both-low.json",
            )
            withServer(server) { testClient(it, maxRetries = 3, runtime = fake.runtime).detectVideo(mp4()) }
            assertEquals(listOf(1250L, 2500L), fake.sleeps)
        }

        @Test
        fun `exhausted HTTP 503 retries throw ServerError after four attempts`() {
            val fake = FakeRuntime()
            val server = fixtureServer("image/documented/service-unavailable-503.json")
            server.use {
                failsWith<ServerError> { testClient(it, maxRetries = 3, runtime = fake.runtime).detectImage(jpeg()) }
            }
            assertEquals(4, server.requests.size)
            assertEquals(3, fake.sleeps.size)
        }

        @Test
        fun `HTTP 429 honors numeric Retry-After, then succeeds`() {
            val fake = FakeRuntime()
            val server = fixtureServer("image/synthetic/rate-limited-429.json", "image/documented/low-risk.json")
            val result = withServer(server) { testClient(it, maxRetries = 1, runtime = fake.runtime).detectImage(jpeg()) }
            assertTrue(result.scored)
            assertEquals(2, server.requests.size)
            assertEquals(listOf(60_000L), fake.sleeps)
        }

        @Test
        fun `Retry-After is capped by retryAfterCap`() {
            val fake = FakeRuntime()
            val server = fixtureServer("image/synthetic/rate-limited-429.json", "image/documented/low-risk.json")
            withServer(server) {
                testClient(it, maxRetries = 1, retryAfterCapMillis = 5_000, runtime = fake.runtime).detectImage(jpeg())
            }
            assertEquals(listOf(5_000L), fake.sleeps)
        }

        @Test
        fun `Retry-After HTTP dates are relative to the clock`() {
            val fake = FakeRuntime(now = utc(2026, 7, 26, 23, 59, 30))
            val limited = loadCase("image/synthetic/rate-limited-429.json")
            val server = TestServer { call, _ ->
                if (call == 1) {
                    TestResponse.fromCase(limited, mapOf("retry-after" to "Sun, 26 Jul 2026 23:59:45 GMT"))
                } else {
                    TestResponse.fixture("image/documented/low-risk.json")
                }
            }
            withServer(server) { testClient(it, maxRetries = 1, runtime = fake.runtime).detectImage(jpeg()) }
            assertEquals(2, server.requests.size)
            assertEquals(listOf(15_000L), fake.sleeps)
        }

        @Test
        fun `invalid Retry-After values fall back to exponential delays`() {
            val fake = FakeRuntime()
            val limited = loadCase("image/synthetic/rate-limited-429.json")
            val values = listOf("soon", "0x10", "Infinity")
            val server = TestServer { call, _ ->
                if (call <= values.size) {
                    TestResponse.fromCase(limited, mapOf("retry-after" to values[call - 1]))
                } else {
                    TestResponse.fixture("image/documented/low-risk.json")
                }
            }
            withServer(server) { testClient(it, maxRetries = 3, runtime = fake.runtime).detectImage(jpeg()) }
            assertEquals(listOf(1000L, 2000L, 4000L), fake.sleeps)
        }

        @Test
        fun `HTTP 429 without Retry-After uses exponential delays`() {
            val fake = FakeRuntime()
            val limited = loadCase("image/synthetic/rate-limited-429.json")
            val server = TestServer { call, _ ->
                if (call < 3) TestResponse.fromCase(limited, emptyMap()) else TestResponse.fixture("image/documented/low-risk.json")
            }
            withServer(server) { testClient(it, maxRetries = 3, runtime = fake.runtime).detectImage(jpeg()) }
            assertEquals(listOf(1000L, 2000L), fake.sleeps)
        }

        @Test
        fun `exhausted HTTP 429 throws RateLimitError`() {
            val server = fixtureServer("video/synthetic/rate-limited-429.json")
            server.use {
                failsWith<RateLimitError> {
                    testClient(it, maxRetries = 2, runtime = FakeRuntime().runtime).detectVideo(mp4())
                }
            }
            assertEquals(3, server.requests.size)
        }

        @ParameterizedTest
        @ValueSource(
            strings = [
                "image/documented/blurry.json",
                "image/synthetic/unauthorized-401.json",
                "image/synthetic/forbidden-403.json",
                "image/documented/low-risk.json",
                "image/documented/no-face.json",
            ],
        )
        fun `never retries non-retryable responses`(fixture: String) {
            val fake = FakeRuntime()
            val server = fixtureServer(fixture)
            withServer(server) {
                try {
                    testClient(it, maxRetries = 3, runtime = fake.runtime).detectImage(jpeg())
                } catch (_: NeuroVerifyError) {
                    // Expected for 401 and 403.
                }
            }
            assertEquals(1, server.requests.size)
            assertTrue(fake.sleeps.isEmpty())
        }

        @Test
        fun `maxRetries 0 disables retries`() {
            val server = fixtureServer("image/documented/internal-error-500.json")
            server.use { failsWith<ServerError> { testClient(it, maxRetries = 0).detectImage(jpeg()) } }
            assertEquals(1, server.requests.size)
        }
    }

    @Nested
    inner class RequestShape {
        @Test
        fun `sends the API key, user agent, and a multipart file part`() {
            val server = fixtureServer("image/documented/low-risk.json")
            withServer(server) { testClient(it).detectImage(MediaInput.bytes("image-bytes".toByteArray(), "Photo.JPG")) }
            val request = server.requests.single()
            assertEquals("POST", request.method)
            assertEquals("/detect/image", request.target)
            assertEquals(TEST_API_KEY, request.header("x-api-key"))
            assertEquals("neuraldefend-kotlin/${NeuroVerifyClient.SDK_VERSION}", request.header("user-agent"))
            assertEquals("application/json", request.header("accept"))
            assertTrue(request.header("content-type")!!.startsWith("multipart/form-data; boundary="))
            assertContains(request.bodyText, "name=\"file\"; filename=\"Photo.JPG\"")
            assertContains(request.bodyText, "Content-Type: image/jpeg")
            assertContains(request.bodyText, "image-bytes")
        }

        @Test
        fun `SDK version matches the Gradle project version`() {
            assertEquals(System.getProperty("neuraldefend.version"), NeuroVerifyClient.SDK_VERSION)
        }

        @Test
        fun `tests run on the requested JDK`() {
            val expected = System.getProperty("neuraldefend.expectedJavaVersion") ?: return
            val actual = System.getProperty("java.specification.version").removePrefix("1.")
            assertEquals(expected, actual)
        }

        @Test
        fun `custom user agent is sent`() {
            val server = fixtureServer("image/documented/low-risk.json")
            withServer(server) { testClient(it, userAgent = "kyc-app/2.4.0").detectImage(jpeg()) }
            assertEquals("kyc-app/2.4.0", server.requests.single().header("user-agent"))
        }

        @Test
        fun `video options are sent as query parameters`() {
            val server = fixtureServer("video/documented/both-low.json")
            withServer(server) { testClient(it).detectVideo(mp4(), maxFrames = 24, sampleRate = 2) }
            assertEquals("/detect/video?max_frames=24&sample_rate=2", server.requests.single().target)
        }

        @Test
        fun `video query is omitted when options are not set`() {
            val server = fixtureServer("video/documented/both-low.json")
            withServer(server) { testClient(it).detectVideo(mp4()) }
            assertEquals("/detect/video", server.requests.single().target)
        }

        @Test
        fun `rejects out-of-range video options locally`() {
            val server = fixtureServer("video/documented/both-low.json")
            server.use {
                val client = testClient(it)
                for ((maxFrames, sampleRate, code) in listOf(
                    Triple(0, null, ValidationErrorCode.INVALID_MAX_FRAMES),
                    Triple(101, null, ValidationErrorCode.INVALID_MAX_FRAMES),
                    Triple(null, 0, ValidationErrorCode.INVALID_SAMPLE_RATE),
                )) {
                    val error = failsWith<ValidationError> { client.detectVideo(mp4(), maxFrames, sampleRate) }
                    assertEquals(code, error.code)
                }
                assertEquals(
                    ValidationErrorCode.INVALID_MAX_FRAMES,
                    assertFailsWith<ValidationError> { client.newVideoCall(mp4(), 0) }.code,
                )
                runBlocking { client.detectVideo(mp4(), maxFrames = 100, sampleRate = 1) }
            }
            assertEquals(1, server.requests.size)
        }

        @Test
        fun `progress reports the upload for each attempt`() {
            val progress = mutableListOf<Pair<Long, Long>>()
            val server = fixtureServer("image/documented/internal-error-500.json", "image/documented/low-risk.json")
            withServer(server) {
                testClient(it, maxRetries = 1, runtime = FakeRuntime().runtime)
                    .detectImage(MediaInput.bytes(ByteArray(7), "p.jpg")) { sent, total -> progress += sent to total }
            }
            assertEquals(listOf(0L to 7L, 7L to 7L, 0L to 7L, 7L to 7L), progress)
        }
    }

    @Nested
    inner class ResponseClassification {
        private fun serve(case: JsonObject) = TestServer { _, _ -> TestResponse.fromCase(case) }

        @Test
        fun `HTTP 200 error envelope throws a redacted ServerError`() {
            val case = loadCase("image/documented/internal-error-500.json")
                .withStatus(200)
                .withEnvelopeField("message", JsonPrimitive("failed for $TEST_API_KEY"))
                .withEnvelopeField("future", JsonObject(mapOf("echo" to JsonArray(listOf(JsonPrimitive("nested $TEST_API_KEY"))))))
            val error = serve(case).use { failsWith<ServerError> { testClient(it).detectImage(jpeg()) } }
            assertEquals(200, error.statusCode)
            assertEquals("failed for [REDACTED]", error.detail)
            assertFalse(error.raw.toString().contains(TEST_API_KEY))
            assertFalse(error.toString().contains(TEST_API_KEY))
        }

        @Test
        fun `API keys echoed in successful results are redacted from raw`() {
            val case = loadCase("image/documented/low-risk.json").withEnvelopeField("echo", JsonPrimitive(TEST_API_KEY))
            val result = withServer(serve(case)) { testClient(it).detectImage(jpeg()) }
            assertEquals("[REDACTED]", result.raw["echo"])
        }

        @Test
        fun `HTTP 400 that is not a rejection throws HttpError`() {
            val case = loadCase("image/documented/low-risk.json").withStatus(400)
            val error = serve(case).use { failsWith<HttpError> { testClient(it).detectImage(jpeg()) } }
            assertEquals(400, error.statusCode)
        }

        @Test
        fun `unexpected HTTP status throws HttpError with the server detail`() {
            val server = TestServer { _, _ ->
                TestResponse(404, mapOf("x-request-id" to "req-404"), """{"detail": "Not Found"}""".toByteArray())
            }
            val error = server.use { failsWith<HttpError> { testClient(it).detectImage(jpeg()) } }
            assertEquals(404, error.statusCode)
            assertEquals("Not Found", error.detail)
            assertEquals("req-404", error.requestId)
        }

        @Test
        fun `non-JSON 401 still throws AuthenticationError`() {
            val server = TestServer { _, _ -> TestResponse(401, body = "<html>".toByteArray()) }
            val error = server.use { failsWith<AuthenticationError> { testClient(it).detectImage(jpeg()) } }
            assertEquals("HTTP 401", error.detail)
        }

        @Test
        fun `server details that echo the API key are redacted`() {
            val server = TestServer { _, _ -> TestResponse(401, body = """{"detail": "bad key $TEST_API_KEY"}""".toByteArray()) }
            val error = server.use { failsWith<AuthenticationError> { testClient(it).detectImage(jpeg()) } }
            assertEquals("bad key [REDACTED]", error.detail)
        }

        @Test
        fun `request id prefers the X-Request-ID header`() {
            val case = loadCase("image/documented/internal-error-500.json")
            val server = TestServer { _, _ -> TestResponse.fromCase(case, mapOf("x-request-id" to "req-123")) }
            val error = server.use { failsWith<ServerError> { testClient(it).detectImage(jpeg()) } }
            assertEquals("req-123", error.requestId)
        }

        @Test
        fun `invalid field values throw ProtocolError`() {
            for ((field, value) in listOf(
                "billable" to JsonPrimitive("yes"),
                "risk_score" to JsonPrimitive(11.0),
                "risk_score" to JsonPrimitive("high"),
                "status_code" to JsonPrimitive(1.5),
                "ai_threat_signals" to JsonArray(listOf(JsonPrimitive(1))),
            )) {
                val case = loadCase("image/documented/low-risk.json").withEnvelopeField(field, value)
                serve(case).use { failsWith<ProtocolError> { testClient(it).detectImage(jpeg()) } }
            }
        }

        @Test
        fun `a missing required nullable field throws ProtocolError`() {
            val case = loadCase("video/documented/both-low.json").withEnvelopeField("audio_risk_score", null)
            serve(case).use { failsWith<ProtocolError> { testClient(it).detectVideo(mp4()) } }
        }

        @Test
        fun `a JSON array body throws ProtocolError`() {
            val server = TestServer { _, _ -> TestResponse(200, body = "[]".toByteArray()) }
            server.use { failsWith<ProtocolError> { testClient(it).detectImage(jpeg()) } }
        }
    }

    @Nested
    inner class MediaValidation {
        @TempDir
        lateinit var directory: File

        @Test
        fun `streams a file and infers the filename`() {
            val file = File(directory, "valid.jpg").apply { writeText("path-content") }
            val server = fixtureServer("image/documented/low-risk.json")
            val result = withServer(server) { testClient(it).detectImage(MediaInput.file(file)) }
            assertTrue(result.scored)
            assertContains(server.requests.single().bodyText, "filename=\"valid.jpg\"")
            assertContains(server.requests.single().bodyText, "path-content")
        }

        @Test
        fun `an explicit filename overrides the file name`() {
            val file = File(directory, "upload.bin").apply { writeText("x") }
            val server = fixtureServer("image/documented/low-risk.json")
            withServer(server) { testClient(it).detectImage(MediaInput.file(file, "selfie.png")) }
            assertContains(server.requests.single().bodyText, "filename=\"selfie.png\"")
            assertContains(server.requests.single().bodyText, "Content-Type: image/png")
        }

        @Test
        fun `rejects empty, missing, directory, and symlink paths`() {
            val empty = File(directory, "empty.jpg").apply { createNewFile() }
            val folder = File(directory, "folder.jpg").apply { mkdir() }
            val target = File(directory, "target.jpg").apply { writeText("x") }
            val link = File(directory, "link.jpg")
            Files.createSymbolicLink(link.toPath(), target.toPath())
            val server = fixtureServer("image/documented/low-risk.json")
            server.use {
                val client = testClient(it)
                for ((file, code) in listOf(
                    empty to ValidationErrorCode.EMPTY_FILE,
                    File(directory, "missing.jpg") to ValidationErrorCode.FILE_NOT_FOUND,
                    folder to ValidationErrorCode.UNSUPPORTED_INPUT,
                    link to ValidationErrorCode.UNSUPPORTED_INPUT,
                )) {
                    assertEquals(code, failsWith<ValidationError> { client.detectImage(MediaInput.file(file)) }.code, file.name)
                }
            }
            assertTrue(server.requests.isEmpty())
        }

        @Test
        fun `rejects oversized media before uploading`() {
            val server = fixtureServer("image/documented/low-risk.json")
            server.use {
                val client = testClient(it)
                val image = MediaInput.stream(MediaInput.IMAGE_MAX_BYTES + 1, "big.jpg") { ByteArrayInputStream(ByteArray(0)) }
                assertEquals(ValidationErrorCode.FILE_TOO_LARGE, failsWith<ValidationError> { client.detectImage(image) }.code)
                val video = MediaInput.stream(MediaInput.VIDEO_MAX_BYTES + 1, "big.mp4") { ByteArrayInputStream(ByteArray(0)) }
                assertEquals(ValidationErrorCode.FILE_TOO_LARGE, failsWith<ValidationError> { client.detectVideo(video) }.code)
            }
            assertTrue(server.requests.isEmpty())
        }

        @Test
        fun `accepts media of exactly the maximum size`() {
            val server = fixtureServer("image/documented/low-risk.json")
            val exact = ByteArray(MediaInput.IMAGE_MAX_BYTES.toInt())
            val result = withServer(server) { testClient(it).detectImage(MediaInput.bytes(exact, "max.jpg")) }
            assertTrue(result.scored)
            assertTrue(server.requests.single().bodyLength > MediaInput.IMAGE_MAX_BYTES)
        }

        @Test
        fun `requires a filename for bytes and streams`() {
            fixtureServer("image/documented/low-risk.json").use {
                val client = testClient(it)
                assertEquals(
                    ValidationErrorCode.FILENAME_REQUIRED,
                    failsWith<ValidationError> { client.detectImage(MediaInput.bytes(ByteArray(3), "  ")) }.code,
                )
                assertEquals(
                    ValidationErrorCode.FILENAME_REQUIRED,
                    failsWith<ValidationError> { client.detectImage(MediaInput.bytes(ByteArray(3), "dir/")) }.code,
                )
            }
        }

        @Test
        fun `warns about undocumented extensions but still uploads`() {
            val warnings = mutableListOf<ValidationWarning>()
            val server = fixtureServer("image/documented/low-risk.json")
            withServer(server) {
                testClient(it, onWarning = { w -> warnings += w }).detectImage(MediaInput.bytes(ByteArray(3), "scan.gif"))
            }
            assertEquals("unsupported_extension", warnings.single().code)
            assertEquals("scan.gif", warnings.single().filename)
            assertContains(server.requests.single().bodyText, "Content-Type: application/octet-stream")
        }

        @Test
        fun `single-use streams require maxRetries 0`() {
            fixtureServer("image/documented/low-risk.json").use {
                val error = failsWith<ValidationError> {
                    testClient(it, maxRetries = 1)
                        .detectImage(MediaInput.singleUseStream(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 3, "x.jpg"))
                }
                assertEquals(ValidationErrorCode.STREAM_NOT_REPLAYABLE, error.code)
                val result = runBlocking {
                    testClient(it).detectImage(MediaInput.singleUseStream(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 3, "x.jpg"))
                }
                assertTrue(result.scored)
            }
        }

        @Test
        fun `streams must produce exactly the declared length`() {
            fixtureServer("image/documented/low-risk.json").use {
                val client = testClient(it)
                for (actual in listOf(2, 4)) {
                    failsWith<ValidationError> {
                        client.detectImage(MediaInput.stream(3, "x.jpg") { ByteArrayInputStream(ByteArray(actual) { 7 }) })
                    }
                }
            }
        }

        @Test
        fun `a supplier that throws surfaces as NetworkError without the key`() {
            fixtureServer("image/documented/low-risk.json").use {
                val error = failsWith<NetworkError> {
                    testClient(it).detectImage(MediaInput.stream(3, "x.jpg") { throw java.io.IOException("disk gone $TEST_API_KEY") })
                }
                assertFalse(error.toString().contains(TEST_API_KEY))
            }
        }

        @Test
        fun `documented formats map to deterministic MIME types`() {
            assertEquals("image/jpeg", MediaInput.mimeTypeFor("photo.jpg"))
            assertEquals("image/heif", MediaInput.mimeTypeFor("PHOTO.HEIF"))
            assertEquals("video/mp4", MediaInput.mimeTypeFor("clip.mp4"))
            assertEquals("video/vnd.avi", MediaInput.mimeTypeFor("clip.avi"))
            assertEquals("video/ogg", MediaInput.mimeTypeFor("clip.ogv"))
            assertEquals("application/octet-stream", MediaInput.mimeTypeFor("unknown.xyz"))
            assertEquals("application/octet-stream", MediaInput.mimeTypeFor("noextension"))
            assertEquals(9, MediaInput.IMAGE_EXTENSIONS.size)
            assertEquals(9, MediaInput.VIDEO_EXTENSIONS.size)
            assertEquals(10L * 1024 * 1024, MediaInput.IMAGE_MAX_BYTES)
            assertEquals(1_500_000_000L, MediaInput.VIDEO_MAX_BYTES)
        }
    }

    @Nested
    inner class Configuration {
        @Test
        fun defaults() {
            NeuroVerifyClient(apiKey = "key").use { client ->
                assertEquals(NeuroVerifyClient.PRODUCTION_URL, client.baseUrl)
                assertEquals(120_000L, client.timeoutMillis)
                assertEquals(3, client.maxRetries)
                assertEquals(60_000L, client.retryAfterCapMillis)
            }
            assertEquals("https://deepscan.neuraldefend.com", NeuroVerifyClient.PRODUCTION_URL)
            assertEquals("https://stage.deepscan.neuraldefend.com", NeuroVerifyClient.STAGING_URL)
        }

        @Test
        fun `staging is pinned`() {
            NeuroVerifyClient.staging(apiKey = "key").use { assertEquals(NeuroVerifyClient.STAGING_URL, it.baseUrl) }
            val pinned = NeuroVerifyClient.staging("key") {
                baseUrl("https://api.example.com")
                allowCustomBaseUrl(true)
                maxRetries(0)
            }
            pinned.use {
                assertEquals(NeuroVerifyClient.STAGING_URL, it.baseUrl)
                assertEquals(0, it.maxRetries)
            }
        }

        @Test
        fun `Kotlin factory applies options`() {
            NeuroVerifyClient(apiKey = "key") {
                timeout(kotlin.time.Duration.parse("5s"))
                maxRetries(1)
            }.use {
                assertEquals(5_000L, it.timeoutMillis)
                assertEquals(1, it.maxRetries)
            }
        }

        @Test
        fun `custom origins require explicit opt-in`() {
            val error = assertFailsWith<ValidationError> { NeuroVerifyClient(apiKey = "key") { baseUrl("https://api.example.com") } }
            assertEquals(ValidationErrorCode.CUSTOM_BASE_URL_REQUIRES_OPT_IN, error.code)
            NeuroVerifyClient(apiKey = "key") {
                baseUrl("https://API.example.com:8443/")
                allowCustomBaseUrl(true)
            }.use { assertEquals("https://api.example.com:8443", it.baseUrl) }
            NeuroVerifyClient(apiKey = "key") { baseUrl("https://deepscan.neuraldefend.com:443/") }
                .use { assertEquals(NeuroVerifyClient.PRODUCTION_URL, it.baseUrl) }
        }

        @ParameterizedTest
        @ValueSource(
            strings = [
                "http://deepscan.neuraldefend.com",
                "https://deepscan.neuraldefend.com/api",
                "https://user:pass@deepscan.neuraldefend.com",
                "https://deepscan.neuraldefend.com?x=1",
                "https://deepscan.neuraldefend.com#frag",
                "not a url",
                "ftp://deepscan.neuraldefend.com",
            ],
        )
        fun `rejects invalid base URLs`(url: String) {
            val error = assertFailsWith<ValidationError> {
                NeuroVerifyClient(apiKey = "key") {
                    baseUrl(url)
                    allowCustomBaseUrl(true)
                }
            }
            assertEquals(ValidationErrorCode.INVALID_BASE_URL, error.code)
        }

        @Test
        fun `validates the API key, timeout, and retries`() {
            fun code(block: () -> Unit) = assertFailsWith<ValidationError> { block() }.code
            assertEquals(ValidationErrorCode.API_KEY_REQUIRED, code { NeuroVerifyClient.builder().apiKey("   ").build() })
            assertEquals(
                ValidationErrorCode.INVALID_TIMEOUT,
                code { NeuroVerifyClient.builder().apiKey("k").timeout(0, java.util.concurrent.TimeUnit.SECONDS).build() },
            )
            assertEquals(ValidationErrorCode.INVALID_RETRIES, code { NeuroVerifyClient.builder().apiKey("k").maxRetries(-1).build() })
            assertEquals(ValidationErrorCode.INVALID_RETRIES, code { NeuroVerifyClient.builder().apiKey("k").maxRetries(4).build() })
        }

        @Test
        fun `the API key is trimmed and redacted from toString and toJson`() {
            val server = fixtureServer("image/documented/low-risk.json")
            server.use {
                val client = testClient(it, apiKey = "  $TEST_API_KEY  ")
                assertFalse(client.toString().contains(TEST_API_KEY))
                assertEquals("[REDACTED]", client.toJson()["apiKey"])
                runBlocking { client.detectImage(jpeg()) }
            }
            assertEquals(TEST_API_KEY, server.requests.single().header("x-api-key"))
        }

        @Test
        fun `JVM servers read NEURALDEFEND_API_KEY and NEURALDEFEND_BASE_URL`() {
            val environment = mapOf(
                "NEURALDEFEND_API_KEY" to "environment-key",
                "NEURALDEFEND_BASE_URL" to "https://stage.deepscan.neuraldefend.com",
            )
            val client = NeuroVerifyClient.builder().apply { this.environment = environment::get }.build()
            client.use { assertEquals(NeuroVerifyClient.STAGING_URL, it.baseUrl) }
            val missing = assertFailsWith<ValidationError> {
                NeuroVerifyClient.builder().apply { this.environment = { null } }.build()
            }
            assertContains(missing.detail, "NEURALDEFEND_API_KEY")
        }

        @Test
        fun `close rejects new calls and leaves a supplied OkHttpClient open`() {
            val supplied = okhttp3.OkHttpClient()
            val client = NeuroVerifyClient.builder().apiKey("key").okHttpClient(supplied).build()
            client.close()
            client.close()
            assertFalse(supplied.dispatcher.executorService.isShutdown)
            assertFailsWith<IllegalStateException> { runBlocking { client.detectImage(jpeg()) } }
            assertFailsWith<IllegalStateException> { client.newImageCall(jpeg()) }

            val owned = NeuroVerifyClient(apiKey = "key")
            owned.close()
        }

        @Test
        fun `errors format status and request id without secrets`() {
            assertEquals(
                "AuthenticationError: Invalid API key (statusCode: 401, requestId: req-1)",
                AuthenticationError("Invalid API key", "req-1").toString(),
            )
            assertEquals("TimeoutError: slow", TimeoutError("slow").toString())
            assertNull(NetworkError("x").statusCode)
            assertIs<HttpError>(ServerError("x", 503))
        }

        @Test
        fun `risk levels parse only documented wire values`() {
            assertEquals(RiskLevel.HIGH, RiskLevel.fromWire("high"))
            assertNull(RiskLevel.fromWire("critical"))
            assertNull(RiskLevel.fromWire(null))
            assertEquals(
                setOf("unified_face_authenticity_score"),
                loadCase("image/documented/low-risk.json")["body"]!!.jsonObject.keys,
            )
        }
    }
}
