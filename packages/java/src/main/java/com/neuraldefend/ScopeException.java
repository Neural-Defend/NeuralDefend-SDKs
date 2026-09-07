package com.neuraldefend;

/** Raised for HTTP 403 when the key lacks endpoint access. */
public final class ScopeException extends RuntimeException {
    private final String detail;
    private final int statusCode;
    private final String requestId;

    public ScopeException(String detail, String requestId) {
        super(detail);
        this.detail = detail;
        this.statusCode = 403;
        this.requestId = requestId == null ? "" : requestId;
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
}
