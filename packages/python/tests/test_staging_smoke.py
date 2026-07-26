import os
from pathlib import Path

import pytest

from neuraldefend import ImageResult, NeuroVerifyClient, VideoResult


def _fixture_path(name: str) -> Path:
    value = os.getenv(name)
    if not value:
        pytest.skip(f"{name} is not configured")
    path = Path(value)
    if not path.is_file():
        pytest.fail(f"{name} does not identify a staging fixture")
    return path


def _assert_consistent_result(result: ImageResult | VideoResult) -> None:
    assert result.status in {"success", "rejected"}
    assert result.unique_trx_id
    assert isinstance(result.billable, bool)
    assert result.scored is (result.status == "success")
    assert result.rejected is (result.status == "rejected")


@pytest.mark.staging
def test_staging_image_contract() -> None:
    api_key = os.getenv("NEURALDEFEND_STAGING_API_KEY")
    if not api_key:
        pytest.skip("NEURALDEFEND_STAGING_API_KEY is not configured")

    with NeuroVerifyClient.staging(api_key=api_key, max_retries=0) as client:
        result = client.detect_image(_fixture_path("NEURALDEFEND_STAGING_IMAGE"))

    _assert_consistent_result(result)


@pytest.mark.staging
def test_staging_video_contract() -> None:
    api_key = os.getenv("NEURALDEFEND_STAGING_API_KEY")
    if not api_key:
        pytest.skip("NEURALDEFEND_STAGING_API_KEY is not configured")

    with NeuroVerifyClient.staging(api_key=api_key, max_retries=0) as client:
        result = client.detect_video(
            _fixture_path("NEURALDEFEND_STAGING_VIDEO"),
            max_frames=2,
        )

    _assert_consistent_result(result)
    if result.scored:
        assert result.video_risk_score is not None
        assert result.video_risk_level in {"low", "medium", "high"}
