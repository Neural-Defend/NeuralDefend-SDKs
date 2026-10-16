# Python examples

## API key

Request an API key from **[neuraldefend.com](https://neuraldefend.com/)** (choose **Book a
Demo**) or contact [support@neuraldefend.com](mailto:support@neuraldefend.com). After
onboarding:

```bash
export NEURALDEFEND_API_KEY="replace-with-your-api-key"
export NEURALDEFEND_IMAGE="/path/to/selfie.jpg"   # optional
export NEURALDEFEND_VIDEO="/path/to/clip.mp4"     # optional
python detect_media.py
```

## Files

- `detect_media.py` — minimal image and/or video detection using `NeuroVerifyClient`.

## Industry use cases

Each file turns a NeuroVerify result into a business decision and prints it as JSON. Set
`NEURALDEFEND_API_KEY`, put the media file named in the script next to it, and run it.

- [`use_cases/ekyc_onboarding.py`](use_cases/ekyc_onboarding.py) — check a new applicant's selfie during eKYC onboarding.
- [`use_cases/kyc_reverification.py`](use_cases/kyc_reverification.py) — re-verify an existing customer before a sensitive action.
- [`use_cases/video_kyc.py`](use_cases/video_kyc.py) — review a recorded video KYC session (face and voice).
- [`use_cases/hr_tech.py`](use_cases/hr_tech.py) — screen a remote candidate's interview recording and ID photo.
- [`use_cases/video_conferencing.py`](use_cases/video_conferencing.py) — check a meeting participant's clip for deepfakes.
