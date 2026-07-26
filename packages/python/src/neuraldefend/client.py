"""Hand-written streaming facade for the NeuroVerify API."""

import io
import logging
import math
import os
import random as random_module
import stat
import time
import warnings
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import (
    Any,
    BinaryIO,
    Callable,
    Optional,
    Union,
    cast,
)

import httpx

from .errors import (
    AuthenticationError,
    HttpError,
    NetworkError,
    ProtocolError,
    RateLimitError,
    ScopeError,
    ServerError,
    TimeoutError,
    ValidationError,
)
from .models import ImageResult, VideoResult, _immutable_mapping

PRODUCTION_URL = "https://deepscan.neuraldefend.com"
STAGING_URL = "https://stage.deepscan.neuraldefend.com"
DEFAULT_TIMEOUT = 120.0
DEFAULT_MAX_RETRIES = 3
IMAGE_MAX_BYTES = 10 * 1024 * 1024
VIDEO_MAX_BYTES = 1_500_000_000
MAX_RETRY_AFTER = 3600.0
SDK_VERSION = "1.0.0"

_IMAGE_MIME_TYPES: dict[str, str] = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".bmp": "image/bmp",
    ".tif": "image/tiff",
    ".tiff": "image/tiff",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".heif": "image/heif",
}
_VIDEO_MIME_TYPES: dict[str, str] = {
    ".mp4": "video/mp4",
    ".avi": "video/vnd.avi",
    ".mov": "video/quicktime",
    ".mkv": "video/matroska",
    ".wmv": "video/x-ms-wmv",
    ".flv": "video/x-flv",
    ".webm": "video/webm",
    ".ogg": "video/ogg",
    ".ogv": "video/ogg",
}
_MIME_TYPES = {**_IMAGE_MIME_TYPES, **_VIDEO_MIME_TYPES}
_IMAGE_EXTENSIONS = set(_IMAGE_MIME_TYPES)
_VIDEO_EXTENSIONS = set(_VIDEO_MIME_TYPES)


def _mime_for_filename(filename: str) -> str:
    suffix = Path(filename).suffix.lower()
    return _MIME_TYPES.get(suffix, "application/octet-stream")


_LOGGER = logging.getLogger("neuraldefend")
_PathInput = Union[str, os.PathLike[str]]
MediaInput = Union[_PathInput, bytes, BinaryIO]


class _LimitedReader:
    """Replay a prefix and enforce a streaming byte limit without closing the source."""

    def __init__(self, source: BinaryIO, prefix: bytes, limit: int) -> None:
        self._source = source
        self._prefix = prefix
        self._offset = 0
        self._limit = limit
        self._count = 0

    def read(self, size: int = -1) -> bytes:
        chunks = []
        remaining = size
        if self._offset < len(self._prefix) and size != 0:
            if size < 0:
                prefix = self._prefix[self._offset :]
            else:
                prefix = self._prefix[self._offset : self._offset + size]
            self._offset += len(prefix)
            chunks.append(prefix)
            if size > 0:
                remaining -= len(prefix)

        if size < 0 or remaining != 0:
            value = self._source.read(remaining if size >= 0 else -1)
            if not isinstance(value, bytes):
                raise ValidationError("file-like object must return bytes from read()")
            chunks.append(value)

        result = b"".join(chunks)
        self._count += len(result)
        if self._count > self._limit:
            raise ValidationError("file exceeds the endpoint size limit")
        return result


class _Upload:
    def __init__(
        self,
        *,
        filename: str,
        max_bytes: int,
        data: Optional[bytes] = None,
        stream: Optional[BinaryIO] = None,
        initial_position: Optional[int] = None,
        prefix: bytes = b"",
        owns_stream: bool = False,
    ) -> None:
        self.filename = filename
        self.max_bytes = max_bytes
        self.data = data
        self.stream = stream
        self.initial_position = initial_position
        self.prefix = prefix
        self.owns_stream = owns_stream

    @contextmanager
    def open_attempt(self) -> Iterator[BinaryIO]:
        if self.data is not None:
            with io.BytesIO(self.data) as opened:
                yield opened
            return

        if self.stream is None:
            raise RuntimeError("invalid upload source")
        if self.initial_position is not None:
            try:
                self.stream.seek(0, os.SEEK_END)
                end = self.stream.tell()
                size = end - self.initial_position
                if size <= 0:
                    raise ValidationError("file must not be empty")
                if size > self.max_bytes:
                    raise ValidationError("file exceeds the endpoint size limit")
                self.stream.seek(self.initial_position)
            except ValidationError:
                raise
            except (OSError, ValueError, TypeError) as exc:
                raise ValidationError("file-like object could not be rewound for retry") from exc
            yield self.stream
            return

        yield cast(BinaryIO, _LimitedReader(self.stream, self.prefix, self.max_bytes))

    def close(self) -> None:
        if self.owns_stream and self.stream is not None:
            self.stream.close()


