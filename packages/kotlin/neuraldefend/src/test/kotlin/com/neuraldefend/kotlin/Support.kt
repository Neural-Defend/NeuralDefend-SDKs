package com.neuraldefend.kotlin

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.BufferedInputStream
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

const val TEST_API_KEY = "secret-test-key"

val fixturesRoot: File = File(System.getProperty("neuraldefend.fixtures") ?: "../../../tests/fixtures")

fun loadCase(relativePath: String): JsonObject =
    Json.parseToJsonElement(File(fixturesRoot, relativePath).readText()).jsonObject

/** Every fixture path relative to [fixturesRoot], sorted. */
fun allFixturePaths(): List<String> = listOf("image", "video").flatMap { kind ->
    File(fixturesRoot, kind).walkTopDown()
        .filter { it.isFile && it.name.endsWith(".json") }
        .map { it.relativeTo(fixturesRoot).invariantSeparatorsPath }
        .toList()
}.sorted()

/** The response envelope of a fixture as the SDK decodes it. */
@Suppress("UNCHECKED_CAST")
fun wireEnvelope(case: JsonObject): Map<String, Any?> {
    val key = if (case["endpoint"]!!.jsonPrimitive.content == "/detect/image") {
        "unified_face_authenticity_score"
    } else {
        "unified_video_authenticity_score"
    }
    return decodeObject(case["body"]!!.jsonObject[key].toString())!!
}

fun fixtureBody(case: JsonObject): ByteArray {
    val body = case["body"]!!
    return if (case["body_kind"]?.jsonPrimitive?.content == "raw") {
        body.jsonPrimitive.content.toByteArray()
    } else {
        body.toString().toByteArray()
    }
}

fun JsonObject.with(key: String, value: JsonElement): JsonObject = JsonObject(this + (key to value))

fun JsonObject.withEnvelopeField(field: String, value: JsonElement?): JsonObject {
    val body = this["body"]!!.jsonObject
    val key = body.keys.single()
    val envelope = body[key]!!.jsonObject
    val updated = if (value == null) JsonObject(envelope - field) else JsonObject(envelope + (field to value))
    return with("body", JsonObject(mapOf(key to updated)))
}

fun JsonObject.withStatus(status: Int): JsonObject = with("http_status", JsonPrimitive(status))

/** A response the [TestServer] sends. */
class TestResponse(
    val status: Int,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray = ByteArray(0),
    val delayMillis: Long = 0,
) {
    companion object {
        fun fromCase(case: JsonObject, overrideHeaders: Map<String, String>? = null): TestResponse {
            val headers = overrideHeaders
                ?: case["headers"]?.jsonObject?.mapValues { it.value.jsonPrimitive.content }.orEmpty()
            return TestResponse(case["http_status"]!!.jsonPrimitive.int, headers, fixtureBody(case))
        }

        fun fixture(path: String): TestResponse = fromCase(loadCase(path))
    }
}

/** A request observed by the [TestServer]. Bodies above [TestServer.recordLimit] are counted, not stored. */
class RecordedRequest(
    val method: String,
    val target: String,
    val headers: Map<String, String>,
    val body: ByteArray,
    val bodyLength: Long,
) {
    val bodyText: String get() = String(body, Charsets.ISO_8859_1)
    fun header(name: String): String? = headers[name.lowercase()]
}

/**
 * Minimal HTTP/1.1 server on a real loopback socket. Each connection serves one request and
 * is closed, which keeps OkHttp's behavior deterministic.
 */
