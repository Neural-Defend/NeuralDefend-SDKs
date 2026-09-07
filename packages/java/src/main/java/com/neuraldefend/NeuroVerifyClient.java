package com.neuraldefend;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonPrimitive;
import com.google.gson.JsonSyntaxException;
import com.google.gson.reflect.TypeToken;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.time.Duration;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ThreadLocalRandom;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okio.BufferedSink;
import okio.Okio;

/** Public NeuroVerify API client with streaming multipart uploads. */
public final class NeuroVerifyClient {
    public static final String PRODUCTION_URL = "https://deepscan.neuraldefend.com";
    public static final String STAGING_URL = "https://stage.deepscan.neuraldefend.com";

    private static final Duration DEFAULT_TIMEOUT = Duration.ofSeconds(120);
    private static final int DEFAULT_MAX_RETRIES = 3;
    private static final double MAX_RETRY_AFTER = 3600.0;
    private static final Gson GSON = new Gson();
    private static final java.lang.reflect.Type MAP_TYPE =
            new TypeToken<Map<String, Object>>() {}.getType();

    private final String baseUrl;
    private final String apiKey;
    private final int maxRetries;
    private final String userAgent;
    private final OkHttpClient httpClient;
    private final ClientOptions.Sleeper sleeper;
    private final java.util.function.DoubleSupplier random;
    private final java.util.function.Supplier<Instant> clock;

    private NeuroVerifyClient(
            String baseUrl,
            String apiKey,
            int maxRetries,
            String userAgent,
            OkHttpClient httpClient,
            ClientOptions.Sleeper sleeper,
            java.util.function.DoubleSupplier random,
            java.util.function.Supplier<Instant> clock) {
        this.baseUrl = baseUrl;
        this.apiKey = apiKey;
        this.maxRetries = maxRetries;
        this.userAgent = userAgent;
        this.httpClient = httpClient;
        this.sleeper = sleeper;
        this.random = random;
        this.clock = clock;
    }

    /** Constructs a client using options and environment fallbacks. */
    public static NeuroVerifyClient newClient(ClientOptions options) {
        Objects.requireNonNull(options, "options");
        String apiKey = options.apiKey == null ? "" : options.apiKey.strip();
        if (apiKey.isEmpty()) {
            apiKey = strip(System.getenv("NEURALDEFEND_API_KEY"));
        }
        if (apiKey.isEmpty()) {
            throw new ValidationException(
                    "api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)");
        }

        Duration timeout = options.timeout == null ? DEFAULT_TIMEOUT : options.timeout;
        if (timeout.isZero() || timeout.isNegative()) {
            throw new ValidationException("timeout must be a positive number");
        }

        int maxRetries =
                options.maxRetries == null ? DEFAULT_MAX_RETRIES : options.maxRetries;
        if (maxRetries < 0 || maxRetries > DEFAULT_MAX_RETRIES) {
            throw new ValidationException("max_retries must be an integer from 0 through 3");
        }

        String baseUrl = options.baseUrl;
        if (baseUrl == null || baseUrl.isBlank()) {
            baseUrl = System.getenv("NEURALDEFEND_BASE_URL");
        }
        if (baseUrl == null || baseUrl.isBlank()) {
            baseUrl = PRODUCTION_URL;
        }

        boolean allowHttp = options.allowHttpForTesting || options.httpClient != null;
        baseUrl = validateBaseUrl(baseUrl, allowHttp, options.allowCustomBaseUrl);

        String userAgent = options.userAgent;
        if (userAgent == null || userAgent.isBlank()) {
            userAgent = "neuraldefend-java/" + SdkVersion.VERSION;
        }

        OkHttpClient httpClient = options.httpClient;
        if (httpClient == null) {
            httpClient =
                    new OkHttpClient.Builder()
                            .followRedirects(false)
                            .followSslRedirects(false)
                            .callTimeout(timeout)
                            .build();
        }

        ClientOptions.Sleeper sleeper = options.sleeper;
        if (sleeper == null) {
            sleeper =
                    duration -> {
                        try {
                            Thread.sleep(duration.toMillis());
                        } catch (InterruptedException ex) {
                            Thread.currentThread().interrupt();
                            throw new RuntimeException(ex);
                        }
                    };
        }

        java.util.function.DoubleSupplier random = options.random;
        if (random == null) {
            random = () -> ThreadLocalRandom.current().nextDouble();
        }

        java.util.function.Supplier<Instant> clock = options.clock;
        if (clock == null) {
            clock = Instant::now;
        }

        return new NeuroVerifyClient(
                baseUrl, apiKey, maxRetries, userAgent, httpClient, sleeper, random, clock);
    }

