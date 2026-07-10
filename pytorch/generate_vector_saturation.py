"""Generate a deterministic saturation vector for MODE=3 coverage closure."""

from __future__ import annotations

from pathlib import Path


IMAGE_WIDTH = 28
IMAGE_HEIGHT = 28


def main() -> None:
    output_path = Path("generated/test_vectors/vector4_saturation.mem")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="ascii", newline="\n") as output_file:
        for row in range(IMAGE_HEIGHT):
            for column in range(IMAGE_WIDTH):
                border = (
                    row == 0
                    or row == IMAGE_HEIGHT - 1
                    or column == 0
                    or column == IMAGE_WIDTH - 1
                )
                output_file.write("00000000\n" if border else "ffffffff\n")

    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
