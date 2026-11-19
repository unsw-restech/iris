"""The BBBC039 preparation script, run as the IRIS maintainer runs it, on tiny
made-up labelled images, asserting on the files it writes. A mistake here
would silently train the model on wrong labels. bin/check runs it in
microct/1 through tests/bin/test_prepare_bbbc039.sh.

The labelled images are written as BBBC039 publishes its own: RGBA PNGs on
black whose nuclei are the very dark reds (1, 0, 0), (2, 0, 0) and (3, 0, 0).
"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import tifffile
from PIL import Image

SCRIPT = Path(__file__).resolve().parent / "prepare_bbbc039.py"

COLOURS = {".": (0, 0, 0, 255), "a": (1, 0, 0, 255), "b": (2, 0, 0, 255), "c": (3, 0, 0, 255)}
CLASSES = {".": 1, "n": 2, "e": 3}  # background, nucleus, nucleus edge


def picture(rows, key):
    return np.array([[key[c] for c in row] for row in rows], dtype=np.uint8)


class Download:
    """A folder laid out as BBBC039's download is, holding made-up fields."""

    def __init__(self, root):
        self.images = root / "images"
        self.labelled = root / "labelled"
        self.metadata = root / "metadata"
        self.output = root / "prepared"
        for folder in (self.images, self.labelled, self.metadata):
            folder.mkdir()

    def field(self, name, rows):
        shape = (len(rows), len(rows[0]))
        tifffile.imwrite(self.images / f"{name}.tif", np.full(shape, 500, dtype=np.uint16))
        Image.fromarray(picture(rows, COLOURS), "RGBA").save(self.labelled / f"{name}.png")

    def split(self, training=(), test=(), validation=()):
        for list_name, names in (("training", training), ("test", test), ("validation", validation)):
            text = "".join(f"{name}.png\n" for name in names)
            (self.metadata / f"{list_name}.txt").write_text(text)

    def prepare(self):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--images", str(self.images), "--labelled-images", str(self.labelled),
             "--metadata", str(self.metadata), "--output", str(self.output)],
            capture_output=True, text=True, timeout=60)


