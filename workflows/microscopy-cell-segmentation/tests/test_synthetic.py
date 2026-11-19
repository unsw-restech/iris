"""Synthetic-dataset test for Nuclei Segmentation (U-Net).

Builds a tiny image set and its training pairs on the fly, runs the entry
point on CPU and asserts only on what a researcher gets: the run directory,
iris-view's arrays, the tracking store and the line a broken dataset stops
the job with. The image set reader is tested through this run. bin/check
runs it in the container the workflow's form pins (bin/envrun); by hand:

    cd workflows/microscopy-cell-segmentation/tests && ../../../bin/envrun microct/1 python -m unittest test_synthetic
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import dask.array as da
import numpy as np
import tifffile

WORKFLOW = Path(__file__).resolve().parents[1]
REPO = WORKFLOW.parents[1]
LIB = REPO / "lib"
OWN_LIB = WORKFLOW / "lib"  # this workflow's copy of the library's job side (bin/libcopy), which a job runs
ENTRY = WORKFLOW / "src" / "run.py"

sys.path.insert(0, str(LIB / "tests"))
import run_dirs  # noqa: E402  (it puts lib/ on the path)
from datasets import NX, NY  # noqa: E402  (the image size every synthetic run uses)

from iris import rundir  # noqa: E402
from iris.tracking import import_runs, store_uri  # noqa: E402
from iris.view import load_run  # noqa: E402

import mlflow  # noqa: E402  (after iris.tracking, which quiets its start-up hint)

SLUG = "microscopy-cell-segmentation"
WRITTEN = ["field2.tif", "field10.tif", "a_first.tif", "field02.tif"]
FILE_NAME_ORDER = ["a_first.tif", "field02.tif", "field10.tif", "field2.tif"]
TRAINING = ["pair1.tif", "pair2.tif", "pair3.tif"]


def make_image(seed):
    """Unsigned 16-bit intensities, half of them above 32767, different for each seed."""
    rng = np.random.default_rng(seed)
    image = rng.integers(1000, 4000, size=(NY, NX), dtype=np.uint16)
    image[:, NX // 2:] = rng.integers(40000, 60000, size=(NY, NX - NX // 2), dtype=np.uint16)
    return image


def make_label():
    """Class 1 for background, 2 for nucleus and 3 for nucleus edge, with a
    band of 0 (unlabelled) pixels."""
    label = np.ones((NY, NX), dtype=np.uint8)
    label[:, NX // 2:] = 2
    label[:, NX // 2 - 2:NX // 2 + 2] = 3
    label[:NY // 5] = 0
    return label


def write_image(path, image):
    """Write `image` as IRIS's microCT slices are stored, 16-bit as `short`."""
    tifffile.imwrite(path, image.view(np.int16) if image.dtype == np.uint16 else image)


def write_dataset(root):
    """Lay out <root>/images/ and <root>/train/{images,labels}/, and return
    the image set's images by file name."""
    for folder in ("images", "train/images", "train/labels"):
        (root / folder).mkdir(parents=True)
    images = {name: make_image(seed) for seed, name in enumerate(WRITTEN)}
    for name, image in images.items():
        write_image(root / "images" / name, image)
    for seed, name in enumerate(TRAINING, start=100):
        write_image(root / "train" / "images" / name, make_image(seed))
        tifffile.imwrite(root / "train" / "labels" / name, make_label())
    return images


def entry_command(dataset, run_dir, iris_home, script=ENTRY, code=None, epochs=2):
    """The command line and environment a job runs the entry point with."""
    cmd = [
        sys.executable, str(script),
        "--dataset", str(dataset), "--run-dir", str(run_dir),
        "--experiment", SLUG,
        "--epochs", str(epochs), "--patch-size", "32", "--lr", "0.001",
        "--val-percent", "20", "--batch-size", "4", "--seed", "",
        "--field", "ncpus=2", "--field", "walltime=0:30:00", "--field", "mail_events=ae",
    ]
    env = dict(os.environ, PYTHONPATH=str(OWN_LIB), CUDA_VISIBLE_DEVICES="",
               IRIS_HOME=str(iris_home), PBS_JOBID="1234.kman.restech.unsw.edu.au", PBS_QUEUE="cpuq",
               IRIS_ENV_VERSION="microct/1", IRIS_ENV_DIGEST="sha256:" + "ab" * 32)
    if code is not None:
        env["IRIS_CODE"] = str(code)
    return cmd, env


