"""Concurrency-bounded media analysis orchestration."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Literal

import anyio

from .config import ServerConfig
from .path_security import (
    IMAGE_MAX_BYTES,
    VIDEO_MAX_BYTES,
    LocalFileError,
    open_validated_media,
)
from .results import ToolOutcome, error_outcome, image_outcome, video_outcome
from .sdk_adapter import SDKAdapter, SDKAdapterError


class MediaAuthenticityService:
    def __init__(self, config: ServerConfig, adapter: SDKAdapter) -> None:
        self._config = config
        self._adapter = adapter
        self._semaphore = asyncio.Semaphore(config.max_concurrency)

    async def detect_image(self, file_path: str) -> ToolOutcome:
        async with self._semaphore:
            task = asyncio.create_task(asyncio.to_thread(self._detect_image_sync, file_path))
            try:
                return await asyncio.shield(task)
            except asyncio.CancelledError:
                with anyio.CancelScope(shield=True):
                    try:
                        await task
                    except Exception:
                        pass
                raise

    async def detect_video(self, file_path: str, max_frames: int) -> ToolOutcome:
        if (
            isinstance(max_frames, bool)
            or not isinstance(max_frames, int)
            or not 1 <= max_frames <= 100
        ):
            return error_outcome(
                "video",
                "local_validation",
                local_message="max_frames must be an integer from 1 through 100.",
            )
        async with self._semaphore:
            task = asyncio.create_task(
                asyncio.to_thread(self._detect_video_sync, file_path, max_frames)
            )
            try:
                return await asyncio.shield(task)
            except asyncio.CancelledError:
                with anyio.CancelScope(shield=True):
                    try:
                        await task
                    except Exception:
                        pass
                raise

    def _sensitive_values(self, file_path: str) -> tuple[str, ...]:
        return (self._config.api_key, file_path, Path(file_path).name)

    def _detect_image_sync(self, file_path: str) -> ToolOutcome:
        return self._detect_sync("image", file_path, max_frames=None)

    def _detect_video_sync(self, file_path: str, max_frames: int) -> ToolOutcome:
        return self._detect_sync("video", file_path, max_frames=max_frames)

    def _detect_sync(
        self,
        media_type: Literal["image", "video"],
        file_path: str,
        *,
        max_frames: int | None,
    ) -> ToolOutcome:
        max_bytes = IMAGE_MAX_BYTES if media_type == "image" else VIDEO_MAX_BYTES
        try:
            with open_validated_media(
                file_path,
                self._config.allowed_roots,
                max_bytes=max_bytes,
            ) as media:
                if media_type == "image":
                    result = self._adapter.detect_image(
                        media.stream,
                        filename=media.filename,
                    )
                    return image_outcome(result, self._sensitive_values(file_path))
                if max_frames is None:  # Defensive; callers validate this invariant.
                    return error_outcome("video", "local_validation")
                result = self._adapter.detect_video(
                    media.stream,
                    filename=media.filename,
                    max_frames=max_frames,
                )
                return video_outcome(result, self._sensitive_values(file_path))
        except LocalFileError as exc:
            return error_outcome(
                media_type,
                "local_validation",
                local_message=exc.public_message,
            )
        except SDKAdapterError as exc:
            return error_outcome(media_type, exc.kind, status_code=exc.status_code)
