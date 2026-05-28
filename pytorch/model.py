"""Small classifiers used by the ZedBoard AI vision pipeline."""

from __future__ import annotations

import torch
from torch import nn

from preprocess import COMBINED_FEATURE_PIXELS, IMAGE_PIXELS


class ThresholdMLP(nn.Module):
    """MLP for thresholded 28x28 digit images."""

    def __init__(self, hidden_features: int = 64, input_features: int = IMAGE_PIXELS) -> None:
        super().__init__()
        self.input_features = input_features
        self.fc1 = nn.Linear(input_features, hidden_features)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(hidden_features, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x.reshape(x.shape[0], self.input_features)
        x = self.fc1(x)
        x = self.relu(x)
        return self.fc2(x)


class ThresholdSobelMLP(ThresholdMLP):
    """MLP for combined threshold and Sobel 28x28 feature vectors."""

    def __init__(self, hidden_features: int = 96) -> None:
        super().__init__(hidden_features=hidden_features, input_features=COMBINED_FEATURE_PIXELS)


def build_mlp(input_features: int, hidden_features: int) -> ThresholdMLP:
    """Build the two-layer classifier used by both baseline and Sobel models."""
    return ThresholdMLP(hidden_features=hidden_features, input_features=input_features)
