"""The volume reader: a dataset's volume/ in, one lazy 3D array out.

This is the only place that decides how stored intensities are read. The job
and iris-view both go through it, so they always see the same values.
"""

from pathlib import Path

import numpy as np
import xarray as xr


def to_intensity(array):
    """Apply the signed/unsigned rule to stored intensities.

    16-bit data stored as `short` is read as unsigned, as the sample's
    `data_description` ("<ushort>") says. The bits are reinterpreted, so
    40000 stored as -25536 reads as 40000 again. Works on numpy and dask
    arrays alike.

    Fixed by a full-range read of the microCT sample (job 9544832, #29):
    read as unsigned, its brightest 293 voxels continue the histogram's
    tail smoothly past 32767 up to 34311; read as signed they would sit
    alone near -32768, with nothing between -3 and -1.
    """
    if array.dtype == np.int16:
        return array.view(np.uint16)
    return array


def _volume_variable(ds, path):
    candidates = [name for name, var in ds.data_vars.items() if var.ndim == 3]
    if len(candidates) != 1:
        raise ValueError(f"{path}: expected one 3D variable, found {candidates or 'none'}")
    return ds[candidates[0]]


def open_volume(dataset):
    """Read every .nc block in <dataset>/volume/, in filename order, as one
    lazy (z, y, x) DataArray. Nothing is loaded until it is indexed, and each
    z-slice is its own chunk, so reading one slice reads only that slice."""
    files = sorted(Path(dataset, "volume").glob("*.nc"))
    if not files:
        raise FileNotFoundError(f"No .nc files in {Path(dataset, 'volume')}")
    blocks = []
    for f in files:
        # decode_cf=False: no fill-value masking (netCDF's default fill for
        # `short` is a real intensity once read as unsigned) and no float casts.
        var = _volume_variable(xr.open_dataset(f, decode_cf=False), f)
        # Chunked per slice from the file itself: with whole-block chunks, the
        # unsigned view below stops dask narrowing a slice read to that slice,
        # so each slice read a whole block (740 MB to read one 18 MB slice).
        blocks.append(var.rename(dict(zip(var.dims, ("z", "y", "x")))).chunk({"z": 1}))
    vol = xr.concat(blocks, dim="z")
    return vol.copy(data=to_intensity(vol.data))


def voxel_spacing(dataset):
    """The voxel size <dataset>/volume/'s first block records in its
    voxel_size_xyz and voxel_unit attributes, as the microCT sample's do,
    as {"xyz", "unit"}, or None."""
    first = sorted(Path(dataset, "volume").glob("*.nc"))[0]
    with xr.open_dataset(first, decode_cf=False) as ds:
        xyz = ds.attrs.get("voxel_size_xyz")
        if xyz is None:
            return None
        # str() first gives float32's shortest form: 0.00866752, not 0.008667520061...
        return {"xyz": [float(str(v)) for v in np.atleast_1d(xyz)], "unit": str(ds.attrs.get("voxel_unit", ""))}


class IntensityStats:
    """Min, max, mean and standard deviation over arrays seen one at a time,
    such as a volume's slices as inference reads them. Each array's count,
    mean and sum of squared deviations are merged in (Chan et al.), which
    stays accurate where a running sum of squares would cancel. There are
    no percentiles: they would mean reading the whole volume again."""

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
