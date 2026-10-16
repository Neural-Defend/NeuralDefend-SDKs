"""HR tech: screen a remote candidate's interview recording and ID photo."""

import json
from datetime import datetime, timezone
from pathlib import Path

from neuraldefend import NeuroVerifyClient, NeuroVerifyError, ValidationError

client = NeuroVerifyClient()  # reads NEURALDEFEND_API_KEY; create once and reuse


def save_audit(record):
    print("audit:", json.dumps(record))  # replace with a write to your database


def screen_candidate(candidate_id, interview_path, photo_bytes, photo_filename):
    try:
        interview = client.detect_video(interview_path)
        save_audit(
            {
                "subject": candidate_id,
                "transaction_id": interview.unique_trx_id,
                "status": interview.status,
                "video_risk_level": interview.video_risk_level,
                "audio_risk_level": interview.audio_risk_level,
                "billable": interview.billable,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        )
        photo = client.detect_image(photo_bytes, filename=photo_filename)
        save_audit(
            {
                "subject": candidate_id,
                "transaction_id": photo.unique_trx_id,
                "status": photo.status,
                "risk_level": photo.risk_level,
                "billable": photo.billable,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        )
    except NeuroVerifyError as error:
        # ValidationError means bad input or config; anything else is auth, limits, or outages.
        failed = "INVALID_INPUT" if isinstance(error, ValidationError) else "SERVICE_UNAVAILABLE"
        return {
            "candidate_id": candidate_id,
            "decision": failed,
            "flags": [],
            "transaction_ids": [],
            "reason": error.detail,
        }

    flags = []
    if interview.video_risk_level == "high":
        flags.append("FACE_SWAP_SUSPECTED")
    if interview.audio_risk_level == "high":
        flags.append("VOICE_CLONE_SUSPECTED")
    if photo.risk_level == "high":
        flags.append("PHOTO_SPOOF_SUSPECTED")

    levels = (interview.video_risk_level, interview.audio_risk_level, photo.risk_level)
    if flags:
        decision = "RECRUITER_REVIEW"
    elif not interview.scored or not photo.scored or "medium" in levels:
        decision = "ADDITIONAL_VERIFICATION"  # rejected, unknown status, or inconclusive
    else:
        decision = "CLEAR"

    return {
        "candidate_id": candidate_id,
        "decision": decision,
        "flags": flags,
        "transaction_ids": [interview.unique_trx_id, photo.unique_trx_id],
    }


if __name__ == "__main__":
    photo = Path("id_photo.jpg").read_bytes()
    decision = screen_candidate("cand_4004", "interview.mp4", photo, "id_photo.jpg")
    print(json.dumps(decision, indent=2))
