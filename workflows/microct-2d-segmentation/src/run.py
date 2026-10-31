#!/usr/bin/env python3
"""microCT 2D Segmentation (U-Net): the reference workflow's entry point.

Trains a 2D U-Net from scratch on a dataset's training pairs, then segments
its whole volume slice by slice along z into one label volume. Before it
runs this script, the job writes it into --run-dir as run.py and records
its code there (iris_record_code in lib/iris-job.sh). The script writes the
rest there: the label volume (uint8 BigTIFF, one deflate page per slice),
the trained weights, and the run's record through RunRecord, with every
form field and the seed actually used, which dataset it read, and training
loss and per-class Dice/IoU on held-out patches per epoch. The workflow
page's table lists every file, and iris.rundir names them.

Classes are 1..K, where K is the highest value in train/labels; 0 marks an
unlabelled pixel and is never predicted. lib/ must be on PYTHONPATH (the job
script does this).
"""

import argparse
import os
import secrets
import sys
import time
from pathlib import Path

import numpy as np
import tifffile
import torch
import torch.nn as nn
import torch.nn.functional as F

from iris import rundir
from iris.dataset import IntensityStats, dataset_record
from iris.labels import MAX_CLASSES, write_label_volume
from iris.record import RunRecord
from iris.volume import open_volume, to_intensity

# This workflow's folder in the clone; its name is the slug. A job runs a
# copy of this script from the run directory and sets IRIS_CODE to it.
CODE = Path(os.environ.get("IRIS_CODE") or Path(__file__).resolve().parents[1])

DOWNSAMPLE = 16  # the U-Net halves the image four times
TILE = 1024      # inference tile edge; bounds GPU memory whatever the slice size
MARGIN = 32      # context around each tile, cropped off after the forward pass


class DatasetError(Exception):
    """A problem with the researcher's dataset, reported as one line."""


# -- Data ------------------------------------------------------------------

def pad_to(img, h, w, mode="reflect"):
    """Pad a 2D array at the bottom and right to h x w."""
    return np.pad(img, ((0, h - img.shape[0]), (0, w - img.shape[1])), mode=mode)


def read_training_pairs(dataset):
    """Return [(name, image, label)] for train/images and train/labels,
    paired by identical filename. Images keep their dtype, after the volume
    reader's signed/unsigned rule; labels are int64."""
    images = Path(dataset, "train", "images")
    labels = Path(dataset, "train", "labels")
    for d in (images, labels):
        if not d.is_dir():
            raise DatasetError(f"Missing {d}")
    names = sorted(p.name for p in images.iterdir() if p.is_file())
    label_names = sorted(p.name for p in labels.iterdir() if p.is_file())
    if names != label_names:
        odd = sorted(set(names) ^ set(label_names))[:5]
        raise DatasetError(f"train/images and train/labels hold different file names: {', '.join(odd)}")
    if not names:
        raise DatasetError(f"No training pairs in {images}")

    pairs = []
    for name in names:
        img = tifffile.imread(images / name)
        lab = tifffile.imread(labels / name)
        if img.ndim != 2 or lab.shape != img.shape:
            raise DatasetError(f"{name}: image {img.shape} and label {lab.shape} must be matching 2D slices")
        if np.issubdtype(lab.dtype, np.floating) and not np.array_equal(lab, np.round(lab)):
            raise DatasetError(f"{name}: label values must be whole numbers")
        if lab.min() < 0:
            raise DatasetError(f"{name}: label values must be 0 (unlabelled) or a class number from 1")
        pairs.append((name, to_intensity(img), lab.astype(np.int64)))
    return pairs


def count_classes(pairs):
    n = max(int(lab.max()) for _, _, lab in pairs)
    if n > MAX_CLASSES:
        raise DatasetError(
            f"The labels hold {n} classes; at most {MAX_CLASSES} fit in the uint8 label volume.")
    if n < 1:
        raise DatasetError("The labels hold no class: every pixel is 0 (unlabelled).")
    return n


