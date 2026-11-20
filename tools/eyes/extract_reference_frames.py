"""Extract app-compatible landmarks from an indexed, local photo collection.

Run inside an isolated environment with mediapipe and pillow installed.
The source photographs and index are read-only inputs.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path

import mediapipe as mp
import numpy as np
from PIL import Image, ImageOps


LEFT = [33, 133, 160, 159, 158, 144, 145, 153]
RIGHT = [362, 263, 387, 386, 385, 373, 374, 380]
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
        397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
        172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = args.index.resolve().parent
    records = list(csv.DictReader(args.index.open(encoding="utf-8-sig", newline="")))
    options = mp.tasks.vision.FaceLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(args.model.resolve())),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_faces=2,
        min_face_detection_confidence=.5,
        min_face_presence_confidence=.5,
    )
    rows = []
    with mp.tasks.vision.FaceLandmarker.create_from_options(options) as detector:
        for record in records:
            path = (root / record["archivo"]).resolve()
            if not path.is_relative_to(root):
                raise ValueError("A source path escapes the reference directory")
            row = {**record, "source_path": str(path)}
            with Image.open(path) as source:
                image = ImageOps.exif_transpose(source).convert("RGB")
            row["original_size"] = list(image.size)
            image.thumbnail((1600, 1600))
            width, height = image.size
            result = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB,
                                              data=np.asarray(image)))
            row["face_count"] = len(result.face_landmarks)
            frame = {"faceDetected": row["face_count"] == 1,
                     "imageWidth": width, "imageHeight": height,
                     "leftEye": [], "rightEye": [], "faceContour": []}
            if row["face_count"] == 1:
                landmarks = result.face_landmarks[0]

                def points(indices):
                    return [{"x": landmarks[i].x * width,
                             "y": landmarks[i].y * height} for i in indices]

                frame.update(leftEye=points(LEFT), rightEye=points(RIGHT),
                             faceContour=points(OVAL))
            row["frame"] = frame
            rows.append(row)
            print(f"{record['archivo']}: faces={row['face_count']}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "mediapipe_version": mp.__version__,
        "running_mode": "IMAGE / CPU / independent photographs",
        "model_sha256": hashlib.sha256(args.model.read_bytes()).hexdigest(),
        "source_index": str(args.index.resolve()), "rows": rows,
    }, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
