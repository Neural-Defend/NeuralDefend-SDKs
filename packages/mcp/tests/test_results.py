from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from neuraldefend_mcp.results import (
    SCHEMA_VERSION,
    error_outcome,
    image_outcome,
    video_outcome,
)
from neuraldefend_mcp.server import _call_result

FIXTURES = Path(__file__).parents[3] / "tests" / "fixtures"


def _fixture(media_type: str, category: str, name: str) -> SimpleNamespace:
    data = json.loads((FIXTURES / media_type / category / f"{name}.json").read_text("utf-8"))
    envelope = (
        "unified_face_authenticity_score"
        if media_type == "image"
        else "unified_video_authenticity_score"
    )
    return SimpleNamespace(**data["body"][envelope])


@pytest.mark.parametrize(
    ("name", "status", "level"),
    [
        ("low-risk", "success", "low"),
        ("medium-risk", "success", "medium"),
        ("high-risk-spoof", "success", "high"),
        ("no-face", "rejected", None),
        ("multiple-faces", "rejected", None),
        ("blurry", "rejected", None),
        ("nsfw", "rejected", None),
        ("security-rejection", "rejected", None),
        ("unsupported-format", "rejected", None),
        ("too-large", "rejected", None),
    ],
)
def test_all_image_business_results(name: str, status: str, level: str | None) -> None:
    outcome = image_outcome(_fixture("image", "documented", name), ())
    structured = outcome.structured()
    assert structured["schemaVersion"] == SCHEMA_VERSION
    assert structured["mediaType"] == "image"
    assert structured["status"] == status
    assert structured["scored"] is (status == "success")
    assert structured["risk"]["image"]["level"] == level  # type: ignore[index]
    if status == "rejected":
        assert outcome.is_error is False
        assert "not evidence" in outcome.text()


@pytest.mark.parametrize(
    ("name", "video_level", "audio_level"),
    [
        ("both-low", "low", "low"),
        ("video-high-audio-low", "high", "low"),
        ("video-low-audio-high", "low", "high"),
        ("both-high", "high", "high"),
        ("silent-no-audio", "low", None),
        ("medium-no-audio", "medium", None),
        ("no-face", None, None),
        ("multiple-faces", None, None),
        ("security-rejection", None, None),
        ("unsupported-format", None, None),
        ("too-large", None, None),
    ],
)
def test_all_video_business_results(
    name: str,
    video_level: str | None,
    audio_level: str | None,
) -> None:
    outcome = video_outcome(_fixture("video", "documented", name), ())
    structured = outcome.structured()
    risk = structured["risk"]
    assert structured["mediaType"] == "video"
    assert risk["video"]["level"] == video_level  # type: ignore[index]
    assert risk["audio"]["level"] == audio_level  # type: ignore[index]
    assert "overall" not in json.dumps(structured).lower()
    assert "independently" in outcome.text() or outcome.status == "rejected"


def test_silent_video_preserves_success_and_audio_message() -> None:
    outcome = video_outcome(_fixture("video", "documented", "silent-no-audio"), ())
    structured = outcome.structured()
    assert outcome.scored
    assert structured["risk"]["audio"] == {  # type: ignore[index]
        "score": None,
        "level": None,
        "message": "No audio track detected",
    }
    assert "Audio: not scored (No audio track detected)." in outcome.text()


@pytest.mark.parametrize(
    ("name", "expected_guidance"),
    [
        ("low-risk", "not definitive"),
        ("medium-risk", "additional evidence"),
        ("high-risk-spoof", "Escalate for human review"),
    ],
)
def test_text_and_structured_risk_are_aligned(name: str, expected_guidance: str) -> None:
    outcome = image_outcome(_fixture("image", "documented", name), ())
    risk = outcome.structured()["risk"]["image"]  # type: ignore[index]
    assert str(risk["level"]) in outcome.text()
    assert f"{risk['score']:g}/10" in outcome.text()
    assert expected_guidance in outcome.text()


