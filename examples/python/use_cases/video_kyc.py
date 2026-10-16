"""Video KYC: review a recorded identity-verification session (face and voice)."""

import json
from datetime import datetime, timezone

from neuraldefend import NeuroVerifyClient, NeuroVerifyError, ValidationError

client = NeuroVerifyClient()  # reads NEURALDEFEND_API_KEY; create once and reuse


def save_audit(record):
    print("audit:", json.dumps(record))  # replace with a write to your database


def review_video_kyc_session(session_id, recording_path):
    try:
        # Pass the path so the SDK streams the file; 24 frames gives better coverage.
        result = client.detect_video(recording_path, max_frames=24)
    except NeuroVerifyError as error:
        # ValidationError means bad input or config; anything else is auth, limits, or outages.
        failed = "INVALID_INPUT" if isinstance(error, ValidationError) else "SERVICE_UNAVAILABLE"
        return {
            "session_id": session_id,
            "decision": failed,
            "reason": error.detail,
            "video_risk_level": None,
            "audio_risk_level": None,
            "transaction_id": None,
        }

    save_audit(
        {
            "subject": session_id,
            "transaction_id": result.unique_trx_id,
            "status": result.status,
            "video_risk_level": result.video_risk_level,
            "audio_risk_level": result.audio_risk_level,
            "billable": result.billable,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )

    levels = (result.video_risk_level, result.audio_risk_level)
    reason = result.video_message
    if result.rejected:  # e.g. no face in the recording
        decision = "RE_RECORD"
    elif not result.scored:  # a status this code does not know yet
        decision = "AGENT_REVIEW"
    elif "high" in levels:
        decision = "FRAUD_REVIEW"
    elif not result.has_audio:
        decision = "AGENT_REVIEW"
        reason = "No audio track in the session recording"
    elif "medium" in levels:
        decision = "AGENT_REVIEW"
    else:
        decision = "APPROVE"

    return {
        "session_id": session_id,
        "decision": decision,
        "reason": reason,
        "video_risk_level": result.video_risk_level,
        "audio_risk_level": result.audio_risk_level,
        "transaction_id": result.unique_trx_id,
    }


if __name__ == "__main__":
    print(json.dumps(review_video_kyc_session("vkyc_3003", "session.mp4"), indent=2))
