package com.neuraldefend;

import java.util.Map;

/** Raised for an error envelope, including final HTTP 500/503. */
public final class ServerException extends RuntimeException {
    private final String detail;
    private final int statusCode;
    private final String requestId;
    private final Map<String, Object> envelope;

    public ServerException(
            String detail, int statusCode, String requestId, Map<String, Object> envelope) {
        super(detail);
        this.detail = detail;
        this.statusCode = statusCode;
        this.requestId = requestId == null ? "" : requestId;
        this.envelope = envelope;
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

    public Map<String, Object> getEnvelope() {
        return envelope;
    }
}