class TestServer(
    private val recordLimit: Int = 32 * 1024 * 1024,
    private val respond: (call: Int, request: RecordedRequest) -> TestResponse,
) : Closeable {
    private val socket = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
    private val pool = Executors.newCachedThreadPool()
    private val calls = AtomicInteger()
    val requests: MutableList<RecordedRequest> = CopyOnWriteArrayList()
    val origin: String get() = "http://127.0.0.1:${socket.localPort}"

    init {
        pool.execute {
            while (!socket.isClosed) {
                val connection = try {
                    socket.accept()
                } catch (_: Exception) {
                    break
                }
                pool.execute { serve(connection) }
            }
        }
    }

    private fun serve(connection: Socket) {
        connection.use {
            try {
                val input = BufferedInputStream(it.getInputStream())
                val requestLine = readLine(input) ?: return
                val headers = linkedMapOf<String, String>()
                while (true) {
                    val line = readLine(input) ?: return
                    if (line.isEmpty()) break
                    val colon = line.indexOf(':')
                    headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
                }
                val length = headers["content-length"]?.toLong() ?: 0
                val stored = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                var remaining = length
                while (remaining > 0) {
                    val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                    if (read < 0) break
                    if (stored.size() < recordLimit) stored.write(buffer, 0, read)
                    remaining -= read
                }
                val parts = requestLine.split(" ")
                val request = RecordedRequest(parts[0], parts[1], headers, stored.toByteArray(), length - remaining)
                requests.add(request)
                val response = respond(calls.incrementAndGet(), request)
                if (response.delayMillis > 0) Thread.sleep(response.delayMillis)
                write(it.getOutputStream(), response)
            } catch (_: Exception) {
                // The client may abandon the connection (timeouts and cancellation tests).
            }
        }
    }

    private fun write(output: OutputStream, response: TestResponse) {
        val head = StringBuilder("HTTP/1.1 ${response.status} Test\r\n")
        for ((name, value) in response.headers) {
            if (name.equals("content-length", true) || name.equals("connection", true)) continue
            head.append(name).append(": ").append(value).append("\r\n")
        }
        head.append("content-length: ").append(response.body.size).append("\r\n")
        head.append("connection: close\r\n\r\n")
        output.write(head.toString().toByteArray(Charsets.ISO_8859_1))
        output.write(response.body)
        output.flush()
    }

    private fun readLine(input: InputStream): String? {
        val line = StringBuilder()
        while (true) {
            val next = input.read()
            if (next < 0) return if (line.isEmpty()) null else line.toString()
            if (next == '\n'.code) return line.toString().trimEnd('\r')
            line.append(next.toChar())
        }
    }

    override fun close() {
        socket.close()
        pool.shutdownNow()
    }
}

fun fixtureServer(vararg fixtures: String): TestServer = TestServer { call, _ ->
    TestResponse.fixture(fixtures[(call - 1).coerceIn(0, fixtures.size - 1)])
}

/** Deterministic sleep, jitter, and clock that record every requested delay. */
internal class FakeRuntime(
    private val jitter: Double = 0.0,
    private val now: Long = utc(2026, 7, 26, 23, 59, 0),
) {
    val sleeps: MutableList<Long> = CopyOnWriteArrayList()
    val runtime: ClientRuntime = ClientRuntime(
        sleep = { sleeps.add(it) },
        random = { jitter },
        nowMillis = { now },
    )
}

fun utc(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int): Long =
    java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).apply {
        clear()
        set(year, month - 1, day, hour, minute, second)
    }.timeInMillis

internal fun testClient(
    server: TestServer,
    maxRetries: Int = 0,
    timeoutMillis: Long = 30_000,
    retryAfterCapMillis: Long = 60_000,
    userAgent: String? = null,
    runtime: ClientRuntime = ClientRuntime.DEFAULT,
    onWarning: WarningListener? = null,
    apiKey: String = TEST_API_KEY,
    environment: (String) -> String? = { null },
): NeuroVerifyClient = testClient(
    server.origin, maxRetries, timeoutMillis, retryAfterCapMillis, userAgent, runtime, onWarning, apiKey, environment,
)

internal fun testClient(
    origin: String,
    maxRetries: Int = 0,
    timeoutMillis: Long = 30_000,
    retryAfterCapMillis: Long = 60_000,
    userAgent: String? = null,
    runtime: ClientRuntime = ClientRuntime.DEFAULT,
    onWarning: WarningListener? = null,
    apiKey: String = TEST_API_KEY,
    environment: (String) -> String? = { null },
): NeuroVerifyClient = NeuroVerifyClient.builder().apply {
    allowInsecureForTesting = true
    this.runtime = runtime
    this.environment = environment
}
    .apiKey(apiKey)
    .baseUrl(origin)
    .allowCustomBaseUrl(true)
    .maxRetries(maxRetries)
    .timeout(timeoutMillis, java.util.concurrent.TimeUnit.MILLISECONDS)
    .retryAfterCap(retryAfterCapMillis, java.util.concurrent.TimeUnit.MILLISECONDS)
    .userAgent(userAgent)
    .onWarning(onWarning)
    .build()

/** Test client for Java sources, which cannot call functions with Kotlin default arguments. */
fun javaTestClient(server: TestServer): NeuroVerifyClient = testClient(server)

fun jpeg(): MediaInput = MediaInput.bytes("image-bytes".toByteArray(), "selfie.jpg")

fun mp4(): MediaInput = MediaInput.bytes("video-bytes".toByteArray(), "clip.mp4")
