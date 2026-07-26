import io
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
import pytest
from conftest import load_case, response_from_case

import neuraldefend.client as client_module
from neuraldefend import (
    AuthenticationError,
    HttpError,
    NetworkError,
    NeuroVerifyClient,
    ProtocolError,
    ServerError,
    TimeoutError,
    ValidationError,
)


def _client_with_handler(handler: Any, **kwargs: Any) -> NeuroVerifyClient:
    return NeuroVerifyClient(
        "secret-test-key",
        base_url="http://test.local",
        transport=httpx.MockTransport(handler),
        **kwargs,
    )


def test_retries_500_three_times_with_backoff_and_rewinds() -> None:
    failure = load_case("image/documented/internal-error-500.json")
    success = load_case("image/documented/low-risk.json")
    calls: list[bytes] = []
    sleeps: list[float] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.read())
        case = failure if len(calls) <= 3 else success
        return response_from_case(case, request)

    stream = io.BytesIO(b"streamed-payload")
    client = _client_with_handler(
        handler,
        max_retries=3,
        _sleep=sleeps.append,
        _random=lambda: 0.0,
    )
    try:
        result = client.detect_image(stream, filename="retry.jpg")
    finally:
        client.close()

    assert result.scored
    assert len(calls) == 4
    assert sleeps == [1.0, 2.0, 4.0]
    assert all(b"streamed-payload" in body for body in calls)
    assert not stream.closed


def test_429_honors_retry_after_then_succeeds() -> None:
    limited = load_case("image/synthetic/rate-limited-429.json")
    success = load_case("image/documented/low-risk.json")
    sleeps: list[float] = []
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        request.read()
        calls += 1
        return response_from_case(limited if calls == 1 else success, request)

    client = _client_with_handler(handler, max_retries=1, _sleep=sleeps.append)
    try:
        assert client.detect_image(b"x", filename="x.jpg").scored
    finally:
        client.close()
    assert calls == 2
    assert sleeps == [60.0]


def test_retry_after_http_date_and_cap() -> None:
    request = httpx.Request("POST", "http://test.local/detect/image")
    response = httpx.Response(
        429,
        headers={"Retry-After": "Sun, 26 Jul 2026 13:00:00 GMT"},
        request=request,
    )
    client = _client_with_handler(
        lambda request: response,
        _clock=lambda: datetime(2026, 7, 26, 12, 0, tzinfo=timezone.utc),
    )
    try:
        assert client._retry_delay(response, 0) == 3600.0
    finally:
        client.close()


def test_429_without_retry_after_uses_backoff_without_jitter() -> None:
    request = httpx.Request("POST", "http://test.local/detect/image")
    response = httpx.Response(429, request=request)
    client = _client_with_handler(lambda request: response, _random=lambda: 1.0)
    try:
        assert client._retry_delay(response, 0) == 1.0
    finally:
        client.close()


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-Infinity"])
def test_non_finite_retry_after_uses_backoff(value: str) -> None:
    request = httpx.Request("POST", "http://test.local/detect/image")
    response = httpx.Response(429, headers={"Retry-After": value}, request=request)
    client = _client_with_handler(lambda request: response)
    try:
        assert client._retry_delay(response, 1) == 2.0
    finally:
        client.close()