class PrepareTestCase(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.download = Download(Path(folder.name))

    def label_slice(self, rows):
        """The label slice the script writes for a training field drawn as `rows`."""
        self.download.field("field", rows)
        self.download.split(training=["field"])
        done = self.download.prepare()
        self.assertEqual(done.returncode, 0, done.stderr)
        return tifffile.imread(self.download.output / "train" / "labels" / "field.tif")

    def assert_label_slice(self, rows, expected):
        written = self.label_slice(rows)
        self.assertEqual(written.dtype, np.uint8)
        np.testing.assert_array_equal(written, picture(expected, CLASSES))


class LabelSlices(PrepareTestCase):
    def test_a_nucleus_has_a_two_pixel_edge_on_class_1_background(self):
        self.assert_label_slice(
            [".........",
             ".aaaaaaa.",
             ".aaaaaaa.",
             ".aaaaaaa.",
             ".aaaaaaa.",
             ".aaaaaaa.",
             ".aaaaaaa.",
             ".aaaaaaa.",
             "........."],
            [".........",
             ".eeeeeee.",
             ".eeeeeee.",
             ".eennnee.",
             ".eennnee.",
             ".eennnee.",
             ".eeeeeee.",
             ".eeeeeee.",
             "........."])

    def test_touching_nuclei_of_different_colours_are_separated_by_edge(self):
        self.assert_label_slice(
            ["..............",
             ".aaaaaabbbbbb.",
             ".aaaaaabbbbbb.",
             ".aaaaaabbbbbb.",
             ".aaaaaabbbbbb.",
             ".aaaaaabbbbbb.",
             ".aaaaaabbbbbb.",
             ".aaaaaabbbbbb.",
             ".............."],
            ["..............",
             ".eeeeeeeeeeee.",
             ".eeeeeeeeeeee.",
             ".eenneeeennee.",
             ".eenneeeennee.",
             ".eenneeeennee.",
             ".eeeeeeeeeeee.",
             ".eeeeeeeeeeee.",
             ".............."])

    def test_the_image_frame_is_not_a_nucleus_outline(self):
        self.assert_label_slice(
            ["ccccc.",
             "ccccc.",
             "ccccc.",
             "ccccc.",
             "ccccc.",
             "......"],
            ["nnnee.",
             "nnnee.",
             "nnnee.",
             "eeeee.",
             "eeeee.",
             "......"])

    def test_a_field_with_no_nuclei_is_all_background(self):
        self.assert_label_slice(["....", "....", "...."], ["....", "....", "...."])


class Dataset(PrepareTestCase):
    FIELD = ["...", ".a.", "..."]

    def test_training_fields_become_pairs_and_test_fields_the_image_set(self):
        for name in ("train1", "train2", "test1", "validation1"):
            self.download.field(name, self.FIELD)
        self.download.split(training=["train1", "train2"], test=["test1"], validation=["validation1"])

        done = self.download.prepare()

        self.assertEqual(done.returncode, 0, done.stderr)
        written = sorted(str(p.relative_to(self.download.output)) for p in self.download.output.rglob("*.tif"))
        self.assertEqual(written, ["images/test1.tif",
                                   "train/images/train1.tif", "train/images/train2.tif",
                                   "train/labels/train1.tif", "train/labels/train2.tif"])

    def test_images_keep_their_pixels_as_single_page_2d_tiffs(self):
        self.download.field("train1", self.FIELD)
        self.download.field("test1", self.FIELD)
        self.download.split(training=["train1"], test=["test1"])

        done = self.download.prepare()

        self.assertEqual(done.returncode, 0, done.stderr)
        for path in ("images/test1.tif", "train/images/train1.tif"):
            with tifffile.TiffFile(self.download.output / path) as tiff:
                self.assertEqual(len(tiff.pages), 1)
                page = tiff.pages[0].asarray()
            self.assertEqual(page.dtype, np.uint16)
            np.testing.assert_array_equal(page, np.full((3, 3), 500))


class Refusals(PrepareTestCase):
    """Each stops with one line naming the problem, and writes no dataset."""

    FIELD = ["...", ".a.", "..."]

    def assert_refused(self, message):
        done = self.download.prepare()
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertEqual(len(done.stderr.strip().splitlines()), 1, done.stderr)
        self.assertIn(message, done.stderr)
        self.assertFalse(self.download.output.exists())

    def test_a_field_listed_without_its_image(self):
        self.download.field("train1", self.FIELD)
        (self.download.images / "train1.tif").unlink()
        self.download.split(training=["train1"])
        self.assert_refused("train1.tif")

    def test_a_field_listed_without_its_labelled_image(self):
        self.download.field("train1", self.FIELD)
        (self.download.labelled / "train1.png").unlink()
        self.download.split(training=["train1"])
        self.assert_refused("train1.png")

    def test_a_labelled_image_of_another_size_than_its_image(self):
        self.download.field("train1", self.FIELD)
        tifffile.imwrite(self.download.images / "train1.tif", np.zeros((4, 4), dtype=np.uint16))
        self.download.split(training=["train1"])
        self.assert_refused("train1")

    def test_an_image_that_is_not_single_page_2d(self):
        self.download.field("test1", self.FIELD)
        tifffile.imwrite(self.download.images / "test1.tif", np.zeros((2, 3, 3), dtype=np.uint16))
        self.download.split(test=["test1"])
        self.assert_refused("test1.tif")

    def test_fields_of_different_sizes(self):
        self.download.field("train1", self.FIELD)
        self.download.field("test1", ["....", ".a..", "...."])
        self.download.split(training=["train1"], test=["test1"])
        self.assert_refused("test1.tif")

    def test_fields_of_different_bit_depths(self):
        self.download.field("train1", self.FIELD)
        self.download.field("test1", self.FIELD)
        tifffile.imwrite(self.download.images / "test1.tif", np.zeros((3, 3), dtype=np.uint8))
        self.download.split(training=["train1"], test=["test1"])
        self.assert_refused("test1.tif")

    def test_a_field_listed_for_both_training_and_the_image_set(self):
        self.download.field("field1", self.FIELD)
        self.download.split(training=["field1"], test=["field1"])
        self.assert_refused("field1")

    def test_an_output_folder_that_already_exists(self):
        self.download.field("train1", self.FIELD)
        self.download.split(training=["train1"])
        self.download.output.mkdir()
        keep = self.download.output / "keep.txt"
        keep.write_text("kept")

        done = self.download.prepare()

        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn(str(self.download.output), done.stderr)
        self.assertEqual([p.name for p in self.download.output.iterdir()], ["keep.txt"])


if __name__ == "__main__":
    unittest.main()
