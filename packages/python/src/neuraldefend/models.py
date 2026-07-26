"""Stable, generator-independent result types."""

from collections.abc import Mapping
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Any, Optional, cast

_RISK_LEVELS = {"low", "medium", "high"}


def _deep_freeze(value: Any) -> Any:
    if isinstance(value, Mapping):
        frozen = {str(key): _deep_freeze(item) for key, item in value.items()}
        return MappingProxyType(frozen)
    if isinstance(value, (list, tuple)):
        return tuple(_deep_freeze(item) for item in value)
    if isinstance(value, set):
        return frozenset(_deep_freeze(item) for item in value)
    return value


def _immutable_mapping(value: Mapping[str, Any]) -> Mapping[str, Any]:
    return cast(Mapping[str, Any], _deep_freeze(value))


@dataclass(frozen=True)
class ImageResult:
    """An image scoring or business-rejection result."""

    unique_trx_id: str
    filename: str
    content_type: str
    status: str
    status_code: int
    billable: bool
    risk_score: Optional[float]
    risk_level: Optional[str]
    message: str
    raw: Mapping[str, Any] = field(repr=False)
    ai_threat_signals: tuple[str, ...] = ()

    @property
    def scored(self) -> bool:
        return (
            self.status == "success"
            and self.risk_score is not None
            and self.risk_level in _RISK_LEVELS
        )

    @property
    def rejected(self) -> bool:
        return self.status == "rejected"

    @property
    def high_risk(self) -> bool:
        return self.risk_level == "high"

    def to_dict(self) -> dict[str, Any]:
        """Return stable normalized fields as JSON-serializable data."""
        return {
            "unique_trx_id": self.unique_trx_id,
            "filename": self.filename,
            "content_type": self.content_type,
            "status": self.status,
            "status_code": self.status_code,
            "billable": self.billable,
            "risk_score": self.risk_score,
            "risk_level": self.risk_level,
            "message": self.message,
            "ai_threat_signals": list(self.ai_threat_signals),
            "scored": self.scored,
            "rejected": self.rejected,
            "high_risk": self.high_risk,
        }


@dataclass(frozen=True)
class VideoResult:
    """A video scoring or business-rejection result."""

    unique_trx_id: str
    filename: str
    content_type: str
    status: str
    status_code: int
    billable: bool
    video_risk_score: Optional[float]
    video_risk_level: Optional[str]
    video_message: str
    audio_risk_score: Optional[float]
    audio_risk_level: Optional[str]
    audio_message: Optional[str]
    raw: Mapping[str, Any] = field(repr=False)
    ai_threat_signals: tuple[str, ...] = ()

    @property
    def scored(self) -> bool:
        video_scored = self.video_risk_score is not None and self.video_risk_level in _RISK_LEVELS
        audio_scored = (self.audio_risk_score is None and self.audio_risk_level is None) or (
            self.audio_risk_score is not None and self.audio_risk_level in _RISK_LEVELS
        )
        return self.status == "success" and video_scored and audio_scored

    @property
    def rejected(self) -> bool:
        return self.status == "rejected"

    @property
    def has_audio(self) -> bool:
        return self.audio_risk_score is not None

    @property
    def overall_risk_score(self) -> Optional[float]:
        """Return client-side max score; the API has no combined score."""
        scores = [
            score for score in (self.video_risk_score, self.audio_risk_score) if score is not None
        ]
        return max(scores) if scores else None

    def to_dict(self) -> dict[str, Any]:
        """Return stable normalized fields as JSON-serializable data."""
        return {
            "unique_trx_id": self.unique_trx_id,
            "filename": self.filename,
            "content_type": self.content_type,
            "status": self.status,
            "status_code": self.status_code,
            "billable": self.billable,
            "video_risk_score": self.video_risk_score,
            "video_risk_level": self.video_risk_level,
            "video_message": self.video_message,
            "audio_risk_score": self.audio_risk_score,
            "audio_risk_level": self.audio_risk_level,
            "audio_message": self.audio_message,
            "ai_threat_signals": list(self.ai_threat_signals),
            "scored": self.scored,
            "rejected": self.rejected,
            "has_audio": self.has_audio,
            "overall_risk_score": self.overall_risk_score,
        }
