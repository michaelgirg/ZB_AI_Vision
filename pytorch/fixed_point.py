"""Fixed-point quantization utilities for ARM deployment."""

from __future__ import annotations

from dataclasses import dataclass

import torch
from torch import nn


@dataclass(frozen=True)
class QuantizedMLP:
    """Integer representation of the two-layer threshold MLP."""

    input_scale: float
    input_q_max: int
    fc1_weight_q: torch.Tensor
    fc1_bias_q: torch.Tensor
    fc2_weight_q: torch.Tensor
    fc2_bias_q: torch.Tensor
    fc1_weight_scale: float
    hidden_activation_scale: float
    fc2_weight_scale: float
    hidden_requant_multiplier: int
    hidden_requant_shift: int


def symmetric_int8_scale(tensor: torch.Tensor) -> float:
    max_abs = float(tensor.detach().abs().max().item())
    if max_abs == 0.0:
        return 1.0
    return max_abs / 127.0


def quantize_symmetric_int8(tensor: torch.Tensor, scale: float) -> torch.Tensor:
    return torch.clamp(torch.round(tensor.detach().cpu() / scale), -127, 127).to(torch.int8)


def classifier_input_to_q(tensor: torch.Tensor, input_scale: float, input_q_max: int) -> torch.Tensor:
    """Convert normalized classifier inputs into unsigned integer features."""
    if input_scale <= 0.0:
        raise ValueError("input_scale must be positive")
    return torch.clamp(torch.round(tensor.detach().cpu() / input_scale), 0, input_q_max).to(torch.int32)


def calibrate_hidden_activation_scale(
    model: nn.Module,
    calibration_inputs: torch.Tensor,
) -> float:
    """Choose a uint7 ReLU activation scale from representative inputs."""
    model.eval()
    with torch.no_grad():
        hidden = torch.relu(model.fc1(calibration_inputs.reshape(calibration_inputs.shape[0], -1)))

    max_value = float(hidden.max().item())
    if max_value == 0.0:
        return 1.0
    return max_value / 127.0


def quantize_mlp(
    model: nn.Module,
    calibration_inputs: torch.Tensor,
    input_scale: float = 1.0,
    input_q_max: int = 1,
) -> QuantizedMLP:
    """Post-training quantize the MLP for integer ARM inference."""
    model.eval()

    fc1_weight_scale = symmetric_int8_scale(model.fc1.weight)
    hidden_activation_scale = calibrate_hidden_activation_scale(model, calibration_inputs)
    fc2_weight_scale = symmetric_int8_scale(model.fc2.weight)

    fc1_weight_q = quantize_symmetric_int8(model.fc1.weight, fc1_weight_scale)
    fc2_weight_q = quantize_symmetric_int8(model.fc2.weight, fc2_weight_scale)
    hidden_requant_shift = 20
    hidden_requant_multiplier = max(
        1,
        int(round(((input_scale * fc1_weight_scale) / hidden_activation_scale) * (1 << hidden_requant_shift))),
    )

    fc1_bias_q = torch.round(model.fc1.bias.detach().cpu() / (input_scale * fc1_weight_scale)).to(torch.int32)
    fc2_bias_q = torch.round(
        model.fc2.bias.detach().cpu() / (hidden_activation_scale * fc2_weight_scale)
    ).to(torch.int32)

    return QuantizedMLP(
        input_scale=input_scale,
        input_q_max=input_q_max,
        fc1_weight_q=fc1_weight_q,
        fc1_bias_q=fc1_bias_q,
        fc2_weight_q=fc2_weight_q,
        fc2_bias_q=fc2_bias_q,
        fc1_weight_scale=fc1_weight_scale,
        hidden_activation_scale=hidden_activation_scale,
        fc2_weight_scale=fc2_weight_scale,
        hidden_requant_multiplier=hidden_requant_multiplier,
        hidden_requant_shift=hidden_requant_shift,
    )


def requantize_relu_to_uint7(hidden_acc: torch.Tensor, quantized: QuantizedMLP) -> torch.Tensor:
    """Requantize first-layer accumulators using integer multiplier/shift math."""
    positive = torch.clamp(hidden_acc.to(torch.int64), min=0)
    rounding = 1 << (quantized.hidden_requant_shift - 1)
    hidden_q = (
        (positive * int(quantized.hidden_requant_multiplier) + rounding)
        >> int(quantized.hidden_requant_shift)
    )
    return torch.clamp(hidden_q, 0, 127).to(torch.int32)


def fixed_point_logits(inputs: torch.Tensor, quantized: QuantizedMLP) -> torch.Tensor:
    """Run integer inference and return int32 output logits.

    The returned values are in the second-layer accumulator domain. Argmax can
    be taken directly on these integer logits.
    """
    x_q = classifier_input_to_q(
        inputs,
        input_scale=quantized.input_scale,
        input_q_max=quantized.input_q_max,
    ).reshape(inputs.shape[0], -1)

    fc1_w = quantized.fc1_weight_q.to(torch.int32)
    hidden_acc = x_q @ fc1_w.t() + quantized.fc1_bias_q.to(torch.int32)
    hidden_q = requantize_relu_to_uint7(hidden_acc, quantized)

    fc2_w = quantized.fc2_weight_q.to(torch.int32)
    return hidden_q @ fc2_w.t() + quantized.fc2_bias_q.to(torch.int32)


def dequantize_logits(logits_q: torch.Tensor, quantized: QuantizedMLP) -> torch.Tensor:
    scale = quantized.hidden_activation_scale * quantized.fc2_weight_scale
    return logits_q.to(torch.float32) * scale
