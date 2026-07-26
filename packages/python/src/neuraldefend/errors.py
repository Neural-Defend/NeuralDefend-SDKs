"""Public exception hierarchy for the NeuroVerify SDK."""

from collections.abc import Mapping
from typing import Any, Optional

from .models import _immutable_mapping


class NeuroVerifyError(Exception):
    """Base class for all SDK errors."""

    def __init__(
        self,
        detail: str,
        *,
        status_code: Optional[int] = None,
        request_id: Optional[str] = None,
    ) -> None:
        super().__init__(detail)
        self.detail = detail
        self.status_code = status_code
        self.request_id = request_id


class ValidationError(NeuroVerifyError):
    """Raised when local request validation fails."""


class ProtocolError(NeuroVerifyError):
    """Raised when the server response does not match the required envelope."""


class NetworkError(NeuroVerifyError):
    """Raised for non-timeout network failures; requests are not retried."""


class TimeoutError(NeuroVerifyError):
    """Raised when an HTTP operation times out; requests are not retried."""


class HttpError(NeuroVerifyError):
    """Raised for an otherwise unclassified HTTP response."""


class AuthenticationError(HttpError):
    """Raised for HTTP 401."""


class ScopeError(HttpError):
    """Raised for HTTP 403 when the key lacks endpoint access."""


class RateLimitError(HttpError):
    """Raised when HTTP 429 remains after configured retries."""

    def __init__(
        self,
        detail: str,
        *,
        retry_after: Optional[float],
        limit: Optional[str],
        remaining: Optional[str],
        reset: Optional[str],
        request_id: Optional[str] = None,
    ) -> None:
        super().__init__(detail, status_code=429, request_id=request_id)
        self.retry_after = retry_after
        self.limit = limit
        self.remaining = remaining
        self.reset = reset


class ServerError(HttpError):
    """Raised for an error envelope, including final HTTP 500/503."""

    def __init__(
        self,
        detail: str,
        *,
        status_code: Optional[int],
        request_id: Optional[str] = None,
        envelope: Optional[Mapping[str, Any]] = None,
    ) -> None:
        super().__init__(detail, status_code=status_code, request_id=request_id)
        self.envelope = _immutable_mapping(envelope) if envelope is not None else None
