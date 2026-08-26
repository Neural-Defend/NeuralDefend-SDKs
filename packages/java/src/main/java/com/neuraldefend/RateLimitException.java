package com.neuraldefend;

/** Raised when HTTP 429 remains after configured retries. */
public final class RateLimitException extends RuntimeException {
    private final String detail;
    private final int statusCode;
    private final String requestId;
    private final Double retryAfter;
    private final String limit;
    private final String remaining;
    private final String reset;

    public RateLimitException(
            String detail,
            String requestId,
            Double retryAfter,
            String limit,
            String remaining,
            String reset) {
        super(detail);
        this.detail = detail;
        this.statusCode = 429;
        this.requestId = requestId == null ? "" : requestId;
        this.retryAfter = retryAfter;
        this.limit = limit;
        this.remaining = remaining;
        this.reset = reset;
    }

    public String getDetail() {
        return detail;
    }

    public int getStatusCode() {
        return statusCode;
    }

    public String getRequestId() {
        return requestId;
    }

    public Double getRetryAfter() {
        return retryAfter;
    }

    public String getLimit() {
        return limit;
    }

    public String getRemaining() {
        return remaining;
    }

    public String getReset() {
        return reset;
    }
}
