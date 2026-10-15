package com.neuraldefend;

/** Raised for an otherwise unclassified HTTP response. */
public final class HttpException extends RuntimeException {
    private final String detail;
    private final int statusCode;
    private final String requestId;

    public HttpException(String detail, int statusCode, String requestId) {
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
