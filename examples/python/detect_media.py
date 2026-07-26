"""Minimal NeuroVerify image and video example."""

import json
import os

from neuraldefend import NeuroVerifyClient


def main() -> None:
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
