"""Export trained PyTorch weights to a C header for Vitis."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch

from model import ThresholdMLP


def format_float_array(name: str, tensor: torch.Tensor, columns: int = 8) -> str:
    values = tensor.detach().cpu().reshape(-1).tolist()
    items = [f"{float(value):.8e}f" for value in values]
    lines = []
    for index in range(0, len(items), columns):
        lines.append("    " + ", ".join(items[index : index + columns]))
    return f"static const float {name}[{len(items)}] = {{\n" + ",\n".join(lines) + "\n};\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, default=Path("generated/model/threshold_mlp.pt"))
    parser.add_argument("--output", type=Path, default=Path("generated/headers/model_weights.h"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    hidden = int(checkpoint["hidden_features"])

    model = ThresholdMLP(hidden_features=hidden)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    text = [
        "#pragma once",
        "",
        "#define MODEL_INPUTS 784",
        f"#define MODEL_HIDDEN {hidden}",
        "#define MODEL_OUTPUTS 10",
        f"#define MODEL_THRESHOLD {int(checkpoint['threshold'])}",
        "",
        format_float_array("fc1_weights", model.fc1.weight),
        format_float_array("fc1_bias", model.fc1.bias),
        format_float_array("fc2_weights", model.fc2.weight),
        format_float_array("fc2_bias", model.fc2.bias),
    ]
    args.output.write_text("\n".join(text), encoding="utf-8")
    print(f"saved {args.output}")


if __name__ == "__main__":
    main()