def test_only_bounded_whitelisted_fields_are_exposed() -> None:
    result = _fixture("image", "robustness", "unknown-extra-field")
    result.filename = "private-face.jpg"
    result.raw = {"headers": {"x-api-key": "secret"}, "future": "do-not-expose"}
    result.future_unbounded = "x" * 100_000
    outcome = image_outcome(result, ("secret", "private-face.jpg"))
    serialized = json.dumps(outcome.structured())
    assert "private-face.jpg" not in serialized
    assert "secret" not in serialized
    assert "future" not in serialized
    assert "headers" not in serialized
    assert len(serialized) < 10_000


def test_sensitive_values_and_absolute_paths_are_redacted_from_messages() -> None:
    result = _fixture("image", "documented", "low-risk")
    result.message = r"key-secret and xy in D:\Customers\face.jpg and /srv/private/face.jpg"
    result.ai_threat_signals = ["C:\\Customers\\face.jpg", "safe signal"]
    outcome = image_outcome(
        result,
        ("key-secret", "xy", r"D:\Customers\face.jpg", "face.jpg"),
    )
    serialized = json.dumps(outcome.structured())
    assert "key-secret" not in serialized
    assert "xy" not in serialized
    assert "Customers" not in serialized
    assert "/srv/private" not in serialized
    assert "face.jpg" not in serialized
    assert "safe signal" in serialized


@pytest.mark.parametrize(
    ("kind", "code", "status"),
    [
        ("local_validation", "local_validation", None),
        ("authentication", "authentication", 401),
        ("scope", "scope", 403),
        ("rate_limit", "rate_limit", 429),
        ("server", "server", 503),
        ("timeout", "transport", None),
        ("validation", "local_validation", None),
        ("protocol", "protocol", None),
        ("transport", "transport", None),
    ],
)
def test_sanitized_error_mapping(kind: str, code: str, status: int | None) -> None:
    outcome = error_outcome("image", kind)
    structured = outcome.structured()
    assert outcome.is_error
    assert structured["statusCode"] == status
    assert structured["error"]["code"] == code  # type: ignore[index]
    assert outcome.text() == structured["error"]["message"]  # type: ignore[index]


def test_fastmcp_result_uses_same_internal_object_for_both_channels() -> None:
    outcome = image_outcome(_fixture("image", "documented", "medium-risk"), ())
    result = _call_result(outcome)
    assert result.content[0].text == outcome.text()  # type: ignore[union-attr]
    assert result.structuredContent == outcome.structured()
    assert result.isError is False


def test_unknown_status_becomes_sanitized_protocol_error() -> None:
    outcome = video_outcome(_fixture("video", "robustness", "unknown-status"), ())
    assert outcome.status == "error"
    assert outcome.error_code == "protocol"


@pytest.mark.parametrize("media_type", ["image", "video"])
def test_unknown_risk_level_never_receives_low_risk_guidance(media_type: str) -> None:
    outcome = (
        image_outcome(_fixture("image", "robustness", "unknown-risk-level"), ())
        if media_type == "image"
        else video_outcome(_fixture("video", "robustness", "unknown-risk-level"), ())
    )
    assert outcome.status == "error"
    assert outcome.error_code == "protocol"
    assert "Low risk" not in outcome.text()


@pytest.mark.parametrize("score", [0, 10.1, float("inf"), float("-inf")])
def test_out_of_contract_image_score_becomes_protocol_error(score: float) -> None:
    result = _fixture("image", "documented", "low-risk")
    result.risk_score = score
    outcome = image_outcome(result, ())
    assert outcome.status == "error"
    assert outcome.error_code == "protocol"
    assert not outcome.scored


@pytest.mark.parametrize("kind", ["timeout", "transport", "protocol"])
def test_indeterminate_failures_do_not_claim_non_billable_or_recommend_retry(kind: str) -> None:
    outcome = error_outcome("image", kind)
    assert outcome.billable is None
    assert outcome.retryable is False
