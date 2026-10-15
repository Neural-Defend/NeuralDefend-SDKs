package com.neuraldefend;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

import static org.junit.jupiter.api.Assertions.*;

final class ContractTest {
    private static final Path FIXTURES_ROOT =
            Path.of("..", "..", "tests", "fixtures").toAbsolutePath().normalize();
    private static final Gson GSON = new Gson();
    private static final java.lang.reflect.Type MAP_TYPE =
            new TypeToken<Map<String, Object>>() {}.getType();

    private MockWebServer server;

    @BeforeEach
    void setUp() throws IOException {
        server = new MockWebServer();
        server.start();
    }

    @AfterEach
    void tearDown() throws IOException {
        server.shutdown();
    }

    static List<String> imageResults() {
        return List.of(
                "image/documented/low-risk.json",
                "image/documented/medium-risk.json",
                "image/documented/high-risk-spoof.json",
                "image/documented/no-face.json",
                "image/documented/multiple-faces.json",
                "image/documented/nsfw.json",
                "image/documented/blurry.json",
                "image/documented/unsupported-format.json",
                "image/documented/security-rejection.json",
                "image/documented/too-large.json");
    }

    static List<String> videoResults() {
        return List.of(
                "video/documented/both-low.json",
                "video/documented/video-high-audio-low.json",
                "video/documented/both-high.json",
                "video/documented/video-low-audio-high.json",
                "video/documented/medium-no-audio.json",
                "video/documented/silent-no-audio.json",
                "video/documented/no-face.json",
                "video/documented/multiple-faces.json",
                "video/documented/unsupported-format.json",
                "video/documented/security-rejection.json",
                "video/documented/too-large.json");
    }

    @ParameterizedTest
    @MethodSource("imageResults")
    void allDocumentedImageResults(String fixturePath) throws Exception {
        Map<String, Object> caseData = loadCase(fixturePath);
        NeuroVerifyClient client = clientForCase(caseData);
        ImageResult result =
                client.detectImage(Media.bytesMedia("sample.jpg", "image".getBytes(StandardCharsets.UTF_8)));

        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) caseData.get("body");
        @SuppressWarnings("unchecked")
        Map<String, Object> wire =
                (Map<String, Object>) body.get("unified_face_authenticity_score");

