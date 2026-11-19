"""Build the demonstration workflow's prepared dataset from BBBC039.

https://bbbc.broadinstitute.org/BBBC039 publishes 200 fields: a TIFF of each,
a labelled image of each, and metadata lists splitting them. This script needs
all three unpacked, and runs in the microct/1 environment:

    bin/envrun microct/1 python workflows/microscopy-cell-segmentation/dataset/prepare_bbbc039.py \\
        --images <images folder> --labelled-images <labelled images folder> \\
        --metadata <metadata folder> --output <new folder>

The fields in training.txt become training pairs, in train/images/ and
train/labels/, and those in test.txt become the image set, in images/, so the
images a run segments are ones its model did not train on. Those in
validation.txt are not used.

A labelled image is a colour PNG on black in which touching nuclei have
different colours. A label slice is a uint8 TIFF holding class 1 for
background, class 2 for nucleus and class 3 for nucleus edge, the two pixels
just inside each nucleus's outline. 0 stays reserved for unlabelled, so no
slice holds it. The image frame is no nucleus's outline: a nucleus it cuts has
no edge along it.

Every field is checked before anything is written, so a refused run leaves no
dataset behind, and the dataset is built under a temporary name beside it and
renamed into place, so a run killed halfway leaves none either.
"""

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
import tifffile
from PIL import Image
from scipy import ndimage

BACKGROUND, NUCLEUS, NUCLEUS_EDGE = 1, 2, 3
EDGE_WIDTH = 2


class Refused(Exception):
    """A problem with the download, said in one line."""


def separate_nuclei(colours):
    """Number each nucleus in an (y, x, 3) colour array, 0 for background: a
    nucleus is one connected piece of one colour."""
    packed = colours[..., 0] << 16 | colours[..., 1] << 8 | colours[..., 2]
    nuclei = np.zeros(packed.shape, dtype=np.int32)
    numbered = 0
    for colour in np.unique(packed[packed > 0]):
        pieces, count = ndimage.label(packed == colour)
        nuclei[pieces > 0] = pieces[pieces > 0] + numbered
        numbered += count
    return nuclei


def label_slice(colours):
    """The label slice for an (y, x, 3) colour array."""
    nuclei = separate_nuclei(colours)
    reach = ndimage.iterate_structure(ndimage.generate_binary_structure(2, 1), EDGE_WIDTH)
    # A pixel is edge if another nucleus or the background lies within reach.
    # "nearest" repeats the frame's own pixels, so the frame adds no edge.
    highest = ndimage.maximum_filter(nuclei, footprint=reach, mode="nearest")
    lowest = ndimage.minimum_filter(nuclei, footprint=reach, mode="nearest")
    labels = np.full(nuclei.shape, BACKGROUND, dtype=np.uint8)
    labels[nuclei > 0] = NUCLEUS
    labels[(nuclei > 0) & (highest != lowest)] = NUCLEUS_EDGE
    return labels


def read_list(metadata, name):
    """The field names a metadata list holds, without their extension."""
    path = metadata / name
    try:
        return [Path(line).stem for line in path.read_text().split()]
    except OSError as error:
        raise Refused(f"{path}: can't read the list: {error.strerror}") from error


def image_kind(path):
    """The (shape, data type) of a single-page 2D TIFF."""
    try:
        with tifffile.TiffFile(path) as tiff:
            page = tiff.pages[0]
            if len(tiff.pages) != 1 or page.ndim != 2:
                raise Refused(f"{path}: not a single-page, single-channel 2D TIFF")
            return page.shape, page.dtype
    except (OSError, tifffile.TiffFileError) as error:
        raise Refused(f"{path}: can't read the image: {error}") from error


def read_colours(path):
    """A labelled image as an (y, x, 3) colour array."""
    try:
        with Image.open(path) as image:
            return np.asarray(image.convert("RGB"), dtype=np.uint32)
    except OSError as error:
        raise Refused(f"{path}: can't read the labelled image: {error}") from error


def prepare(images, labelled_images, metadata, output):
    if output.exists():
        raise Refused(f"{output}: already exists; give a new folder")
    training = read_list(metadata, "training.txt")
    test = read_list(metadata, "test.txt")
    both = sorted(set(training) & set(test))
    if both:
        raise Refused(f"{both[0]}: listed for both training and the image set")

    kinds = {stem: image_kind(images / f"{stem}.tif") for stem in training + test}
    if len(set(kinds.values())) > 1:
        first = next(iter(kinds))
        other = next(stem for stem in kinds if kinds[stem] != kinds[first])
        raise Refused(f"{other}.tif: its size or bit depth differs from {first}.tif's")
    labels = {}
    for stem in training:
        path = labelled_images / f"{stem}.png"
        colours = read_colours(path)
        if colours.shape[:2] != kinds[stem][0]:
            raise Refused(f"{path}: {colours.shape[:2]} pixels, but {stem}.tif is {kinds[stem][0]}")
        labels[stem] = label_slice(colours)

    # Built under a temporary name beside the dataset, then renamed into
    # place, so a run killed halfway leaves no dataset, only a hidden
    # .<name>.*.partial folder that no later run reads.
    output.parent.mkdir(parents=True, exist_ok=True)
    building = Path(tempfile.mkdtemp(prefix=f".{output.name}.", suffix=".partial", dir=output.parent))
    try:
        umask = os.umask(0)
        os.umask(umask)
        building.chmod(0o777 & ~umask)  # as mkdir would have made it, not mkdtemp's owner-only
        image_set, train_images, train_labels = (building / "images", building / "train" / "images",
                                                 building / "train" / "labels")
        for folder in (image_set, train_images, train_labels):
            folder.mkdir(parents=True)
        for stem in test:
            shutil.copyfile(images / f"{stem}.tif", image_set / f"{stem}.tif")
        for stem in training:
            shutil.copyfile(images / f"{stem}.tif", train_images / f"{stem}.tif")
            tifffile.imwrite(train_labels / f"{stem}.tif", labels[stem])
        building.rename(output)
    except BaseException:
        shutil.rmtree(building, ignore_errors=True)
        raise
    print(f"{output}: {len(training)} training pairs, {len(test)} images in the image set")


def main():
    parser = argparse.ArgumentParser(description="Build the prepared dataset from BBBC039.")
    parser.add_argument("--images", type=Path, required=True, help="the folder of BBBC039's TIFFs")
    parser.add_argument("--labelled-images", type=Path, required=True, help="the folder of BBBC039's colour PNGs")
    parser.add_argument("--metadata", type=Path, required=True, help="the folder holding training.txt and test.txt")
    parser.add_argument("--output", type=Path, required=True, help="the prepared dataset's folder, which must not exist")
    args = parser.parse_args()
    try:
        prepare(args.images, args.labelled_images, args.metadata, args.output)
    except Refused as refused:
        sys.exit(f"prepare_bbbc039: {refused}")


if __name__ == "__main__":
    main()
