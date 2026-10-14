package com.neuraldefend

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.BufferedSink
import java.io.IOException
import java.io.InterruptedIOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Receives upload progress for the current attempt. `sentBytes` restarts at zero when a retry begins. */
public fun interface UploadProgressListener {
    public fun onProgress(sentBytes: Long, totalBytes: Long)
}

internal class RawResponse(val statusCode: Int, val headers: Headers, val body: ByteArray)

/** Carries a local media failure through OkHttp, which only reports [IOException]s. */
private class UploadFailure(val error: Throwable) : IOException(error.message, error)

private const val MAX_RESPONSE_BYTES = 8L * 1024 * 1024
private const val CHUNK_BYTES = 64 * 1024

private class MediaRequestBody(
    private val media: PreparedMedia,
    private val onProgress: UploadProgressListener?,
) : RequestBody() {
    override fun contentType() = media.contentType.toMediaType()

    override fun contentLength(): Long = media.length

    override fun isOneShot(): Boolean = !media.replayable

    override fun writeTo(sink: BufferedSink) {
        val stream = try {
            media.open()
        } catch (error: NeuroVerifyError) {
            throw UploadFailure(error)
        } catch (error: IOException) {
            throw UploadFailure(error)
        } catch (error: RuntimeException) {
            throw UploadFailure(error)
        }
        stream.use { input ->
            val buffer = ByteArray(CHUNK_BYTES)
            var sent = 0L
            onProgress?.onProgress(0, media.length)
            while (true) {
                val read = try {
                    input.read(buffer)
                } catch (error: IOException) {
                    throw UploadFailure(error)
                } catch (error: RuntimeException) {
                    throw UploadFailure(error)
                }
                if (read < 0) break
                if (read == 0) continue
                if (sent + read > media.length) {
                    throw UploadFailure(
                        ValidationError(
                            ValidationErrorCode.FILE_TOO_LARGE,
                            "The upload produced more than the declared ${media.length} bytes.",
                        ),
                    )
                }
                sink.write(buffer, 0, read)
                sent += read
                onProgress?.onProgress(sent, media.length)
            }
            if (sent != media.length) {
                throw UploadFailure(
                    ValidationError(
                        ValidationErrorCode.UNSUPPORTED_INPUT,
                        "The upload ended after $sent of the declared ${media.length} bytes.",
                    ),
                )
            }
        }
    }
}

internal fun buildRequest(
    url: String,
    apiKey: String,
    userAgent: String,
    media: PreparedMedia,
    onProgress: UploadProgressListener?,
): Request {
    val body = MultipartBody.Builder()
        .setType(MultipartBody.FORM)
        .addFormDataPart("file", media.filename, MediaRequestBody(media, onProgress))
        .build()
    return Request.Builder()
        .url(url)
        .header("accept", "application/json")
        .header("x-api-key", apiKey)
        .header("user-agent", userAgent)
        .post(body)
        .build()
}

/**
 * Executes one attempt. The response body is read on OkHttp's thread so the per-call timeout
 * also bounds reading it. Coroutine cancellation cancels the OkHttp call.
 */
internal suspend fun OkHttpClient.executeAttempt(
    request: Request,
    kind: DetectionKind,
    timeoutMillis: Long,
    apiKey: String,
): RawResponse = suspendCancellableCoroutine { continuation ->
    val call = newCall(request)
    continuation.invokeOnCancellation { call.cancel() }
    call.enqueue(
        object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(mapFailure(e, kind, timeoutMillis, apiKey))
            }

            override fun onResponse(call: Call, response: Response) {
                val result = try {
                    response.use { Result.success(RawResponse(it.code, it.headers, readBounded(it))) }
                } catch (error: IOException) {
                    Result.failure(mapFailure(error, kind, timeoutMillis, apiKey))
                } catch (error: NeuroVerifyError) {
                    Result.failure(error)
                }
                result.fold(continuation::resume, continuation::resumeWithException)
            }
        },
    )
}

private fun readBounded(response: Response): ByteArray {
    val source = response.body!!.source()
    if (source.request(MAX_RESPONSE_BYTES + 1)) {
        throw ProtocolError(
            "The response body exceeded ${MAX_RESPONSE_BYTES / (1024 * 1024)} MiB.",
            response.code,
            response.header("x-request-id"),
        )
    }
    return source.buffer.readByteArray()
}

private fun mapFailure(error: IOException, kind: DetectionKind, timeoutMillis: Long, apiKey: String): Throwable {
    if (error is UploadFailure) {
        val cause = error.error
        if (cause is NeuroVerifyError) return cause
        return NetworkError(
            "The ${kind.label} upload could not be read: ${redact(describe(cause), apiKey)}",
        )
    }
    if (error is InterruptedIOException) {
        return TimeoutError("The ${kind.label} request timed out after $timeoutMillis ms.")
    }
    return NetworkError(
        "The ${kind.label} request failed before receiving a response: ${redact(describe(error), apiKey)}",
    )
}

private fun describe(error: Throwable): String = error.message?.takeIf { it.isNotBlank() } ?: error.javaClass.simpleName
