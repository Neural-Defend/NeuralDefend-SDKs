"""Video conferencing: check a short clip of a meeting participant for deepfakes."""

import json
from datetime import datetime, timezone

from neuraldefend import NeuroVerifyClient, NeuroVerifyError, ValidationError

client = NeuroVerifyClient()  # reads NEURALDEFEND_API_KEY; create once and reuse


def save_audit(record):
    print("audit:", json.dumps(record))  # replace with a write to your database


def check_meeting_clip(meeting_id, participant_id, clip_path):
    try:
        result = client.detect_video(clip_path)
    except NeuroVerifyError as error:
        # ValidationError means bad input or config; anything else is auth, limits, or outages.
        failed = "INVALID_INPUT" if isinstance(error, ValidationError) else "SERVICE_UNAVAILABLE"
        return {
            "meeting_id": meeting_id,
            "participant_id": participant_id,
            "decision": failed,
            "reason": error.detail,
            "transaction_id": None,
        }

    save_audit(
        {
            "subject": participant_id,
            "transaction_id": result.unique_trx_id,
            "status": result.status,
            "video_risk_level": result.video_risk_level,
            "audio_risk_level": result.audio_risk_level,
            "billable": result.billable,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )

    levels = (result.video_risk_level, result.audio_risk_level)
    if result.rejected:  # e.g. camera off or no face in the clip
        decision = "SKIP"
    elif not result.scored:  # a status this code does not know yet
        decision = "WATCH"
    elif "high" in levels:
        decision = "ALERT_HOST"
    elif "medium" in levels:
        decision = "WATCH"
    else:
        decision = "OK"

    return {
        "meeting_id": meeting_id,
        "participant_id": participant_id,
        "decision": decision,
        "reason": result.video_message,
        "transaction_id": result.unique_trx_id,
    }


if __name__ == "__main__":
    print(json.dumps(check_meeting_clip("mtg_5005", "user_42", "clip_0001.mp4"), indent=2))
