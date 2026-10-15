package com.neuraldefend;

/** Raised for HTTP 401. */
public final class AuthenticationException extends RuntimeException {
    private final String detail;
    private final int statusCode;
    private final String requestId;

    public AuthenticationException(String detail, String requestId) {
        super(detail);
        this.detail = detail;
        this.statusCode = 401;
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
