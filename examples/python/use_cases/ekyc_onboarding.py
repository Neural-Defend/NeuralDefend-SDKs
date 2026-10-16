"""eKYC onboarding: check a new applicant's selfie before opening an account."""

import json
from datetime import datetime, timezone
from pathlib import Path

from neuraldefend import NeuroVerifyClient, NeuroVerifyError, ValidationError

client = NeuroVerifyClient()  # reads NEURALDEFEND_API_KEY; create once and reuse

DECISIONS = {"low": "APPROVE", "medium": "MANUAL_REVIEW", "high": "FRAUD_REVIEW"}


def save_audit(record):
    print("audit:", json.dumps(record))  # replace with a write to your database


def verify_onboarding_selfie(applicant_id, photo_bytes, filename):
    try:
        result = client.detect_image(photo_bytes, filename=filename)
    except NeuroVerifyError as error:
        # ValidationError means bad input or config; anything else is auth, limits, or outages.
        failed = "INVALID_INPUT" if isinstance(error, ValidationError) else "SERVICE_UNAVAILABLE"
        return {
            "applicant_id": applicant_id,
            "decision": failed,
            "reason": error.detail,
            "transaction_id": None,
        }

    save_audit(
        {
            "subject": applicant_id,
            "transaction_id": result.unique_trx_id,
            "status": result.status,
            "risk_level": result.risk_level,
            "billable": result.billable,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )

    if result.rejected:  # e.g. no face or a blurry photo
        decision = "RETAKE_SELFIE"
    elif result.scored:
        decision = DECISIONS[result.risk_level]
    else:  # a status this code does not know yet
        decision = "MANUAL_REVIEW"

    return {
        "applicant_id": applicant_id,
        "decision": decision,
        "reason": result.message,
        "transaction_id": result.unique_trx_id,
    }


if __name__ == "__main__":
    photo = Path("selfie.jpg").read_bytes()
    print(json.dumps(verify_onboarding_selfie("app_1001", photo, "selfie.jpg"), indent=2))
