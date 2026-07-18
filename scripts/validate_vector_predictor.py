"""Validate the transaction-level vector predictor against checked-in PyTorch vectors."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "generated" / "test_vectors" / "vector_conv4_manifest.json"
WIDTH = 28
HEIGHT = 28
PIXELS = WIDTH * HEIGHT


def read_mem(path: Path) -> list[int]:
    return [int(line.strip(), 16) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def resolve_manifest_path(value: str) -> Path:
    normalized = value.replace("\\", "/")
    return ROOT / normalized


def predict(
    pixels: list[int],
    weights: list[list[int]],
    biases: list[int],
    shifts: list[int],
    relu_enable: list[int],
) -> list[int]:
    if len(pixels) != PIXELS:
        raise ValueError(f"expected {PIXELS} pixels, found {len(pixels)}")

    outputs: list[int] = []
    for row in range(HEIGHT):
        for col in range(WIDTH):
            packed = 0
            if 0 < row < HEIGHT - 1 and 0 < col < WIDTH - 1:
                for filter_index in range(4):
                    accumulator = int(biases[filter_index])
                    tap_index = 0
                    for kernel_row in (-1, 0, 1):
                        for kernel_col in (-1, 0, 1):
                            pixel = pixels[(row + kernel_row) * WIDTH + col + kernel_col]
                            accumulator += pixel * int(weights[filter_index][tap_index])
                            tap_index += 1
                    shifted = accumulator if shifts[filter_index] == 0 else accumulator >> shifts[filter_index]
                    if relu_enable[filter_index] and shifted < 0:
                        shifted = 0
                    shifted = max(0, min(255, shifted))
                    packed |= shifted << (8 * filter_index)
            outputs.append(packed)
    return outputs


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    weights = [
        [int(value) for kernel_row in filter_kernel for value in kernel_row]
        for filter_kernel in manifest["weights"]
    ]
    biases = [int(value) for value in manifest["biases"]]
    shifts = [int(value) for value in manifest["shifts"]]
    relu_enable = [int(value) for value in manifest["relu_enable"]]

    failures = 0
    for sample in manifest["samples"]:
        input_path = resolve_manifest_path(sample["input_mem"])
        expected_path = resolve_manifest_path(sample["conv4_mem"])
        actual = predict(read_mem(input_path), weights, biases, shifts, relu_enable)
        expected = read_mem(expected_path)
        mismatches = [index for index, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]]
        if len(actual) != len(expected):
            mismatches.extend(range(min(len(actual), len(expected)), max(len(actual), len(expected))))
        if mismatches:
            failures += 1
            first = mismatches[0]
            actual_word = actual[first] if first < len(actual) else None
            expected_word = expected[first] if first < len(expected) else None
            print(
                f"FAIL {sample['name']}: mismatches={len(mismatches)} first={first} "
                f"actual={actual_word!r} expected={expected_word!r}"
            )
        else:
            print(f"PASS {sample['name']}: {len(actual)}/{len(expected)} packed outputs")

    if failures:
        raise SystemExit(f"vector predictor validation failed for {failures} sample(s)")
    print("vector predictor validation passed")


if __name__ == "__main__":
    main()
