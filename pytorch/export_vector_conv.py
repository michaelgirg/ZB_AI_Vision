"""Quantize the trained four-filter convolution and export RTL golden data."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import torch
import torch.nn.functional as functional
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms

from vector_conv_model import IMAGE_HEIGHT, IMAGE_WIDTH, VECTOR_FILTERS, VectorConvClassifier


IMAGE_PIXELS = IMAGE_HEIGHT * IMAGE_WIDTH
TAPS = 9


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=Path("generated/model/vector_conv4_cnn.pt"))
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--test-vector-dir", type=Path, default=Path("generated/test_vectors"))
    parser.add_argument("--header-dir", type=Path, default=Path("generated/headers"))
    parser.add_argument("--calibration-samples", type=int, default=2048)
    parser.add_argument("--calibration-percentile", type=float, default=0.999)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--all-samples", action="store_true")
    parser.add_argument("--sample", type=str, default="sample_000")
    return parser.parse_args()


def read_mem_u8(path: Path) -> torch.Tensor:
    values = [int(line.strip(), 16) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(values) != IMAGE_PIXELS:
        raise ValueError(f"{path} contains {len(values)} pixels, expected {IMAGE_PIXELS}")
    return torch.tensor(values, dtype=torch.uint8).reshape(1, 1, IMAGE_HEIGHT, IMAGE_WIDTH)


def quantize_parameters(model: VectorConvClassifier) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    weights = model.conv.weight.detach().cpu()[:, 0, :, :]
    biases = model.conv.bias.detach().cpu()
    weight_scales = weights.abs().reshape(VECTOR_FILTERS, -1).amax(dim=1) / 127.0
    weight_scales = torch.clamp(weight_scales, min=1e-12)
    q_weights = torch.round(weights / weight_scales[:, None, None]).clamp(-128, 127).to(torch.int8)
    q_biases = torch.round(biases * 255.0 / weight_scales).to(torch.int32)
    return q_weights, q_biases, weight_scales


def integer_accumulators(
    images_u8: torch.Tensor,
    q_weights: torch.Tensor,
    q_biases: torch.Tensor,
) -> torch.Tensor:
    patches = functional.unfold(images_u8.to(torch.float64), kernel_size=3, padding=1).to(torch.int64)
    weights_flat = q_weights.reshape(VECTOR_FILTERS, TAPS).to(torch.int64)
    accum = torch.einsum("fk,bkl->bfl", weights_flat, patches)
    accum = accum + q_biases.to(torch.int64).reshape(1, VECTOR_FILTERS, 1)
    return accum.reshape(images_u8.shape[0], VECTOR_FILTERS, IMAGE_HEIGHT, IMAGE_WIDTH)


def choose_shifts(accum: torch.Tensor, percentile: float) -> torch.Tensor:
    shifts = []
    for filter_index in range(VECTOR_FILTERS):
        interior = torch.clamp(accum[:, filter_index, 1:-1, 1:-1], min=0).reshape(-1).to(torch.float64)
        reference = float(torch.quantile(interior, percentile).item())
        ratio = max(reference / 240.0, 1.0)
        shifts.append(min(31, max(0, int(math.ceil(math.log2(ratio))))))
    return torch.tensor(shifts, dtype=torch.int64)


def fixed_features(accum: torch.Tensor, shifts: torch.Tensor) -> torch.Tensor:
    output = torch.zeros_like(accum, dtype=torch.uint8)
    for filter_index in range(VECTOR_FILTERS):
        shifted = torch.bitwise_right_shift(accum[:, filter_index], int(shifts[filter_index].item()))
        output[:, filter_index] = torch.clamp(shifted, 0, 255).to(torch.uint8)
    output[:, :, 0, :] = 0
    output[:, :, -1, :] = 0
    output[:, :, :, 0] = 0
    output[:, :, :, -1] = 0
    return output


def packed_mem_lines(features: torch.Tensor) -> list[str]:
    if features.shape != (VECTOR_FILTERS, IMAGE_HEIGHT, IMAGE_WIDTH):
        raise ValueError(f"unexpected feature shape {tuple(features.shape)}")
    channels = features.reshape(VECTOR_FILTERS, IMAGE_PIXELS).to(torch.int64)
    packed = channels[0] | (channels[1] << 8) | (channels[2] << 16) | (channels[3] << 24)
    return [f"{int(value):08X}" for value in packed.tolist()]


def write_header(
    path: Path,
    q_weights: torch.Tensor,
    q_biases: torch.Tensor,
    shifts: torch.Tensor,
    output_scales: torch.Tensor,
) -> None:
    lines = [
        "#pragma once",
        "",
        "#include <stdint.h>",
        "",
        "#define VECTOR_CONV_FILTERS 4",
        "#define VECTOR_CONV_TAPS 9",
        "",
        "static const int8_t vector_conv_weights[VECTOR_CONV_FILTERS][VECTOR_CONV_TAPS] = {",
    ]
    for filter_index in range(VECTOR_FILTERS):
        values = ", ".join(str(int(value)) for value in q_weights[filter_index].reshape(-1).tolist())
        lines.append(f"    {{ {values} }},")
    lines.extend(
        [
            "};",
            "",
            "static const int32_t vector_conv_bias[VECTOR_CONV_FILTERS] = {",
            "    " + ", ".join(str(int(value)) for value in q_biases.tolist()),
            "};",
            "",
            "static const uint8_t vector_conv_shift[VECTOR_CONV_FILTERS] = {",
            "    " + ", ".join(str(int(value)) for value in shifts.tolist()),
            "};",
            "",
            "static const uint8_t vector_conv_relu_enable[VECTOR_CONV_FILTERS] = { 1, 1, 1, 1 };",
            "",
            "static const float vector_conv_output_scale[VECTOR_CONV_FILTERS] = {",
            "    " + ", ".join(f"{float(value):.10g}f" for value in output_scales.tolist()),
            "};",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def quantized_accuracy(
    model: VectorConvClassifier,
    loader: DataLoader,
    q_weights: torch.Tensor,
    q_biases: torch.Tensor,
    shifts: torch.Tensor,
    output_scales: torch.Tensor,
) -> float:
    model.eval()
    correct = 0
    total = 0
    with torch.no_grad():
        for images, labels in loader:
            images_u8 = torch.round(images * 255.0).to(torch.uint8)
            accum = integer_accumulators(images_u8, q_weights, q_biases)
            fixed = fixed_features(accum, shifts).to(torch.float32)
            dequantized = fixed * output_scales.reshape(1, VECTOR_FILTERS, 1, 1)
            predictions = model.classify_features(dequantized).argmax(dim=1)
            correct += int((predictions == labels).sum().item())
            total += int(labels.numel())
    return correct / max(total, 1)


def main() -> None:
    args = parse_args()
    if not 0.0 < args.calibration_percentile <= 1.0:
        raise ValueError("calibration percentile must be in range (0, 1]")

    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model = VectorConvClassifier(filters=int(checkpoint["filters"]))
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    q_weights, q_biases, weight_scales = quantize_parameters(model)

    transform = transforms.ToTensor()
    train_set = datasets.MNIST(root=str(args.data_dir), train=True, download=False, transform=transform)
    calibration_count = min(args.calibration_samples, len(train_set))
    calibration_loader = DataLoader(
        Subset(train_set, range(calibration_count)),
        batch_size=args.batch_size,
        shuffle=False,
    )
    calibration_accum = []
    for images, _ in calibration_loader:
        calibration_accum.append(
            integer_accumulators(torch.round(images * 255.0).to(torch.uint8), q_weights, q_biases)
        )
    shifts = choose_shifts(torch.cat(calibration_accum, dim=0), args.calibration_percentile)
    output_scales = weight_scales * torch.pow(2.0, shifts.to(torch.float32)) / 255.0

    test_set = datasets.MNIST(root=str(args.data_dir), train=False, download=False, transform=transform)
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)
    fixed_accuracy = quantized_accuracy(
        model,
        test_loader,
        q_weights,
        q_biases,
        shifts,
        output_scales,
    )

    args.test_vector_dir.mkdir(parents=True, exist_ok=True)
    args.header_dir.mkdir(parents=True, exist_ok=True)
    if args.all_samples:
        input_paths = sorted(args.test_vector_dir.glob("sample_*_input.mem"))
    else:
        input_paths = [args.test_vector_dir / f"{args.sample}_input.mem"]
    if not input_paths:
        raise FileNotFoundError("no input memory files were found")

    samples = []
    for input_path in input_paths:
        image_u8 = read_mem_u8(input_path)
        features = fixed_features(integer_accumulators(image_u8, q_weights, q_biases), shifts)[0]
        stem = input_path.name.replace("_input.mem", "")
        output_path = args.test_vector_dir / f"{stem}_conv4.mem"
        output_path.write_text("\n".join(packed_mem_lines(features)) + "\n", encoding="utf-8")
        samples.append(
            {
                "name": stem,
                "input_mem": str(input_path),
                "conv4_mem": str(output_path),
            }
        )
        print(f"{stem}: wrote {output_path}")

    header_path = args.header_dir / "vector_conv4_config.h"
    write_header(header_path, q_weights, q_biases, shifts, output_scales)
    manifest = {
        "checkpoint": str(args.checkpoint),
        "filters": VECTOR_FILTERS,
        "layout": "NHWC packed as filter0 in bits 7:0 through filter3 in bits 31:24",
        "weights": q_weights.to(torch.int32).tolist(),
        "biases": q_biases.tolist(),
        "shifts": shifts.tolist(),
        "relu_enable": [1] * VECTOR_FILTERS,
        "weight_scales": weight_scales.tolist(),
        "output_scales": output_scales.tolist(),
        "fixed_feature_classifier_accuracy": fixed_accuracy,
        "calibration_samples": calibration_count,
        "calibration_percentile": args.calibration_percentile,
        "samples": samples,
    }
    manifest_path = args.test_vector_dir / "vector_conv4_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"fixed-feature classifier accuracy={fixed_accuracy:.4f}")
    print(f"wrote {header_path}")
    print(f"wrote {manifest_path}")


if __name__ == "__main__":
    main()