    /** Constructs a client pinned to {@link #STAGING_URL}. */
    public static NeuroVerifyClient staging(ClientOptions options) {
        Objects.requireNonNull(options, "options");
        options.baseUrl = STAGING_URL;
        return newClient(options);
    }

    public String getBaseUrl() {
        return baseUrl;
    }

    /** Analyzes an image upload. */
    public ImageResult detectImage(Media media) {
        Media.PreparedUpload upload =
                media.prepare(Media.MediaKind.IMAGE, Media.IMAGE_MAX_BYTES, Media.IMAGE_EXTENSIONS);
        try {
            Response response = send("/detect/image", upload, null);
            try {
                return classifyImage(response);
            } finally {
                response.close();
            }
        } finally {
            upload.close();
        }
    }

    /** Analyzes a video upload. */
    public VideoResult detectVideo(Media media, VideoOptions options) {
        Objects.requireNonNull(options, "options");
        validateVideoParameter("max_frames", options.maxFrames, 100);
        validateVideoParameter("sample_rate", options.sampleRate, 0);

        Media.PreparedUpload upload =
                media.prepare(Media.MediaKind.VIDEO, Media.VIDEO_MAX_BYTES, Media.VIDEO_EXTENSIONS);
        try {
            if (!upload.isSeekable() && maxRetries != 0) {
                throw new ValidationException("non-seekable streams require max_retries=0");
            }

            HttpUrl.Builder query = null;
            if (options.maxFrames != null || options.sampleRate != null) {
                query = Objects.requireNonNull(HttpUrl.parse(baseUrl + "/detect/video")).newBuilder();
                if (options.maxFrames != null) {
                    query.addQueryParameter("max_frames", Integer.toString(options.maxFrames));
                }
                if (options.sampleRate != null) {
                    query.addQueryParameter("sample_rate", Integer.toString(options.sampleRate));
                }
            }

            Response response = send("/detect/video", upload, query);
            try {
                return classifyVideo(response);
            } finally {
                response.close();
            }
        } finally {
            upload.close();
        }
    }

    private static String strip(String value) {
        return value == null ? "" : value.strip();
    }

    private static String validateBaseUrl(
            String value, boolean allowHttp, boolean allowCustomBaseUrl) {
        value = value.strip();
        if (value.isEmpty()) {
            throw new ValidationException("base_url must be a non-empty URL");
        }
        URI parsed;
        try {
            parsed = new URI(value);
        } catch (URISyntaxException ex) {
            throw new ValidationException("base_url is invalid");
        }
        if (parsed.getScheme() == null
                || parsed.getHost() == null
                || parsed.getScheme().isBlank()
                || parsed.getHost().isBlank()) {
            throw new ValidationException("base_url is invalid");
        }
        if (parsed.getRawQuery() != null
                || parsed.getFragment() != null
                || parsed.getUserInfo() != null) {
            throw new ValidationException(
                    "base_url must be an origin URL without credentials, path, query, or fragment");
        }
        String path = parsed.getPath();
        if (path != null && !path.isEmpty() && !"/".equals(path)) {
            throw new ValidationException(
                    "base_url must be an origin URL without credentials, path, query, or fragment");
        }
        String scheme = parsed.getScheme().toLowerCase(Locale.ROOT);
        if (!"https".equals(scheme) && !(allowHttp && "http".equals(scheme))) {
            throw new ValidationException("base_url must use HTTPS");
        }
        String origin = scheme + "://" + parsed.getHost();
        if (parsed.getPort() > 0) {
            origin += ":" + parsed.getPort();
        }
        if (!PRODUCTION_URL.equals(origin)
                && !STAGING_URL.equals(origin)
                && !allowCustomBaseUrl
                && !allowHttp) {
            throw new ValidationException(
                    "a non-Neural Defend base_url requires allow_custom_base_url=true because it"
                            + " receives the API key and uploaded media");
        }
        return origin;
    }

