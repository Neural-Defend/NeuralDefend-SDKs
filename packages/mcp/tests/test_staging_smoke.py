from __future__ import annotations

import os
from pathlib import Path

import pytest

from neuraldefend_mcp.config import ServerConfig
from neuraldefend_mcp.sdk_adapter import NeuralDefendSDKAdapter
from neuraldefend_mcp.service import MediaAuthenticityService


def _fixture_path(name: str) -> Path:
    value = os.getenv(name)
    if not value:
        pytest.skip(f"{name} is not configured")
    path = Path(value)
    if not path.is_file():
        pytest.fail(f"{name} does not identify a staging fixture")
    return path


def _service(api_key: str, root: Path) -> tuple[MediaAuthenticityService, NeuralDefendSDKAdapter]:
    adapter = NeuralDefendSDKAdapter(api_key, "staging")
    config = ServerConfig(
        api_key=api_key,
        allowed_roots=(root.resolve(),),
        environment="staging",
        max_concurrency=1,
    )
    return MediaAuthenticityService(config, adapter), adapter


@pytest.mark.staging
@pytest.mark.asyncio
async def test_staging_image_and_video_contracts() -> None:
    api_key = os.getenv("NEURALDEFEND_STAGING_API_KEY")
    if not api_key:
        pytest.skip("NEURALDEFEND_STAGING_API_KEY is not configured")
    image = _fixture_path("NEURALDEFEND_STAGING_IMAGE")
    video = _fixture_path("NEURALDEFEND_STAGING_VIDEO")
    if image.parent.resolve() != video.parent.resolve():
        pytest.fail("staging fixtures must share one allowed directory")

    service, adapter = _service(api_key, image.parent)
    try:
        image_outcome = await service.detect_image(str(image))
        video_outcome = await service.detect_video(str(video), 2)
    finally:
        adapter.close()

    for outcome in (image_outcome, video_outcome):
        assert outcome.status in {"success", "rejected"}
        assert outcome.transaction_id
        assert isinstance(outcome.billable, bool)
        assert outcome.scored is (outcome.status == "success")
        assert outcome.error_code is None