def cut_patches(pairs, size):
    """Cut every pair into size x size patches on a non-overlapping grid.
    Edge patches are padded (image by reflection, label with 0, unlabelled).
    Patches with no labelled pixel teach nothing and are dropped, so the
    held-out percentage is of labelled patches."""
    images, labels = [], []
    for _, img, lab in pairs:
        h = img.shape[0] + -img.shape[0] % size
        w = img.shape[1] + -img.shape[1] % size
        img = pad_to(img, h, w)
        lab = pad_to(lab, h, w, mode="constant")
        for y in range(0, img.shape[0], size):
            for x in range(0, img.shape[1], size):
                lp = lab[y:y + size, x:x + size]
                if lp.any():
                    images.append(img[y:y + size, x:x + size])
                    labels.append(lp)
    return np.stack(images), np.stack(labels)


def split(n, val_percent, rng):
    """Hold out val_percent of n patches at random. Keeps at least one patch
    on each side when there are two or more."""
    order = rng.permutation(n)
    n_val = round(n * val_percent / 100)
    if n >= 2:
        n_val = min(max(n_val, 1 if val_percent > 0 else 0), n - 1)
    else:
        n_val = 0
    return order[n_val:], order[:n_val]


# -- Model -----------------------------------------------------------------

def block(cin, cout):
    return nn.Sequential(
        nn.Conv2d(cin, cout, 3, padding=1, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True),
        nn.Conv2d(cout, cout, 3, padding=1, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True),
    )


class UNet(nn.Module):
    """A plain 2D U-Net: four downsamplings, 32 channels at the top."""

    def __init__(self, n_classes, base=32):
        super().__init__()
        ch = [base * 2 ** i for i in range(5)]
        self.down = nn.ModuleList([block(1, ch[0])] + [block(ch[i], ch[i + 1]) for i in range(4)])
        self.up = nn.ModuleList([nn.ConvTranspose2d(ch[i + 1], ch[i], 2, stride=2) for i in reversed(range(4))])
        self.merge = nn.ModuleList([block(ch[i] * 2, ch[i]) for i in reversed(range(4))])
        self.head = nn.Conv2d(ch[0], n_classes, 1)

    def forward(self, x):
        skips = []
        for i, down in enumerate(self.down):
            x = down(x if i == 0 else F.max_pool2d(x, 2))
            skips.append(x)
        x = skips.pop()
        for up, merge in zip(self.up, self.merge):
            x = merge(torch.cat([skips.pop(), up(x)], dim=1))
        return self.head(x)


# -- Training --------------------------------------------------------------

def augment(x, y):
    """Random flips and quarter turns, the same for image and label."""
    k = int(torch.randint(4, (1,)))
    x, y = torch.rot90(x, k, (-2, -1)), torch.rot90(y, k, (-2, -1))
    if torch.rand(1) < 0.5:
        x, y = x.flip(-1), y.flip(-1)
    return x, y


def train_epoch(model, opt, images, labels, batch_size, device, generator):
    model.train()
    order = torch.randperm(len(images), generator=generator)
    total, n = 0.0, 0
    for i in range(0, len(order), batch_size):
        idx = order[i:i + batch_size]
        x, y = augment(images[idx], labels[idx])
        x, y = x.to(device), y.to(device)
        loss = F.cross_entropy(model(x), y, ignore_index=-1)
        opt.zero_grad()
        loss.backward()
        opt.step()
        total += loss.item() * len(idx)
        n += len(idx)
    return total / n


@torch.no_grad()
def score(model, images, labels, n_classes, batch_size, device):
    """Per-class Dice and IoU over the labelled pixels of the held-out
    patches, pooled across patches. None where a class is absent from both
    prediction and truth."""
    model.eval()
    tp = torch.zeros(n_classes, dtype=torch.float64)
    fp = torch.zeros_like(tp)
    fn = torch.zeros_like(tp)
    for i in range(0, len(images), batch_size):
        x = images[i:i + batch_size].to(device)
        y = labels[i:i + batch_size].to(device)
        pred = model(x).argmax(1)
        known = y >= 0
        p, t = pred[known], y[known]
        for c in range(n_classes):
            tp[c] += ((p == c) & (t == c)).sum().item()
            fp[c] += ((p == c) & (t != c)).sum().item()
            fn[c] += ((p != c) & (t == c)).sum().item()
    dice, iou = {}, {}
    for c in range(n_classes):
        denom = tp[c] + fp[c] + fn[c]
        key = str(c + 1)
        dice[key] = float(2 * tp[c] / (denom + tp[c])) if denom else None
        iou[key] = float(tp[c] / denom) if denom else None
    return dice, iou


