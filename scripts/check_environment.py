"""Check whether the Python golden pipeline dependencies are available."""

from __future__ import annotations

import importlib.util
import sys


REQUIRED = ["torch", "torchvision"]


def main() -> int:
    missing = [name for name in REQUIRED if importlib.util.find_spec(name) is None]
    print(f"python: {sys.version.split()[0]}")
    if missing:
        print("missing: " + ", ".join(missing))
        print("Install PyTorch and torchvision before training.")
        return 1
    print("ok: torch and torchvision are available")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

