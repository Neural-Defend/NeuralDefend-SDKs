package com.neuraldefend.kotlin

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import java.io.Closeable
import java.net.URI
import java.net.URISyntaxException
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlin.time.Duration

/**
 * Client for the NeuroVerify image and video authenticity API.
 *
 * Kotlin:
 * ```kotlin
 * val client = NeuroVerifyClient(apiKey = key)
 * val result = client.detectImage(MediaInput.file(photo))
 * ```
 *
 * Java:
 * ```java
 * NeuroVerifyClient client = NeuroVerifyClient.builder().apiKey(key).build();
 * ImageResult result = client.newImageCall(MediaInput.file(photo)).execute();
 * ```
 *
 * A client is thread-safe and should be reused. Call [close] when it is no longer needed.
 * Results are decision-support signals, not proof of authenticity.
 */
public class NeuroVerifyClient private constructor(
    config: Config,
    private val runtime: ClientRuntime,
) : Closeable {
    /** Validated API origin, for example `https://deepscan.neuraldefend.com`. */
    public val baseUrl: String = config.baseUrl

    /** Per-attempt timeout in milliseconds. */
    public val timeoutMillis: Long = config.timeoutMillis

    /** Retries after the initial request for HTTP 429, 500, and 503. */
    public val maxRetries: Int = config.maxRetries

    /** Maximum wait honored from a `Retry-After` header, in milliseconds. */
    public val retryAfterCapMillis: Long = config.retryAfterCapMillis

    private val apiKey: String = config.apiKey
    private val userAgent: String = config.userAgent
    private val onWarning: (ValidationWarning) -> Unit = config.onWarning
    private val ownsHttp: Boolean = config.okHttpClient == null
    private val http: OkHttpClient = (config.okHttpClient ?: OkHttpClient())
        .newBuilder()
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        .callTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
        .connectTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
        .readTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
        .writeTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
        .build()
    private val callScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val closed = AtomicBoolean(false)

    /**
     * Uploads an image to `/detect/image`.
     *
     * Business rejections (no face, multiple faces, quality or security failures) are returned
     * as results with [ResultStatus.REJECTED]; branch on [ImageResult.status]. Operational
     * failures throw a [NeuroVerifyError]. Cancelling the calling coroutine cancels the
     * upload and any retry wait.
     */
    @JvmSynthetic
    public suspend fun detectImage(media: MediaInput, onProgress: UploadProgressListener? = null): ImageResult {
        val response = execute(DetectionKind.IMAGE, media, emptyMap(), onProgress)
        return classify(response, DetectionKind.IMAGE) { envelope, requestId ->
            parseImage(envelope, response.statusCode, requestId, apiKey)
        }
    }

    /**
     * Uploads a video to `/detect/video`.
     *
     * [maxFrames] (1 through 100; API default 12) and [sampleRate] (at least 1) are sent as
     * query parameters. Video and audio are scored independently.
     */
    @JvmSynthetic
    public suspend fun detectVideo(
        media: MediaInput,
        maxFrames: Int? = null,
        sampleRate: Int? = null,
        onProgress: UploadProgressListener? = null,
    ): VideoResult {
        val query = videoQuery(maxFrames, sampleRate)
        val response = execute(DetectionKind.VIDEO, media, query, onProgress)
        return classify(response, DetectionKind.VIDEO) { envelope, requestId ->
            parseVideo(envelope, response.statusCode, requestId, apiKey)
        }
    }

    /**
     * Creates a call for [detectImage] that Java and callback-based code can [execute][NeuroVerifyCall.execute],
     * [enqueue][NeuroVerifyCall.enqueue], or [cancel][NeuroVerifyCall.cancel].
     */
    @JvmOverloads
    public fun newImageCall(media: MediaInput, onProgress: UploadProgressListener? = null): NeuroVerifyCall<ImageResult> {
        checkOpen()
        return NeuroVerifyCall(callScope) { detectImage(media, onProgress) }
    }

    /** Creates a call for [detectVideo]. Pass `null` to use the API default for an option. */
    @JvmOverloads
    public fun newVideoCall(
        media: MediaInput,
        maxFrames: Int? = null,
        sampleRate: Int? = null,
        onProgress: UploadProgressListener? = null,
    ): NeuroVerifyCall<VideoResult> {
        checkOpen()
        videoQuery(maxFrames, sampleRate)
        return NeuroVerifyCall(callScope) { detectVideo(media, maxFrames, sampleRate, onProgress) }
    }

    /**
     * Releases the HTTP resources created by this SDK; new calls then throw
     * [IllegalStateException]. A caller-supplied `OkHttpClient` is left open. Close a client
     * only after its calls have finished.
     */
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        if (ownsHttp) {
            http.dispatcher.executorService.shutdown()
            http.connectionPool.evictAll()
        }
    }

    /** JSON-compatible configuration with the API key redacted. */
    public fun toJson(): Map<String, Any?> = linkedMapOf(
        "apiKey" to REDACTED,
        "baseUrl" to baseUrl,
        "timeoutMs" to timeoutMillis,
        "maxRetries" to maxRetries,
    )

    override fun toString(): String =
        "NeuroVerifyClient(apiKey=$REDACTED, baseUrl=$baseUrl, timeoutMs=$timeoutMillis, maxRetries=$maxRetries)"

    private fun checkOpen() {
        check(!closed.get()) { "This NeuroVerifyClient has been closed." }
    }

    private fun videoQuery(maxFrames: Int?, sampleRate: Int?): Map<String, String> {
        if (maxFrames != null && (maxFrames < 1 || maxFrames > 100)) {
            throw ValidationError(
                ValidationErrorCode.INVALID_MAX_FRAMES,
                "maxFrames must be an integer from 1 through 100.",
            )
        }
        if (sampleRate != null && sampleRate < 1) {
            throw ValidationError(
                ValidationErrorCode.INVALID_SAMPLE_RATE,
                "sampleRate must be an integer greater than or equal to 1.",
            )
        }
        return buildMap {
            if (maxFrames != null) put("max_frames", maxFrames.toString())
            if (sampleRate != null) put("sample_rate", sampleRate.toString())
        }
    }

    private suspend fun execute(
        kind: DetectionKind,
        input: MediaInput,
        query: Map<String, String>,
        onProgress: UploadProgressListener?,
    ): RawResponse {
        checkOpen()
        val media = withContext(Dispatchers.IO) { prepareMedia(input, kind, onWarning) }
        if (!media.replayable && maxRetries != 0) {
            throw ValidationError(
                ValidationErrorCode.STREAM_NOT_REPLAYABLE,
                "Single-use streams require maxRetries = 0; use MediaInput.file, MediaInput.bytes, " +
                    "or MediaInput.stream to allow retries.",
            )
        }
        val url = (baseUrl + kind.path).toHttpUrl().newBuilder().apply {
            for ((name, value) in query) addQueryParameter(name, value)
        }.build().toString()

        var attempt = 0
        while (true) {
            val request = buildRequest(url, apiKey, userAgent, media, onProgress)
            val response = http.executeAttempt(request, kind, timeoutMillis, apiKey)
            val retryable = response.statusCode == 429 || response.statusCode == 500 || response.statusCode == 503
            if (!retryable || attempt >= maxRetries) return response
            runtime.sleep(retryDelayMillis(response, attempt))
            attempt++
        }
    }

    private fun retryDelayMillis(response: RawResponse, attempt: Int): Long {
        val baseSeconds = min(2.0.pow(attempt), 4.0)
        if (response.statusCode == 429) {
            parseRetryAfter(response.headers["retry-after"])?.let { return it }
            return min(secondsToMillis(baseSeconds), retryAfterCapMillis)
        }
        val jitter = runtime.random().coerceIn(0.0, 1.0) * baseSeconds * 0.25
        return secondsToMillis(baseSeconds + jitter)
    }

    private fun parseRetryAfter(value: String?): Long? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        val parsed = if (NUMERIC_SECONDS.matches(trimmed)) {
            val seconds = trimmed.toDouble()
            if (!seconds.isFinite()) return null
            secondsToMillis(seconds)
        } else {
            val date = parseHttpDate(trimmed) ?: return null
            date - runtime.nowMillis()
        }
        return parsed.coerceIn(0, retryAfterCapMillis)
    }

    private fun <T> classify(
        response: RawResponse,
        kind: DetectionKind,
        parse: (Map<String, Any?>, String?) -> T,
    ): T {
        val status = response.statusCode
        val headerRequestId = response.headers["x-request-id"] ?: response.headers["x-correlation-id"]
        val json = decodeObject(String(response.body, Charsets.UTF_8))

        fun detailOr(fallback: String): String = (json?.get("detail") as? String)?.let { redact(it, apiKey) } ?: fallback

        when (status) {
            401 -> throw AuthenticationError(detailOr("HTTP 401"), headerRequestId)
            403 -> throw ScopeError(detailOr("HTTP 403"), headerRequestId)
            429 -> throw RateLimitError(
                detailOr("HTTP 429"),
                headerRequestId,
                retryAfterMillis = parseRetryAfter(response.headers["retry-after"]),
                limit = response.headers["x-ratelimit-limit"],
                remaining = response.headers["x-ratelimit-remaining"],
                reset = response.headers["x-ratelimit-reset"],
            )
            200, 400, 500, 503 -> Unit
            else -> throw HttpError(detailOr("Unexpected HTTP $status."), status, headerRequestId)
        }

        @Suppress("UNCHECKED_CAST")
        val envelope = json?.get(kind.envelope) as? Map<String, Any?>
        if (status == 500 || status == 503) {
            if (envelope == null) throw ServerError("HTTP $status", status, headerRequestId)
            val requestId = headerRequestId ?: transactionId(envelope)
            val message = envelope[kind.messageField] as? String
            throw ServerError(
                message?.let { redact(it, apiKey) } ?: "HTTP $status",
                status,
                requestId,
                freezeEnvelope(envelope, apiKey),
            )
        }
        if (json == null) throw ProtocolError("The server returned malformed JSON.", status, headerRequestId)
        if (envelope == null) {
            throw ProtocolError("The response was missing \"${kind.envelope}\".", status, headerRequestId)
        }
        val requestId = headerRequestId ?: transactionId(envelope)
        val result = parse(envelope, requestId)
        if (status == 400 && !(result as DetectionResult).rejected) {
            throw HttpError("HTTP 400 response was not a rejection.", 400, requestId)
        }
        return result
    }

    /**
     * Configures a [NeuroVerifyClient]. Kotlin callers usually use the
     * `NeuroVerifyClient(apiKey) { ... }` factory instead.
     */
    public class Builder internal constructor() {
        private var apiKey: String? = null
        private var baseUrl: String? = null
        private var staging = false
        private var allowCustomBaseUrl = false
        private var timeoutMillis = DEFAULT_TIMEOUT_MILLIS
        private var maxRetries = MAX_RETRIES
        private var retryAfterCapMillis = DEFAULT_RETRY_AFTER_CAP_MILLIS
        private var userAgent: String? = null
        private var okHttpClient: OkHttpClient? = null
        private var onWarning: ((ValidationWarning) -> Unit)? = null
        internal var allowInsecureForTesting = false
        internal var environment: (String) -> String? = ::systemEnvironment
        internal var runtime: ClientRuntime = ClientRuntime.DEFAULT

        /**
         * Sent in the `x-api-key` header. On JVM servers it falls back to `NEURALDEFEND_API_KEY`;
         * Android apps must pass it explicitly. Never ship a long-lived production key inside an app.
         */
        public fun apiKey(apiKey: String?): Builder = apply { this.apiKey = apiKey }

        /**
         * HTTPS origin. Defaults to `NEURALDEFEND_BASE_URL` on JVM servers, then to [PRODUCTION_URL].
         * A non-Neural Defend origin also requires [allowCustomBaseUrl].
         */
        public fun baseUrl(baseUrl: String?): Builder = apply { this.baseUrl = baseUrl }

        /** Pins [STAGING_URL] and ignores `NEURALDEFEND_BASE_URL`. Use only with a staging credential. */
        public fun staging(): Builder = apply { staging = true }

        /** Must be `true` before a custom origin is accepted, because it receives the key and media. */
        public fun allowCustomBaseUrl(allow: Boolean): Builder = apply { allowCustomBaseUrl = allow }

        /** Per-attempt timeout, including reading the response. Default 120 seconds. */
        public fun timeout(timeout: Long, unit: TimeUnit): Builder = apply { timeoutMillis = unit.toMillis(timeout) }

        /** Per-attempt timeout, including reading the response. Default 120 seconds. */
        @JvmSynthetic
        public fun timeout(timeout: Duration): Builder = apply { timeoutMillis = timeout.inWholeMilliseconds }

        /** Retries after the initial request (0 through 3, default 3) for HTTP 429, 500, and 503. */
        public fun maxRetries(maxRetries: Int): Builder = apply { this.maxRetries = maxRetries }

        /** Caps the wait honored from a `Retry-After` header. Default 60 seconds. */
        public fun retryAfterCap(cap: Long, unit: TimeUnit): Builder = apply { retryAfterCapMillis = unit.toMillis(cap) }

        /** Caps the wait honored from a `Retry-After` header. Default 60 seconds. */
        @JvmSynthetic
        public fun retryAfterCap(cap: Duration): Builder = apply { retryAfterCapMillis = cap.inWholeMilliseconds }

        /** Overrides `neuraldefend-kotlin/<version>`. */
        public fun userAgent(userAgent: String?): Builder = apply { this.userAgent = userAgent }

        /**
         * Shares an existing `OkHttpClient` (connection pool, interceptors, certificate pinning).
         * The SDK derives its own configuration from it: redirects and transport retries are
         * disabled and the timeout is applied. A supplied client is not shut down by [close].
         */
        public fun okHttpClient(client: OkHttpClient?): Builder = apply { okHttpClient = client }

        /** Receives non-fatal media validation warnings. */
        public fun onWarning(listener: WarningListener?): Builder =
            apply { onWarning = listener?.let { l -> { warning: ValidationWarning -> l.onWarning(warning) } } }

        /** Validates the configuration and creates the client. Throws [ValidationError]. */
        public fun build(): NeuroVerifyClient {
            val onAndroid = isAndroid()
            fun env(name: String): String? = if (onAndroid) null else environment(name)?.takeIf { it.isNotBlank() }

            val key = (apiKey ?: env("NEURALDEFEND_API_KEY"))?.trim().orEmpty()
            if (key.isEmpty()) {
                throw ValidationError(
                    ValidationErrorCode.API_KEY_REQUIRED,
                    if (onAndroid) {
                        "apiKey is required in Android apps; pass it explicitly."
                    } else {
                        "apiKey is required; pass it explicitly or set NEURALDEFEND_API_KEY."
                    },
                )
            }
            if (timeoutMillis <= 0) {
                throw ValidationError(ValidationErrorCode.INVALID_TIMEOUT, "timeout must be greater than zero.")
            }
            if (maxRetries < 0 || maxRetries > MAX_RETRIES) {
                throw ValidationError(ValidationErrorCode.INVALID_RETRIES, "maxRetries must be an integer from 0 through 3.")
            }
            val origin = validateBaseUrl(
                if (staging) STAGING_URL else baseUrl ?: env("NEURALDEFEND_BASE_URL") ?: PRODUCTION_URL,
                allowInsecure = allowInsecureForTesting,
                allowCustom = allowCustomBaseUrl && !staging,
            )
            val config = Config(
                apiKey = key,
                baseUrl = origin,
                timeoutMillis = timeoutMillis,
                maxRetries = maxRetries,
                retryAfterCapMillis = retryAfterCapMillis.coerceAtLeast(0),
                userAgent = userAgent?.takeIf { it.isNotBlank() } ?: "neuraldefend-kotlin/$SDK_VERSION",
                okHttpClient = okHttpClient,
                onWarning = onWarning ?: {},
            )
            return NeuroVerifyClient(config, runtime)
        }
    }

    public companion object {
        /** Default production API origin. */
        public const val PRODUCTION_URL: String = "https://deepscan.neuraldefend.com"

        /** Staging API origin, for integration testing with a staging key. */
        public const val STAGING_URL: String = "https://stage.deepscan.neuraldefend.com"

        /** Version of this SDK, also sent in the default `User-Agent`. */
        public const val SDK_VERSION: String = com.neuraldefend.kotlin.SDK_VERSION

        internal const val DEFAULT_TIMEOUT_MILLIS: Long = 120_000
        internal const val DEFAULT_RETRY_AFTER_CAP_MILLIS: Long = 60_000
        internal const val MAX_RETRIES: Int = 3

        private val NUMERIC_SECONDS = Regex("""^[+-]?(\d+(\.\d*)?|\.\d+)$""")

        /** Starts configuring a client. */
        @JvmStatic
        public fun builder(): Builder = Builder()

        /** Creates a client pinned to [STAGING_URL]. Use only with a staging credential. */
        @JvmStatic
        @JvmOverloads
        public fun staging(apiKey: String? = null): NeuroVerifyClient = Builder().apiKey(apiKey).staging().build()

        /** Creates a client pinned to [STAGING_URL] with additional options. */
        @JvmSynthetic
        public fun staging(apiKey: String?, configure: Builder.() -> Unit): NeuroVerifyClient =
            Builder().apply(configure).apply { if (apiKey != null) apiKey(apiKey) }.staging().build()
    }
}

