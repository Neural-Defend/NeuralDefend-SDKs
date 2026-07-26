from dataclasses import FrozenInstanceError
from typing import Any, Callable

import pytest
from conftest import load_case

from neuraldefend import (
    AuthenticationError,
    NeuroVerifyClient,
    ProtocolError,
    RateLimitError,
    ScopeError,
    ServerError,
)

IMAGE_RESULTS = [
    "image/documented/low-risk.json",
    "image/documented/medium-risk.json",
    "image/documented/high-risk-spoof.json",
    "image/documented/no-face.json",
    "image/documented/multiple-faces.json",
    "image/documented/nsfw.json",
    "image/documented/blurry.json",
    "image/documented/unsupported-format.json",
    "image/documented/security-rejection.json",
    "image/documented/too-large.json",
]

VIDEO_RESULTS = [
    "video/documented/both-low.json",
    "video/documented/video-high-audio-low.json",
    "video/documented/both-high.json",
    "video/documented/video-low-audio-high.json",
    "video/documented/medium-no-audio.json",
    "video/documented/silent-no-audio.json",
    "video/documented/no-face.json",
    "video/documented/multiple-faces.json",
    "video/documented/unsupported-format.json",
    "video/documented/security-rejection.json",
    "video/documented/too-large.json",
]


