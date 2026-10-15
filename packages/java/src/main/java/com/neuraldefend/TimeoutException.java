package com.neuraldefend;

/** Raised when an HTTP operation times out; requests are not retried. */
public final class TimeoutException extends RuntimeException {
    private final String detail;

    public TimeoutException(String detail) {
        super(detail);
        this.detail = detail;
    }

    public String getDetail() {
        return detail;
    }
}