/** Receives non-fatal media validation warnings. */
public fun interface WarningListener {
    public fun onWarning(warning: ValidationWarning)
}

/**
 * Creates a production client (or the origin set with `baseUrl`).
 *
 * ```kotlin
 * val client = NeuroVerifyClient(apiKey = key) {
 *     timeout(60.seconds)
 *     maxRetries(1)
 * }
 * ```
 */
@JvmSynthetic
public fun NeuroVerifyClient(
    apiKey: String? = null,
    configure: NeuroVerifyClient.Builder.() -> Unit = {},
): NeuroVerifyClient = NeuroVerifyClient.builder()
    .apply(configure)
    .apply { if (apiKey != null) apiKey(apiKey) }
    .build()

internal class Config(
    val apiKey: String,
    val baseUrl: String,
    val timeoutMillis: Long,
    val maxRetries: Int,
    val retryAfterCapMillis: Long,
    val userAgent: String,
    val okHttpClient: OkHttpClient?,
    val onWarning: (ValidationWarning) -> Unit,
)

/** Replaceable timing and randomness used by retry tests. */
internal class ClientRuntime(
    val sleep: suspend (Long) -> Unit,
    val random: () -> Double,
    val nowMillis: () -> Long,
) {
    companion object {
        val DEFAULT = ClientRuntime(
            sleep = { delay(it) },
            random = { Math.random() },
            nowMillis = { System.currentTimeMillis() },
        )
    }
}

