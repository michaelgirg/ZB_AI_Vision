"""Export int8/int32 MLP weights and fixed-point validation metadata."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms

from fixed_point import dequantize_logits, fixed_point_logits, quantize_mlp
from model import ThresholdMLP, build_mlp
from preprocess import (
    COMBINED_FEATURE_PIXELS,
    DEFAULT_THRESHOLD,
    IMAGE_PIXELS,
    classifier_input_for_mode,
)


class FeatureMnist(torch.utils.data.Dataset):
    def __init__(
        self,
        root: Path,
        train: bool,
        threshold: int,
        feature_mode: str,
        download: bool,
    ) -> None:
        self.mnist = datasets.MNIST(
            root=str(root),
            train=train,
            download=download,
            transform=transforms.PILToTensor(),
        )
        self.threshold = threshold
        self.feature_mode = feature_mode

    def __len__(self) -> int:
        return len(self.mnist)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, int]:
        image, label = self.mnist[index]
        return classifier_input_for_mode(image, self.feature_mode, self.threshold), int(label)


def input_quantization_for_mode(feature_mode: str) -> tuple[float, int]:
    if feature_mode == "threshold":
        return 1.0, 1
    if feature_mode == "threshold_sobel":
        return 1.0 / 255.0, 255
    raise ValueError(f"unsupported feature mode: {feature_mode}")


def input_features_for_mode(feature_mode: str) -> int:
    if feature_mode == "threshold":
        return IMAGE_PIXELS
    if feature_mode == "threshold_sobel":
        return COMBINED_FEATURE_PIXELS
    raise ValueError(f"unsupported feature mode: {feature_mode}")


def format_int_array(c_type: str, name: str, tensor: torch.Tensor, columns: int = 12) -> str:
    values = tensor.detach().cpu().reshape(-1).tolist()
    items = [str(int(value)) for value in values]
    lines = []
    for index in range(0, len(items), columns):
        lines.append("    " + ", ".join(items[index : index + columns]))
    return f"static const {c_type} {name}[{len(items)}] = {{\n" + ",\n".join(lines) + "\n};\n"


def evaluate(
    model: ThresholdMLP,
    quantized,
    loader: DataLoader,
) -> dict[str, float]:
    total = 0
    float_correct = 0
    fixed_correct = 0
    agreement = 0
    max_abs_logit_error = 0.0

    model.eval()
    with torch.no_grad():
        for images, labels in loader:
            float_logits = model(images)
            logits_q = fixed_point_logits(images, quantized)
            fixed_logits = dequantize_logits(logits_q, quantized)

            float_pred = float_logits.argmax(dim=1)
            fixed_pred = logits_q.argmax(dim=1)

            labels = labels.to(torch.int64)
            total += int(labels.numel())
            float_correct += int((float_pred == labels).sum().item())
            fixed_correct += int((fixed_pred == labels).sum().item())
            agreement += int((float_pred == fixed_pred).sum().item())
            error = torch.max(torch.abs(float_logits - fixed_logits)).item()
            max_abs_logit_error = max(max_abs_logit_error, float(error))

    return {
        "samples": total,
        "float_accuracy": float_correct / max(total, 1),
        "fixed_accuracy": fixed_correct / max(total, 1),
        "prediction_agreement": agreement / max(total, 1),
        "max_abs_logit_error": max_abs_logit_error,
    }


def collect_sample_predictions(
    model: ThresholdMLP,
    quantized,
    dataset: ThresholdedMnist,
    count: int,
) -> list[dict]:
    samples = []
    model.eval()
    with torch.no_grad():
        for index in range(count):
            image, label = dataset[index]
            image_batched = image.unsqueeze(0)
            float_logits = model(image_batched).squeeze(0)
            logits_q = fixed_point_logits(image_batched, quantized).squeeze(0)
            fixed_logits = dequantize_logits(logits_q.unsqueeze(0), quantized).squeeze(0)
            probabilities = torch.softmax(fixed_logits, dim=0)
            prediction = int(torch.argmax(logits_q).item())

            samples.append(
                {
                    "sample": f"sample_{index:03d}",
                    "label": int(label),
                    "float_prediction": int(torch.argmax(float_logits).item()),
                    "fixed_prediction": prediction,
                    "fixed_confidence": float(probabilities[prediction].item()),
                    "fixed_logits_q": [int(value) for value in logits_q.tolist()],
                    "fixed_logits_dequant": [round(float(value), 6) for value in fixed_logits.tolist()],
                }
            )
    return samples


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=Path("generated/model/threshold_mlp.pt"))
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--header", type=Path, default=Path("generated/headers/model_weights_quantized.h"))
    parser.add_argument("--golden-header", type=Path, default=Path("generated/headers/model_quantized_golden.h"))
    parser.add_argument("--metadata", type=Path, default=Path("generated/model/quantized_metrics.json"))
    parser.add_argument("--threshold", type=int, default=None)
    parser.add_argument("--calibration-samples", type=int, default=1024)
    parser.add_argument("--eval-samples", type=int, default=10000)
    parser.add_argument("--sample-count", type=int, default=8)
    parser.add_argument("--download", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    hidden = int(checkpoint["hidden_features"])
    threshold = int(args.threshold if args.threshold is not None else checkpoint.get("threshold", DEFAULT_THRESHOLD))
    feature_mode = str(checkpoint.get("feature_mode", "threshold"))
    input_features = int(checkpoint.get("input_features", input_features_for_mode(feature_mode)))
    input_scale, input_q_max = input_quantization_for_mode(feature_mode)

    model = build_mlp(input_features=input_features, hidden_features=hidden)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()

    train_set = FeatureMnist(
        args.data_dir,
        train=True,
        threshold=threshold,
        feature_mode=feature_mode,
        download=args.download,
    )
    test_set = FeatureMnist(
        args.data_dir,
        train=False,
        threshold=threshold,
        feature_mode=feature_mode,
        download=args.download,
    )

    calibration_count = min(args.calibration_samples, len(train_set))
    calibration_loader = DataLoader(Subset(train_set, range(calibration_count)), batch_size=256, shuffle=False)
    calibration_inputs = torch.cat([images for images, _labels in calibration_loader], dim=0)
    quantized = quantize_mlp(
        model,
        calibration_inputs,
        input_scale=input_scale,
        input_q_max=input_q_max,
    )

    eval_count = min(args.eval_samples, len(test_set))
    eval_loader = DataLoader(Subset(test_set, range(eval_count)), batch_size=256, shuffle=False)
    metrics = evaluate(model, quantized, eval_loader)
    sample_predictions = collect_sample_predictions(model, quantized, test_set, min(args.sample_count, len(test_set)))

    args.header.parent.mkdir(parents=True, exist_ok=True)
    header_text = [
        "#pragma once",
        "",
        "#include <stdint.h>",
        "",
        f"#define MODEL_INPUTS {input_features}",
        f"#define MODEL_HIDDEN {hidden}",
        "#define MODEL_OUTPUTS 10",
        f"#define MODEL_THRESHOLD {threshold}",
        f"#define MODEL_INPUT_Q_MAX {input_q_max}",
        f"#define MODEL_INPUT_SCALE {input_scale:.10e}f",
        f"#define MODEL_FC1_WEIGHT_SCALE {quantized.fc1_weight_scale:.10e}f",
        f"#define MODEL_HIDDEN_ACT_SCALE {quantized.hidden_activation_scale:.10e}f",
        f"#define MODEL_FC2_WEIGHT_SCALE {quantized.fc2_weight_scale:.10e}f",
        "#define MODEL_LOGIT_SCALE (MODEL_HIDDEN_ACT_SCALE * MODEL_FC2_WEIGHT_SCALE)",
        f"#define MODEL_HIDDEN_REQUANT_MULTIPLIER {quantized.hidden_requant_multiplier}",
        f"#define MODEL_HIDDEN_REQUANT_SHIFT {quantized.hidden_requant_shift}",
        "",
        format_int_array("int8_t", "fc1_weights_q", quantized.fc1_weight_q),
        format_int_array("int32_t", "fc1_bias_q", quantized.fc1_bias_q, columns=8),
        format_int_array("int8_t", "fc2_weights_q", quantized.fc2_weight_q),
        format_int_array("int32_t", "fc2_bias_q", quantized.fc2_bias_q, columns=8),
    ]
    args.header.write_text("\n".join(header_text), encoding="utf-8")

    args.golden_header.parent.mkdir(parents=True, exist_ok=True)
    golden_labels = torch.tensor([sample["label"] for sample in sample_predictions], dtype=torch.int32)
    golden_predictions = torch.tensor(
        [sample["fixed_prediction"] for sample in sample_predictions],
        dtype=torch.int32,
    )
    golden_logits = torch.tensor(
        [sample["fixed_logits_q"] for sample in sample_predictions],
        dtype=torch.int32,
    )
    golden_header_text = [
        "#pragma once",
        "",
        "#include <stdint.h>",
        "",
        f"#define MODEL_GOLDEN_SAMPLE_COUNT {len(sample_predictions)}",
        "#define MODEL_GOLDEN_LOGITS_STRIDE 10",
        "",
        format_int_array("int32_t", "golden_labels", golden_labels, columns=12),
        format_int_array("int32_t", "golden_predictions", golden_predictions, columns=12),
        format_int_array("int32_t", "golden_logits_q", golden_logits, columns=10),
    ]
    args.golden_header.write_text("\n".join(golden_header_text), encoding="utf-8")

    metadata = {
        "checkpoint": str(args.checkpoint),
        "header": str(args.header),
        "golden_header": str(args.golden_header),
        "threshold": threshold,
        "feature_mode": feature_mode,
        "input_features": input_features,
        "hidden_features": hidden,
        "calibration_samples": calibration_count,
        "evaluation": metrics,
        "scales": {
            "input": input_scale,
            "fc1_weight": quantized.fc1_weight_scale,
            "hidden_activation": quantized.hidden_activation_scale,
            "fc2_weight": quantized.fc2_weight_scale,
            "logit": quantized.hidden_activation_scale * quantized.fc2_weight_scale,
        },
        "input_quantization": {
            "q_max": input_q_max,
        },
        "requantization": {
            "hidden_multiplier": quantized.hidden_requant_multiplier,
            "hidden_shift": quantized.hidden_requant_shift,
            "hidden_real_multiplier": (input_scale * quantized.fc1_weight_scale)
            / quantized.hidden_activation_scale,
        },
        "sample_predictions": sample_predictions,
    }
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print(f"saved {args.header}")
    print(f"saved {args.golden_header}")
    print(f"saved {args.metadata}")
    print(
        "fixed_accuracy={fixed_accuracy:.4f} agreement={prediction_agreement:.4f}".format(
            **metrics
        )
    )


if __name__ == "__main__":
    main()
