"""Minimal NeuroVerify image and video example.

Get an API key from https://neuraldefend.com/ (Book a Demo), then:

  export NEURALDEFEND_API_KEY="your-api-key"
  export NEURALDEFEND_IMAGE="/path/to/selfie.jpg"   # optional
  export NEURALDEFEND_VIDEO="/path/to/clip.mp4"     # optional
"""

import json
import os

from neuraldefend import NeuroVerifyClient


def main() -> None:
    # Requires NEURALDEFEND_API_KEY from https://neuraldefend.com/ onboarding.
    image_path = os.environ.get("NEURALDEFEND_IMAGE")
    video_path = os.environ.get("NEURALDEFEND_VIDEO")
    if not image_path and not video_path:
        raise SystemExit("Set NEURALDEFEND_IMAGE and/or NEURALDEFEND_VIDEO")

    output = {}
    with NeuroVerifyClient() as client:
        if image_path:
            image = client.detect_image(image_path)
            output["image"] = image.to_dict()
        if video_path:
            video = client.detect_video(video_path)
            output["video"] = video.to_dict()
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
