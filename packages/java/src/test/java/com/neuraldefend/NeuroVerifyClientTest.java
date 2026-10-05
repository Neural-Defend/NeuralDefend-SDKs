package com.neuraldefend;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import okhttp3.OkHttpClient;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import okhttp3.mockwebserver.SocketPolicy;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

final class NeuroVerifyClientTest {
    private static final Path FIXTURES_ROOT =
            Path.of("..", "..", "tests", "fixtures").toAbsolutePath().normalize();
    private static final Gson GSON = new Gson();
    private static final java.lang.reflect.Type MAP_TYPE =
            new TypeToken<Map<String, Object>>() {}.getType();

    private MockWebServer server;
    private final List<Duration> sleeps = new ArrayList<>();

    @BeforeEach
    void setUp() throws IOException {
        server = new MockWebServer();
        server.start();
        sleeps.clear();
    }

    @AfterEach
    void tearDown() throws IOException {
        server.shutdown();
    }

    @Test
    void retries500ThreeTimesWithBackoffAndRewinds() throws Exception {
        Map<String, Object> failure = TestFixtures.loadCase("image/documented/internal-error-500.json");
        Map<String, Object> success = TestFixtures.loadCase("image/documented/low-risk.json");
        final int[] calls = {0};

        server.setDispatcher(
                new okhttp3.mockwebserver.Dispatcher() {
                    @Override
                    public MockResponse dispatch(RecordedRequest request) {
                        calls[0]++;
                        Map<String, Object> caseData = calls[0] > 3 ? success : failure;
                        return buildMockResponse(TestFixtures.responseFromCase(caseData));
                    }
                });

        ClientOptions options = testOptions();
        options.maxRetries = 3;
        options.random = () -> 0.0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        byte[] payload = "streamed-payload".getBytes(StandardCharsets.UTF_8);
        ByteArrayInputStream stream = new ByteArrayInputStream(payload);
        stream.mark(Integer.MAX_VALUE);
        ImageResult result =
                client.detectImage(Media.inputStreamMedia("retry.jpg", stream, payload.length));

        assertTrue(result.scored());
        assertEquals(4, calls[0]);
        assertEquals(
                List.of(Duration.ofSeconds(1), Duration.ofSeconds(2), Duration.ofSeconds(4)),
                sleeps);
    }

    @Test
    void honors429RetryAfterThenSucceeds() throws Exception {
        Map<String, Object> limited = TestFixtures.loadCase("image/synthetic/rate-limited-429.json");
        Map<String, Object> success = TestFixtures.loadCase("image/documented/low-risk.json");
        final int[] calls = {0};

        server.setDispatcher(
                new okhttp3.mockwebserver.Dispatcher() {
                    @Override
                    public MockResponse dispatch(RecordedRequest request) {
                        calls[0]++;
                        Map<String, Object> caseData = calls[0] > 1 ? success : limited;
                        return buildMockResponse(TestFixtures.responseFromCase(caseData));
                    }
                });

        ClientOptions options = testOptions();
        options.maxRetries = 1;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        ImageResult result =
                client.detectImage(
                        Media.bytesMedia("x.jpg", "x".getBytes(StandardCharsets.UTF_8)));
        assertTrue(result.scored());
        assertEquals(2, calls[0]);
        assertEquals(List.of(Duration.ofSeconds(60)), sleeps);
    }

