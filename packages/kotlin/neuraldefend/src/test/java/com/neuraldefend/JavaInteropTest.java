package com.neuraldefend;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;

/** Compiles and runs the public API exactly as a Java 8 application would use it. */
class JavaInteropTest {
    @Test
    void builderAndBlockingCallsWorkFromJava() throws Exception {
        try (TestServer server = SupportKt.fixtureServer("image/documented/low-risk.json", "video/documented/both-low.json")) {
            NeuroVerifyClient client = SupportKt.javaTestClient(server);
            ImageResult image = client.newImageCall(MediaInput.bytes("x".getBytes(StandardCharsets.UTF_8), "a.jpg")).execute();
            assertEquals(ResultStatus.SUCCESS, image.getStatus());
            assertEquals(RiskLevel.LOW, image.getRiskLevel());
            assertTrue(image.isScored());

            byte[] payload = "video".getBytes(StandardCharsets.UTF_8);
            VideoResult video = client.newVideoCall(
                    MediaInput.stream(payload.length, "clip.mp4", () -> new ByteArrayInputStream(payload)),
                    12,
                    null,
                    (sent, total) -> { })
                .execute();
            assertTrue(video.isScored());
            client.close();
        }
    }

    @Test
    void enqueueDeliversTypedErrors() throws Exception {
        try (TestServer server = SupportKt.fixtureServer("image/synthetic/forbidden-403.json")) {
            NeuroVerifyClient client = SupportKt.javaTestClient(server);
            CompletableFuture<NeuroVerifyError> failure = new CompletableFuture<>();
            client.newImageCall(MediaInput.bytes(new byte[] {1}, "a.jpg")).enqueue(new NeuroVerifyCallback<ImageResult>() {
                @Override
                public void onResult(NeuroVerifyCall<ImageResult> call, ImageResult result) {
                    failure.completeExceptionally(new AssertionError("expected ScopeError"));
                }

                @Override
                public void onFailure(NeuroVerifyCall<ImageResult> call, NeuroVerifyError error) {
                    failure.complete(error);
                }
            });
            NeuroVerifyError error = failure.get(10, TimeUnit.SECONDS);
            assertTrue(error instanceof ScopeError);
            assertEquals(Integer.valueOf(403), error.getStatusCode());
            client.close();
        }
    }

    @Test
    void configurationIsValidatedFromJava() {
        NeuroVerifyClient client = NeuroVerifyClient.builder()
            .apiKey("key")
            .timeout(30, TimeUnit.SECONDS)
            .retryAfterCap(10, TimeUnit.SECONDS)
            .maxRetries(1)
            .userAgent("java-app/1.0")
            .onWarning(warning -> { })
            .build();
        assertEquals(30_000L, client.getTimeoutMillis());
        assertEquals(NeuroVerifyClient.PRODUCTION_URL, client.getBaseUrl());
        client.close();

        NeuroVerifyClient staging = NeuroVerifyClient.staging("key");
        assertEquals(NeuroVerifyClient.STAGING_URL, staging.getBaseUrl());
        staging.close();

        ValidationError error = assertThrows(ValidationError.class, () -> NeuroVerifyClient.builder().apiKey("k").maxRetries(9).build());
        assertEquals(ValidationErrorCode.INVALID_RETRIES, error.getCode());
        assertEquals("image/png", MediaInput.mimeTypeFor("x.PNG"));
        assertEquals(10L * 1024 * 1024, MediaInput.IMAGE_MAX_BYTES);
        assertTrue(MediaInput.VIDEO_EXTENSIONS.contains("mp4"));
        assertTrue(NeuroVerifyClient.SDK_VERSION.matches("\\d+\\.\\d+\\.\\d+.*"));
    }
}
