package com.neuraldefend;

/** Raised when the server response does not match the required envelope. */
public final class ProtocolException extends RuntimeException {
    private final String detail;
    private final int statusCode;
    private final String requestId;

    public ProtocolException(String detail, int statusCode, String requestId) {
        super(detail);
        this.detail = detail;
        this.statusCode = statusCode;
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
