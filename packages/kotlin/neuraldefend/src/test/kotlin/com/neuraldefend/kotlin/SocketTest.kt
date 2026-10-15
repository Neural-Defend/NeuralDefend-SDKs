package com.neuraldefend.kotlin

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/** Behavior over real loopback sockets: streaming, timeouts, cancellation, redirects, refusals. */
class SocketTest {
    @TempDir
    lateinit var directory: File

    /** Generates [length] bytes without any backing array, so buffering would exhaust the 256 MiB test heap. */
    private class GeneratedStream(private val length: Long) : InputStream() {
        private var position = 0L

        override fun read(): Int = if (position >= length) -1 else (position++ % 251).toInt()

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (position >= length) return -1
            val count = minOf(len.toLong(), length - position).toInt()
            for (i in 0 until count) b[off + i] = ((position + i) % 251).toByte()
            position += count
            return count
        }
    }

    @Test
    fun `streams a large supplier upload with a small heap`() {
        val length = 600L * 1024 * 1024
        val server = TestServer(recordLimit = 0) { _, _ -> TestResponse.fixture("video/documented/both-low.json") }
        server.use {
            val result = runBlocking {
                testClient(it, timeoutMillis = 120_000)
                    .detectVideo(MediaInput.stream(length, "clip.mp4") { GeneratedStream(length) }, maxFrames = 2)
            }
            assertTrue(result.scored)
        }
        assertTrue(server.requests.single().bodyLength > length)
        assertTrue(Runtime.getRuntime().maxMemory() < length, "the test heap must be smaller than the upload")
    }

    @Test
    fun `streams a large file upload over a real connection`() {
        val file = File(directory, "clip.mp4")
        RandomAccessFile(file, "rw").use { it.setLength(300L * 1024 * 1024) }
        val server = TestServer(recordLimit = 0) { _, _ -> TestResponse.fixture("video/documented/both-low.json") }
        server.use {
            val result = runBlocking { testClient(it).detectVideo(MediaInput.file(file), maxFrames = 2) }
            assertTrue(result.scored)
        }
        assertTrue(server.requests.single().bodyLength > file.length())
    }

    @Test
    fun `a slow server raises TimeoutError and is not retried`() {
        val fake = FakeRuntime()
        val server = TestServer { _, _ ->
            TestResponse.fixture("image/documented/low-risk.json").let { TestResponse(it.status, it.headers, it.body, 3_000) }
        }
        server.use {
            val started = System.nanoTime()
            assertFailsWith<TimeoutError> {
                runBlocking { testClient(it, timeoutMillis = 300, maxRetries = 3, runtime = fake.runtime).detectImage(jpeg()) }
            }
            assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) < 2_000)
        }
        assertEquals(1, server.requests.size)
        assertTrue(fake.sleeps.isEmpty())
    }

    @Test
    fun `coroutine cancellation cancels an in-flight request`() {
        val received = CountDownLatch(1)
        val server = TestServer { _, _ ->
            received.countDown()
            TestResponse(200, delayMillis = 5_000)
        }
        server.use {
            val client = testClient(it)
            val started = System.nanoTime()
            runBlocking {
                val pending = async(kotlinx.coroutines.Dispatchers.IO) { client.detectImage(jpeg()) }
                received.await(5, TimeUnit.SECONDS)
                pending.cancel()
                assertFailsWith<CancellationException> { pending.await() }
            }
            assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) < 3_000)
        }
    }

    @Test
    fun `withTimeout around the SDK reports standard cancellation`() {
        val server = TestServer { _, _ -> TestResponse(200, delayMillis = 5_000) }
        server.use {
            assertFailsWith<kotlinx.coroutines.TimeoutCancellationException> {
                runBlocking { withTimeout(300) { testClient(it).detectImage(jpeg()) } }
            }
        }
    }

    @Test
    fun `NeuroVerifyCall cancel aborts an in-flight execute`() {
        val received = CountDownLatch(1)
        val server = TestServer { _, _ ->
            received.countDown()
            TestResponse(200, delayMillis = 5_000)
        }
        server.use {
            val call = testClient(it).newImageCall(jpeg())
            Thread {
                received.await(5, TimeUnit.SECONDS)
                call.cancel()
            }.start()
            assertFailsWith<AbortError> { call.execute() }
            assertTrue(call.isCanceled)
            assertFailsWith<IllegalStateException> { call.execute() }
        }
    }

    @Test
    fun `NeuroVerifyCall cancel aborts a retry wait`() {
        val server = fixtureServer("image/documented/service-unavailable-503.json")
        server.use {
            val holder = AtomicReference<NeuroVerifyCall<ImageResult>>()
            val runtime = ClientRuntime(
                sleep = {
                    holder.get().cancel()
                    awaitCancellation()
                },
                random = { 0.0 },
                nowMillis = { 0L },
            )
            val call = testClient(it, maxRetries = 3, runtime = runtime).newImageCall(jpeg())
            holder.set(call)
            assertFailsWith<AbortError> { call.execute() }
        }
        assertEquals(1, server.requests.size)
    }

    @Test
    fun `NeuroVerifyCall enqueue delivers results and failures once`() {
        val server = fixtureServer("image/documented/low-risk.json", "image/synthetic/unauthorized-401.json")
        server.use {
            val client = testClient(it)
            val success = CompletableDeferred<Any>()
            client.newImageCall(jpeg()).enqueue(
                object : NeuroVerifyCallback<ImageResult> {
                    override fun onResult(call: NeuroVerifyCall<ImageResult>, result: ImageResult) {
                        success.complete(result)
                    }

                    override fun onFailure(call: NeuroVerifyCall<ImageResult>, error: NeuroVerifyError) {
                        success.complete(error)
                    }
                },
            )
            assertTrue(assertIs<ImageResult>(runBlocking { withTimeout(10_000) { success.await() } }).scored)

            val failure = CompletableDeferred<Any>()
            client.newImageCall(jpeg()).enqueue(
                object : NeuroVerifyCallback<ImageResult> {
                    override fun onResult(call: NeuroVerifyCall<ImageResult>, result: ImageResult) {
                        failure.complete(result)
                    }

                    override fun onFailure(call: NeuroVerifyCall<ImageResult>, error: NeuroVerifyError) {
                        failure.complete(error)
                    }
                },
            )
            assertIs<AuthenticationError>(runBlocking { withTimeout(10_000) { failure.await() } })
        }
    }

    @Test
    fun `NeuroVerifyCall canceled before enqueue reports AbortError`() {
        fixtureServer("image/documented/low-risk.json").use {
            val call = testClient(it).newImageCall(jpeg())
            call.cancel()
            val outcome = CompletableDeferred<NeuroVerifyError>()
            call.enqueue(
                object : NeuroVerifyCallback<ImageResult> {
                    override fun onResult(call: NeuroVerifyCall<ImageResult>, result: ImageResult) = Unit

                    override fun onFailure(call: NeuroVerifyCall<ImageResult>, error: NeuroVerifyError) {
                        outcome.complete(error)
                    }
                },
            )
            assertIs<AbortError>(runBlocking { outcome.await() })
            assertTrue(it.requests.isEmpty())
        }
    }

    @Test
    fun `coroutine cancellation stops a retry wait`() {
        val server = fixtureServer("image/documented/service-unavailable-503.json")
        server.use {
            runBlocking {
                val pending = async { testClient(it, maxRetries = 3).detectImage(jpeg()) }
                delay(500)
                pending.cancel()
                assertFailsWith<CancellationException> { pending.await() }
            }
        }
        assertEquals(1, server.requests.size)
    }

    @Test
    fun `redirects are never followed`() {
        val server = TestServer { _, _ -> TestResponse(302, mapOf("location" to "/elsewhere")) }
        server.use {
            val error = assertFailsWith<HttpError> { runBlocking { testClient(it, maxRetries = 3).detectImage(jpeg()) } }
            assertEquals(302, error.statusCode)
        }
        assertEquals(1, server.requests.size)
    }

    @Test
    fun `a refused connection raises NetworkError without the API key`() {
        val port = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { it.localPort }
        val error = assertFailsWith<NetworkError> {
            runBlocking { testClient("http://127.0.0.1:$port", maxRetries = 3).detectImage(jpeg()) }
        }
        assertFalse(error.toString().contains(TEST_API_KEY))
    }
}
