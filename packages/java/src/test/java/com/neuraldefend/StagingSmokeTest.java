package com.neuraldefend;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import static org.junit.jupiter.api.Assertions.*;

final class StagingSmokeTest {
    @Test
    @EnabledIfEnvironmentVariable(named = "NEURALDEFEND_STAGING_API_KEY", matches = ".+")
    void stagingImageContract() throws Exception {
        String apiKey = System.getenv("NEURALDEFEND_STAGING_API_KEY");
        Path path = stagingFixture("NEURALDEFEND_STAGING_IMAGE");

        ClientOptions options = new ClientOptions();
        options.apiKey = apiKey;
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.staging(options);

        ImageResult result = client.detectImage(Media.fileMedia(path));
        assertConsistentResult(
                result.status, result.uniqueTrxId, result.billable, result.scored(), result.rejected());
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "NEURALDEFEND_STAGING_API_KEY", matches = ".+")
    void stagingVideoContract() throws Exception {
        String apiKey = System.getenv("NEURALDEFEND_STAGING_API_KEY");
        Path path = stagingFixture("NEURALDEFEND_STAGING_VIDEO");

        ClientOptions options = new ClientOptions();
        options.apiKey = apiKey;
        options.maxRetries = 0;
        NeuroVerifyClient client = NeuroVerifyClient.staging(options);

        VideoOptions videoOptions = new VideoOptions();
        videoOptions.maxFrames = 2;
        VideoResult result = client.detectVideo(Media.fileMedia(path), videoOptions);
        assertConsistentResult(
                result.status,
                result.uniqueTrxId,
                result.billable,
                result.scored(),
                result.rejected());
        if (result.scored()) {
            assertNotNull(result.videoRiskScore);
            assertNotNull(result.videoRiskLevel);
            assertTrue(
                    switch (result.videoRiskLevel) {
                        case "low", "medium", "high" -> true;
                        default -> false;
                    });
        }
    }

    private static Path stagingFixture(String envName) {
        String value = System.getenv(envName);
        if (value == null || value.isBlank()) {
            fail(envName + " is not configured");
        }
        Path path = Path.of(value).toAbsolutePath().normalize();
        if (!Files.isRegularFile(path)) {
            fail(envName + " does not identify a staging fixture");
        }
        return path;
    }

    private static void assertConsistentResult(
            String status, String trxId, boolean billable, boolean scored, boolean rejected) {
        assertTrue("success".equals(status) || "rejected".equals(status), "unexpected status");
        assertFalse(trxId.isBlank());
        assertEquals("success".equals(status), scored);
        assertEquals("rejected".equals(status), rejected);
    }
}
