# Python examples

## API key

Request an API key from **[neuraldefend.com](https://neuraldefend.com/)** (choose **Book a
Demo**) or contact [support@neuraldefend.com](mailto:support@neuraldefend.com). After
onboarding:

```bash
export NEURALDEFEND_API_KEY="your-api-key"
export NEURALDEFEND_IMAGE="/path/to/selfie.jpg"   # optional
export NEURALDEFEND_VIDEO="/path/to/clip.mp4"     # optional
python detect_media.py
```

## Files

- `detect_media.py` — minimal image and/or video detection using `NeuroVerifyClient`.
