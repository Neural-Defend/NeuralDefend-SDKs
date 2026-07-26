from __future__ import annotations

import asyncio
import json
import logging
import threading
import time
from pathlib import Path
from types import SimpleNamespace
from typing import Any, BinaryIO

import anyio
import pytest

from neuraldefend_mcp.config import ServerConfig
from neuraldefend_mcp.sdk_adapter import (
    NeuralDefendSDKAdapter,
    SDKAdapterError,
    _exception_kind,
)
from neuraldefend_mcp.service import MediaAuthenticityService

FIXTURES = Path(__file__).parents[3] / "tests" / "fixtures"


def _result(media_type: str, name: str) -> SimpleNamespace:
    data = json.loads((FIXTURES / media_type / "documented" / f"{name}.json").read_text("utf-8"))
    envelope = (
        "unified_face_authenticity_score"
        if media_type == "image"
        else "unified_video_authenticity_score"
    )
    return SimpleNamespace(**data["body"][envelope])


class FakeAdapter:
    def __init__(self) -> None:
        self.image_calls = 0
        self.video_calls = 0
        self.last_stream: BinaryIO | None = None
        self.last_filename: str | None = None
        self.last_max_frames: int | None = None
        self.closed = False

    def detect_image(self, media: BinaryIO, *, filename: str) -> Any:
        self.image_calls += 1
        self.last_stream = media
        self.last_filename = filename
        assert not media.closed
        assert media.read(1) == b"x"
        media.seek(0)
        return _result("image", "low-risk")

    def detect_video(self, media: BinaryIO, *, filename: str, max_frames: int) -> Any:
        self.video_calls += 1
        self.last_stream = media
        self.last_filename = filename
        self.last_max_frames = max_frames
        assert not media.closed
        return _result("video", "silent-no-audio")

    def close(self) -> None:
        self.closed = True


def _service(
    tmp_path: Path,
    adapter: FakeAdapter,
    concurrency: int = 2,
) -> MediaAuthenticityService:
    return MediaAuthenticityService(
        ServerConfig(
            api_key="key-secret",
            allowed_roots=(tmp_path.resolve(),),
            max_concurrency=concurrency,
        ),
        adapter,
    )


@pytest.mark.asyncio
async def test_one_sdk_call_and_same_open_handle_per_image_invocation(tmp_path: Path) -> None:
    media = tmp_path / "private-face.jpg"
    media.write_bytes(b"x-data")
    adapter = FakeAdapter()
    outcome = await _service(tmp_path, adapter).detect_image(str(media))
    assert outcome.scored
    assert adapter.image_calls == 1
    assert adapter.video_calls == 0
    assert adapter.last_filename == "private-face.jpg"
    assert adapter.last_stream is not None
    assert adapter.last_stream.closed


@pytest.mark.asyncio
async def test_video_passes_max_frames_once_and_preserves_silent_audio(tmp_path: Path) -> None:
    media = tmp_path / "private-video.mp4"
    media.write_bytes(b"x-data")
    adapter = FakeAdapter()
    outcome = await _service(tmp_path, adapter).detect_video(str(media), 24)
    assert adapter.video_calls == 1
    assert adapter.last_filename == "private-video.mp4"
    assert adapter.last_max_frames == 24
    assert outcome.audio_risk is not None
    assert outcome.audio_risk.score is None
    assert outcome.audio_risk.message == "No audio track detected"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("media_type", "filename"),
    [
        ("image", "portrait.png"),
        ("image", "portrait.heif"),
        ("video", "recording.mov"),
        ("video", "recording.mkv"),
    ],
)
async def test_preserves_validated_upload_filename(
    tmp_path: Path,
    media_type: str,
    filename: str,
) -> None:
    media = tmp_path / filename
    media.write_bytes(b"x-data")
    adapter = FakeAdapter()
    service = _service(tmp_path, adapter)

    if media_type == "image":
        await service.detect_image(str(media))
    else:
        await service.detect_video(str(media), 12)

    assert adapter.last_filename == filename