    @Test
    void environmentFallback() {
        ClientOptions options = new ClientOptions();
        options.apiKey = "environment-key";
        options.baseUrl = "https://environment.local";
        options.allowCustomBaseUrl = true;
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);
        assertTrue(client.getBaseUrl().contains("environment.local"));
    }

    @Test
    void stagingIsDeterministic() {
        ClientOptions options = new ClientOptions();
        options.apiKey = "key";
        options.baseUrl = "https://wrong.local";
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.staging(options);
        assertEquals(NeuroVerifyClient.STAGING_URL, client.getBaseUrl());
    }

    @Test
    void stagingDoesNotMutateCallerOptions() {
        ClientOptions options = new ClientOptions();
        options.apiKey = "key";
        options.baseUrl = "https://wrong.local";
        options.allowCustomBaseUrl = true;
        options.maxRetries = 0;
        options.userAgent = "custom-agent";
        NeuroVerifyClient client = NeuroVerifyClient.staging(options);
        assertEquals(NeuroVerifyClient.STAGING_URL, client.getBaseUrl());
        assertEquals("https://wrong.local", options.baseUrl);
        assertEquals("custom-agent", options.userAgent);
        assertEquals(0, options.maxRetries);
    }

    @Test
    void customHttpClientDoesNotImplicitlyAllowInsecureOrigins() {
        OkHttpClient httpClient = new OkHttpClient();

        ClientOptions http = new ClientOptions();
        http.apiKey = "key";
        http.baseUrl = "http://127.0.0.1:9";
        http.httpClient = httpClient;
        http.maxRetries = 0;
        ValidationException httpError =
                assertThrows(ValidationException.class, () -> NeuroVerifyClient.newClient(http));
        assertTrue(httpError.getDetail().contains("HTTPS"), httpError.getDetail());

        ClientOptions customHost = new ClientOptions();
        customHost.apiKey = "key";
        customHost.baseUrl = "https://api.example.com";
        customHost.httpClient = httpClient;
        customHost.maxRetries = 0;
        ValidationException hostError =
                assertThrows(ValidationException.class, () -> NeuroVerifyClient.newClient(customHost));
        assertTrue(hostError.getDetail().contains("allow_custom_base_url"), hostError.getDetail());

        ClientOptions allowedHttp = new ClientOptions();
        allowedHttp.apiKey = "key";
        allowedHttp.baseUrl = "http://127.0.0.1:9";
        allowedHttp.allowHttpForTesting = true;
        allowedHttp.maxRetries = 0;
        assertEquals("http://127.0.0.1:9", NeuroVerifyClient.newClient(allowedHttp).getBaseUrl());
    }

    @Test
    void officialOriginsAreCanonicalizedAndDecoratedUrlsAreRejected() {
        ClientOptions mixedCase = new ClientOptions();
        mixedCase.apiKey = "key";
        mixedCase.baseUrl = "HTTPS://Deepscan.NeuralDefend.com:443/./";
        mixedCase.maxRetries = 0;
        assertEquals(
                NeuroVerifyClient.PRODUCTION_URL, NeuroVerifyClient.newClient(mixedCase).getBaseUrl());

        ClientOptions stagingPort = new ClientOptions();
        stagingPort.apiKey = "key";
        stagingPort.baseUrl = "https://Stage.Deepscan.NeuralDefend.com:443/";
        stagingPort.maxRetries = 0;
        assertEquals(
                NeuroVerifyClient.STAGING_URL, NeuroVerifyClient.newClient(stagingPort).getBaseUrl());

        for (String badUrl :
                List.of(
                        "https://user:pass@deepscan.neuraldefend.com",
                        "https://deepscan.neuraldefend.com?x=1",
                        "https://deepscan.neuraldefend.com#frag",
                        "https://deepscan.neuraldefend.com/v1",
                        "http://deepscan.neuraldefend.com")) {
            ClientOptions options = new ClientOptions();
            options.apiKey = "key";
            options.baseUrl = badUrl;
            options.maxRetries = 0;
            assertThrows(
                    ValidationException.class, () -> NeuroVerifyClient.newClient(options), badUrl);
        }
    }

    @Test
    void customBaseUrlRequiresExplicitOptIn() {
        ClientOptions denied = new ClientOptions();
        denied.apiKey = "key";
        denied.baseUrl = "https://api.example.com";
        assertThrows(ValidationException.class, () -> NeuroVerifyClient.newClient(denied));

        ClientOptions allowed = new ClientOptions();
        allowed.apiKey = "key";
        allowed.baseUrl = "https://api.example.com";
        allowed.allowCustomBaseUrl = true;
        allowed.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(allowed);
        assertTrue(client.getBaseUrl().contains("api.example.com"));
    }

    @Test
    void constructorValidation() {
        assertValidation(new ClientOptions(), "api_key");
        ClientOptions timeout = new ClientOptions();
        timeout.apiKey = "key";
        timeout.timeout = Duration.ofSeconds(-1);
        assertValidation(timeout, "timeout");
        ClientOptions lowRetries = new ClientOptions();
        lowRetries.apiKey = "key";
        lowRetries.maxRetries = -1;
        assertValidation(lowRetries, "max_retries");
        ClientOptions highRetries = new ClientOptions();
        highRetries.apiKey = "key";
        highRetries.maxRetries = 4;
        assertValidation(highRetries, "max_retries");
        ClientOptions badOrigin = new ClientOptions();
        badOrigin.apiKey = "key";
        badOrigin.baseUrl = "https://example.com/api";
        assertValidation(badOrigin, "origin");
    }

    @Test
    void videoQueryParameters() throws Exception {
        Map<String, Object> success = TestFixtures.loadCase("video/documented/both-low.json");
        server.setDispatcher(
                new okhttp3.mockwebserver.Dispatcher() {
                    @Override
                    public MockResponse dispatch(RecordedRequest request) {
                        assertEquals("100", request.getRequestUrl().queryParameter("max_frames"));
                        assertEquals("1", request.getRequestUrl().queryParameter("sample_rate"));
                        return buildMockResponse(TestFixtures.responseFromCase(success));
                    }
                });

        ClientOptions options = testOptions();
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);
        VideoOptions videoOptions = new VideoOptions();
        videoOptions.maxFrames = 100;
        videoOptions.sampleRate = 1;
        VideoResult result =
                client.detectVideo(
                        Media.bytesMedia("x.mp4", "x".getBytes(StandardCharsets.UTF_8)),
                        videoOptions);
        assertTrue(result.scored());
    }

    @Test
    void pathValidationAndStreaming() throws Exception {
        Path dir = Files.createTempDirectory("neuraldefend-java-test");
        Path empty = dir.resolve("empty.jpg");
        Files.write(empty, new byte[0]);
        Path folder = dir.resolve("folder.jpg");
        Files.createDirectory(folder);
        Path valid = dir.resolve("valid.jpg");
        Files.write(valid, "path-content".getBytes(StandardCharsets.UTF_8));

        Map<String, Object> success = TestFixtures.loadCase("image/documented/low-risk.json");
        List<byte[]> bodies = new ArrayList<>();
        server.setDispatcher(
                new okhttp3.mockwebserver.Dispatcher() {
                    @Override
                    public MockResponse dispatch(RecordedRequest request) {
                        bodies.add(request.getBody().readByteArray());
                        return buildMockResponse(TestFixtures.responseFromCase(success));
                    }
                });

        ClientOptions options = testOptions();
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        for (Path invalid : List.of(empty, folder, dir.resolve("missing.jpg"))) {
            assertThrows(
                    ValidationException.class, () -> client.detectImage(Media.fileMedia(invalid)));
        }

        ImageResult result = client.detectImage(Media.fileMedia(valid));
        assertTrue(result.scored());
        assertFalse(bodies.isEmpty());
        assertTrue(new String(bodies.get(0), StandardCharsets.UTF_8).contains("path-content"));
    }

    @Test
    void nonSeekableRequiresRetriesDisabled() {
        ClientOptions options = testOptions();
        options.maxRetries = 3;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);
        NonSeekableInputStream stream = new NonSeekableInputStream("x".getBytes(StandardCharsets.UTF_8));
        ValidationException error =
                assertThrows(
                        ValidationException.class,
                        () ->
                                client.detectImage(
                                        Media.inputStreamMedia("x.jpg", stream, -1)));
        assertTrue(error.getDetail().contains("max_retries=0"));
    }

    @Test
    void deterministicMimeForDocumentedFormats() {
        assertEquals("image/jpeg", Media.mimeForFilename("photo.jpg"));
        assertEquals("image/heif", Media.mimeForFilename("photo.heif"));
        assertEquals("video/mp4", Media.mimeForFilename("clip.mp4"));
        assertEquals("application/octet-stream", Media.mimeForFilename("unknown.xyz"));
    }

    @Test
    void errorEnvelopeOnHttp200RaisesServerError() throws Exception {
        Map<String, Object> caseData = TestFixtures.loadCase("image/documented/internal-error-500.json");
        caseData.put("http_status", 200);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) caseData.get("body");
        @SuppressWarnings("unchecked")
        Map<String, Object> score =
                (Map<String, Object>) body.get("unified_face_authenticity_score");
        score.put("message", "failed for secret-test-key");
        score.put("future", Map.of("echo", "secret-test-key"));

        server.enqueue(buildMockResponse(TestFixtures.responseFromCase(caseData)));
        ClientOptions options = testOptions();
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        ServerException error =
                assertThrows(
                        ServerException.class,
                        () ->
                                client.detectImage(
                                        Media.bytesMedia(
                                                "x.jpg", "x".getBytes(StandardCharsets.UTF_8))));
        assertFalse(error.getMessage().contains("secret-test-key"));
        assertFalse(String.valueOf(error.getEnvelope()).contains("secret-test-key"));
        assertTrue(String.valueOf(error.getEnvelope()).contains("[REDACTED]"));
    }

    @Test
    void customHttpClientDoesNotFollowRedirects() throws Exception {
        Map<String, Object> success = TestFixtures.loadCase("image/documented/low-risk.json");
        server.enqueue(
                new MockResponse()
                        .setResponseCode(302)
                        .addHeader("Location", server.url("/detect/image").toString()));
        server.enqueue(buildMockResponse(TestFixtures.responseFromCase(success)));

        ClientOptions options = testOptions();
        options.maxRetries = 0;
        options.httpClient =
                new OkHttpClient.Builder().followRedirects(true).followSslRedirects(true).build();
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        HttpException error =
                assertThrows(
                        HttpException.class,
                        () ->
                                client.detectImage(
                                        Media.bytesMedia(
                                                "x.jpg", "x".getBytes(StandardCharsets.UTF_8))));
        assertEquals(302, error.getStatusCode());
        assertEquals(1, server.getRequestCount());
    }

    @Test
    void customHttpClientHonorsConfiguredTimeout() {
        server.enqueue(new MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE));
        ClientOptions options = testOptions();
        options.maxRetries = 0;
        options.timeout = Duration.ofMillis(400);
        options.httpClient =
                new OkHttpClient.Builder()
                        .readTimeout(Duration.ofSeconds(30))
                        .callTimeout(Duration.ofSeconds(30))
                        .build();
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        assertTimeoutPreemptively(
                Duration.ofSeconds(3),
                () ->
                        assertThrows(
                                TimeoutException.class,
                                () ->
                                        client.detectImage(
                                                Media.bytesMedia(
                                                        "x.jpg",
                                                        "x".getBytes(StandardCharsets.UTF_8)))));
    }

    @Test
    void callerStreamsStayOpenAndRewindFailuresStayValidationErrors() throws Exception {
        Map<String, Object> success = TestFixtures.loadCase("image/documented/low-risk.json");
        server.enqueue(buildMockResponse(TestFixtures.responseFromCase(success)));
        ClientOptions options = testOptions();
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);

        TrackingStream image = new TrackingStream("image-bytes".getBytes(StandardCharsets.UTF_8));
        ImageResult imageResult =
                client.detectImage(Media.inputStreamMedia("x.jpg", image, -1));
        assertTrue(imageResult.scored());
        assertFalse(image.closed);

        Map<String, Object> videoSuccess = TestFixtures.loadCase("video/documented/both-low.json");
        server.enqueue(buildMockResponse(TestFixtures.responseFromCase(videoSuccess)));
        TrackingStream video = new TrackingStream("video-bytes".getBytes(StandardCharsets.UTF_8));
        VideoResult videoResult =
                client.detectVideo(
                        Media.inputStreamMedia("x.mp4", video, -1), new VideoOptions());
        assertTrue(videoResult.scored());
        assertFalse(video.closed);

        TrackingStream rejected = new TrackingStream("x".getBytes(StandardCharsets.UTF_8));
        ClientOptions retrying = testOptions();
        retrying.maxRetries = 3;
        NeuroVerifyClient retryClient = NeuroVerifyClient.newClient(retrying);
        ValidationException error =
                assertThrows(
                        ValidationException.class,
                        () ->
                                retryClient.detectVideo(
                                        Media.inputStreamMedia("x.mp4", rejected, -1),
                                        new VideoOptions()));
        assertTrue(error.getDetail().contains("max_retries=0"));
        assertFalse(rejected.closed);

        server.enqueue(buildMockResponse(TestFixtures.responseFromCase(success)));
        ClientOptions rewindOptions = testOptions();
        rewindOptions.maxRetries = 1;
        NeuroVerifyClient rewindClient = NeuroVerifyClient.newClient(rewindOptions);
        ResetOnceStream flaky = new ResetOnceStream("payload".getBytes(StandardCharsets.UTF_8));
        ValidationException rewind =
                assertThrows(
                        ValidationException.class,
                        () ->
                                rewindClient.detectImage(
                                        Media.inputStreamMedia("x.jpg", flaky, flaky.available())));
        assertTrue(rewind.getDetail().contains("rewound"), rewind.getDetail());
    }

    @Test
    void retryAfterHttpDateIsCappedWithoutJitter() throws Exception {
        Map<String, Object> limited = TestFixtures.loadCase("image/synthetic/rate-limited-429.json");
        Map<String, Object> success = TestFixtures.loadCase("image/documented/low-risk.json");
        @SuppressWarnings("unchecked")
        Map<String, Object> headers = (Map<String, Object>) limited.get("headers");
        headers.put("retry-after", "Sun, 26 Jul 2026 13:00:00 GMT");
        final int[] calls = {0};
        server.setDispatcher(
                new okhttp3.mockwebserver.Dispatcher() {
                    @Override
                    public MockResponse dispatch(RecordedRequest request) {
                        calls[0]++;
                        Map<String, Object> caseData = calls[0] > 1 ? success : limited;
                        return buildMockResponse(TestFixtures.responseFromCase(caseData));
                    }
                });

        ClientOptions options = testOptions();
        options.maxRetries = 1;
        options.random = () -> 1.0;
        options.clock = () -> Instant.parse("2026-07-26T12:00:00Z");
        NeuroVerifyClient client = NeuroVerifyClient.newClient(options);
        ImageResult result =
                client.detectImage(
                        Media.bytesMedia("x.jpg", "x".getBytes(StandardCharsets.UTF_8)));
        assertTrue(result.scored());
        assertEquals(List.of(Duration.ofSeconds(3600)), sleeps);
    }

    private ClientOptions testOptions() {
        ClientOptions options = new ClientOptions();
        options.apiKey = "secret-test-key";
        options.baseUrl = server.url("/").toString().replaceAll("/$", "");
        options.allowCustomBaseUrl = true;
        options.allowHttpForTesting = true;
        options.sleeper = sleeps::add;
        options.httpClient =
                new okhttp3.OkHttpClient.Builder()
                        .followRedirects(false)
                        .followSslRedirects(false)
                        .build();
        return options;
    }

    private void assertValidation(ClientOptions options, String fragment) {
        ValidationException error =
                assertThrows(ValidationException.class, () -> NeuroVerifyClient.newClient(options));
        assertTrue(error.getDetail().contains(fragment), error.getDetail());
    }

    private Map<String, Object> loadCase(String relativePath) throws IOException {
        return TestFixtures.loadCase(relativePath);
    }

    private MockResponse buildMockResponse(TestFixtures.ResponseParts parts) {
        MockResponse response = new MockResponse().setResponseCode(parts.status());
        for (Map.Entry<String, String> header : parts.headers().entrySet()) {
            response.addHeader(header.getKey(), header.getValue());
        }
        response.setBody(new String(parts.body(), StandardCharsets.UTF_8));
        return response;
    }

    private static final class TrackingStream extends InputStream {
        private final byte[] value;
        private int offset;
        private boolean closed;

        TrackingStream(byte[] value) {
            this.value = value;
        }

        @Override
        public int read() {
            if (offset >= value.length) {
                return -1;
            }
            return value[offset++] & 0xff;
        }

        @Override
        public void close() {
            closed = true;
        }
    }

    private static final class ResetOnceStream extends InputStream {
        private final byte[] value;
        private int offset;
        private int mark;
        private int resets;

        ResetOnceStream(byte[] value) {
            this.value = value;
        }

        @Override
        public int read() {
            if (offset >= value.length) {
                return -1;
            }
            return value[offset++] & 0xff;
        }

        @Override
        public int available() {
            return Math.max(0, value.length - offset);
        }

        @Override
        public boolean markSupported() {
            return true;
        }

        @Override
        public synchronized void mark(int readlimit) {
            mark = offset;
        }

        @Override
        public synchronized void reset() throws IOException {
            resets++;
            if (resets > 1) {
                throw new IOException("cannot rewind");
            }
            offset = mark;
        }
    }

    private static final class NonSeekableInputStream extends java.io.InputStream {
        private final byte[] value;
        private int offset;

        NonSeekableInputStream(byte[] value) {
            this.value = value;
        }

        @Override
        public int read() {
            if (offset >= value.length) {
                return -1;
            }
            return value[offset++] & 0xff;
        }
    }
}
