"""A tiny synthetic microCT dataset, laid out as iris.dataset reads one, for
the library's tests and the workflows' synthetic runs: a netCDF volume in
blocks, as the sample has it, and two-class training pairs.
"""

import netCDF4
import numpy as np
import tifffile

BLOCK_SLICES = 3
N_BLOCKS = 2
NY, NX = 70, 50  # not a multiple of the patch size or of the U-Net's stride
SHAPE = (BLOCK_SLICES * N_BLOCKS, NY, NX)
VOXEL_SIZE_XYZ = [0.5, 0.5, 0.25]


def make_volume():
    """Unsigned 16-bit intensities, most of them above 32767.

    32769 is netCDF's default fill value for `short` once stored (-32767),
    so a reader that masks fill values would lose it."""
    rng = np.random.default_rng(0)
    vol = rng.integers(1000, 4000, size=SHAPE, dtype=np.uint16)
    vol[:, :, NX // 2:] = rng.integers(40000, 60000, size=(SHAPE[0], NY, NX - NX // 2), dtype=np.uint16)
    vol[0, 0, 0] = 32769
    vol[-1, -1, -1] = 65535
    return vol


def write_dataset(root, vol, labels):
    """Lay out <root>/volume/*.nc and <root>/train/{images,labels}/*.tif."""
    (root / "volume").mkdir(parents=True)
    for b in range(N_BLOCKS):
        block = vol[b * BLOCK_SLICES:(b + 1) * BLOCK_SLICES]
        with netCDF4.Dataset(root / "volume" / f"block{b:08d}.nc", "w", format="NETCDF3_CLASSIC") as nc:
            nc.createDimension("tomo_zdim", block.shape[0])
            nc.createDimension("tomo_ydim", NY)
            nc.createDimension("tomo_xdim", NX)
            nc.createDimension("md5_dim", 16)
            nc.data_description = "Raw reconstructed tomogram data <ushort>"
            nc.voxel_size_xyz = np.array(VOXEL_SIZE_XYZ, dtype=np.float32)  # as the sample has them
            nc.voxel_unit = "mm"
            var = nc.createVariable("tomo", "i2", ("tomo_zdim", "tomo_ydim", "tomo_xdim"), fill_value=False)
            var.set_auto_maskandscale(False)
            var[:] = block.view(np.int16)  # stored as `short`, like the sample volume
            nc.createVariable("md5_checksum", "i1", ("md5_dim",))[:] = np.arange(16) + b
    (root / "train" / "images").mkdir(parents=True)
    (root / "train" / "labels").mkdir(parents=True)
    for z, lab in labels.items():
        name = f"slice{z:04d}.tif"
        tifffile.imwrite(root / "train" / "images" / name, vol[z].view(np.int16))  # same dtype as the volume
        tifffile.imwrite(root / "train" / "labels" / name, lab)


def two_class_labels():
    """Three training pairs: class 1 on the dim half, class 2 on the bright
    half, with a band of 0 (unlabelled) pixels between them."""
    labels = {}
    for z in (0, 2, 5):
        lab = np.zeros((NY, NX), dtype=np.uint8)
        lab[:, :NX // 2 - 3] = 1
        lab[:, NX // 2 + 3:] = 2
        lab[: NY // 4] = 0
        labels[z] = lab
    return labels