private fun systemEnvironment(name: String): String? = System.getenv(name)

internal fun isAndroid(): Boolean = System.getProperty("java.vm.name").orEmpty().contains("Dalvik", ignoreCase = true) ||
    System.getProperty("java.vendor").orEmpty().contains("Android", ignoreCase = true)

private fun secondsToMillis(seconds: Double): Long = (seconds * 1000).roundToLong()

private fun transactionId(envelope: Map<String, Any?>): String? = (envelope["unique_trx_id"] as? String)?.takeIf { it.isNotEmpty() }

private fun parseHttpDate(value: String): Long? {
    for (pattern in HTTP_DATE_PATTERNS) {
        val format = SimpleDateFormat(pattern, Locale.US).apply {
            timeZone = TimeZone.getTimeZone("GMT")
            isLenient = false
        }
        try {
            return format.parse(value)?.time
        } catch (_: ParseException) {
            continue
        }
    }
    return null
}

private val HTTP_DATE_PATTERNS = listOf(
    "EEE, dd MMM yyyy HH:mm:ss zzz",
    "EEEE, dd-MMM-yy HH:mm:ss zzz",
    "EEE MMM d HH:mm:ss yyyy",
)

private fun validateBaseUrl(value: String, allowInsecure: Boolean, allowCustom: Boolean): String {
    val invalid = {
        ValidationError(
            ValidationErrorCode.INVALID_BASE_URL,
            "baseUrl must be an HTTPS origin without credentials, a path, query, or fragment.",
        )
    }
    val uri = try {
        URI(value.trim())
    } catch (_: URISyntaxException) {
        throw invalid()
    }
    val scheme = uri.scheme?.lowercase(Locale.ROOT)
    val schemeAllowed = scheme == "https" || (allowInsecure && scheme == "http")
    val path = uri.rawPath.orEmpty()
    if (!schemeAllowed || uri.host.isNullOrEmpty() || uri.rawUserInfo != null || uri.rawQuery != null ||
        uri.rawFragment != null || (path.isNotEmpty() && path != "/")
    ) {
        throw invalid()
    }
    val host = uri.host.lowercase(Locale.ROOT)
    val defaultPort = if (scheme == "https") 443 else 80
    val origin = if (uri.port == -1 || uri.port == defaultPort) "$scheme://$host" else "$scheme://$host:${uri.port}"
    if (origin != NeuroVerifyClient.PRODUCTION_URL && origin != NeuroVerifyClient.STAGING_URL && !allowCustom) {
        throw ValidationError(
            ValidationErrorCode.CUSTOM_BASE_URL_REQUIRES_OPT_IN,
            "A non-Neural Defend baseUrl requires allowCustomBaseUrl(true) because it receives the API key " +
                "and uploaded media.",
        )
    }
    return origin
}
