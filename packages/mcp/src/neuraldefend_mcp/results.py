"""Whitelisted, bounded tool results and their text rendering."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any, Literal

SCHEMA_VERSION = "1.0"
_MAX_MESSAGE_CHARS = 500
_MAX_SIGNAL_CHARS = 120
_MAX_SIGNALS = 32
_CONTROL_CHARACTERS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
_ABSOLUTE_PATHS = re.compile(
    r"(?i)(?:\b[a-z]:[\\/][^\s,;]*|\\\\[^\s,;]+|(?<![\w:])/(?:[^\s/,;]+/)*[^\s,;]*)"
)
_SAFE_TRANSACTION = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")


@dataclass(frozen=True)
class Risk:
    score: float | None
    level: Literal["low", "medium", "high"] | None
    message: str | None

    def structured(self) -> dict[str, object]:
        return {"score": self.score, "level": self.level, "message": self.message}


@dataclass(frozen=True)
class ToolOutcome:
    media_type: Literal["image", "video"]
    status: Literal["success", "rejected", "error"]
    status_code: int | None
    scored: bool
    billable: bool | None
    transaction_id: str | None
    signals: tuple[str, ...]
    image_risk: Risk | None = None
    video_risk: Risk | None = None
    audio_risk: Risk | None = None
    error_code: str | None = None
    error_message: str | None = None
    retryable: bool | None = None

    @property
    def is_error(self) -> bool:
        return self.status == "error"

    def structured(self) -> dict[str, object]:
        risk: dict[str, object | None]
        if self.media_type == "image":
            risk = {"image": self.image_risk.structured() if self.image_risk else None}
        else:
            risk = {
                "video": self.video_risk.structured() if self.video_risk else None,
                "audio": self.audio_risk.structured() if self.audio_risk else None,
            }
        payload: dict[str, object] = {
            "schemaVersion": SCHEMA_VERSION,
            "mediaType": self.media_type,
            "status": self.status,
            "statusCode": self.status_code,
            "scored": self.scored,
            "billable": self.billable,
            "transactionId": self.transaction_id,
            "risk": risk,
            "signals": list(self.signals),
        }
        if self.error_code is not None:
            payload["error"] = {
                "code": self.error_code,
                "message": self.error_message,
                "retryable": self.retryable,
            }
        return payload

    def text(self) -> str:
        if self.status == "error":
            return self.error_message or "Authenticity analysis failed."
        if self.status == "rejected":
            risk = self.image_risk if self.media_type == "image" else self.video_risk
            message = risk.message if risk and risk.message else "The media could not be scored."
            return (
                f"Could not score {self.media_type}: {message} "
                "An unscorable result is not evidence that the media is authentic."
            )
        if self.media_type == "image":
            return _image_text(self)
        return _video_text(self)


def _score_text(score: float | None) -> str:
    return f" ({score:g}/10)" if score is not None else ""


def _guidance(level: str | None) -> str:
    if level == "high":
        return "Escalate for human review; do not auto-reject from this result alone."
    if level == "medium":
        return "Review with additional evidence."
    if level == "low":
        return "Low risk is not definitive proof of authenticity."
    return "Treat this as one input to a broader review."


def _image_text(outcome: ToolOutcome) -> str:
    risk = outcome.image_risk or Risk(None, None, None)
    level = risk.level or "unknown"
    message = f" {risk.message}" if risk.message else ""
    return f"Image scored: {level} risk{_score_text(risk.score)}.{message} {_guidance(risk.level)}"


def _modality_text(label: str, risk: Risk | None) -> str:
    if risk is None or (risk.score is None and risk.level is None):
        detail = risk.message if risk and risk.message else "not scored"
        return f"{label}: not scored ({detail})."
    level = risk.level or "unknown"
    detail = f" {risk.message}" if risk.message else ""
    return f"{label}: {level} risk{_score_text(risk.score)}.{detail}"


def _video_text(outcome: ToolOutcome) -> str:
    risks = tuple(risk for risk in (outcome.video_risk, outcome.audio_risk) if risk is not None)
    guidance_levels = {risk.level for risk in risks if risk.level is not None}
    has_unknown_scored_level = any(risk.score is not None and risk.level is None for risk in risks)
    if "high" in guidance_levels:
        guidance = _guidance("high")
    elif "medium" in guidance_levels:
        guidance = _guidance("medium")
    elif guidance_levels == {"low"} and not has_unknown_scored_level:
        guidance = _guidance("low")
    else:
        guidance = _guidance(None)
    return (
        f"Video scored independently. {_modality_text('Video', outcome.video_risk)} "
        f"{_modality_text('Audio', outcome.audio_risk)} {guidance}"
    )


def _sanitize_text(value: Any, sensitive_values: tuple[str, ...], *, limit: int) -> str | None:
    if not isinstance(value, str):
        return None
    text = _CONTROL_CHARACTERS.sub(" ", value).strip()
    for sensitive in sensitive_values:
        if sensitive:
            text = text.replace(sensitive, "[redacted]")
    text = _ABSOLUTE_PATHS.sub("[redacted-path]", text)
    if len(text) > limit:
        text = f"{text[: limit - 1]}…"
    return text or None


def _safe_score(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    score = float(value)
    if not math.isfinite(score) or not 0.1 <= score <= 10:
        return None
    return score


def _safe_level(value: Any) -> Literal["low", "medium", "high"] | None:
    if value == "low":
        return "low"
    if value == "medium":
        return "medium"
    if value == "high":
        return "high"
    return None


def _safe_status_code(value: Any) -> int | None:
    if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 9_999:
        return value
    return None


def _safe_transaction(value: Any) -> str | None:
    if isinstance(value, str) and _SAFE_TRANSACTION.fullmatch(value):
        return value
    return None


def _safe_signals(value: Any, sensitive_values: tuple[str, ...]) -> tuple[str, ...]:
    if not isinstance(value, list | tuple):
        return ()
    output: list[str] = []
    for item in value[:_MAX_SIGNALS]:
        sanitized = _sanitize_text(item, sensitive_values, limit=_MAX_SIGNAL_CHARS)
        if sanitized is not None:
            output.append(sanitized)
    return tuple(output)


def _safe_billable(value: Any) -> bool | None:
    return value if isinstance(value, bool) else None


def image_outcome(result: Any, sensitive_values: tuple[str, ...]) -> ToolOutcome:
    status = getattr(result, "status", None)
    if status not in {"success", "rejected"}:
        return error_outcome("image", "protocol")
    risk = Risk(
        score=_safe_score(getattr(result, "risk_score", None)),
        level=_safe_level(getattr(result, "risk_level", None)),
        message=_sanitize_text(
            getattr(result, "message", None), sensitive_values, limit=_MAX_MESSAGE_CHARS
        ),
    )
    if status == "success" and (risk.score is None or risk.level is None):
        return error_outcome("image", "protocol")
    return ToolOutcome(
        media_type="image",
        status=status,
        status_code=_safe_status_code(getattr(result, "status_code", None)),
        scored=status == "success",
        billable=_safe_billable(getattr(result, "billable", None)),
        transaction_id=_safe_transaction(getattr(result, "unique_trx_id", None)),
        image_risk=risk,
        signals=_safe_signals(getattr(result, "ai_threat_signals", ()), sensitive_values),
    )


def video_outcome(result: Any, sensitive_values: tuple[str, ...]) -> ToolOutcome:
    status = getattr(result, "status", None)
    if status not in {"success", "rejected"}:
        return error_outcome("video", "protocol")
    video_risk = Risk(
        score=_safe_score(getattr(result, "video_risk_score", None)),
        level=_safe_level(getattr(result, "video_risk_level", None)),
        message=_sanitize_text(
            getattr(result, "video_message", None), sensitive_values, limit=_MAX_MESSAGE_CHARS
        ),
    )
    audio_risk = Risk(
        score=_safe_score(getattr(result, "audio_risk_score", None)),
        level=_safe_level(getattr(result, "audio_risk_level", None)),
        message=_sanitize_text(
            getattr(result, "audio_message", None), sensitive_values, limit=_MAX_MESSAGE_CHARS
        ),
    )
    video_is_scored = video_risk.score is not None and video_risk.level is not None
    audio_is_consistent = (audio_risk.score is None and audio_risk.level is None) or (
        audio_risk.score is not None and audio_risk.level is not None
    )
    if status == "success" and (not video_is_scored or not audio_is_consistent):
        return error_outcome("video", "protocol")
    return ToolOutcome(
        media_type="video",
        status=status,
        status_code=_safe_status_code(getattr(result, "status_code", None)),
        scored=status == "success",
        billable=_safe_billable(getattr(result, "billable", None)),
        transaction_id=_safe_transaction(getattr(result, "unique_trx_id", None)),
        video_risk=video_risk,
        audio_risk=audio_risk,
        signals=_safe_signals(getattr(result, "ai_threat_signals", ()), sensitive_values),
    )


_ERRORS: dict[str, tuple[str, str, bool, int | None]] = {
    "local_validation": (
        "local_validation",
        "The local media file was rejected before upload.",
        False,
        None,
    ),
    "authentication": (
        "authentication",
        "Authentication failed. Check the server's API key configuration.",
        False,
        401,
    ),
    "scope": (
        "scope",
        "The configured API key is not authorized for this analysis.",
        False,
        403,
    ),
    "rate_limit": ("rate_limit", "The service rate limit was reached. Try again later.", True, 429),
    "server": ("server", "The analysis service is temporarily unavailable.", True, 503),
    "timeout": ("transport", "The analysis request timed out.", False, None),
    "validation": (
        "local_validation",
        "The media was rejected by local SDK validation.",
        False,
        None,
    ),
    "protocol": ("protocol", "The analysis service returned an unsupported response.", False, None),
    "transport": ("transport", "The analysis service could not be reached.", False, None),
}


def error_outcome(
    media_type: Literal["image", "video"],
    kind: str,
    *,
    status_code: int | None = None,
    local_message: str | None = None,
) -> ToolOutcome:
    code, message, retryable, default_status = _ERRORS.get(kind, _ERRORS["transport"])
    if kind == "local_validation" and local_message:
        message = local_message
    return ToolOutcome(
        media_type=media_type,
        status="error",
        status_code=status_code or default_status,
        scored=False,
        billable=False if kind not in {"timeout", "transport", "protocol"} else None,
        transaction_id=None,
        signals=(),
        error_code=code,
        error_message=message,
        retryable=retryable,
    )