    private static void validateVideoParameter(String name, Integer value, int upper) {
        if (value == null) {
            return;
        }
        if (value < 1) {
            throw new ValidationException(name + " must be an integer of at least 1");
        }
        if (upper > 0 && value > upper) {
            throw new ValidationException(name + " must be at most " + upper);
        }
    }

    private Response send(
            String path, Media.PreparedUpload upload, HttpUrl.Builder queryBuilder) {
        if (!upload.isSeekable() && maxRetries != 0) {
            throw new ValidationException("non-seekable streams require max_retries=0");
        }

        String target = baseUrl + path;
        if (queryBuilder != null) {
            target = queryBuilder.build().toString();
        }

        for (int attempt = 0; attempt <= maxRetries; attempt++) {
            Request request = buildRequest(target, upload);
            try {
                Response response = httpClient.newCall(request).execute();
                int code = response.code();
                if ((code != 429 && code != 500 && code != 503) || attempt >= maxRetries) {
                    return response;
                }
                Duration delay = retryDelay(response, attempt);
                response.close();
                sleeper.sleep(delay);
            } catch (IOException ex) {
                if (isTimeout(ex)) {
                    throw new TimeoutException(redact(ex.getMessage()));
                }
                throw new NetworkException(redact(ex.getMessage()));
            }
        }
        throw new ValidationException("unreachable retry state");
    }

    private Request buildRequest(String target, Media.PreparedUpload upload) {
        MediaType partType = MediaType.parse(Media.mimeForFilename(upload.filename));
        RequestBody fileBody =
                new RequestBody() {
                    @Override
                    public MediaType contentType() {
                        return partType;
                    }

                    @Override
                    public void writeTo(BufferedSink sink) throws IOException {
                        try (InputStream input = upload.openAttempt()) {
                            sink.writeAll(Okio.source(input));
                        } catch (ValidationException ex) {
                            throw new IOException(ex.getDetail(), ex);
                        }
                    }
                };

        RequestBody body =
                new MultipartBody.Builder()
                        .setType(MultipartBody.FORM)
                        .addFormDataPart("file", upload.filename, fileBody)
                        .build();

        return new Request.Builder()
                .url(target)
                .post(body)
                .header("Accept", "application/json")
                .header("User-Agent", userAgent)
                .header("x-api-key", apiKey)
                .build();
    }

    private Duration retryDelay(Response response, int attempt) {
        int code = response.code();
        if (code == 429) {
            Double parsed = parseRetryAfter(response.header("Retry-After"));
            if (parsed != null) {
                return Duration.ofMillis((long) (parsed * 1000.0));
            }
            long backoff = (long) Math.min(Math.pow(2, attempt), 4) * 1000L;
            return Duration.ofMillis(backoff);
        }
        double base = Math.min(Math.pow(2, attempt), 4);
        double jitter = Math.max(0, Math.min(1, random.getAsDouble())) * base * 0.25;
        return Duration.ofMillis((long) ((base + jitter) * 1000.0));
    }

    private Double parseRetryAfter(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        value = value.strip();
        try {
            double seconds = Double.parseDouble(value);
            if (Double.isInfinite(seconds) || Double.isNaN(seconds)) {
                return null;
            }
            return Math.max(0, Math.min(MAX_RETRY_AFTER, seconds));
        } catch (NumberFormatException ignored) {
            // Fall through to HTTP-date parsing.
        }
        try {
            Instant when = ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant();
            double seconds = Duration.between(clock.get(), when).toMillis() / 1000.0;
            if (Double.isInfinite(seconds) || Double.isNaN(seconds)) {
                return null;
            }
            return Math.max(0, Math.min(MAX_RETRY_AFTER, seconds));
        } catch (DateTimeParseException ex) {
            return null;
        }
    }

    private ImageResult classifyImage(Response response) {
        raiseSimpleHttpErrors(response);
        int code = response.code();
        if (code != 200 && code != 400 && code != 500 && code != 503) {
            throw unknownHttpError(response);
        }

        Map<String, Object> score;
        try {
            score = parseEnvelope(response, "unified_face_authenticity_score");
        } catch (ProtocolException ex) {
            if (code == 500 || code == 503) {
                throw new ServerException(
                        "HTTP " + code, code, requestId(response, null), null);
            }
            throw ex;
        }

        ImageResult result;
        try {
            result = parseImageResult(score, code);
        } catch (ProtocolException ex) {
            if (code == 500 || code == 503) {
                throw new ServerException(
                        "HTTP " + code, code, requestId(response, null), null);
            }
            throw ex;
        }

        raiseForEnvelopeStatus(response, score, result.status, result.message);
        if (code == 500 || code == 503) {
            throw new ServerException(
                    redact(result.message),
                    code,
                    requestId(response, score),
                    sanitizedEnvelope(score));
        }
        if (code == 400 && !"rejected".equals(result.status)) {
            throw new HttpException(
                    "HTTP 400 response was not a rejection",
                    400,
                    requestId(response, score));
        }
        return result;
    }