@pytest.mark.asyncio
@pytest.mark.parametrize("max_frames", [True, False, 0, 101, -1, 1.5, "12"])
async def test_invalid_max_frames_never_calls_sdk(tmp_path: Path, max_frames: Any) -> None:
    media = tmp_path / "private-video.mp4"
    media.write_bytes(b"x")
    adapter = FakeAdapter()
    outcome = await _service(tmp_path, adapter).detect_video(str(media), max_frames)
    assert outcome.error_code == "local_validation"
    assert adapter.video_calls == 0


@pytest.mark.asyncio
async def test_local_validation_never_calls_sdk(tmp_path: Path) -> None:
    adapter = FakeAdapter()
    outcome = await _service(tmp_path, adapter).detect_image(str(tmp_path / "missing.jpg"))
    assert outcome.error_code == "local_validation"
    assert adapter.image_calls == 0


class RaisingAdapter(FakeAdapter):
    def __init__(self, kind: str, status_code: int | None = None) -> None:
        super().__init__()
        self.kind = kind
        self.status_code = status_code

    def detect_image(self, media: BinaryIO, *, filename: str) -> Any:
        self.image_calls += 1
        raise SDKAdapterError(self.kind, self.status_code)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("kind", "status_code", "expected"),
    [
        ("authentication", 401, "authentication"),
        ("scope", 403, "scope"),
        ("rate_limit", 429, "rate_limit"),
        ("server", 500, "server"),
        ("timeout", None, "transport"),
        ("transport", None, "transport"),
    ],
)
async def test_sdk_errors_are_sanitized(
    tmp_path: Path,
    kind: str,
    status_code: int | None,
    expected: str,
) -> None:
    media = tmp_path / "private-face.jpg"
    media.write_bytes(b"x")
    adapter = RaisingAdapter(kind, status_code)
    outcome = await _service(tmp_path, adapter).detect_image(str(media))
    assert outcome.error_code == expected
    assert adapter.image_calls == 1
    assert "private-face" not in outcome.text()
    assert "key-secret" not in outcome.text()


class ConcurrentAdapter(FakeAdapter):
    def __init__(self) -> None:
        super().__init__()
        self.active = 0
        self.maximum_active = 0
        self._lock = threading.Lock()

    def detect_image(self, media: BinaryIO, *, filename: str) -> Any:
        with self._lock:
            self.image_calls += 1
            self.active += 1
            self.maximum_active = max(self.maximum_active, self.active)
        try:
            time.sleep(0.05)
            return _result("image", "low-risk")
        finally:
            with self._lock:
                self.active -= 1


@pytest.mark.asyncio
async def test_concurrent_sdk_calls_are_bounded(tmp_path: Path) -> None:
    paths = []
    for index in range(6):
        path = tmp_path / f"media-{index}.jpg"
        path.write_bytes(b"x")
        paths.append(path)
    adapter = ConcurrentAdapter()
    service = _service(tmp_path, adapter, concurrency=2)
    outcomes = await asyncio.gather(*(service.detect_image(str(path)) for path in paths))
    assert all(outcome.scored for outcome in outcomes)
    assert adapter.image_calls == 6
    assert adapter.maximum_active == 2


@pytest.mark.asyncio
async def test_cancellation_keeps_thread_inside_concurrency_limit(tmp_path: Path) -> None:
    class BlockingAdapter(ConcurrentAdapter):
        def __init__(self) -> None:
            super().__init__()
            self.started = threading.Event()
            self.release = threading.Event()

        def detect_image(self, media: BinaryIO, *, filename: str) -> Any:
            with self._lock:
                self.image_calls += 1
                self.active += 1
                self.maximum_active = max(self.maximum_active, self.active)
                self.started.set()
            try:
                assert self.release.wait(timeout=2)
                return _result("image", "low-risk")
            finally:
                with self._lock:
                    self.active -= 1

    first_path = tmp_path / "first.jpg"
    second_path = tmp_path / "second.jpg"
    first_path.write_bytes(b"x")
    second_path.write_bytes(b"x")
    adapter = BlockingAdapter()
    service = _service(tmp_path, adapter, concurrency=1)

    first = asyncio.create_task(service.detect_image(str(first_path)))
    assert await asyncio.to_thread(adapter.started.wait, 1)
    first.cancel()
    second = asyncio.create_task(service.detect_image(str(second_path)))
    await asyncio.sleep(0.05)
    assert adapter.image_calls == 1
    assert adapter.maximum_active == 1

    adapter.release.set()
    with pytest.raises(asyncio.CancelledError):
        await first
    assert (await second).scored
    assert adapter.maximum_active == 1