# -- Inference -------------------------------------------------------------

@torch.no_grad()
def segment(model, vol, mean, std, device, intensity):
    """Yield one uint8 label slice (classes 1..K) per z-slice of `vol`,
    adding each slice's stored intensities to `intensity`.

    Each slice is segmented in TILE x TILE tiles, each seen with MARGIN
    pixels of context on every side so tile edges leave no seams."""
    model.eval()
    ny, nx = vol.shape[1:]
    tile = min(TILE, max(ny, nx) + -max(ny, nx) % DOWNSAMPLE)
    h, w = ny + -ny % tile, nx + -nx % tile
    for z in range(vol.shape[0]):
        raw = vol[z].values
        intensity.add(raw)
        img = (raw.astype(np.float32) - mean) / std
        img = np.pad(pad_to(img, h, w), MARGIN, mode="reflect")
        out = np.empty((h, w), dtype=np.uint8)
        for y in range(0, h, tile):
            for x in range(0, w, tile):
                window = img[y:y + tile + 2 * MARGIN, x:x + tile + 2 * MARGIN]
                pred = model(torch.from_numpy(np.ascontiguousarray(window))[None, None].to(device)).argmax(1)[0]
                out[y:y + tile, x:x + tile] = (pred[MARGIN:-MARGIN, MARGIN:-MARGIN] + 1).cpu().numpy()
        yield out[:ny, :nx]


# -- Entry point -----------------------------------------------------------

def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--dataset", required=True, help="dataset folder holding volume/ and train/")
    p.add_argument("--run-dir", required=True, help="where every output of this run goes")
    p.add_argument("--experiment", default="microct-2d-segmentation")
    p.add_argument("--epochs", type=int, default=50)
    p.add_argument("--patch-size", type=int, default=256)
    p.add_argument("--lr", type=float, default=0.001)
    p.add_argument("--val-percent", type=float, default=20)
    p.add_argument("--batch-size", type=int, default=16)
    p.add_argument("--seed", default="", help="blank picks a new random seed, which is recorded")
    p.add_argument("--field", action="append", default=[], metavar="NAME=VALUE",
                   help="a form field this script does not use, such as ncpus, recorded in params.json")
    args = p.parse_args(argv)
    if args.patch_size < 2 * DOWNSAMPLE or args.patch_size % DOWNSAMPLE:
        # Below 32 the U-Net's bottleneck is 1x1, where BatchNorm fails on a batch of one.
        p.error(f"--patch-size must be a multiple of {DOWNSAMPLE}, at least {2 * DOWNSAMPLE}")
    if not 0 <= args.val_percent < 100:
        p.error("--val-percent must be from 0 to under 100")
    if args.seed.strip():
        try:
            args.seed = int(args.seed)
        except ValueError:
            p.error("--seed must be a whole number or blank")
    else:
        args.seed = secrets.randbelow(2 ** 31)
    try:
        args.fields = dict(f.split("=", 1) for f in args.field)
    except ValueError:
        p.error("--field must be NAME=VALUE")
    return args


