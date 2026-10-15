package com.neuraldefend;

import java.time.Duration;
import java.util.function.DoubleSupplier;
import java.util.function.Supplier;
import okhttp3.OkHttpClient;

/** Configuration for {@link NeuroVerifyClient}. */
public final class ClientOptions {
    public String apiKey;
    public String baseUrl;
    public boolean allowCustomBaseUrl;
    public boolean allowHttpForTesting;
    public Duration timeout;
    /** Retries for HTTP 429/500/503 (0-3). Defaults to 3 when null. */
    public Integer maxRetries;
    public OkHttpClient httpClient;
    public String userAgent;
    public Sleeper sleeper;
    public DoubleSupplier random;
    public Supplier<java.time.Instant> clock;

    /** Sleeps between retry attempts (primarily for tests). */
    @FunctionalInterface
    public interface Sleeper {
        void sleep(Duration duration);
    }
}
