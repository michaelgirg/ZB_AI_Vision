"""Four-filter CNN used to train the vector convolution hardware parameters."""

from __future__ import annotations

import torch
from torch import nn


VECTOR_FILTERS = 4
CLASSIFIER_HIDDEN = 64
IMAGE_HEIGHT = 28
IMAGE_WIDTH = 28


class VectorConvClassifier(nn.Module):
    """Small MNIST classifier with a hardware-matched four-filter front end."""

    def __init__(self, filters: int = VECTOR_FILTERS) -> None:
        super().__init__()
        self.filters = filters
        self.conv = nn.Conv2d(1, filters, kernel_size=3, padding=1, bias=True)
        self.relu = nn.ReLU()
        self.pool = nn.MaxPool2d(kernel_size=2, stride=2)
        self.classifier = nn.Sequential(
            nn.Linear(filters * 14 * 14, CLASSIFIER_HIDDEN),
            nn.ReLU(),
            nn.Linear(CLASSIFIER_HIDDEN, 10),
        )

        border_mask = torch.ones((1, 1, IMAGE_HEIGHT, IMAGE_WIDTH), dtype=torch.float32)
        border_mask[:, :, 0, :] = 0.0
        border_mask[:, :, -1, :] = 0.0
        border_mask[:, :, :, 0] = 0.0
        border_mask[:, :, :, -1] = 0.0
        self.register_buffer("border_mask", border_mask, persistent=False)

    def forward_features(self, image: torch.Tensor) -> torch.Tensor:
        features = self.relu(self.conv(image))
        return features * self.border_mask

    def classify_features(self, features: torch.Tensor) -> torch.Tensor:
        pooled = self.pool(features)
        return self.classifier(pooled.reshape(pooled.shape[0], -1))

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return self.classify_features(self.forward_features(image))