def main(argv=None):
    args = parse_args(argv)
    run_dir = Path(args.run_dir)

    # Everything that can fail on the dataset fails here, before training.
    pairs = read_training_pairs(args.dataset)
    n_classes = count_classes(pairs)
    try:
        vol = open_volume(args.dataset)
    except (FileNotFoundError, ValueError) as e:
        raise DatasetError(e) from e
    for name, img, _ in pairs:
        if img.shape != vol.shape[1:]:
            raise DatasetError(f"{name} is {img.shape}; volume slices are {vol.shape[1:]}")
        if img.dtype != vol.dtype:
            # Mean and std come from the training images, so a different
            # intensity scale would quietly ruin the whole label volume.
            raise DatasetError(f"{name} is {img.dtype}; the volume is {vol.dtype}. Export training images at the volume's bit depth.")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    gpu = torch.cuda.get_device_name(device) if device.type == "cuda" else "none"
    with RunRecord(run_dir, args.experiment, CODE, tags={"gpu": gpu}) as record:
        dataset = record.write_dataset(lambda: dataset_record(args.dataset, vol))
        intensity = IntensityStats()
        train_and_segment(args, record, pairs, n_classes, vol, device, intensity)
        if dataset is not None:
            record.write_dataset(lambda: {**dataset, "intensity": intensity.summary()})


def train_and_segment(args, record, pairs, n_classes, vol, device, intensity):
    """Train on the training pairs, then segment the whole volume into the
    run directory, recording params and per-epoch metrics as it goes and
    adding every slice it reads to `intensity`, an IntensityStats."""
    run_dir = record.run_dir
    started = time.time()
    torch.manual_seed(args.seed)
    rng = np.random.default_rng(args.seed)
    generator = torch.Generator().manual_seed(args.seed)

    pixels = np.concatenate([img.ravel() for _, img, _ in pairs]).astype(np.float32)
    mean, std = float(pixels.mean()), float(pixels.std()) or 1.0
    images, labels = cut_patches(pairs, args.patch_size)
    train_idx, val_idx = split(len(images), args.val_percent, rng)
    images = torch.from_numpy((images.astype(np.float32) - mean) / std)[:, None]
    labels = torch.from_numpy(labels - 1)  # classes 0..K-1, unlabelled -1

    params = {
        "dataset": str(Path(args.dataset).resolve()),
        "run_dir": str(run_dir.resolve()),
        "experiment": args.experiment,
        "epochs": args.epochs,
        "patch_size": args.patch_size,
        "lr": args.lr,
        "val_percent": args.val_percent,
        "batch_size": args.batch_size,
        "seed": args.seed,
        "n_classes": n_classes,
        "training_pairs": len(pairs),
        "train_patches": len(train_idx),
        "val_patches": len(val_idx),
        "intensity_mean": mean,
        "intensity_std": std,
        "volume_shape": list(vol.shape),
        "device": str(device),
        **args.fields,
    }
    record.write_params(params)
    if args.val_percent > 0 and not len(val_idx):
        print("WARNING: only one labelled patch, so none is held out and Dice/IoU are empty. "
              "Use a smaller patch size or label more slices.", file=sys.stderr)
    print(f"{len(pairs)} training pairs, {n_classes} classes, "
          f"{len(train_idx)} training / {len(val_idx)} held-out patches, seed {args.seed}, on {device}")

    model = UNet(n_classes).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    for epoch in range(1, args.epochs + 1):
        loss = train_epoch(model, opt, images[train_idx], labels[train_idx], args.batch_size, device, generator)
        dice, iou = score(model, images[val_idx], labels[val_idx], n_classes, args.batch_size, device)
        record.log_epoch(epoch, train_loss=loss, dice=dice, iou=iou)
        print(f"epoch {epoch}/{args.epochs}  loss {loss:.4f}  dice {dice}")
    trained = time.time()
    print(f"Set up and trained {args.epochs} epochs in {trained - started:.0f} s")

    torch.save({"state_dict": model.state_dict(), "n_classes": n_classes,
                "intensity_mean": mean, "intensity_std": std}, run_dir / rundir.MODEL)

    write_label_volume(run_dir / rundir.LABELS, segment(model, vol, mean, std, device, intensity), vol.shape)
    print(f"Wrote {run_dir / 'labels.tif'} {tuple(vol.shape)} in {time.time() - trained:.0f} s")


if __name__ == "__main__":
    try:
        main()
    except DatasetError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
