package com.neuraldefend;

/** Raised for non-timeout network failures; requests are not retried. */
public final class NetworkException extends RuntimeException {
    private final String detail;

    public NetworkException(String detail) {
        super(detail);
        this.detail = detail;
    }

    public String getDetail() {
        return detail;
    }
}