class SyntheticRun(unittest.TestCase):
    """An unedited run: the entry script, written into the run directory as
    the job writes it, run from there."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.dataset = root / "dataset"
        cls.images = write_dataset(cls.dataset)
        cls.ordered = np.stack([cls.images[name] for name in FILE_NAME_ORDER])
        cls.iris_home = root / "iris"
        cls.run_dir = cls.dataset / "runs" / "1234"
        code, commit = run_dirs.clone_with_entry(root, ENTRY.read_text(), SLUG)
        recorded = run_dirs.record_code(cls.run_dir, code, commit)
        assert recorded.returncode == 0, recorded.stderr
        cmd, env = entry_command(cls.dataset, cls.run_dir, cls.iris_home, cls.run_dir / rundir.RUN_PY, code)
        cls.result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, name):
        return json.loads((self.run_dir / name).read_text())

    def test_run_succeeds(self):
        self.assertEqual(self.result.returncode, 0, self.result.stderr)

    def test_labels_hold_one_uint8_page_per_image(self):
        with tifffile.TiffFile(self.run_dir / "labels.tif") as tif:
            self.assertEqual(tif.series[0].shape, (len(WRITTEN), NY, NX))
            self.assertEqual(len(tif.pages), len(WRITTEN))
            for page in tif.pages:
                labels = page.asarray()
                self.assertEqual(labels.dtype, np.uint8)
                self.assertEqual(labels.shape, (NY, NX))
                self.assertTrue(set(np.unique(labels)) <= {1, 2, 3})

    def test_the_dataset_record_gives_each_page_its_image_in_file_name_order(self):
        extras = self.read("dataset.json")["extras"]
        self.assertEqual(extras["image_set"], {"shape": [len(WRITTEN), NY, NX], "dtype": "uint16",
                                               "files": FILE_NAME_ORDER})

    def test_the_dataset_record_counts_the_training_pairs_and_holds_no_voxel_spacing(self):
        extras = self.read("dataset.json")["extras"]
        self.assertEqual(extras["train"], {"images": 3, "labels": 3})
        self.assertEqual(sorted(extras), ["image_set", "intensity", "train"])
        self.assertNotIn("voxel_spacing", json.dumps(extras))

    def test_the_dataset_record_holds_the_image_sets_intensity_statistics(self):
        intensity = self.read("dataset.json")["extras"]["intensity"]
        self.assertEqual(intensity["min"], int(self.ordered.min()))
        self.assertEqual(intensity["max"], int(self.ordered.max()))
        self.assertGreater(intensity["max"], 32767)  # read as unsigned
        self.assertAlmostEqual(intensity["mean"], float(self.ordered.mean()), places=6)
        self.assertAlmostEqual(intensity["std"], float(self.ordered.std()), places=6)

    def test_params_record_the_run(self):
        params = self.read("params.json")
        self.assertIsInstance(params["seed"], int)
        self.assertEqual(params["experiment"], SLUG)
        self.assertEqual(params["epochs"], 2)
        self.assertEqual(params["patch_size"], 32)
        self.assertEqual(params["n_classes"], 3)
        self.assertEqual(params["training_pairs"], 3)
        self.assertEqual(params["image_set_shape"], [len(WRITTEN), NY, NX])
        self.assertEqual(params["ncpus"], "2")
        self.assertEqual(params["walltime"], "0:30:00")
        self.assertEqual(params["mail_events"], "ae")

    def test_metrics_hold_loss_and_per_class_dice_and_iou_each_epoch(self):
        metrics = self.read("metrics.json")
        self.assertEqual([e["epoch"] for e in metrics["log"]], [1, 2])
        for epoch in metrics["log"]:
            self.assertIsInstance(epoch["train_loss"], float)
            for name in ("dice", "iou"):
                self.assertEqual(sorted(epoch[name]), ["1", "2", "3"])
                for value in epoch[name].values():
                    self.assertTrue(value is None or 0.0 <= value <= 1.0)

    def test_the_run_record_names_this_workflow(self):
        run = self.read("run.json")
        self.assertEqual(run["run"]["workflow"], SLUG)
        self.assertEqual(run["run"]["status"], "FINISHED")
        self.assertIs(run["code"]["edited"], False)
        self.assertEqual(run["environment"]["version"], "microct/1")

    def test_iris_view_loads_the_images_in_file_name_order_with_their_labels(self):
        raw, labels = load_run(self.run_dir)
        self.assertIsInstance(raw, da.Array)
        self.assertEqual(raw.chunks[0], (1,) * len(WRITTEN))  # one image read at a time
        self.assertEqual(raw.dtype, np.uint16)
        np.testing.assert_array_equal(np.asarray(raw), self.ordered)
        np.testing.assert_array_equal(np.asarray(labels), tifffile.imread(self.run_dir / "labels.tif"))

    def test_the_run_reaches_the_tracking_store(self):
        self.assertEqual(import_runs(self.iris_home), {"imported": 1, "pending": 0})
        client = mlflow.MlflowClient(store_uri(self.iris_home))
        [run] = client.search_runs([client.get_experiment_by_name(SLUG).experiment_id])
        self.assertEqual(run.info.run_name, "1234")
        self.assertEqual(run.info.status, "FINISHED")
        self.assertEqual(run.data.tags["slug"], SLUG)
        self.assertEqual(run.data.params["n_classes"], "3")
        self.assertEqual([m.step for m in client.get_metric_history(run.info.run_id, "train_loss")], [1, 2])


class EditedRun(unittest.TestCase):

    def test_an_edit_on_the_form_is_recorded_as_the_runs_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "dataset" / "runs" / "1234"
            code, commit = run_dirs.clone_with_entry(tmp, ENTRY.read_text(), SLUG)
            old = "    def __init__(self, n_classes, base=32):"
            new = "    def __init__(self, n_classes, base=16):"
            recorded = run_dirs.record_code(run_dir, code, commit, run_py=ENTRY.read_text().replace(old, new, 1))
            self.assertEqual(recorded.returncode, 0, recorded.stderr)
            diff = (run_dir / "run.diff").read_text()
            self.assertIn("-" + old + "\n", diff)
            self.assertIn("+" + new + "\n", diff)


def wrong_size(root):
    tifffile.imwrite(root / "images" / "field10.tif", np.zeros((NY + 1, NX), dtype=np.uint16))


def wrong_bit_depth(root):
    tifffile.imwrite(root / "images" / "field10.tif", np.zeros((NY, NX), dtype=np.uint8))


def colour(root):
    tifffile.imwrite(root / "images" / "field10.tif", np.zeros((NY, NX, 3), dtype=np.uint8), photometric="rgb")


def multi_page(root):
    tifffile.imwrite(root / "images" / "field10.tif", np.zeros((2, NY, NX), dtype=np.uint16))


def not_a_tiff(root):
    (root / "images" / "field10.tif").write_text("not a TIFF")


def no_image_set(root):
    for image in (root / "images").iterdir():
        image.unlink()
    (root / "images").rmdir()


def empty_image_set(root):
    for image in (root / "images").iterdir():
        image.unlink()


def training_image_wrong_size(root):
    tifffile.imwrite(root / "train" / "images" / "pair1.tif", np.zeros((NY + 1, NX), dtype=np.uint16))
    tifffile.imwrite(root / "train" / "labels" / "pair1.tif", np.ones((NY + 1, NX), dtype=np.uint8))


def training_image_wrong_bit_depth(root):
    tifffile.imwrite(root / "train" / "images" / "pair1.tif", np.zeros((NY, NX), dtype=np.uint8))


def training_image_colour(root):
    tifffile.imwrite(root / "train" / "images" / "pair1.tif", np.zeros((NY, NX, 3), dtype=np.uint8), photometric="rgb")


def training_image_not_a_tiff(root):
    (root / "train" / "images" / "pair1.tif").write_text("not a TIFF")


def label_multi_page(root):
    tifffile.imwrite(root / "train" / "labels" / "pair1.tif", np.ones((2, NY, NX), dtype=np.uint8))


def different_training_names(root):
    (root / "train" / "labels" / "pair1.tif").rename(root / "train" / "labels" / "pair9.tif")


def no_training_images_folder(root):
    shutil.rmtree(root / "train" / "images")


def no_training_labels_folder(root):
    shutil.rmtree(root / "train" / "labels")


def no_training_pairs(root):
    for pair in (root / "train").glob("*/*"):
        pair.unlink()


def label_wrong_size(root):
    tifffile.imwrite(root / "train" / "labels" / "pair1.tif", np.ones((NY + 1, NX), dtype=np.uint8))


def label_not_whole(root):
    tifffile.imwrite(root / "train" / "labels" / "pair1.tif", np.full((NY, NX), 1.5, dtype=np.float32))


def label_negative(root):
    label = make_label().astype(np.int16)
    label[0, 0] = -1
    tifffile.imwrite(root / "train" / "labels" / "pair1.tif", label)


def label_too_many_classes(root):
    label = make_label().astype(np.uint16)
    label[0, 0] = 256
    tifffile.imwrite(root / "train" / "labels" / "pair1.tif", label)


def labels_all_unlabelled(root):
    for label in (root / "train" / "labels").iterdir():
        tifffile.imwrite(label, np.zeros((NY, NX), dtype=np.uint8))


class DatasetErrors(unittest.TestCase):
    """Each broken dataset stops the job before training, with one line
    naming what to fix. They run side by side: most of each is Python
    importing PyTorch."""

    BROKEN = {
        wrong_size: "field10.tif",
        wrong_bit_depth: "field10.tif",
        colour: "field10.tif",
        multi_page: "field10.tif",
        not_a_tiff: "field10.tif",
        no_image_set: "images",
        empty_image_set: "images",
        training_image_wrong_size: "pair1.tif",
        training_image_wrong_bit_depth: "pair1.tif",
        training_image_colour: "pair1.tif",
        training_image_not_a_tiff: "pair1.tif",
        label_multi_page: "pair1.tif",
        different_training_names: "pair1.tif",
        no_training_images_folder: "train/images",
        no_training_labels_folder: "train/labels",
        no_training_pairs: "No training pairs",
        label_wrong_size: "pair1.tif",
        label_not_whole: "whole numbers",
        label_negative: "pair1.tif",
        label_too_many_classes: "256 classes",
        labels_all_unlabelled: "no class",
    }

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()

        def stop(breaks):
            root = Path(cls.tmp.name) / breaks.__name__
            write_dataset(root)
            breaks(root)
            cmd, env = entry_command(root, root / "runs" / "1", root / "iris")
            return breaks, root, subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=300)

        with ThreadPoolExecutor(max_workers=4) as pool:
            cls.stopped = list(pool.map(stop, cls.BROKEN))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_each_stops_before_training_with_one_line_naming_the_problem(self):
        for breaks, root, result in self.stopped:
            with self.subTest(breaks.__name__):
                self.assertEqual(result.returncode, 1, result.stderr)
                lines = result.stderr.strip().splitlines()
                self.assertEqual(len(lines), 1, result.stderr)
                self.assertTrue(lines[0].startswith("ERROR: "), lines[0])
                self.assertIn(self.BROKEN[breaks], lines[0])
                self.assertFalse((root / "runs" / "1" / "model.pt").exists())


if __name__ == "__main__":
    unittest.main()
