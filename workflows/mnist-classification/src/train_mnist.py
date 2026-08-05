#!/usr/bin/env python3
"""
ARES — MNIST image classification.

Trains a small convolutional network on MNIST and writes metrics, a confusion
matrix and the trained weights to an output directory.

**torch is the only third-party dependency.** MNIST is read straight from the
IDX files with the standard library, so Katana's `pytorch` module is enough on
its own — there is nothing to pip install and no container to pull. The dataset
is ~11 MB.

Usage:
    python3 train_mnist.py --data-dir DATA --outdir OUT [--epochs 3] ...
"""

import argparse
import array
import gzip
import json
import os
import struct
import sys
import time
import urllib.request

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset

# The mirror torchvision itself uses. The original yann.lecun.com URLs now 404.
MNIST_URL = "https://ossci-datasets.s3.amazonaws.com/mnist/"
MNIST_FILES = {
    "train_images": "train-images-idx3-ubyte.gz",
    "train_labels": "train-labels-idx1-ubyte.gz",
    "test_images": "t10k-images-idx3-ubyte.gz",
    "test_labels": "t10k-labels-idx1-ubyte.gz",
}

# MNIST channel statistics — the standard values used throughout the literature.
MNIST_MEAN = 0.1307
MNIST_STD = 0.3081
NUM_CLASSES = 10


class MnistCNN(nn.Module):
    """Two convolutional blocks, then a small classifier head.

    Deliberately ordinary. The point of this workflow is the HPC plumbing around
    the model, not the model — swap this class for your own and the rest of the
    pipeline keeps working.
    """

    def __init__(self, num_classes=NUM_CLASSES):
        super().__init__()
        self.block1 = nn.Sequential(
            nn.Conv2d(1, 32, kernel_size=3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.Conv2d(32, 32, kernel_size=3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),          # 28x28 -> 14x14
            nn.Dropout(0.25),
        )
        self.block2 = nn.Sequential(
            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),          # 14x14 -> 7x7
            nn.Dropout(0.25),
        )
        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(64 * 7 * 7, 128),
            nn.ReLU(inplace=True),
            nn.Dropout(0.5),
            nn.Linear(128, num_classes),
        )

    def forward(self, x):
        return self.head(self.block2(self.block1(x)))


class Logger:
    """Writes to stdout (so it lands in the PBS log) and to a file at once."""

    def __init__(self, path):
        self.handle = open(path, "w", encoding="utf-8")

    def __call__(self, message=""):
        print(message, flush=True)
        self.handle.write(message + "\n")
        self.handle.flush()

    def close(self):
        self.handle.close()


def download_mnist(data_dir, log):
    """Fetch any missing IDX files. ~11 MB total; a no-op once cached.

    urllib honours HTTP_PROXY/HTTPS_PROXY from the environment, which is what
    lets this work from behind a proxy. Run katana/prepare.sh on a login node
    if the compute nodes have no outbound access.
    """
    os.makedirs(data_dir, exist_ok=True)
    for filename in MNIST_FILES.values():
        target = os.path.join(data_dir, filename)
        if os.path.exists(target):
            continue
        log(f"  downloading {filename}")
        # Download to a .part file so an interrupted transfer can't leave a
        # truncated archive that later runs would try to parse.
        partial = target + ".part"
        try:
            urllib.request.urlretrieve(MNIST_URL + filename, partial)
            os.replace(partial, target)
        except Exception:
            if os.path.exists(partial):
                os.remove(partial)
            raise


def read_idx(path):
    """Parse an IDX file. Returns (dims, array('B') of the payload).

    IDX header: 2 zero bytes, a type byte, then a byte giving the number of
    dimensions, followed by that many big-endian uint32 dimension sizes.
    """
    with gzip.open(path, "rb") as handle:
        magic, = struct.unpack(">I", handle.read(4))
        ndim = magic & 0xFF
        dims = struct.unpack(">" + "I" * ndim, handle.read(4 * ndim))
        payload = handle.read()

    expected = 1
    for d in dims:
        expected *= d
    if len(payload) != expected:
        raise ValueError(
            f"{os.path.basename(path)}: expected {expected} bytes for dims "
            f"{dims}, got {len(payload)} — the file is probably truncated. "
            f"Delete it and re-run to download again."
        )
    return dims, array.array("B", payload)


