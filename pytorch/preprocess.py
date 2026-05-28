"""Shared preprocessing utilities for the ZedBoard AI vision pipeline."""

from __future__ import annotations

from typing import Iterable

import torch


IMAGE_WIDTH = 28
IMAGE_HEIGHT = 28
IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT
COMBINED_FEATURE_PIXELS = IMAGE_PIXELS * 2
DEFAULT_THRESHOLD = 128


def threshold_u8_tensor(image: torch.Tensor, threshold: int = DEFAULT_THRESHOLD) -> torch.Tensor:
    """Return a uint8 thresholded image with values 0 or 255."""
    if not 0 <= threshold <= 255:
        raise ValueError("threshold must be in range 0..255")

    image_u8 = to_u8_image(image)
    return torch.where(
        image_u8 >= threshold,
        torch.full_like(image_u8, 255),
        torch.zeros_like(image_u8),
    )


def classifier_input_from_u8(image: torch.Tensor, threshold: int = DEFAULT_THRESHOLD) -> torch.Tensor:
    """Return a flattened float tensor containing 0.0 or 1.0 classifier inputs."""
    thresholded = threshold_u8_tensor(image, threshold)
    return (thresholded.reshape(-1).float() / 255.0).contiguous()


def sobel_u8_tensor(image: torch.Tensor) -> torch.Tensor:
    """Return a uint8 Sobel edge image using a 3x3 kernel and zero borders."""
    image_i32 = to_u8_image(image).to(torch.int32)
    output = torch.zeros((IMAGE_HEIGHT, IMAGE_WIDTH), dtype=torch.uint8)

    top_left = image_i32[:-2, :-2]
    top = image_i32[:-2, 1:-1]
    top_right = image_i32[:-2, 2:]
    left = image_i32[1:-1, :-2]
    right = image_i32[1:-1, 2:]
    bottom_left = image_i32[2:, :-2]
    bottom = image_i32[2:, 1:-1]
    bottom_right = image_i32[2:, 2:]

    gx = -top_left + top_right - (2 * left) + (2 * right) - bottom_left + bottom_right
    gy = -top_left - (2 * top) - top_right + bottom_left + (2 * bottom) + bottom_right
    edge = torch.clamp(torch.abs(gx) + torch.abs(gy), 0, 255).to(torch.uint8)
    output[1:-1, 1:-1] = edge

    return output.contiguous()


def threshold_sobel_u8_features(
    image: torch.Tensor,
    threshold: int = DEFAULT_THRESHOLD,
) -> torch.Tensor:
    """Return flattened uint8 threshold and Sobel features."""
    thresholded = threshold_u8_tensor(image, threshold).reshape(-1)
    sobel = sobel_u8_tensor(image).reshape(-1)
    return torch.cat((thresholded, sobel), dim=0).contiguous()


def threshold_sobel_classifier_input_from_u8(
    image: torch.Tensor,
    threshold: int = DEFAULT_THRESHOLD,
) -> torch.Tensor:
    """Return 1568 normalized float features: threshold image followed by Sobel image."""
    features = threshold_sobel_u8_features(image, threshold)
    return (features.float() / 255.0).contiguous()


def classifier_input_for_mode(
    image: torch.Tensor,
    feature_mode: str,
    threshold: int = DEFAULT_THRESHOLD,
) -> torch.Tensor:
    """Return classifier input features for the requested preprocessing mode."""
    if feature_mode == "threshold":
        return classifier_input_from_u8(image, threshold)
    if feature_mode == "threshold_sobel":
        return threshold_sobel_classifier_input_from_u8(image, threshold)
    raise ValueError(f"unsupported feature mode: {feature_mode}")


def to_u8_image(image: torch.Tensor) -> torch.Tensor:
    """Normalize common MNIST tensor formats to a 28x28 uint8 tensor."""
    if image.ndim == 3 and image.shape[0] == 1:
        image = image.squeeze(0)

    if image.shape != (IMAGE_HEIGHT, IMAGE_WIDTH):
        raise ValueError(f"expected image shape {(IMAGE_HEIGHT, IMAGE_WIDTH)}, got {tuple(image.shape)}")

    if image.dtype == torch.uint8:
        return image.contiguous()

    if image.is_floating_point():
        max_value = float(image.max().item())
        min_value = float(image.min().item())
        if min_value < 0.0:
            raise ValueError("floating-point image values must be non-negative")
        if max_value <= 1.0:
            return torch.clamp(torch.round(image * 255.0), 0, 255).to(torch.uint8).contiguous()
        return torch.clamp(torch.round(image), 0, 255).to(torch.uint8).contiguous()

    return torch.clamp(image, 0, 255).to(torch.uint8).contiguous()


def tensor_to_mem_lines(values: torch.Tensor) -> list[str]:
    """Convert uint8 tensor values to two-digit hex lines for Verilog $readmemh."""
    flat = values.reshape(-1).to(torch.uint8).tolist()
    return [f"{int(value):02X}" for value in flat]


def c_array_u8(name: str, values: Iterable[int], columns: int = 16) -> str:
    """Format uint8 values as a C array."""
    items = [f"0x{int(value) & 0xFF:02X}" for value in values]
    lines = []
    for index in range(0, len(items), columns):
        lines.append("    " + ", ".join(items[index : index + columns]))
    body = ",\n".join(lines)
    return f"static const unsigned char {name}[{len(items)}] = {{\n{body}\n}};\n"
