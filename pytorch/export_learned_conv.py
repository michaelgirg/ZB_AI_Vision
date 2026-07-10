"""Export learned INT8 3x3 convolution golden vectors and config headers."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

from preprocess import (
    IMAGE_HEIGHT,
    IMAGE_PIXELS,
    IMAGE_WIDTH,
    LEARNED_CONV_BIAS,
    LEARNED_CONV_KERNEL,
    LEARNED_CONV_RELU_EN,
    LEARNED_CONV_SHIFT,
    learned_conv3x3_u8_tensor,
    tensor_to_mem_lines,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-vector-dir", type=Path, default=Path("generated/test_vectors"))
    parser.add_argument("--header-dir", type=Path, default=Path("generated/headers"))
    parser.add_argument("--sample", type=str, default="sample_000")
    parser.add_argument("--all-samples", action="store_true")
    return parser.parse_args()


def read_mem_u8(path: Path) -> torch.Tensor:
    values = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped:
            values.append(int(stripped, 16))

    if len(values) != IMAGE_PIXELS:
        raise ValueError(f"{path} has {len(values)} pixels, expected {IMAGE_PIXELS}")

    return torch.tensor(values, dtype=torch.uint8).reshape(IMAGE_HEIGHT, IMAGE_WIDTH)


def c_signed8(value: int) -> str:
    return f"{value}"


def write_config_header(path: Path) -> None:
    kernel_flat = [value for row in LEARNED_CONV_KERNEL for value in row]
    kernel_items = ", ".join(c_signed8(int(value)) for value in kernel_flat)

    path.write_text(
        "#pragma once\n\n"
        "#include <stdint.h>\n\n"
        "#define LEARNED_CONV_KERNEL_SIZE 9\n"
        f"#define LEARNED_CONV_BIAS {int(LEARNED_CONV_BIAS)}\n"
        f"#define LEARNED_CONV_SHIFT {int(LEARNED_CONV_SHIFT)}\n"
        f"#define LEARNED_CONV_RELU_EN {int(LEARNED_CONV_RELU_EN)}\n\n"
        f"static const int8_t learned_conv_kernel[LEARNED_CONV_KERNEL_SIZE] = "
        f"{{ {kernel_items} }};\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    args.test_vector_dir.mkdir(parents=True, exist_ok=True)
    args.header_dir.mkdir(parents=True, exist_ok=True)

    if args.all_samples:
        input_paths = sorted(args.test_vector_dir.glob("sample_*_input.mem"))
    else:
        input_paths = [args.test_vector_dir / f"{args.sample}_input.mem"]

    if not input_paths:
        raise FileNotFoundError(f"No sample input .mem files found in {args.test_vector_dir}")

    manifest = {
        "kernel": LEARNED_CONV_KERNEL,
        "bias": int(LEARNED_CONV_BIAS),
        "shift": int(LEARNED_CONV_SHIFT),
        "relu_enable": int(LEARNED_CONV_RELU_EN),
        "samples": [],
    }

    for input_path in input_paths:
        if not input_path.exists():
            raise FileNotFoundError(input_path)

        stem = input_path.name.replace("_input.mem", "")
        image = read_mem_u8(input_path)
        conv = learned_conv3x3_u8_tensor(image)
        conv_path = args.test_vector_dir / f"{stem}_conv.mem"
        conv_path.write_text("\n".join(tensor_to_mem_lines(conv)) + "\n", encoding="utf-8")

        manifest["samples"].append(
            {
                "name": stem,
                "input_mem": str(input_path),
                "conv_mem": str(conv_path),
            }
        )
        print(f"{stem}: wrote {conv_path}")

    write_config_header(args.header_dir / "learned_conv_config.h")
    (args.test_vector_dir / "learned_conv_manifest.json").write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )
    print(f"wrote {args.header_dir / 'learned_conv_config.h'}")
    print(f"wrote {args.test_vector_dir / 'learned_conv_manifest.json'}")


if __name__ == "__main__":
    main()