def to_tensors(image_path, label_path):
    """Read one IDX image/label pair into normalised (images, labels) tensors."""
    (n_images, rows, cols), image_bytes = read_idx(image_path)
    (n_labels,), label_bytes = read_idx(label_path)
    if n_images != n_labels:
        raise ValueError(f"{n_images} images but {n_labels} labels")

    images = torch.frombuffer(bytearray(image_bytes), dtype=torch.uint8)
    images = images.reshape(n_images, 1, rows, cols).float().div_(255.0)
    images = images.sub_(MNIST_MEAN).div_(MNIST_STD)

    labels = torch.frombuffer(bytearray(label_bytes), dtype=torch.uint8).long()
    return images, labels


def load_data(data_dir, batch_size, workers, log):
    log("Loading MNIST")
    download_mnist(data_dir, log)

    paths = {k: os.path.join(data_dir, v) for k, v in MNIST_FILES.items()}
    train_x, train_y = to_tensors(paths["train_images"], paths["train_labels"])
    test_x, test_y = to_tensors(paths["test_images"], paths["test_labels"])

    pin = torch.cuda.is_available()
    train_loader = DataLoader(
        TensorDataset(train_x, train_y), batch_size=batch_size,
        shuffle=True, num_workers=workers, pin_memory=pin,
    )
    test_loader = DataLoader(
        TensorDataset(test_x, test_y), batch_size=max(batch_size, 512),
        shuffle=False, num_workers=workers, pin_memory=pin,
    )
    return train_loader, test_loader


def resolve_device(requested):
    if requested == "cpu":
        return torch.device("cpu")
    if requested == "cuda":
        if not torch.cuda.is_available():
            raise RuntimeError(
                "--device cuda was requested but torch.cuda.is_available() is "
                "False. Check that the job asked for a GPU (ngpus=1) and that "
                "the loaded pytorch module is a CUDA build."
            )
        return torch.device("cuda")
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def train_one_epoch(model, loader, optimiser, device):
    model.train()
    running_loss = 0.0
    seen = 0
    for images, labels in loader:
        images, labels = images.to(device), labels.to(device)
        optimiser.zero_grad(set_to_none=True)
        loss = F.cross_entropy(model(images), labels)
        loss.backward()
        optimiser.step()
        running_loss += loss.item() * labels.size(0)
        seen += labels.size(0)
    return running_loss / seen


@torch.no_grad()
def evaluate(model, loader, device):
    """Return (accuracy, confusion_matrix) over the whole loader."""
    model.eval()
    confusion = torch.zeros(NUM_CLASSES, NUM_CLASSES, dtype=torch.long)
    correct = 0
    seen = 0
    for images, labels in loader:
        images = images.to(device)
        predictions = model(images).argmax(dim=1).cpu()
        correct += (predictions == labels).sum().item()
        seen += labels.size(0)
        # index = true * NUM_CLASSES + predicted, accumulated in one pass
        flat = labels * NUM_CLASSES + predictions
        confusion += torch.bincount(
            flat, minlength=NUM_CLASSES * NUM_CLASSES
        ).reshape(NUM_CLASSES, NUM_CLASSES)
    return correct / seen, confusion


def format_confusion(confusion):
    """Plain-text confusion matrix — rows are true labels, columns predicted."""
    width = max(6, len(str(int(confusion.max()))) + 2)
    lines = [
        "Confusion matrix - rows are true labels, columns are predictions.",
        "",
        " " * 6 + "".join(f"{c:>{width}}" for c in range(NUM_CLASSES)),
    ]
    for true_label in range(NUM_CLASSES):
        row = "".join(f"{int(v):>{width}}" for v in confusion[true_label])
        lines.append(f"{true_label:>4}  {row}")
    return "\n".join(lines) + "\n"


