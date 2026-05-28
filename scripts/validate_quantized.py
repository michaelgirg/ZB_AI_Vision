"""Validate the exported quantized model metadata."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, default=Path("generated/model/quantized_metrics.json"))
    parser.add_argument("--min-fixed-accuracy", type=float, default=0.93)
    parser.add_argument("--min-agreement", type=float, default=0.97)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    evaluation = metadata["evaluation"]
    project_root = args.metadata.resolve().parents[2]

    failures = 0
    fixed_accuracy = float(evaluation["fixed_accuracy"])
    agreement = float(evaluation["prediction_agreement"])

    if fixed_accuracy < args.min_fixed_accuracy:
        print(
            f"FAIL: fixed accuracy {fixed_accuracy:.4f} is below "
            f"{args.min_fixed_accuracy:.4f}"
        )
        failures += 1

    if agreement < args.min_agreement:
        print(f"FAIL: prediction agreement {agreement:.4f} is below {args.min_agreement:.4f}")
        failures += 1

    for key in ("header", "golden_header"):
        path = Path(metadata[key])
        if not path.is_absolute():
            path = project_root / path
        if not path.exists():
            print(f"FAIL: missing exported {key}: {path}")
            failures += 1

    bad_samples = [
        sample for sample in metadata["sample_predictions"]
        if int(sample["fixed_prediction"]) != int(sample["label"])
    ]
    if bad_samples:
        names = ", ".join(sample["sample"] for sample in bad_samples)
        print(f"FAIL: fixed-point exported sample prediction mismatch for {names}")
        failures += 1

    if failures:
        print(f"quantized validation failed with {failures} issue(s)")
        return 1

    print(
        "PASS: fixed_accuracy={:.4f} agreement={:.4f} max_abs_logit_error={:.4f}".format(
            fixed_accuracy,
            agreement,
            float(evaluation["max_abs_logit_error"]),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
