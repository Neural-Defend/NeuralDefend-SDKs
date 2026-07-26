"""The only module coupled to the concurrently evolving Python SDK."""

from __future__ import annotations

from typing import Any, BinaryIO, Protocol

from .config import APIEnvironment


class SDKAdapterError(Exception):
    """A classified SDK failure that intentionally discards raw exception text."""

    def __init__(self, kind: str, status_code: int | None = None) -> None:
        super().__init__(kind)
        self.kind = kind
        self.status_code = status_code


class SDKAdapter(Protocol):
    def detect_image(self, media: BinaryIO, *, filename: str) -> Any: ...

    def detect_video(self, media: BinaryIO, *, filename: str, max_frames: int) -> Any: ...

    def close(self) -> None: ...


def _exception_kind(exc: Exception) -> str:
    names = {base.__name__ for base in type(exc).__mro__}
    if "AuthenticationError" in names:
        return "authentication"
    if names.intersection({"ScopeError", "PermissionError_"}):
        return "scope"
    if "RateLimitError" in names:
        return "rate_limit"
    if "ServerError" in names:
        return "server"
    if names.intersection({"TimeoutError", "TimeoutError_"}):
        return "timeout"
    if "ValidationError" in names:
        return "validation"
    if "ProtocolError" in names:
        return "protocol"
    if names.intersection({"NetworkError", "TransportError", "HttpError", "NeuroVerifyError"}):
        return "transport"
    return "transport"


def _safe_status_code(exc: Exception) -> int | None:
    value = getattr(exc, "status_code", None)
    if isinstance(value, int) and not isinstance(value, bool) and 100 <= value <= 599:
        return value
    return None


class NeuralDefendSDKAdapter:
    """Thin adapter around NeuroVerifyClient; no retries are added here."""

    def __init__(self, api_key: str, environment: APIEnvironment = "production") -> None:
        from neuraldefend import NeuroVerifyClient
        from neuraldefend.client import PRODUCTION_URL

        if environment == "staging":
            self._client: Any = NeuroVerifyClient.staging(api_key=api_key)
        elif environment == "production":
            self._client = NeuroVerifyClient(api_key=api_key, base_url=PRODUCTION_URL)
        else:
            raise ValueError("Unsupported API environment.")
        self._exit: Any = None
        enter = getattr(self._client, "__enter__", None)
        if callable(enter):
            entered = enter()
            if entered is not None:
                self._client = entered
            self._exit = getattr(self._client, "__exit__", None)

    def detect_image(self, media: BinaryIO, *, filename: str) -> Any:
        try:
            return self._client.detect_image(media, filename=filename)
        except Exception as exc:
            raise SDKAdapterError(_exception_kind(exc), _safe_status_code(exc)) from None

    def detect_video(self, media: BinaryIO, *, filename: str, max_frames: int) -> Any:
        try:
            return self._client.detect_video(
                media,
                filename=filename,
                max_frames=max_frames,
            )
        except Exception as exc:
            raise SDKAdapterError(_exception_kind(exc), _safe_status_code(exc)) from None

    def close(self) -> None:
        if callable(self._exit):
            self._exit(None, None, None)
            return
        close = getattr(self._client, "close", None)
        if callable(close):
            close()