    private VideoResult classifyVideo(Response response) {
        raiseSimpleHttpErrors(response);
        int code = response.code();
        if (code != 200 && code != 400 && code != 500 && code != 503) {
            throw unknownHttpError(response);
        }

        Map<String, Object> score;
        try {
            score = parseEnvelope(response, "unified_video_authenticity_score");
        } catch (ProtocolException ex) {
            if (code == 500 || code == 503) {
                throw new ServerException(
                        "HTTP " + code, code, requestId(response, null), null);
            }
            throw ex;
        }

        VideoResult result;
        try {
            result = parseVideoResult(score, code);
        } catch (ProtocolException ex) {
            if (code == 500 || code == 503) {
                throw new ServerException(
                        "HTTP " + code, code, requestId(response, null), null);
            }
            throw ex;
        }

        raiseForEnvelopeStatus(response, score, result.status, result.videoMessage);
        if (code == 500 || code == 503) {
            throw new ServerException(
                    redact(result.videoMessage),
                    code,
                    requestId(response, score),
                    sanitizedEnvelope(score));
        }
        if (code == 400 && !"rejected".equals(result.status)) {
            throw new HttpException(
                    "HTTP 400 response was not a rejection",
                    400,
                    requestId(response, score));
        }
        return result;
    }

    private void raiseSimpleHttpErrors(Response response) {
        int code = response.code();
        switch (code) {
            case 401 -> throw new AuthenticationException(responseDetail(response), requestId(response, null));
            case 403 -> throw new ScopeException(responseDetail(response), requestId(response, null));
            case 429 -> throw new RateLimitException(
                    responseDetail(response),
                    requestId(response, null),
                    parseRetryAfter(response.header("Retry-After")),
                    response.header("X-RateLimit-Limit"),
                    response.header("X-RateLimit-Remaining"),
                    response.header("X-RateLimit-Reset"));
            default -> {}
        }
    }