class NeuroVerifyClient:
    """Synchronous NeuroVerify client with streaming multipart uploads."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        timeout: float = DEFAULT_TIMEOUT,
        max_retries: int = DEFAULT_MAX_RETRIES,
        user_agent: Optional[str] = None,
        *,
        allow_custom_base_url: bool = False,
        transport: Optional[httpx.BaseTransport] = None,
        _sleep: Callable[[float], None] = time.sleep,
        _random: Callable[[], float] = random_module.random,
        _clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        resolved_key = api_key if api_key is not None else os.getenv("NEURALDEFEND_API_KEY")
        if not isinstance(resolved_key, str) or not resolved_key.strip():
            raise ValidationError(
                "api_key is required (pass it explicitly or set NEURALDEFEND_API_KEY)"
            )
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValidationError("timeout must be a positive number")
        if (
            isinstance(max_retries, bool)
            or not isinstance(max_retries, int)
            or not 0 <= max_retries <= DEFAULT_MAX_RETRIES
        ):
            raise ValidationError("max_retries must be an integer from 0 through 3")
        if not isinstance(allow_custom_base_url, bool):
            raise ValidationError("allow_custom_base_url must be a boolean")

        resolved_url = (
            base_url if base_url is not None else os.getenv("NEURALDEFEND_BASE_URL", PRODUCTION_URL)
        )
        self._base_url = self._validate_base_url(
            resolved_url,
            has_test_transport=transport is not None,
            allow_custom_base_url=allow_custom_base_url,
        )
        self._api_key = resolved_key.strip()
        self._timeout = float(timeout)
        self._max_retries = max_retries
        self._user_agent = user_agent or f"neuraldefend-python/{SDK_VERSION}"
        self._sleep = _sleep
        self._random = _random
        self._clock = _clock
        self._client = httpx.Client(
            base_url=self._base_url,
            timeout=self._timeout,
            transport=transport,
            headers={
                "Accept": "application/json",
                "User-Agent": self._user_agent,
                "x-api-key": self._api_key,
            },
            follow_redirects=False,
        )

    @staticmethod
    def _validate_base_url(
        value: str,
        *,
        has_test_transport: bool,
        allow_custom_base_url: bool,
    ) -> str:
        if not isinstance(value, str) or not value.strip():
            raise ValidationError("base_url must be a non-empty URL")
        try:
            parsed = httpx.URL(value)
        except (TypeError, ValueError) as exc:
            raise ValidationError("base_url is invalid") from exc
        if (
            not parsed.host
            or parsed.query
            or parsed.fragment
            or parsed.username
            or parsed.password
            or parsed.path not in ("", "/")
        ):
            raise ValidationError(
                "base_url must be an origin URL without credentials, path, query, or fragment"
            )
        if parsed.scheme != "https" and not (has_test_transport and parsed.scheme == "http"):
            raise ValidationError("base_url must use HTTPS")
        origin = str(parsed).rstrip("/")
        if (
            origin not in (PRODUCTION_URL, STAGING_URL)
            and not has_test_transport
            and allow_custom_base_url is not True
        ):
            raise ValidationError(
                "a non-Neural Defend base_url requires allow_custom_base_url=True "
                "because it receives the API key and uploaded media"
            )
        return origin

    @classmethod
    def staging(cls, api_key: Optional[str] = None, **kwargs: Any) -> "NeuroVerifyClient":
        """Create a client pinned to staging, ignoring base-URL environment settings."""
        kwargs.pop("base_url", None)
        return cls(api_key=api_key, base_url=STAGING_URL, **kwargs)

    def __enter__(self) -> "NeuroVerifyClient":
        return self

    def __exit__(self, exc_type: Any, exc_value: Any, traceback: Any) -> None:
        self.close()

    def __repr__(self) -> str:
        return (
            f"NeuroVerifyClient(base_url={self._base_url!r}, "
            f"timeout={self._timeout!r}, max_retries={self._max_retries!r}, "
            f"user_agent={self._user_agent!r}, api_key='[REDACTED]')"
        )

    def close(self) -> None:
        """Close the underlying connection pool."""
        self._client.close()

    def detect_image(
        self,
        file: MediaInput,
        *,
        filename: Optional[str] = None,
    ) -> ImageResult:
        """Analyze an image from a path, bytes, or binary file-like object."""
        upload = self._prepare_upload(
            file,
            filename=filename,
            max_bytes=IMAGE_MAX_BYTES,
            extensions=_IMAGE_EXTENSIONS,
        )
        try:
            response = self._send("/detect/image", upload, params=None)
            return self._classify_image(response)
        finally:
            upload.close()

    def detect_video(
        self,
        file: MediaInput,
        *,
        filename: Optional[str] = None,
        max_frames: Optional[int] = None,
        sample_rate: Optional[int] = None,
    ) -> VideoResult:
        """Analyze video and audio modalities from a streaming upload."""
        self._validate_video_parameter("max_frames", max_frames, upper=100)
        self._validate_video_parameter("sample_rate", sample_rate)
        upload = self._prepare_upload(
            file,
            filename=filename,
            max_bytes=VIDEO_MAX_BYTES,
            extensions=_VIDEO_EXTENSIONS,
        )
        params: dict[str, int] = {}
        if max_frames is not None:
            params["max_frames"] = max_frames
        if sample_rate is not None:
            params["sample_rate"] = sample_rate
        try:
            response = self._send("/detect/video", upload, params=params)
            return self._classify_video(response)
        finally:
            upload.close()

    @staticmethod
    def _validate_video_parameter(
        name: str, value: Optional[int], *, upper: Optional[int] = None
    ) -> None:
        if value is None:
            return
        if isinstance(value, bool) or not isinstance(value, int) or value < 1:
            raise ValidationError(f"{name} must be an integer of at least 1")
        if upper is not None and value > upper:
            raise ValidationError(f"{name} must be at most {upper}")

    def _prepare_upload(
        self,
        value: MediaInput,
        *,
        filename: Optional[str],
        max_bytes: int,
        extensions: set[str],
    ) -> _Upload:
        selected_name: str
        if filename is not None:
            if not isinstance(filename, str) or not filename.strip():
                raise ValidationError("filename must be a non-empty string")
            selected_name = Path(filename).name
        else:
            selected_name = ""

        if isinstance(value, (str, os.PathLike)):
            path = Path(value)
            try:
                opened = path.open("rb")
            except OSError as exc:
                raise ValidationError("file path does not exist or is not readable") from exc
            try:
                details = os.fstat(opened.fileno())
                if not stat.S_ISREG(details.st_mode):
                    raise ValidationError("file path must reference a regular file")
                if details.st_size == 0:
                    raise ValidationError("file must not be empty")
                if details.st_size > max_bytes:
                    raise ValidationError("file exceeds the endpoint size limit")
                selected_name = selected_name or path.name
                upload = _Upload(
                    filename=selected_name,
                    max_bytes=max_bytes,
                    stream=opened,
                    initial_position=0,
                    owns_stream=True,
                )
            except Exception:
                opened.close()
                raise
        elif isinstance(value, bytes):
            if not value:
                raise ValidationError("file must not be empty")
            if len(value) > max_bytes:
                raise ValidationError("file exceeds the endpoint size limit")
            if not selected_name:
                raise ValidationError("filename is required when uploading bytes")
            upload = _Upload(filename=selected_name, max_bytes=max_bytes, data=value)
        elif hasattr(value, "read"):
            stream = value
            selected_name = selected_name or self._stream_filename(stream) or ""
            if not selected_name:
                raise ValidationError("filename is required for a nameless file-like object")
            upload = self._prepare_stream(stream, selected_name, max_bytes)
        else:
            raise ValidationError("file must be a path, bytes, or binary file-like object")

        try:
            if Path(selected_name).suffix.lower() not in extensions:
                suffix = Path(selected_name).suffix
                warnings.warn(
                    f"unsupported file extension {suffix!r}; the server will inspect the content",
                    UserWarning,
                    stacklevel=3,
                )
        except Exception:
            upload.close()
            raise
        return upload

    def _prepare_stream(self, stream: BinaryIO, filename: str, max_bytes: int) -> _Upload:
        seekable = False
        try:
            seekable = bool(stream.seekable())
        except (AttributeError, OSError, ValueError):
            seekable = False

        if seekable:
            try:
                stream.tell()
                sample: Any = stream.read(0)
                if isinstance(sample, str):
                    raise ValidationError("file-like object must be opened in binary mode")
                stream.seek(0, os.SEEK_END)
                end = stream.tell()
                stream.seek(0)
            except ValidationError:
                raise
            except (OSError, ValueError, TypeError) as exc:
                raise ValidationError("file-like object must support seek() and tell()") from exc
            size = end
            if size <= 0:
                raise ValidationError("file must not be empty")
            if size > max_bytes:
                raise ValidationError("file exceeds the endpoint size limit")
            return _Upload(
                filename=filename,
                max_bytes=max_bytes,
                stream=stream,
                initial_position=0,
            )

        if self._max_retries != 0:
            raise ValidationError("non-seekable streams require max_retries=0")
        try:
            prefix = stream.read(1)
        except (OSError, ValueError, TypeError) as exc:
            raise ValidationError("file-like object is not readable") from exc
        if not isinstance(prefix, bytes):
            raise ValidationError("file-like object must return bytes from read()")
        if not prefix:
            raise ValidationError("file must not be empty")
        return _Upload(
            filename=filename,
            max_bytes=max_bytes,
            stream=stream,
            prefix=prefix,
        )

    @staticmethod
    def _stream_filename(stream: BinaryIO) -> Optional[str]:
        name = getattr(stream, "name", None)
        if isinstance(name, (str, os.PathLike)):
            candidate = Path(name).name
            return candidate or None
        return None

    def _send(
        self, path: str, upload: _Upload, params: Optional[Mapping[str, int]]
    ) -> httpx.Response:
        for attempt in range(self._max_retries + 1):
            content_type = _mime_for_filename(upload.filename)
            try:
                with upload.open_attempt() as stream:
                    response = self._client.post(
                        path,
                        params=params,
                        files={"file": (upload.filename, stream, content_type)},
                    )
            except httpx.TimeoutException as exc:
                raise TimeoutError(self._redact(str(exc) or "request timed out")) from exc
            except httpx.RequestError as exc:
                raise NetworkError(self._redact(str(exc) or "network request failed")) from exc

            if response.status_code not in (429, 500, 503) or attempt >= self._max_retries:
                return response
            delay = self._retry_delay(response, attempt)
            _LOGGER.debug(
                "Retrying NeuroVerify request after HTTP %d in %.3f seconds (attempt %d)",
                response.status_code,
                delay,
                attempt + 2,
            )
            self._sleep(delay)
        raise RuntimeError("unreachable retry state")

    def _retry_delay(self, response: httpx.Response, attempt: int) -> float:
        if response.status_code == 429:
            parsed = self._parse_retry_after(response.headers.get("Retry-After"))
            if parsed is not None:
                return parsed
            return float(min(2**attempt, 4))
        base = float(min(2**attempt, 4))
        jitter = max(0.0, min(1.0, float(self._random()))) * base * 0.25
        return base + jitter

    def _parse_retry_after(self, value: Optional[str]) -> Optional[float]:
        if value is None:
            return None
        try:
            seconds = float(value.strip())
        except ValueError:
            try:
                target = parsedate_to_datetime(value)
                if target.tzinfo is None:
                    target = target.replace(tzinfo=timezone.utc)
                now = self._clock()
                if now.tzinfo is None:
                    now = now.replace(tzinfo=timezone.utc)
                seconds = (target - now).total_seconds()
            except (TypeError, ValueError, OverflowError):
                return None
        if not math.isfinite(seconds):
            return None
        return max(0.0, min(MAX_RETRY_AFTER, seconds))

    def _classify_image(self, response: httpx.Response) -> ImageResult:
        self._raise_simple_http_errors(response)
        if response.status_code not in (200, 400, 500, 503):
            raise self._unknown_http_error(response)
        try:
            body, score = self._parse_envelope(response, "unified_face_authenticity_score")
            result = self._parse_image_result(score, response.status_code)
        except ProtocolError as exc:
            if response.status_code in (500, 503):
                raise ServerError(
                    f"HTTP {response.status_code}",
                    status_code=response.status_code,
                    request_id=self._request_id(response),
                ) from exc
            raise
        self._raise_for_envelope_status(response, score, result.status, result.message)
        if response.status_code in (500, 503):
            raise ServerError(
                self._redact(result.message),
                status_code=response.status_code,
                request_id=self._request_id(response, score),
                envelope=self._sanitized_envelope(score),
            )
        if response.status_code == 400 and result.status != "rejected":
            raise HttpError(
                "HTTP 400 response was not a rejection",
                status_code=400,
                request_id=self._request_id(response, score),
            )
        del body
        return result

    def _classify_video(self, response: httpx.Response) -> VideoResult:
        self._raise_simple_http_errors(response)
        if response.status_code not in (200, 400, 500, 503):
            raise self._unknown_http_error(response)
        try:
            body, score = self._parse_envelope(response, "unified_video_authenticity_score")
            result = self._parse_video_result(score, response.status_code)
        except ProtocolError as exc:
            if response.status_code in (500, 503):
                raise ServerError(
                    f"HTTP {response.status_code}",
                    status_code=response.status_code,
                    request_id=self._request_id(response),
                ) from exc
            raise
        self._raise_for_envelope_status(response, score, result.status, result.video_message)
        if response.status_code in (500, 503):
            raise ServerError(
                self._redact(result.video_message),
                status_code=response.status_code,
                request_id=self._request_id(response, score),
                envelope=self._sanitized_envelope(score),
            )
        if response.status_code == 400 and result.status != "rejected":
            raise HttpError(
                "HTTP 400 response was not a rejection",
                status_code=400,
                request_id=self._request_id(response, score),
            )
        del body
        return result

    def _raise_simple_http_errors(self, response: httpx.Response) -> None:
        status = response.status_code
        if status not in (401, 403, 429):
            return
        detail = self._response_detail(response)
        request_id = self._request_id(response)
        if status == 401:
            raise AuthenticationError(detail, status_code=401, request_id=request_id)
        if status == 403:
            raise ScopeError(detail, status_code=403, request_id=request_id)
        raise RateLimitError(
            detail,
            retry_after=self._parse_retry_after(response.headers.get("Retry-After")),
            limit=response.headers.get("X-RateLimit-Limit"),
            remaining=response.headers.get("X-RateLimit-Remaining"),
            reset=response.headers.get("X-RateLimit-Reset"),
            request_id=request_id,
        )

    def _parse_envelope(
        self, response: httpx.Response, envelope_name: str
    ) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
        try:
            decoded = response.json()
        except (ValueError, UnicodeDecodeError) as exc:
            raise ProtocolError(
                "response body is not valid JSON",
                status_code=response.status_code,
                request_id=self._request_id(response),
            ) from exc
        if not isinstance(decoded, dict):
            raise ProtocolError(
                "response body must be a JSON object",
                status_code=response.status_code,
                request_id=self._request_id(response),
            )
        score = decoded.get(envelope_name)
        if not isinstance(score, dict):
            raise ProtocolError(
                f"response is missing the {envelope_name!r} envelope",
                status_code=response.status_code,
                request_id=self._request_id(response),
            )
        return cast(Mapping[str, Any], decoded), cast(Mapping[str, Any], score)

    def _parse_image_result(self, score: Mapping[str, Any], http_status: int) -> ImageResult:
        return ImageResult(
            unique_trx_id=self._required_str(score, "unique_trx_id", http_status),
            filename=self._required_str(score, "filename", http_status),
            content_type=self._required_str(score, "content_type", http_status),
            status=self._required_str(score, "status", http_status),
            status_code=self._required_int(score, "status_code", http_status),
            billable=self._billable(score, http_status),
            risk_score=self._optional_float(score, "risk_score", http_status),
            risk_level=self._optional_str(score, "risk_level", http_status),
            message=self._required_str(score, "message", http_status),
            ai_threat_signals=self._signals(score, http_status),
            raw=_immutable_mapping(self._sanitized_envelope(score)),
        )

    def _parse_video_result(self, score: Mapping[str, Any], http_status: int) -> VideoResult:
        return VideoResult(
            unique_trx_id=self._required_str(score, "unique_trx_id", http_status),
            filename=self._required_str(score, "filename", http_status),
            content_type=self._required_str(score, "content_type", http_status),
            status=self._required_str(score, "status", http_status),
            status_code=self._required_int(score, "status_code", http_status),
            billable=self._billable(score, http_status),
            video_risk_score=self._optional_float(score, "video_risk_score", http_status),
            video_risk_level=self._optional_str(score, "video_risk_level", http_status),
            video_message=self._required_str(score, "video_message", http_status),
            audio_risk_score=self._optional_float(score, "audio_risk_score", http_status),
            audio_risk_level=self._optional_str(score, "audio_risk_level", http_status),
            audio_message=self._optional_str(score, "audio_message", http_status),
            ai_threat_signals=self._signals(score, http_status),
            raw=_immutable_mapping(self._sanitized_envelope(score)),
        )

    def _raise_for_envelope_status(
        self,
        response: httpx.Response,
        score: Mapping[str, Any],
        status: str,
        message: str,
    ) -> None:
        if status == "error":
            raise ServerError(
                self._redact(message),
                status_code=response.status_code,
                request_id=self._request_id(response, score),
                envelope=self._sanitized_envelope(score),
            )

    def _required_str(self, score: Mapping[str, Any], name: str, http_status: int) -> str:
        value = score.get(name)
        if not isinstance(value, str):
            raise ProtocolError(
                f"response field {name!r} must be a string",
                status_code=http_status,
            )
        return value

    def _required_int(self, score: Mapping[str, Any], name: str, http_status: int) -> int:
        value = score.get(name)
        if isinstance(value, bool) or not isinstance(value, int):
            raise ProtocolError(
                f"response field {name!r} must be an integer",
                status_code=http_status,
            )
        return value

    def _optional_str(self, score: Mapping[str, Any], name: str, http_status: int) -> Optional[str]:
        if name not in score:
            raise ProtocolError(
                f"response is missing required field {name!r}",
                status_code=http_status,
            )
        value = score.get(name)
        if value is not None and not isinstance(value, str):
            raise ProtocolError(
                f"response field {name!r} must be a string or null",
                status_code=http_status,
            )
        return value

    def _optional_float(
        self, score: Mapping[str, Any], name: str, http_status: int
    ) -> Optional[float]:
        if name not in score:
            raise ProtocolError(
                f"response is missing required field {name!r}",
                status_code=http_status,
            )
        value = score.get(name)
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ProtocolError(
                f"response field {name!r} must be numeric or null",
                status_code=http_status,
            )
        numeric = float(value)
        if not math.isfinite(numeric) or not 0.1 <= numeric <= 10.0:
            raise ProtocolError(
                f"response field {name!r} must be from 0.1 through 10.0 or null",
                status_code=http_status,
            )
        return numeric

    def _billable(self, score: Mapping[str, Any], http_status: int) -> bool:
        value = score.get("billable")
        if value == "Y":
            return True
        if value == "N":
            return False
        raise ProtocolError(
            "response field 'billable' must be exactly 'Y' or 'N'",
            status_code=http_status,
        )

    def _signals(self, score: Mapping[str, Any], http_status: int) -> tuple[str, ...]:
        value = score.get("ai_threat_signals", [])
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise ProtocolError(
                "response field 'ai_threat_signals' must be an array of strings",
                status_code=http_status,
            )
        return tuple(value)

    def _unknown_http_error(self, response: httpx.Response) -> HttpError:
        return HttpError(
            self._response_detail(response),
            status_code=response.status_code,
            request_id=self._request_id(response),
        )

    def _response_detail(self, response: httpx.Response) -> str:
        detail = f"HTTP {response.status_code}"
        try:
            decoded = response.json()
            if isinstance(decoded, dict) and isinstance(decoded.get("detail"), str):
                detail = decoded["detail"]
        except (ValueError, UnicodeDecodeError):
            pass
        return self._redact(detail)

    @staticmethod
    def _request_id(
        response: httpx.Response, score: Optional[Mapping[str, Any]] = None
    ) -> Optional[str]:
        header = response.headers.get("X-Request-ID")
        if isinstance(header, str) and header:
            return header
        if score is not None and isinstance(score.get("unique_trx_id"), str):
            return cast(str, score["unique_trx_id"])
        return None

    def _redact(self, value: str) -> str:
        return value.replace(self._api_key, "[REDACTED]")

    def _sanitized_envelope(self, value: Mapping[str, Any]) -> Mapping[str, Any]:
        def sanitize(item: Any) -> Any:
            if isinstance(item, str):
                return self._redact(item)
            if isinstance(item, Mapping):
                return {str(key): sanitize(nested) for key, nested in item.items()}
            if isinstance(item, (list, tuple)):
                return [sanitize(nested) for nested in item]
            return item

        return cast(Mapping[str, Any], sanitize(value))
