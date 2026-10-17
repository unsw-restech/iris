"""The volume reader: a dataset's volume/ in, one lazy 3D array out.

This is the only place that decides how stored intensities are read. The job
and iris-view both go through it, so they always see the same values.
"""

from pathlib import Path

import numpy as np
import xarray as xr


def to_intensity(array):
    """Apply the signed/unsigned rule to stored intensities.

    Provisional rule, until a full-range read of the sample volume on Katana
    fixes it (#24, Further Notes): 16-bit data stored as `short` is read as
    unsigned, as the sample's `data_description` ("<ushort>") says. The bits
    are reinterpreted, so 40000 stored as -25536 reads as 40000 again.
    Works on numpy and dask arrays alike.
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
    lazy (z, y, x) DataArray. Nothing is loaded until it is indexed."""
    files = sorted(Path(dataset, "volume").glob("*.nc"))
    if not files:
        raise FileNotFoundError(f"No .nc files in {Path(dataset, 'volume')}")
    blocks = []
    for f in files:
        # decode_cf=False: no fill-value masking (netCDF's default fill for
        # `short` is a real intensity once read as unsigned) and no float casts.
        var = _volume_variable(xr.open_dataset(f, decode_cf=False, chunks={}), f)
        blocks.append(var.rename(dict(zip(var.dims, ("z", "y", "x")))))
    vol = xr.concat(blocks, dim="z")
    return vol.copy(data=to_intensity(vol.data))