@pytest.mark.parametrize("fixture_path", IMAGE_RESULTS)
def test_all_documented_image_results(
    fixture_path: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    case = load_case(fixture_path)
    result = client_for_case(case).detect_image(b"image", filename="sample.jpg")
    wire = case["body"]["unified_face_authenticity_score"]

    assert result.status == wire["status"]
    assert result.status_code == wire["status_code"]
    assert result.billable is (wire["billable"] == "Y")
    assert result.risk_score == wire["risk_score"]
    assert result.risk_level == wire["risk_level"]
    assert result.message
    assert result.scored is (wire["status"] == "success")
    assert result.rejected is (wire["status"] == "rejected")
    assert result.high_risk is (wire["risk_level"] == "high")


@pytest.mark.parametrize("fixture_path", VIDEO_RESULTS)
def test_all_documented_video_results(
    fixture_path: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    case = load_case(fixture_path)
    result = client_for_case(case).detect_video(b"video", filename="sample.mp4")
    wire = case["body"]["unified_video_authenticity_score"]

    assert result.status == wire["status"]
    assert result.status_code == wire["status_code"]
    assert result.billable is (wire["billable"] == "Y")
    assert result.video_risk_score == wire["video_risk_score"]
    assert result.video_risk_level == wire["video_risk_level"]
    assert result.audio_risk_score == wire["audio_risk_score"]
    assert result.audio_risk_level == wire["audio_risk_level"]
    assert result.has_audio is (wire["audio_risk_score"] is not None)
    expected_scores = [
        score for score in (wire["video_risk_score"], wire["audio_risk_score"]) if score is not None
    ]
    assert result.overall_risk_score == (max(expected_scores) if expected_scores else None)


@pytest.mark.parametrize(
    ("fixture_path", "method"),
    [
        ("image/documented/internal-error-500.json", "image"),
        ("image/documented/service-unavailable-503.json", "image"),
        ("video/documented/internal-error-500.json", "video"),
        ("video/documented/service-unavailable-503.json", "video"),
    ],
)
def test_server_error_envelopes(
    fixture_path: str,
    method: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    case = load_case(fixture_path)
    client = client_for_case(case)
    with pytest.raises(ServerError) as caught:
        if method == "image":
            client.detect_image(b"x", filename="x.jpg")
        else:
            client.detect_video(b"x", filename="x.mp4")

    assert caught.value.status_code == case["http_status"]
    assert caught.value.envelope is not None
    assert caught.value.request_id is not None


@pytest.mark.parametrize(
    ("fixture_path", "error_type"),
    [
        ("image/synthetic/unauthorized-401.json", AuthenticationError),
        ("video/synthetic/unauthorized-401.json", AuthenticationError),
        ("image/synthetic/forbidden-403.json", ScopeError),
        ("video/synthetic/forbidden-403.json", ScopeError),
    ],
)
def test_auth_and_scope_errors(
    fixture_path: str,
    error_type: type,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    case = load_case(fixture_path)
    with pytest.raises(error_type) as caught:
        client = client_for_case(case)
        if fixture_path.startswith("image/"):
            client.detect_image(b"x", filename="x.jpg")
        else:
            client.detect_video(b"x", filename="x.mp4")
    assert caught.value.detail == case["body"]["detail"]
    assert caught.value.status_code == case["http_status"]


@pytest.mark.parametrize(
    "fixture_path",
    [
        "image/synthetic/rate-limited-429.json",
        "video/synthetic/rate-limited-429.json",
    ],
)
def test_rate_limit_error_headers(
    fixture_path: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    case = load_case(fixture_path)
    with pytest.raises(RateLimitError) as caught:
        client = client_for_case(case)
        if fixture_path.startswith("image/"):
            client.detect_image(b"x", filename="x.jpg")
        else:
            client.detect_video(b"x", filename="x.mp4")
    error = caught.value
    assert error.retry_after == 60
    assert error.limit == "1000"
    assert error.remaining == "0"
    assert error.reset == "2026-07-27T00:00:00Z"


@pytest.mark.parametrize(
    ("fixture_path", "method"),
    [
        ("image/robustness/missing-envelope.json", "image"),
        ("image/robustness/malformed-json.json", "image"),
        ("video/robustness/missing-envelope.json", "video"),
        ("video/robustness/malformed-json.json", "video"),
    ],
)
def test_malformed_responses_raise_protocol_error(
    fixture_path: str,
    method: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    client = client_for_case(load_case(fixture_path))
    with pytest.raises(ProtocolError):
        if method == "image":
            client.detect_image(b"x", filename="x.jpg")
        else:
            client.detect_video(b"x", filename="x.mp4")


@pytest.mark.parametrize(
    "fixture_path",
    [
        "image/robustness/unknown-status-code.json",
        "image/robustness/unknown-status.json",
        "image/robustness/unknown-risk-level.json",
        "video/robustness/unknown-status-code.json",
        "video/robustness/unknown-status.json",
        "video/robustness/unknown-risk-level.json",
    ],
)
def test_unknown_response_values_are_preserved(
    fixture_path: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    case = load_case(fixture_path)
    client = client_for_case(case)
    if fixture_path.startswith("image/"):
        result = client.detect_image(b"x", filename="x.jpg")
        wire = case["body"]["unified_face_authenticity_score"]
        assert result.status == wire["status"]
        assert result.status_code == wire["status_code"]
        assert result.risk_level == wire["risk_level"]
        if fixture_path.endswith("unknown-risk-level.json"):
            assert result.scored is False
    else:
        result = client.detect_video(b"x", filename="x.mp4")
        wire = case["body"]["unified_video_authenticity_score"]
        assert result.status == wire["status"]
        assert result.status_code == wire["status_code"]
        assert result.video_risk_level == wire["video_risk_level"]
        if fixture_path.endswith("unknown-risk-level.json"):
            assert result.scored is False


@pytest.mark.parametrize(
    ("fixture_path", "method"),
    [
        ("image/robustness/unknown-extra-field.json", "image"),
        ("video/robustness/unknown-extra-field.json", "video"),
    ],
)
def test_unknown_fields_are_deeply_immutable(
    fixture_path: str,
    method: str,
    client_for_case: Callable[[dict[str, Any]], NeuroVerifyClient],
) -> None:
    client = client_for_case(load_case(fixture_path))
    if method == "image":
        result = client.detect_image(b"x", filename="x.jpg")
    else:
        result = client.detect_video(b"x", filename="x.mp4")

    assert result.raw["future_signal"]["confidence"] == 0.42
    with pytest.raises(TypeError):
        result.raw["future_signal"]["confidence"] = 1
    with pytest.raises(FrozenInstanceError):
        result.status = "changed"