def test_malformed_server_response_remains_server_error() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        return httpx.Response(503, text="<html>unavailable</html>", request=request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        with pytest.raises(ServerError) as caught:
            client.detect_image(b"x", filename="x.jpg")
        assert caught.value.status_code == 503
    finally:
        client.close()


@pytest.mark.parametrize(
    "payload",
    [{}, {"unified_face_authenticity_score": {}}],
)
def test_structurally_malformed_server_response_remains_server_error(
    payload: dict[str, object],
) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        return httpx.Response(503, json=payload, request=request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        with pytest.raises(ServerError):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()


def test_missing_required_nullable_field_is_protocol_error() -> None:
    case = json.loads(json.dumps(load_case("image/documented/low-risk.json")))
    del case["body"]["unified_face_authenticity_score"]["risk_score"]

    def handler(request: httpx.Request) -> httpx.Response:
        return response_from_case(case, request)

    client = _client_with_handler(handler)
    try:
        with pytest.raises(ProtocolError, match="risk_score"):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()


@pytest.mark.parametrize("value", [0.0, 10.1])
def test_out_of_contract_score_is_protocol_error(value: float) -> None:
    case = json.loads(json.dumps(load_case("image/documented/low-risk.json")))
    case["body"]["unified_face_authenticity_score"]["risk_score"] = value

    def handler(request: httpx.Request) -> httpx.Response:
        return response_from_case(case, request)

    client = _client_with_handler(handler)
    try:
        with pytest.raises(ProtocolError, match="0.1 through 10.0"):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()


@pytest.mark.parametrize("raw_score", ["1e400", "-1e400"])
def test_non_finite_json_score_is_protocol_error(raw_score: str) -> None:
    case = json.loads(json.dumps(load_case("image/documented/low-risk.json")))
    case["body"]["unified_face_authenticity_score"]["risk_score"] = 123456.0
    content = json.dumps(case["body"]).replace("123456.0", raw_score)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            case["http_status"],
            content=content,
            headers=case["headers"],
            request=request,
        )

    client = _client_with_handler(handler)
    try:
        with pytest.raises(ProtocolError, match="0.1 through 10.0"):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()


def test_results_serialize_only_stable_normalized_fields() -> None:
    image_case = load_case("image/documented/medium-risk.json")
    video_case = load_case("video/documented/both-low.json")

    def handler(request: httpx.Request) -> httpx.Response:
        case = video_case if request.url.path.endswith("/video") else image_case
        return response_from_case(case, request)

    client = _client_with_handler(handler)
    try:
        image = client.detect_image(b"image", filename="image.jpg")
        video = client.detect_video(b"video", filename="video.mp4")
    finally:
        client.close()

    image_output = image.to_dict()
    video_output = video.to_dict()
    assert image_output["risk_score"] == image.risk_score
    assert image_output["scored"] is True
    assert isinstance(image_output["ai_threat_signals"], list)
    assert "raw" not in image_output
    assert image.raw["risk_score"] == image.risk_score
    assert video_output["overall_risk_score"] == video.overall_risk_score
    assert video_output["has_audio"] is True
    assert "raw" not in video_output
    assert video.raw["video_risk_score"] == video.video_risk_score
    assert json.loads(json.dumps({"image": image_output, "video": video_output}))


@pytest.mark.parametrize("status", [200, 400, 401, 403, 418])
def test_non_retryable_http_statuses_are_called_once(status: int) -> None:
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        request.read()
        calls += 1
        if status == 200:
            return response_from_case(load_case("image/documented/low-risk.json"), request)
        if status == 400:
            return response_from_case(load_case("image/documented/blurry.json"), request)
        if status == 401:
            return httpx.Response(status, json={"detail": "bad key"}, request=request)
        if status == 403:
            return httpx.Response(status, json={"detail": "scope"}, request=request)
        return httpx.Response(status, json={"detail": "teapot"}, request=request)

    client = _client_with_handler(handler, max_retries=3, _sleep=lambda _: None)
    try:
        try:
            client.detect_image(b"x", filename="x.jpg")
        except (AuthenticationError, HttpError):
            pass
    finally:
        client.close()
    assert calls == 1


@pytest.mark.parametrize(
    ("raised", "expected"),
    [
        (httpx.ReadTimeout("slow"), TimeoutError),
        (httpx.ConnectError("offline"), NetworkError),
    ],
)
def test_transport_failures_are_distinct_and_not_retried(raised: Exception, expected: type) -> None:
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        raise raised

    client = _client_with_handler(handler, max_retries=3)
    try:
        with pytest.raises(expected):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()
    assert calls == 1


def test_configuration_precedence_and_headers(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, str] = {}
    success = load_case("image/documented/low-risk.json")

    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        seen.update(request.headers)
        assert request.url.host == "explicit.local"
        return response_from_case(success, request)

    monkeypatch.setenv("NEURALDEFEND_API_KEY", "environment-key")
    monkeypatch.setenv("NEURALDEFEND_BASE_URL", "https://environment.local")
    client = NeuroVerifyClient(
        "  explicit-key  ",
        base_url="http://explicit.local",
        user_agent="custom-agent",
        max_retries=0,
        transport=httpx.MockTransport(handler),
    )
    try:
        client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()

    assert seen["x-api-key"] == "explicit-key"
    assert seen["user-agent"] == "custom-agent"


def test_environment_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEURALDEFEND_API_KEY", "environment-key")
    monkeypatch.setenv("NEURALDEFEND_BASE_URL", "https://environment.local")
    client = NeuroVerifyClient(max_retries=0, allow_custom_base_url=True)
    try:
        assert "environment.local" in repr(client)
        assert "environment-key" not in repr(client)
    finally:
        client.close()


def test_staging_is_deterministic(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEURALDEFEND_BASE_URL", "https://wrong.local")
    client = NeuroVerifyClient.staging("key")
    try:
        assert client_module.STAGING_URL in repr(client)
    finally:
        client.close()


def test_tls_is_required_without_test_transport() -> None:
    with pytest.raises(ValidationError, match="HTTPS"):
        NeuroVerifyClient("key", base_url="http://insecure.local")


def test_custom_base_url_requires_explicit_opt_in() -> None:
    with pytest.raises(ValidationError, match="allow_custom_base_url"):
        NeuroVerifyClient("key", base_url="https://api.example.com")

    client = NeuroVerifyClient(
        "key",
        base_url="https://api.example.com",
        allow_custom_base_url=True,
    )
    try:
        assert "api.example.com" in repr(client)
    finally:
        client.close()


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"api_key": ""}, "api_key"),
        ({"api_key": "key", "timeout": 0}, "timeout"),
        ({"api_key": "key", "timeout": True}, "timeout"),
        ({"api_key": "key", "max_retries": -1}, "max_retries"),
        ({"api_key": "key", "max_retries": 4}, "max_retries"),
        ({"api_key": "key", "max_retries": True}, "max_retries"),
        (
            {"api_key": "key", "allow_custom_base_url": "false"},
            "allow_custom_base_url",
        ),
        ({"api_key": "key", "base_url": "https://example.com/api"}, "origin"),
    ],
)
def test_constructor_validation(kwargs: dict[str, Any], message: str) -> None:
    with pytest.raises(ValidationError, match=message):
        NeuroVerifyClient(**kwargs)


