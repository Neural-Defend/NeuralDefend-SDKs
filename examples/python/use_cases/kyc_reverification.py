"""KYC re-verification: confirm an existing customer before a sensitive action."""

import json
from datetime import datetime, timezone
from pathlib import Path

from neuraldefend import NeuroVerifyClient, NeuroVerifyError, ValidationError

client = NeuroVerifyClient()  # reads NEURALDEFEND_API_KEY; create once and reuse

DECISIONS = {"low": "ALLOW", "medium": "STEP_UP", "high": "BLOCK_AND_ALERT"}


def save_audit(record):
    print("audit:", json.dumps(record))  # replace with a write to your database


def reverify_customer(customer_id, action, photo_bytes, filename):
    try:
        result = client.detect_image(photo_bytes, filename=filename)
    except NeuroVerifyError as error:
        # ValidationError means bad input or config; anything else is auth, limits, or outages.
        failed = "INVALID_INPUT" if isinstance(error, ValidationError) else "SERVICE_UNAVAILABLE"
        return {
            "customer_id": customer_id,
            "action": action,
            "decision": failed,
            "reason": error.detail,
            "transaction_id": None,
        }

    save_audit(
        {
            "subject": customer_id,
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
        decision = "STEP_UP"

    return {
        "customer_id": customer_id,
        "action": action,
        "decision": decision,
        "reason": result.message,
        "transaction_id": result.unique_trx_id,
    }


if __name__ == "__main__":
    photo = Path("selfie.jpg").read_bytes()
    decision = reverify_customer("cus_2002", "large_withdrawal", photo, "selfie.jpg")
    print(json.dumps(decision, indent=2))
