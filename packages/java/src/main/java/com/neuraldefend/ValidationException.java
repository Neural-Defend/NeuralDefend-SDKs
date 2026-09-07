package com.neuraldefend;

/** Raised when local request validation fails. */
public final class ValidationException extends RuntimeException {
    private final String detail;

    public ValidationException(String detail) {
        super(detail);
        this.detail = detail;
    }

    public String getDetail() {
        return detail;
    }
}
