"""Validate exported golden vectors before RTL or Vitis consumes them."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


IMAGE_PIXELS = 784
IMAGE_WIDTH = 28
IMAGE_HEIGHT = 28
COMBINED_FEATURE_PIXELS = IMAGE_PIXELS * 2


def read_mem(path: Path) -> list[int]:
    values = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        text = line.strip()
        if not text:
            continue
        if len(text) != 2:
            raise ValueError(f"{path}:{line_number}: expected two hex digits, got {text!r}")
        try:
            value = int(text, 16)
        except ValueError as exc:
            raise ValueError(f"{path}:{line_number}: invalid hex byte {text!r}") from exc
        if not 0 <= value <= 255:
            raise ValueError(f"{path}:{line_number}: byte out of range")
        values.append(value)
    return values


def file_sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def resolve_path(base: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return (base / path).resolve()


def first_mismatch(actual: list[int], expected: list[int]) -> int:
    for index, (actual_value, expected_value) in enumerate(zip(actual, expected)):
        if actual_value != expected_value:
            return index
    return min(len(actual), len(expected))


def byte_at(values: list[int], index: int) -> str:
    if index >= len(values):
        return "<missing>"
    return f"0x{values[index]:02X}"


def sobel_expected(input_values: list[int]) -> list[int]:
    if len(input_values) != IMAGE_PIXELS:
        raise ValueError(f"expected {IMAGE_PIXELS} input pixels, got {len(input_values)}")

    output = [0 for _ in range(IMAGE_PIXELS)]
    for row in range(1, IMAGE_HEIGHT - 1):
        for col in range(1, IMAGE_WIDTH - 1):
            index = row * IMAGE_WIDTH + col
            top_left = input_values[(row - 1) * IMAGE_WIDTH + (col - 1)]
            top = input_values[(row - 1) * IMAGE_WIDTH + col]
            top_right = input_values[(row - 1) * IMAGE_WIDTH + (col + 1)]
            left = input_values[row * IMAGE_WIDTH + (col - 1)]
            right = input_values[row * IMAGE_WIDTH + (col + 1)]
            bottom_left = input_values[(row + 1) * IMAGE_WIDTH + (col - 1)]
            bottom = input_values[(row + 1) * IMAGE_WIDTH + col]
            bottom_right = input_values[(row + 1) * IMAGE_WIDTH + (col + 1)]

            gx = -top_left + top_right - (2 * left) + (2 * right) - bottom_left + bottom_right
            gy = -top_left - (2 * top) - top_right + bottom_left + (2 * bottom) + bottom_right
            output[index] = min(abs(gx) + abs(gy), 255)

    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("generated/test_vectors/manifest.json"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest.resolve()
    project_root = manifest_path.parents[2]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    threshold = int(manifest["threshold"])

    failures = 0
    for sample in manifest["samples"]:
        name = sample["name"]
        sample_failures = 0
        input_mem = resolve_path(project_root, sample["input_mem"])
        threshold_mem = resolve_path(project_root, sample["threshold_mem"])
        sobel_mem = resolve_path(project_root, sample["sobel_mem"]) if "sobel_mem" in sample else None
        combined_mem = (
            resolve_path(project_root, sample["threshold_sobel_mem"])
            if "threshold_sobel_mem" in sample
            else None
        )

        input_values = read_mem(input_mem)
        threshold_values = read_mem(threshold_mem)
        sobel_values = read_mem(sobel_mem) if sobel_mem is not None else None
        combined_values = read_mem(combined_mem) if combined_mem is not None else None

        if len(input_values) != IMAGE_PIXELS:
            print(f"FAIL {name}: input has {len(input_values)} pixels, expected {IMAGE_PIXELS}")
            sample_failures += 1
        if len(threshold_values) != IMAGE_PIXELS:
            print(f"FAIL {name}: threshold output has {len(threshold_values)} pixels, expected {IMAGE_PIXELS}")
            sample_failures += 1
        if sobel_values is not None and len(sobel_values) != IMAGE_PIXELS:
            print(f"FAIL {name}: Sobel output has {len(sobel_values)} pixels, expected {IMAGE_PIXELS}")
            sample_failures += 1
        if combined_values is not None and len(combined_values) != COMBINED_FEATURE_PIXELS:
            print(
                f"FAIL {name}: combined feature output has {len(combined_values)} pixels, "
                f"expected {COMBINED_FEATURE_PIXELS}"
            )
            sample_failures += 1

        expected = [255 if value >= threshold else 0 for value in input_values]
        if threshold_values != expected:
            first = first_mismatch(threshold_values, expected)
            print(
                f"FAIL {name}: threshold mismatch at pixel {first}: "
                f"got {byte_at(threshold_values, first)}, expected {byte_at(expected, first)}"
            )
            sample_failures += 1

        if sobel_values is not None:
            expected_sobel = sobel_expected(input_values)
            if sobel_values != expected_sobel:
                first = first_mismatch(sobel_values, expected_sobel)
                print(
                    f"FAIL {name}: Sobel mismatch at pixel {first}: "
                    f"got {byte_at(sobel_values, first)}, expected {byte_at(expected_sobel, first)}"
                )
                sample_failures += 1

        if combined_values is not None and sobel_values is not None:
            expected_combined = threshold_values + sobel_values
            if combined_values != expected_combined:
                first = first_mismatch(combined_values, expected_combined)
                print(
                    f"FAIL {name}: combined feature mismatch at byte {first}: "
                    f"got {byte_at(combined_values, first)}, expected {byte_at(expected_combined, first)}"
                )
                sample_failures += 1

        for key, expected_hash in sample.get("sha256", {}).items():
            if key == "input_mem":
                path = input_mem
            elif key == "threshold_mem":
                path = threshold_mem
            elif key == "sobel_mem":
                path = sobel_mem
            elif key == "threshold_sobel_mem":
                path = combined_mem
            else:
                path = resolve_path(project_root, sample[key])
            if path is None:
                print(f"FAIL {name}: missing path for hash key {key}")
                sample_failures += 1
                continue
            actual_hash = file_sha256(path)
            if actual_hash != expected_hash:
                print(f"FAIL {name}: sha256 mismatch for {key}")
                sample_failures += 1

        if sample_failures == 0:
            print(
                f"PASS {name}: label={sample['label']} prediction={sample['prediction']} "
                f"confidence={float(sample.get('confidence', 0.0)):.3f}"
            )
        failures += sample_failures

    if failures:
        print(f"golden validation failed with {failures} issue(s)")
        return 1

    print("golden validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
