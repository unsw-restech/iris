"""The label writer: label slices in, one slice-compressed uint8 BigTIFF out.

Each z-slice is its own deflate-compressed page, so viewers (napari, Fiji)
can read one slice at a time without decompressing the volume.
"""

import numpy as np
import tifffile

MAX_CLASSES = 255  # uint8, with 0 kept for unlabelled


def write_label_volume(path, slices, shape):
    """Write `slices`, an iterable of (y, x) arrays yielded in z order, as a
    (z, y, x) uint8 BigTIFF. Slices are converted to uint8 as they arrive;
    a value outside 0-255 raises rather than wrapping."""

    def pages():
        for s in slices:
            s = np.asarray(s)
            if s.shape != tuple(shape[1:]):
                raise ValueError(f"label slice has shape {s.shape}, expected {tuple(shape[1:])}")
            if s.size and (s.min() < 0 or s.max() > MAX_CLASSES):
                raise ValueError(f"label values must be 0-{MAX_CLASSES}")
            yield s.astype(np.uint8)

    with tifffile.TiffWriter(path, bigtiff=True) as tif:
        tif.write(pages(), shape=tuple(shape), dtype=np.uint8,
                  compression="zlib", photometric="minisblack", metadata={"axes": "ZYX"})