@pytest.mark.asyncio
async def test_anyio_cancel_scope_keeps_thread_inside_concurrency_limit(
    tmp_path: Path,
) -> None:
    class BlockingAdapter(ConcurrentAdapter):
        def __init__(self) -> None:
            super().__init__()
            self.started = threading.Event()
            self.release = threading.Event()

        def detect_image(self, media: BinaryIO, *, filename: str) -> Any:
            with self._lock:
                self.image_calls += 1
                self.active += 1
                self.maximum_active = max(self.maximum_active, self.active)
                self.started.set()
            try:
                assert self.release.wait(timeout=2)
                return _result("image", "low-risk")
            finally:
                with self._lock:
                    self.active -= 1

    first_path = tmp_path / "first-anyio.jpg"
    second_path = tmp_path / "second-anyio.jpg"
    first_path.write_bytes(b"x")
    second_path.write_bytes(b"x")
    adapter = BlockingAdapter()
    service = _service(tmp_path, adapter, concurrency=1)
    scopes: list[anyio.CancelScope] = []
    scope_ready = anyio.Event()
    second_done = anyio.Event()

    async def first_call() -> None:
        with anyio.CancelScope() as scope:
            scopes.append(scope)
            scope_ready.set()
            await service.detect_image(str(first_path))

    async def second_call() -> None:
        await service.detect_image(str(second_path))
        second_done.set()

    async with anyio.create_task_group() as tasks:
        tasks.start_soon(first_call)
        await scope_ready.wait()
        assert await asyncio.to_thread(adapter.started.wait, 1)
        scopes[0].cancel()
        tasks.start_soon(second_call)
        await asyncio.sleep(0.05)
        assert adapter.image_calls == 1
        adapter.release.set()
        await second_done.wait()

    assert adapter.maximum_active == 1


def test_mcp_adapter_ignores_general_sdk_base_url_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NEURALDEFEND_BASE_URL", "https://attacker.example")
    adapter = NeuralDefendSDKAdapter("key")
    try:
        assert adapter._client._base_url == "https://deepscan.neuraldefend.com"
    finally:
        adapter.close()


def test_mcp_adapter_uses_explicit_staging_environment() -> None:
    adapter = NeuralDefendSDKAdapter("key", "staging")
    try:
        assert adapter._client._base_url == "https://stage.deepscan.neuraldefend.com"
    finally:
        adapter.close()


@pytest.mark.asyncio
async def test_no_sensitive_output_or_logs(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    caplog: pytest.LogCaptureFixture,
) -> None:
    media = tmp_path / "private-face.jpg"
    media.write_bytes(b"x")
    adapter = FakeAdapter()
    with caplog.at_level(logging.DEBUG):
        outcome = await _service(tmp_path, adapter).detect_image(str(media))
    captured = capsys.readouterr()
    combined = outcome.text() + json.dumps(outcome.structured()) + caplog.text
    assert captured.out == ""
    assert "key-secret" not in combined
    assert str(media) not in combined
    assert media.name not in combined


@pytest.mark.parametrize(
    ("error_name", "expected"),
    [
        ("AuthenticationError", "authentication"),
        ("ScopeError", "scope"),
        ("PermissionError_", "scope"),
        ("RateLimitError", "rate_limit"),
        ("ServerError", "server"),
        ("TimeoutError_", "timeout"),
        ("ValidationError", "validation"),
        ("ProtocolError", "protocol"),
        ("NetworkError", "transport"),
        ("FutureSDKError", "transport"),
    ],
)
def test_adapter_exception_classification_isolated_by_public_name(
    error_name: str,
    expected: str,
) -> None:
    error_type = type(error_name, (Exception,), {})
    assert _exception_kind(error_type("sensitive raw detail")) == expected
