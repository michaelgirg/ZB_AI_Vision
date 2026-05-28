"""Export threshold golden vectors for RTL and Vitis validation."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import torch
from PIL import Image
from torchvision import datasets, transforms

from model import ThresholdMLP, build_mlp
from preprocess import (
    COMBINED_FEATURE_PIXELS,
    DEFAULT_THRESHOLD,
    c_array_u8,
    classifier_input_for_mode,
    sobel_u8_tensor,
    tensor_to_mem_lines,
    threshold_u8_tensor,
    threshold_sobel_u8_features,
    to_u8_image,
)


def load_model(checkpoint: Path) -> tuple[ThresholdMLP, dict]:
    data = torch.load(checkpoint, map_location="cpu")
    input_features = int(data.get("input_features", 784))
    model = build_mlp(input_features=input_features, hidden_features=int(data["hidden_features"]))
    model.load_state_dict(data["model_state"])
    model.eval()
    return model, data


def file_sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def save_preview(
    path: Path,
    image_u8: torch.Tensor,
    thresholded: torch.Tensor,
    sobel: torch.Tensor,
    scale: int = 8,
) -> None:
    raw = Image.fromarray(image_u8.numpy(), mode="L").resize((28 * scale, 28 * scale), Image.Resampling.NEAREST)
    th = Image.fromarray(thresholded.numpy(), mode="L").resize((28 * scale, 28 * scale), Image.Resampling.NEAREST)
    edge = Image.fromarray(sobel.numpy(), mode="L").resize((28 * scale, 28 * scale), Image.Resampling.NEAREST)
    gap = 8
    canvas = Image.new("L", (raw.width + gap + th.width + gap + edge.width, raw.height), 32)
    canvas.paste(raw, (0, 0))
    canvas.paste(th, (raw.width + gap, 0))
    canvas.paste(edge, (raw.width + gap + th.width + gap, 0))
    canvas.save(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=Path("generated/model/threshold_mlp.pt"))
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--output-dir", type=Path, default=Path("generated/test_vectors"))
    parser.add_argument("--count", type=int, default=8)
    parser.add_argument("--start-index", type=int, default=0)
    parser.add_argument("--threshold", type=int, default=None)
    parser.add_argument("--download", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model, checkpoint_data = load_model(args.checkpoint)
    threshold = int(args.threshold if args.threshold is not None else checkpoint_data.get("threshold", DEFAULT_THRESHOLD))
    feature_mode = str(checkpoint_data.get("feature_mode", "threshold"))

    dataset = datasets.MNIST(
        root=str(args.data_dir),
        train=False,
        download=args.download,
        transform=transforms.PILToTensor(),
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "threshold": threshold,
        "feature_mode": feature_mode,
        "checkpoint": str(args.checkpoint),
        "samples": [],
    }

    for sample_id, dataset_index in enumerate(range(args.start_index, args.start_index + args.count)):
        image, label = dataset[dataset_index]
        image_u8 = to_u8_image(image)
        thresholded = threshold_u8_tensor(image_u8, threshold)
        sobel = sobel_u8_tensor(image_u8)
        combined_features = threshold_sobel_u8_features(image_u8, threshold)
        classifier_input = classifier_input_for_mode(image_u8, feature_mode, threshold).unsqueeze(0)

        with torch.no_grad():
            logits = model(classifier_input).squeeze(0)
            probabilities = torch.softmax(logits, dim=0)
            prediction = int(torch.argmax(logits).item())
            confidence = float(probabilities[prediction].item())

        stem = f"sample_{sample_id:03d}"
        input_mem = args.output_dir / f"{stem}_input.mem"
        threshold_mem = args.output_dir / f"{stem}_threshold.mem"
        sobel_mem = args.output_dir / f"{stem}_sobel.mem"
        combined_mem = args.output_dir / f"{stem}_threshold_sobel.mem"
        header_path = args.output_dir / f"{stem}_image_data.h"
        preview_path = args.output_dir / f"{stem}_preview.png"

        input_mem.write_text("\n".join(tensor_to_mem_lines(image_u8)) + "\n", encoding="utf-8")
        threshold_mem.write_text("\n".join(tensor_to_mem_lines(thresholded)) + "\n", encoding="utf-8")
        sobel_mem.write_text("\n".join(tensor_to_mem_lines(sobel)) + "\n", encoding="utf-8")
        combined_mem.write_text("\n".join(tensor_to_mem_lines(combined_features)) + "\n", encoding="utf-8")
        save_preview(preview_path, image_u8, thresholded, sobel)

        input_array = c_array_u8(f"{stem}_input_image", image_u8.reshape(-1).tolist())
        expected_array = c_array_u8(f"{stem}_expected_threshold", thresholded.reshape(-1).tolist())
        sobel_array = c_array_u8(f"{stem}_expected_sobel", sobel.reshape(-1).tolist())
        combined_array = c_array_u8(f"{stem}_expected_threshold_sobel", combined_features.tolist())
        header_path.write_text(
            "#pragma once\n\n"
            "#define IMAGE_WIDTH 28\n"
            "#define IMAGE_HEIGHT 28\n"
            "#define IMAGE_PIXELS 784\n"
            f"#define COMBINED_FEATURE_PIXELS {COMBINED_FEATURE_PIXELS}\n\n"
            f"#define {stem.upper()}_LABEL {int(label)}\n"
            f"#define {stem.upper()}_PREDICTION {prediction}\n\n"
            + input_array
            + "\n"
            + expected_array
            + "\n"
            + sobel_array
            + "\n"
            + combined_array,
            encoding="utf-8",
        )

        manifest["samples"].append(
            {
                "name": stem,
                "dataset_index": dataset_index,
                "label": int(label),
                "prediction": prediction,
                "confidence": confidence,
                "correct": prediction == int(label),
                "logits": [round(float(value), 6) for value in logits.tolist()],
                "input_mem": str(input_mem),
                "threshold_mem": str(threshold_mem),
                "sobel_mem": str(sobel_mem),
                "threshold_sobel_mem": str(combined_mem),
                "header": str(header_path),
                "preview": str(preview_path),
                "sha256": {
                    "input_mem": file_sha256(input_mem),
                    "threshold_mem": file_sha256(threshold_mem),
                    "sobel_mem": file_sha256(sobel_mem),
                    "threshold_sobel_mem": file_sha256(combined_mem),
                    "header": file_sha256(header_path),
                    "preview": file_sha256(preview_path),
                },
            }
        )
        print(f"{stem}: label={int(label)} prediction={prediction} confidence={confidence:.3f}")

    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"saved {args.output_dir / 'manifest.json'}")


if __name__ == "__main__":
    main()