        assertEquals(wire.get("status"), result.status);
        assertEquals(asInt(wire.get("status_code")), result.statusCode);
        assertEquals("Y".equals(wire.get("billable")), result.billable);
        assertFloatEqual(wire.get("risk_score"), result.riskScore);
        assertStringEqual(wire.get("risk_level"), result.riskLevel);
        assertFalse(result.message.isEmpty());
        assertEquals("success".equals(wire.get("status")), result.scored());
        assertEquals("rejected".equals(wire.get("status")), result.rejected());
        assertEquals("high".equals(wire.get("risk_level")), result.highRisk());
    }

    @ParameterizedTest
    @MethodSource("videoResults")
    void allDocumentedVideoResults(String fixturePath) throws Exception {
        Map<String, Object> caseData = loadCase(fixturePath);
        NeuroVerifyClient client = clientForCase(caseData);
        VideoResult result =
                client.detectVideo(
                        Media.bytesMedia("sample.mp4", "video".getBytes(StandardCharsets.UTF_8)),
                        new VideoOptions());

        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) caseData.get("body");
        @SuppressWarnings("unchecked")
        Map<String, Object> wire =
                (Map<String, Object>) body.get("unified_video_authenticity_score");

        assertEquals(wire.get("status"), result.status);
        assertEquals(asInt(wire.get("status_code")), result.statusCode);
        assertEquals("Y".equals(wire.get("billable")), result.billable);
        assertFloatEqual(wire.get("video_risk_score"), result.videoRiskScore);
        assertStringEqual(wire.get("video_risk_level"), result.videoRiskLevel);
        assertFloatEqual(wire.get("audio_risk_score"), result.audioRiskScore);
        assertStringEqual(wire.get("audio_risk_level"), result.audioRiskLevel);
        assertEquals(wire.get("audio_risk_score") != null, result.hasAudio());

        List<Double> expectedScores = new ArrayList<>();
        if (wire.get("video_risk_score") instanceof Number number) {
            expectedScores.add(number.doubleValue());
        }
        if (wire.get("audio_risk_score") instanceof Number number) {
            expectedScores.add(number.doubleValue());
        }
        Double expected = null;
        if (!expectedScores.isEmpty()) {
            expected = expectedScores.stream().max(Double::compareTo).orElseThrow();
        }
        assertFloatEqual(expected, result.overallRiskScore());
    }

    @Test
    void serverErrorEnvelopes() throws Exception {
        record Case(String fixture, boolean image) {}
        List<Case> cases =
                List.of(
                        new Case("image/documented/internal-error-500.json", true),
                        new Case("image/documented/service-unavailable-503.json", true),
                        new Case("video/documented/internal-error-500.json", false),
                        new Case("video/documented/service-unavailable-503.json", false));

        for (Case testCase : cases) {
            Map<String, Object> caseData = loadCase(testCase.fixture);
            NeuroVerifyClient client = clientForCase(caseData);
            Exception error =
                    assertThrows(
                            ServerException.class,
                            () -> {
                                if (testCase.image) {
                                    client.detectImage(
                                            Media.bytesMedia(
                                                    "x.jpg", "x".getBytes(StandardCharsets.UTF_8)));
                                } else {
                                    client.detectVideo(
                                            Media.bytesMedia(
                                                    "x.mp4", "x".getBytes(StandardCharsets.UTF_8)),
                                            new VideoOptions());
                                }
                            });
            ServerException serverError = (ServerException) error;
            assertEquals(asInt(caseData.get("http_status")), serverError.getStatusCode());
            assertNotNull(serverError.getEnvelope());
            assertFalse(serverError.getRequestId().isEmpty());
        }
    }

    @Test
    void authAndScopeErrors() throws Exception {
        record Case(String fixture, String wantType) {}
        List<Case> cases =
                List.of(
                        new Case("image/synthetic/unauthorized-401.json", "auth"),
                        new Case("video/synthetic/unauthorized-401.json", "auth"),
                        new Case("image/synthetic/forbidden-403.json", "scope"),
                        new Case("video/synthetic/forbidden-403.json", "scope"));

        for (Case testCase : cases) {
            Map<String, Object> caseData = loadCase(testCase.fixture);
            NeuroVerifyClient client = clientForCase(caseData);
            @SuppressWarnings("unchecked")
            Map<String, Object> body = (Map<String, Object>) caseData.get("body");

            if ("auth".equals(testCase.wantType)) {
                AuthenticationException authError =
                        assertThrows(
                                AuthenticationException.class,
                                () -> detectForFixture(testCase.fixture, client));
                assertEquals(body.get("detail"), authError.getDetail());
                assertEquals(asInt(caseData.get("http_status")), authError.getStatusCode());
            } else {
                ScopeException scopeError =
                        assertThrows(
                                ScopeException.class,
                                () -> detectForFixture(testCase.fixture, client));
                assertEquals(body.get("detail"), scopeError.getDetail());
            }
        }
    }

    @Test
    void rateLimitErrorHeaders() throws Exception {
        for (String fixturePath :
                List.of(
                        "image/synthetic/rate-limited-429.json",
                        "video/synthetic/rate-limited-429.json")) {
            Map<String, Object> caseData = loadCase(fixturePath);
            NeuroVerifyClient client = clientForCase(caseData);
            RateLimitException rateError =
                    assertThrows(
                            RateLimitException.class, () -> detectForFixture(fixturePath, client));
            assertNotNull(rateError.getRetryAfter());
            assertEquals(60.0, rateError.getRetryAfter());
            assertEquals("1000", rateError.getLimit());
            assertEquals("0", rateError.getRemaining());
            assertEquals("2026-07-27T00:00:00Z", rateError.getReset());
        }
    }

    @Test
    void malformedResponsesRaiseProtocolError() throws Exception {
        record Case(String fixture, boolean image) {}
        List<Case> cases =
                List.of(
                        new Case("image/robustness/missing-envelope.json", true),
                        new Case("image/robustness/malformed-json.json", true),
                        new Case("video/robustness/missing-envelope.json", false),
                        new Case("video/robustness/malformed-json.json", false));

        for (Case testCase : cases) {
            NeuroVerifyClient client = clientForCase(loadCase(testCase.fixture));
            assertThrows(
                    ProtocolException.class,
                    () -> {
                        if (testCase.image) {
                            client.detectImage(
                                    Media.bytesMedia(
                                            "x.jpg", "x".getBytes(StandardCharsets.UTF_8)));
                        } else {
                            client.detectVideo(
                                    Media.bytesMedia(
                                            "x.mp4", "x".getBytes(StandardCharsets.UTF_8)),
                                    new VideoOptions());
                        }
                    });
        }
    }

    @Test
    void unknownResponseValuesArePreserved() throws Exception {
        List<String> cases =
                List.of(
                        "image/robustness/unknown-status-code.json",
                        "image/robustness/unknown-status.json",
                        "image/robustness/unknown-risk-level.json",
                        "video/robustness/unknown-status-code.json",
                        "video/robustness/unknown-status.json",
                        "video/robustness/unknown-risk-level.json");

        for (String fixturePath : cases) {
            Map<String, Object> caseData = loadCase(fixturePath);
            NeuroVerifyClient client = clientForCase(caseData);
            if (fixturePath.startsWith("image/")) {
                ImageResult result =
                        client.detectImage(
                                Media.bytesMedia(
                                        "x.jpg", "x".getBytes(StandardCharsets.UTF_8)));
                @SuppressWarnings("unchecked")
                Map<String, Object> wire =
                        (Map<String, Object>)
                                ((Map<String, Object>) caseData.get("body"))
                                        .get("unified_face_authenticity_score");
                assertEquals(wire.get("status"), result.status);
                assertEquals(asInt(wire.get("status_code")), result.statusCode);
                assertEquals(wire.get("risk_level"), result.riskLevel);
                if (fixturePath.endsWith("unknown-risk-level.json")) {
                    assertFalse(result.scored());
                }
            } else {
                VideoResult result =
                        client.detectVideo(
                                Media.bytesMedia(
                                        "x.mp4", "x".getBytes(StandardCharsets.UTF_8)),
                                new VideoOptions());
                @SuppressWarnings("unchecked")
                Map<String, Object> wire =
                        (Map<String, Object>)
                                ((Map<String, Object>) caseData.get("body"))
                                        .get("unified_video_authenticity_score");
                assertEquals(wire.get("status"), result.status);
                assertEquals(asInt(wire.get("status_code")), result.statusCode);
                assertEquals(wire.get("video_risk_level"), result.videoRiskLevel);
                if (fixturePath.endsWith("unknown-risk-level.json")) {
                    assertFalse(result.scored());
                }
            }
        }
    }

    @Test
    void unknownFieldsArePreservedInRaw() throws Exception {
        record Case(String fixture, boolean image) {}
        List<Case> cases =
                List.of(
                        new Case("image/robustness/unknown-extra-field.json", true),
                        new Case("video/robustness/unknown-extra-field.json", false));

        for (Case testCase : cases) {
            NeuroVerifyClient client = clientForCase(loadCase(testCase.fixture));
            Map<String, Object> raw;
            if (testCase.image) {
                raw =
                        client.detectImage(
                                        Media.bytesMedia(
                                                "x.jpg", "x".getBytes(StandardCharsets.UTF_8)))
                                .raw;
            } else {
                raw =
                        client.detectVideo(
                                        Media.bytesMedia(
                                                "x.mp4", "x".getBytes(StandardCharsets.UTF_8)),
                                        new VideoOptions())
                                .raw;
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> future = (Map<String, Object>) raw.get("future_signal");
            assertNotNull(future);
            assertEquals(0.42, ((Number) future.get("confidence")).doubleValue());
        }
    }

    private void detectForFixture(String fixturePath, NeuroVerifyClient client) {
        if (fixturePath.startsWith("image/")) {
            client.detectImage(Media.bytesMedia("x.jpg", "x".getBytes(StandardCharsets.UTF_8)));
        } else {
            client.detectVideo(
                    Media.bytesMedia("x.mp4", "x".getBytes(StandardCharsets.UTF_8)),
                    new VideoOptions());
        }
    }

    private NeuroVerifyClient clientForCase(Map<String, Object> caseData) {
        TestFixtures.ResponseParts parts = TestFixtures.responseFromCase(caseData);
        server.enqueue(buildMockResponse(parts));
        ClientOptions options = new ClientOptions();
        options.apiKey = "test-key";
        options.baseUrl = server.url("/").toString().replaceAll("/$", "");
        options.allowCustomBaseUrl = true;
        options.allowHttpForTesting = true;
        options.maxRetries = 0;
        options.httpClient =
                new okhttp3.OkHttpClient.Builder()
                        .followRedirects(false)
                        .followSslRedirects(false)
                        .build();
        return NeuroVerifyClient.newClient(options);
    }

    private MockResponse buildMockResponse(TestFixtures.ResponseParts parts) {
        MockResponse response = new MockResponse().setResponseCode(parts.status());
        for (Map.Entry<String, String> header : parts.headers().entrySet()) {
            response.addHeader(header.getKey(), header.getValue());
        }
        response.setBody(new String(parts.body(), StandardCharsets.UTF_8));
        return response;
    }

    private Map<String, Object> loadCase(String relativePath) throws IOException {
        return TestFixtures.loadCase(relativePath);
    }

    private static int asInt(Object value) {
        return ((Number) value).intValue();
    }

    private static void assertFloatEqual(Object want, Double got) {
        if (want == null) {
            assertNull(got);
            return;
        }
        assertNotNull(got);
        assertEquals(((Number) want).doubleValue(), got, 0.0001);
    }

    private static void assertStringEqual(Object want, String got) {
        if (want == null) {
            assertNull(got);
            return;
        }
        assertEquals(String.valueOf(want), got);
    }
}