    private Map<String, Object> parseEnvelope(Response response, String envelopeName) {
        String raw;
        try {
            raw = response.body() == null ? "" : response.body().string();
        } catch (IOException ex) {
            throw new ProtocolException(
                    "response body is not valid JSON",
                    response.code(),
                    requestId(response, null));
        }
        JsonElement root;
        try {
            root = JsonParser.parseString(raw);
        } catch (JsonSyntaxException ex) {
            throw new ProtocolException(
                    "response body is not valid JSON",
                    response.code(),
                    requestId(response, null));
        }
        if (!root.isJsonObject()) {
            throw new ProtocolException(
                    "response body is not valid JSON",
                    response.code(),
                    requestId(response, null));
        }
        Map<String, Object> decoded = jsonObjectToMap(root.getAsJsonObject());
        Object scoreValue = decoded.get(envelopeName);
        if (!(scoreValue instanceof Map<?, ?> scoreMap)) {
            throw new ProtocolException(
                    "response is missing the \"" + envelopeName + "\" envelope",
                    response.code(),
                    requestId(response, null));
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> score = (Map<String, Object>) scoreMap;
        return score;
    }

    private static Map<String, Object> jsonObjectToMap(JsonObject object) {
        Map<String, Object> map = new HashMap<>();
        for (Map.Entry<String, JsonElement> entry : object.entrySet()) {
            map.put(entry.getKey(), jsonElementToValue(entry.getValue()));
        }
        return map;
    }

    private static Object jsonElementToValue(JsonElement element) {
        if (element == null || element instanceof JsonNull) {
            return null;
        }
        if (element.isJsonObject()) {
            return jsonObjectToMap(element.getAsJsonObject());
        }
        if (element.isJsonArray()) {
            JsonArray array = element.getAsJsonArray();
            List<Object> values = new ArrayList<>(array.size());
            for (JsonElement item : array) {
                values.add(jsonElementToValue(item));
            }
            return values;
        }
        JsonPrimitive primitive = element.getAsJsonPrimitive();
        if (primitive.isBoolean()) {
            return primitive.getAsBoolean();
        }
        if (primitive.isString()) {
            return primitive.getAsString();
        }
        if (primitive.isNumber()) {
            return primitive.getAsDouble();
        }
        return null;
    }

    private ImageResult parseImageResult(Map<String, Object> score, int httpStatus) {
        String uniqueTrxId = requiredString(score, "unique_trx_id", httpStatus);
        String filename = requiredString(score, "filename", httpStatus);
        String contentType = requiredString(score, "content_type", httpStatus);
        String status = requiredString(score, "status", httpStatus);
        int statusCode = requiredInt(score, "status_code", httpStatus);
        boolean billable = parseBillable(score, httpStatus);
        String message = requiredString(score, "message", httpStatus);
        Double riskScore = optionalFloat(score, "risk_score", httpStatus);
        String riskLevel = optionalString(score, "risk_level", httpStatus);
        List<String> signals = parseSignals(score, httpStatus);
        return new ImageResult(
                uniqueTrxId,
                filename,
                contentType,
                status,
                statusCode,
                billable,
                riskScore,
                riskLevel,
                message,
                signals,
                sanitizedEnvelope(score));
    }

    private VideoResult parseVideoResult(Map<String, Object> score, int httpStatus) {
        String uniqueTrxId = requiredString(score, "unique_trx_id", httpStatus);
        String filename = requiredString(score, "filename", httpStatus);
        String contentType = requiredString(score, "content_type", httpStatus);
        String status = requiredString(score, "status", httpStatus);
        int statusCode = requiredInt(score, "status_code", httpStatus);
        boolean billable = parseBillable(score, httpStatus);
        String videoMessage = requiredString(score, "video_message", httpStatus);
        Double videoRiskScore = optionalFloat(score, "video_risk_score", httpStatus);
        String videoRiskLevel = optionalString(score, "video_risk_level", httpStatus);
        Double audioRiskScore = optionalFloat(score, "audio_risk_score", httpStatus);
        String audioRiskLevel = optionalString(score, "audio_risk_level", httpStatus);
        String audioMessage = optionalString(score, "audio_message", httpStatus);
        List<String> signals = parseSignals(score, httpStatus);
        return new VideoResult(
                uniqueTrxId,
                filename,
                contentType,
                status,
                statusCode,
                billable,
                videoRiskScore,
                videoRiskLevel,
                videoMessage,
                audioRiskScore,
                audioRiskLevel,
                audioMessage,
                signals,
                sanitizedEnvelope(score));
    }

    private void raiseForEnvelopeStatus(
            Response response, Map<String, Object> score, String status, String message) {
        if ("error".equals(status)) {
            throw new ServerException(
                    redact(message),
                    response.code(),
                    requestId(response, score),
                    sanitizedEnvelope(score));
        }
    }

    private String requiredString(Map<String, Object> score, String name, int httpStatus) {
        Object value = score.get(name);
        if (!(value instanceof String stringValue)) {
            throw new ProtocolException(
                    "response field \"" + name + "\" must be a string", httpStatus, "");
        }
        return stringValue;
    }

    private int requiredInt(Map<String, Object> score, String name, int httpStatus) {
        Object value = score.get(name);
        if (value instanceof Number number) {
            double numeric = number.doubleValue();
            if (numeric != Math.rint(numeric)) {
                throw new ProtocolException(
                        "response field \"" + name + "\" must be an integer", httpStatus, "");
            }
            return (int) numeric;
        }
        throw new ProtocolException(
                "response field \"" + name + "\" must be an integer", httpStatus, "");
    }

    private String optionalString(Map<String, Object> score, String name, int httpStatus) {
        if (!score.containsKey(name)) {
            throw new ProtocolException(
                    "response is missing required field \"" + name + "\"", httpStatus, "");
        }
        Object value = score.get(name);
        if (value == null) {
            return null;
        }
        if (!(value instanceof String stringValue)) {
            throw new ProtocolException(
                    "response field \"" + name + "\" must be a string or null", httpStatus, "");
        }
        return stringValue;
    }

    private Double optionalFloat(Map<String, Object> score, String name, int httpStatus) {
        if (!score.containsKey(name)) {
            throw new ProtocolException(
                    "response is missing required field \"" + name + "\"", httpStatus, "");
        }
        Object value = score.get(name);
        if (value == null) {
            return null;
        }
        if (!(value instanceof Number number)) {
            throw new ProtocolException(
                    "response field \"" + name + "\" must be numeric or null", httpStatus, "");
        }
        double numeric = number.doubleValue();
        if (!isFinite(numeric) || numeric < 0.1 || numeric > 10.0) {
            throw new ProtocolException(
                    "response field \"" + name + "\" must be from 0.1 through 10.0 or null",
                    httpStatus,
                    "");
        }
        return numeric;
    }

    private boolean parseBillable(Map<String, Object> score, int httpStatus) {
        Object value = score.get("billable");
        if (!"Y".equals(value) && !"N".equals(value)) {
            throw new ProtocolException(
                    "response field 'billable' must be exactly 'Y' or 'N'", httpStatus, "");
        }
        return "Y".equals(value);
    }

    private List<String> parseSignals(Map<String, Object> score, int httpStatus) {
        Object raw = score.get("ai_threat_signals");
        if (raw == null) {
            return List.of();
        }
        if (!(raw instanceof List<?> items)) {
            throw new ProtocolException(
                    "response field 'ai_threat_signals' must be an array of strings",
                    httpStatus,
                    "");
        }
        List<String> out = new ArrayList<>(items.size());
        for (Object item : items) {
            if (!(item instanceof String stringValue)) {
                throw new ProtocolException(
                        "response field 'ai_threat_signals' must be an array of strings",
                        httpStatus,
                        "");
            }
            out.add(stringValue);
        }
        return out;
    }

    private HttpException unknownHttpError(Response response) {
        return new HttpException(
                responseDetail(response), response.code(), requestId(response, null));
    }

    private String responseDetail(Response response) {
        String detail = "HTTP " + response.code();
        if (response.body() == null) {
            return redact(detail);
        }
        try {
            String raw = response.body().string();
            Map<String, Object> decoded = GSON.fromJson(raw, MAP_TYPE);
            if (decoded != null && decoded.get("detail") instanceof String value) {
                detail = value;
            }
        } catch (IOException | JsonSyntaxException ignored) {
            // Keep HTTP status detail.
        }
        return redact(detail);
    }

    private String requestId(Response response, Map<String, Object> score) {
        String header = response.header("X-Request-ID");
        if (header != null && !header.isBlank()) {
            return header;
        }
        if (score != null) {
            Object value = score.get("unique_trx_id");
            if (value instanceof String stringValue && !stringValue.isBlank()) {
                return stringValue;
            }
        }
        return "";
    }

    private String redact(String value) {
        if (value == null) {
            return "";
        }
        return value.replace(apiKey, "[REDACTED]");
    }

    private Map<String, Object> sanitizedEnvelope(Map<String, Object> value) {
        return sanitizeMap(value);
    }

    private Map<String, Object> sanitizeMap(Map<String, Object> value) {
        Map<String, Object> out = new HashMap<>();
        for (Map.Entry<String, Object> entry : value.entrySet()) {
            out.put(entry.getKey(), sanitizeValue(entry.getValue()));
        }
        return out;
    }

    private Object sanitizeValue(Object item) {
        if (item instanceof String stringValue) {
            return stringValue.replace(apiKey, "[REDACTED]");
        }
        if (item instanceof Map<?, ?> mapValue) {
            Map<String, Object> nested = new HashMap<>();
            for (Map.Entry<?, ?> entry : mapValue.entrySet()) {
                nested.put(String.valueOf(entry.getKey()), sanitizeValue(entry.getValue()));
            }
            return nested;
        }
        if (item instanceof List<?> listValue) {
            List<Object> out = new ArrayList<>(listValue.size());
            for (Object nested : listValue) {
                out.add(sanitizeValue(nested));
            }
            return out;
        }
        return item;
    }

    private static boolean isFinite(double value) {
        return !Double.isInfinite(value) && !Double.isNaN(value);
    }

    private static boolean isTimeout(IOException ex) {
        String message = ex.getMessage();
        if (message != null && message.toLowerCase(Locale.ROOT).contains("timeout")) {
            return true;
        }
        Throwable cause = ex.getCause();
        return cause instanceof IOException && isTimeout((IOException) cause);
    }
}
