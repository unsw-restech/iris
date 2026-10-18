"""The dataset record: which data a run used, so a researcher can
find their dataset again and spot if it changed.

The job writes it to dataset.json in the run directory, and the importer
logs it on the MLflow run as the run's dataset input:

  path       the dataset folder
  train      {"images"|"labels": {"path", "files"}}: each training folder
             and how many files it holds
  volume     {"path", "size_bytes", "mtime", "shape", "dtype"}, plus
             "voxel_spacing" {"xyz", "unit"} if the volume records one.
             size_bytes is the total of the .nc blocks and mtime the
             newest block's, in UTC
  intensity  {"min", "max", "mean", "std"} of every voxel, added once
             inference has read the whole volume

There is no content hash and no percentiles: either would mean reading the
whole volume again just for the record.
"""

from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import xarray as xr


def dataset_record(dataset, vol):
    """The record for `dataset`, whose volume `vol` came from
    iris.volume.open_volume, without its intensity statistics."""
    root = Path(dataset).resolve()
    blocks = sorted((root / "volume").glob("*.nc"))
    stats = [f.stat() for f in blocks]
    volume = {
        "path": str(root / "volume"),
        "size_bytes": sum(s.st_size for s in stats),
        "mtime": datetime.fromtimestamp(max(s.st_mtime for s in stats), timezone.utc).isoformat(),
        "shape": list(vol.shape),
        "dtype": str(vol.dtype),
    }
    spacing = voxel_spacing(blocks[0])
    if spacing:
        volume["voxel_spacing"] = spacing
    train = {}
    for name in ("images", "labels"):
        folder = root / "train" / name
        train[name] = {"path": str(folder), "files": sum(1 for p in folder.iterdir() if p.is_file())}
    return {"path": str(root), "train": train, "volume": volume}


class IntensityStats:
    """Min, max, mean and standard deviation over arrays seen one at a time,
    such as a volume's slices as inference reads them. Each array's count,
    mean and sum of squared deviations are merged in (Chan et al.), which
    stays accurate where a running sum of squares would cancel."""

    def __init__(self):
        self.n, self.mean, self.m2 = 0, 0.0, 0.0
        self.min = self.max = None

    def add(self, array):
        a = np.asarray(array)
        if not a.size:
            return
        n, mean = a.size, float(a.mean(dtype=np.float64))
        m2 = float(np.square(a - mean, dtype=np.float64).sum())
        total = self.n + n
        delta = mean - self.mean
        self.mean += delta * n / total
        self.m2 += m2 + delta * delta * self.n * n / total
        self.n = total
        lo, hi = a.min().item(), a.max().item()
        self.min = lo if self.min is None else min(self.min, lo)
        self.max = hi if self.max is None else max(self.max, hi)

    def summary(self):
        """{"min", "max", "mean", "std"}, std being the population one."""
        return {"min": self.min, "max": self.max, "mean": self.mean,
                "std": (self.m2 / self.n) ** 0.5 if self.n else None}


def voxel_spacing(block):
    """The voxel size a netCDF block records in its voxel_size_xyz and
    voxel_unit attributes, as the microCT sample's do, or None."""
    with xr.open_dataset(block, decode_cf=False) as ds:
        xyz = ds.attrs.get("voxel_size_xyz")
        if xyz is None:
            return None
        # str() first gives float32's shortest form: 0.00866752, not 0.008667520061...
        return {"xyz": [float(str(v)) for v in np.atleast_1d(xyz)], "unit": str(ds.attrs.get("voxel_unit", ""))}
