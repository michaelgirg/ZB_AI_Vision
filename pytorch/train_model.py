"""Train the thresholded MNIST classifier for the ZedBoard MVP."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from model import build_mlp
from preprocess import (
    COMBINED_FEATURE_PIXELS,
    DEFAULT_THRESHOLD,
    IMAGE_PIXELS,
    classifier_input_for_mode,
)


class FeatureMnist(torch.utils.data.Dataset):
    def __init__(
        self,
        root: Path,
        train: bool,
        threshold: int,
        feature_mode: str,
        download: bool,
    ) -> None:
        self.mnist = datasets.MNIST(
            root=str(root),
            train=train,
            download=download,
            transform=transforms.PILToTensor(),
        )
        self.threshold = threshold
        self.feature_mode = feature_mode

    def __len__(self) -> int:
        return len(self.mnist)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, int]:
        image, label = self.mnist[index]
        return classifier_input_for_mode(image, self.feature_mode, self.threshold), int(label)


def input_features_for_mode(feature_mode: str) -> int:
    if feature_mode == "threshold":
        return IMAGE_PIXELS
    if feature_mode == "threshold_sobel":
        return COMBINED_FEATURE_PIXELS
    raise ValueError(f"unsupported feature mode: {feature_mode}")


def checkpoint_name_for_mode(feature_mode: str) -> str:
    if feature_mode == "threshold":
        return "threshold_mlp.pt"
    if feature_mode == "threshold_sobel":
        return "threshold_sobel_mlp.pt"
    raise ValueError(f"unsupported feature mode: {feature_mode}")


def accuracy(model: nn.Module, loader: DataLoader, device: torch.device) -> float:
    model.eval()
    correct = 0
    total = 0
    with torch.no_grad():
        for images, labels in loader:
            images = images.to(device)
            labels = labels.to(device)
            predictions = model(images).argmax(dim=1)
            correct += int((predictions == labels).sum().item())
            total += int(labels.numel())
    return correct / max(total, 1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--output-dir", type=Path, default=Path("generated/model"))
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--hidden", type=int, default=64)
    parser.add_argument("--feature-mode", choices=("threshold", "threshold_sobel"), default="threshold")
    parser.add_argument("--checkpoint-name", type=str, default=None)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--seed", type=int, default=7)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    input_features = input_features_for_mode(args.feature_mode)
    train_set = FeatureMnist(
        args.data_dir,
        train=True,
        threshold=args.threshold,
        feature_mode=args.feature_mode,
        download=args.download,
    )
    test_set = FeatureMnist(
        args.data_dir,
        train=False,
        threshold=args.threshold,
        feature_mode=args.feature_mode,
        download=args.download,
    )
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True)
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)

    model = build_mlp(input_features=input_features, hidden_features=args.hidden).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    criterion = nn.CrossEntropyLoss()

    history = []
    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        for images, labels in train_loader:
            images = images.to(device)
            labels = labels.to(device)

            optimizer.zero_grad(set_to_none=True)
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.item()) * int(labels.numel())

        train_loss = total_loss / len(train_set)
        test_acc = accuracy(model, test_loader, device)
        history.append({"epoch": epoch, "train_loss": train_loss, "test_accuracy": test_acc})
        print(f"epoch={epoch} train_loss={train_loss:.4f} test_accuracy={test_acc:.4f}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_name = args.checkpoint_name or checkpoint_name_for_mode(args.feature_mode)
    checkpoint_path = args.output_dir / checkpoint_name
    torch.save(
        {
            "model_state": model.cpu().state_dict(),
            "hidden_features": args.hidden,
            "input_features": input_features,
            "feature_mode": args.feature_mode,
            "threshold": args.threshold,
            "image_shape": [28, 28],
        },
        checkpoint_path,
    )

    metrics = {
        "checkpoint": str(checkpoint_path),
        "threshold": args.threshold,
        "feature_mode": args.feature_mode,
        "input_features": input_features,
        "hidden_features": args.hidden,
        "epochs": args.epochs,
        "history": history,
    }
    metrics_name = "metrics.json" if args.feature_mode == "threshold" else f"metrics_{args.feature_mode}.json"
    (args.output_dir / metrics_name).write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(f"saved {checkpoint_path}")


if __name__ == "__main__":
    main()