def test_api_key_is_redacted_from_repr_and_errors() -> None:
    key = "super-secret-value"

    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        return httpx.Response(401, json={"detail": "invalid " + key}, request=request)

    client = NeuroVerifyClient(
        key,
        base_url="http://test.local",
        max_retries=0,
        transport=httpx.MockTransport(handler),
    )
    try:
        assert key not in repr(client)
        with pytest.raises(AuthenticationError) as caught:
            client.detect_image(b"x", filename="x.jpg")
        assert key not in str(caught.value)
        assert key not in repr(caught.value)
    finally:
        client.close()


@pytest.mark.parametrize("value", [None, 0, 101, True, 1.5, "2"])
def test_max_frames_validation(value: Any) -> None:
    if value is None:
        return
    client = _client_with_handler(lambda request: httpx.Response(500, request=request))
    try:
        with pytest.raises(ValidationError):
            client.detect_video(b"x", filename="x.mp4", max_frames=value)
    finally:
        client.close()


@pytest.mark.parametrize("value", [0, True, 1.5, "2"])
def test_sample_rate_validation(value: Any) -> None:
    client = _client_with_handler(lambda request: httpx.Response(500, request=request))
    try:
        with pytest.raises(ValidationError):
            client.detect_video(b"x", filename="x.mp4", sample_rate=value)
    finally:
        client.close()


def test_video_query_parameters() -> None:
    success = load_case("video/documented/both-low.json")

    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        assert request.url.params["max_frames"] == "100"
        assert request.url.params["sample_rate"] == "1"
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        assert client.detect_video(b"x", filename="x.mp4", max_frames=100, sample_rate=1).scored
    finally:
        client.close()


