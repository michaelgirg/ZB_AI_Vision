"""Train the four-filter CNN front end used by the vector convolution RTL."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from vector_conv_model import VECTOR_FILTERS, VectorConvClassifier


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path("generated/data"))
    parser.add_argument("--output-dir", type=Path, default=Path("generated/model"))
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--download", action="store_true")
    return parser.parse_args()


def evaluate(model: nn.Module, loader: DataLoader, device: torch.device) -> float:
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


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    transform = transforms.ToTensor()
    train_set = datasets.MNIST(
        root=str(args.data_dir),
        train=True,
        download=args.download,
        transform=transform,
    )
    test_set = datasets.MNIST(
        root=str(args.data_dir),
        train=False,
        download=args.download,
        transform=transform,
    )
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True)
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)

    model = VectorConvClassifier().to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    criterion = nn.CrossEntropyLoss()

    history = []
    for epoch in range(1, args.epochs + 1):
        model.train()
        loss_sum = 0.0
        for images, labels in train_loader:
            images = images.to(device)
            labels = labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            loss_sum += float(loss.item()) * int(labels.numel())

        test_accuracy = evaluate(model, test_loader, device)
        train_loss = loss_sum / len(train_set)
        history.append(
            {
                "epoch": epoch,
                "train_loss": train_loss,
                "test_accuracy": test_accuracy,
            }
        )
        print(f"epoch={epoch} train_loss={train_loss:.4f} test_accuracy={test_accuracy:.4f}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_path = args.output_dir / "vector_conv4_cnn.pt"
    torch.save(
        {
            "model_state": model.cpu().state_dict(),
            "filters": VECTOR_FILTERS,
            "image_shape": [28, 28],
            "epochs": args.epochs,
            "seed": args.seed,
        },
        checkpoint_path,
    )
    metrics = {
        "checkpoint": str(checkpoint_path),
        "filters": VECTOR_FILTERS,
        "epochs": args.epochs,
        "seed": args.seed,
        "history": history,
    }
    (args.output_dir / "metrics_vector_conv4.json").write_text(
        json.dumps(metrics, indent=2),
        encoding="utf-8",
    )
    print(f"saved {checkpoint_path}")


if __name__ == "__main__":
    main()