def parse_args():
    parser = argparse.ArgumentParser(description="ARES MNIST image classification")
    parser.add_argument("--data-dir", required=True,
                        help="Directory holding (or to receive) the MNIST IDX files")
    parser.add_argument("--outdir", required=True,
                        help="Directory for metrics, logs and the trained model")
    parser.add_argument("--epochs", type=int, default=3,
                        help="Number of passes over the training set")
    parser.add_argument("--batch-size", type=int, default=128,
                        help="Images per training batch")
    parser.add_argument("--lr", type=float, default=0.001,
                        help="Adam learning rate")
    parser.add_argument("--workers", type=int, default=2,
                        help="DataLoader worker processes")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed, for reproducible accuracy")
    parser.add_argument("--device", choices=["auto", "cuda", "cpu"], default="auto",
                        help="auto falls back to CPU when no GPU is visible")
    return parser.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    os.makedirs(args.data_dir, exist_ok=True)

    log = Logger(os.path.join(args.outdir, "training_log.txt"))
    started = time.time()

    try:
        torch.manual_seed(args.seed)
        device = resolve_device(args.device)
        cuda_available = torch.cuda.is_available()

        log("========================================")
        log("  ARES - MNIST image classification")
        log("========================================")
        log("")
        log(f"PyTorch      : {torch.__version__}")
        log(f"CUDA build   : {torch.version.cuda or 'no (CPU-only build)'}")
        log(f"CUDA visible : {cuda_available}")
        log(f"Device       : {device.type}")
        if device.type == "cuda":
            log(f"GPU          : {torch.cuda.get_device_name(0)}")
        else:
            log("GPU          : none in use - training on CPU")
        log(f"Data dir     : {args.data_dir}")
        log(f"Output dir   : {args.outdir}")
        log(f"Epochs       : {args.epochs}")
        log(f"Batch size   : {args.batch_size}")
        log(f"Learning rate: {args.lr}")
        log("")

        train_loader, test_loader = load_data(
            args.data_dir, args.batch_size, args.workers, log
        )
        log(f"Train images : {len(train_loader.dataset)}")
        log(f"Test images  : {len(test_loader.dataset)}")
        log("")

        model = MnistCNN().to(device)
        parameters = sum(p.numel() for p in model.parameters())
        log(f"Model parameters: {parameters:,}")
        log("")

        optimiser = torch.optim.Adam(model.parameters(), lr=args.lr)

        epochs = []
        for epoch in range(1, args.epochs + 1):
            epoch_started = time.time()
            train_loss = train_one_epoch(model, train_loader, optimiser, device)
            accuracy, confusion = evaluate(model, test_loader, device)
            elapsed = time.time() - epoch_started
            log(f"Epoch {epoch}/{args.epochs}  "
                f"train_loss={train_loss:.4f}  "
                f"test_accuracy={accuracy * 100:.2f}%  "
                f"({elapsed:.1f}s)")
            epochs.append({
                "epoch": epoch,
                "train_loss": round(train_loss, 6),
                "test_accuracy": round(accuracy, 6),
                "seconds": round(elapsed, 2),
            })

        total_seconds = time.time() - started
        final_accuracy = epochs[-1]["test_accuracy"]

        matrix_path = os.path.join(args.outdir, "confusion_matrix.txt")
        with open(matrix_path, "w", encoding="utf-8") as handle:
            handle.write(format_confusion(confusion))

        model_path = os.path.join(args.outdir, "model.pt")
        torch.save(model.state_dict(), model_path)

        metrics = {
            "workflow": "ares-mnist-classification",
            "version": "1.1.0",
            "status": "success",
            "device": device.type,
            "gpu": torch.cuda.get_device_name(0) if device.type == "cuda" else None,
            "torch_version": torch.__version__,
            "torch_cuda_build": torch.version.cuda,
            "cuda_available": cuda_available,
            "parameters": parameters,
            "epochs": epochs,
            "final_test_accuracy": final_accuracy,
            "total_seconds": round(total_seconds, 2),
            "hyperparameters": {
                "epochs": args.epochs,
                "batch_size": args.batch_size,
                "learning_rate": args.lr,
                "seed": args.seed,
            },
        }
        metrics_path = os.path.join(args.outdir, "metrics.json")
        with open(metrics_path, "w", encoding="utf-8") as handle:
            json.dump(metrics, handle, indent=2)
            handle.write("\n")

        log("")
        log(f"Final test accuracy : {final_accuracy * 100:.2f}%")
        log(f"Total time          : {total_seconds:.1f}s")
        log("")
        log("Wrote:")
        for path in (metrics_path, matrix_path, model_path, log.handle.name):
            log(f"  {path}")
        log("")
        log("========================================")
        log("  Complete")
        log("========================================")

    except Exception as error:  # noqa: BLE001 — surface the reason, then fail the job
        log("")
        log(f"FAILED: {type(error).__name__}: {error}")
        log.close()
        raise
    else:
        log.close()


if __name__ == "__main__":
    sys.exit(main())