@pytest.mark.parametrize("payload", [b"", b"1234"])
def test_bytes_empty_and_size_limits(payload: bytes, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(client_module, "IMAGE_MAX_BYTES", 3)
    client = _client_with_handler(lambda request: httpx.Response(200, request=request))
    try:
        with pytest.raises(ValidationError):
            client.detect_image(payload, filename="x.jpg")
    finally:
        client.close()


def test_path_validation_and_streaming(tmp_path: Path) -> None:
    empty = tmp_path / "empty.jpg"
    empty.write_bytes(b"")
    folder = tmp_path / "folder.jpg"
    folder.mkdir()
    valid = tmp_path / "valid.jpg"
    valid.write_bytes(b"path-content")
    success = load_case("image/documented/low-risk.json")
    bodies: list[bytes] = []

    def handler(request: httpx.Request) -> httpx.Response:
        bodies.append(request.read())
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        for invalid in (empty, folder, tmp_path / "missing.jpg"):
            with pytest.raises(ValidationError):
                client.detect_image(invalid)
        assert client.detect_image(valid).scored
    finally:
        client.close()
    assert b"path-content" in bodies[0]


def test_path_is_opened_once_and_reused_across_retries(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    path = tmp_path / "retry.jpg"
    path.write_bytes(b"stable-path-content")
    failure = load_case("image/documented/internal-error-500.json")
    success = load_case("image/documented/low-risk.json")
    real_open = Path.open
    open_count = 0
    bodies: list[bytes] = []

    def tracked_open(self: Path, *args: Any, **kwargs: Any) -> Any:
        nonlocal open_count
        if self == path:
            open_count += 1
        return real_open(self, *args, **kwargs)

    def handler(request: httpx.Request) -> httpx.Response:
        bodies.append(request.read())
        return response_from_case(failure if len(bodies) == 1 else success, request)

    monkeypatch.setattr(Path, "open", tracked_open)
    client = _client_with_handler(handler, max_retries=1, _sleep=lambda _: None)
    try:
        assert client.detect_image(path).scored
    finally:
        client.close()

    assert open_count == 1
    assert len(bodies) == 2
    assert all(b"stable-path-content" in body for body in bodies)


def test_unsupported_extension_warns_but_sends() -> None:
    success = load_case("image/documented/low-risk.json")

    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        with pytest.warns(UserWarning, match="unsupported"):
            assert client.detect_image(b"x", filename="x.unknown").scored
    finally:
        client.close()


class _NonSeekable:
    def __init__(self, value: bytes) -> None:
        self.value = value
        self.offset = 0
        self.closed = False

    def read(self, size: int = -1) -> bytes:
        if size < 0:
            size = len(self.value) - self.offset
        result = self.value[self.offset : self.offset + size]
        self.offset += len(result)
        return result


def test_non_seekable_requires_retries_disabled_and_is_not_closed() -> None:
    with_retries = _client_with_handler(lambda request: httpx.Response(200, request=request))
    try:
        with pytest.raises(ValidationError, match="max_retries=0"):
            with_retries.detect_image(_NonSeekable(b"x"), filename="x.jpg")
    finally:
        with_retries.close()

    success = load_case("image/documented/low-risk.json")
    source = _NonSeekable(b"non-seekable")

    def handler(request: httpx.Request) -> httpx.Response:
        assert b"non-seekable" in request.read()
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        assert client.detect_image(source, filename="x.jpg").scored
    finally:
        client.close()
    assert not source.closed


def test_seekable_stream_rewinds_to_beginning_and_is_not_closed() -> None:
    success = load_case("image/documented/low-risk.json")
    source = io.BytesIO(b"skip-payload")
    source.seek(5)

    def handler(request: httpx.Request) -> httpx.Response:
        body = request.read()
        assert b"skip-payload" in body
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        assert client.detect_image(source, filename="x.jpg").scored
    finally:
        client.close()
    assert not source.closed


def test_text_stream_is_rejected() -> None:
    client = _client_with_handler(lambda request: httpx.Response(200, request=request))
    try:
        with pytest.raises(ValidationError, match="binary"):
            client.detect_image(io.StringIO("text"), filename="x.jpg")
    finally:
        client.close()


def test_unknown_http_and_invalid_billable() -> None:
    def unknown(request: httpx.Request) -> httpx.Response:
        request.read()
        return httpx.Response(418, json={"detail": "teapot"}, request=request)

    client = _client_with_handler(unknown, max_retries=0)
    try:
        with pytest.raises(HttpError, match="teapot"):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()

    case = load_case("image/documented/low-risk.json")
    case = json.loads(json.dumps(case))
    case["body"]["unified_face_authenticity_score"]["billable"] = "yes"

    def invalid(request: httpx.Request) -> httpx.Response:
        request.read()
        return response_from_case(case, request)

    client = _client_with_handler(invalid, max_retries=0)
    try:
        with pytest.raises(ProtocolError, match="exactly"):
            client.detect_image(b"x", filename="x.jpg")
    finally:
        client.close()


def test_error_envelope_on_http_200_raises_server_error() -> None:
    case = load_case("image/documented/internal-error-500.json")
    case = json.loads(json.dumps(case))
    case["http_status"] = 200
    score = case["body"]["unified_face_authenticity_score"]
    score["message"] = "failed for secret-test-key"
    score["future"] = {"echo": "secret-test-key"}

    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        return response_from_case(case, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        with pytest.raises(ServerError) as caught:
            client.detect_image(b"x", filename="x.jpg")
        assert "secret-test-key" not in str(caught.value)
        assert "secret-test-key" not in repr(caught.value.envelope)
    finally:
        client.close()


def test_context_manager_closes_client() -> None:
    client = _client_with_handler(lambda request: httpx.Response(200, request=request))
    with client as entered:
        assert entered is client
    assert client._client.is_closed


@pytest.mark.parametrize(
    "media",
    [
        b"unnamed",
        io.BytesIO(b"unnamed"),
    ],
)
def test_bytes_and_nameless_streams_require_filename(media: Any) -> None:
    client = _client_with_handler(lambda request: httpx.Response(200, request=request))
    try:
        with pytest.raises(ValidationError, match="filename is required"):
            client.detect_image(media)
    finally:
        client.close()


@pytest.mark.parametrize(
    ("filename", "expected_mime"),
    [
        ("photo.jpg", "image/jpeg"),
        ("photo.jpeg", "image/jpeg"),
        ("photo.png", "image/png"),
        ("photo.bmp", "image/bmp"),
        ("photo.tif", "image/tiff"),
        ("photo.tiff", "image/tiff"),
        ("photo.webp", "image/webp"),
        ("photo.heic", "image/heic"),
        ("photo.heif", "image/heif"),
        ("clip.mp4", "video/mp4"),
        ("clip.avi", "video/vnd.avi"),
        ("clip.mov", "video/quicktime"),
        ("clip.mkv", "video/matroska"),
        ("clip.wmv", "video/x-ms-wmv"),
        ("clip.flv", "video/x-flv"),
        ("clip.webm", "video/webm"),
        ("clip.ogg", "video/ogg"),
        ("clip.ogv", "video/ogg"),
        ("unknown.xyz", "application/octet-stream"),
    ],
)
def test_deterministic_mime_for_documented_formats(filename: str, expected_mime: str) -> None:
    from neuraldefend.client import _mime_for_filename

    assert _mime_for_filename(filename) == expected_mime


def test_multipart_carries_deterministic_mime_header() -> None:
    success = load_case("image/documented/low-risk.json")
    captured_ct: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = request.read()
        for line in body.split(b"\r\n"):
            if line.lower().startswith(b"content-type: image/"):
                captured_ct.append(line.decode().split(": ", 1)[1])
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        assert client.detect_image(b"x", filename="selfie.jpg").scored
    finally:
        client.close()
    assert captured_ct == ["image/jpeg"]


def test_heif_extension_is_accepted_without_warning() -> None:
    success = load_case("image/documented/low-risk.json")

    def handler(request: httpx.Request) -> httpx.Response:
        request.read()
        return response_from_case(success, request)

    client = _client_with_handler(handler, max_retries=0)
    try:
        import warnings

        with warnings.catch_warnings():
            warnings.simplefilter("error")
            assert client.detect_image(b"x", filename="photo.heif").scored
    finally:
        client.close()
