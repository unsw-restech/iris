"""Synthetic-dataset test for the microCT reference workflow (seam 2 in #24).

Builds a tiny dataset on the fly, runs the entry point on CPU for one epoch
and asserts only on what lands in the run directory. Run from the repo root
in the desktop CPU venv (envs/imaging/desktop.sh):

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s workflows/microct-2d-segmentation/tests
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import netCDF4
import numpy as np
import tifffile

WORKFLOW = Path(__file__).resolve().parents[1]
REPO = WORKFLOW.parents[1]
LIB = REPO / "lib"
ENTRY = WORKFLOW / "src" / "run.py"

sys.path.insert(0, str(LIB))
from iris.tracking import import_runs, store_uri  # noqa: E402
from iris.volume import open_volume  # noqa: E402

import mlflow  # noqa: E402  (after iris.tracking, which quiets its start-up hint)

BLOCK_SLICES = 3
N_BLOCKS = 2
NY, NX = 70, 50  # not a multiple of the patch size or of the U-Net's stride
SHAPE = (BLOCK_SLICES * N_BLOCKS, NY, NX)


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


def run_entry(dataset, run_dir, iris_home, job_id="1234.kman.restech.unsw.edu.au", **overrides):
    """Run the entry point as a job would, with PBS's variables set and the
    IRIS home (run index and tracking store) pointed at `iris_home`."""
    args = {"epochs": 1, "patch_size": 32, "lr": 0.001, "val_percent": 20, "batch_size": 4, "seed": ""}
    args.update(overrides)
    cmd = [
        sys.executable, str(ENTRY),
        "--dataset", str(dataset), "--run-dir", str(run_dir),
        "--experiment", "microct-2d-segmentation",
        "--epochs", str(args["epochs"]), "--patch-size", str(args["patch_size"]),
        "--lr", str(args["lr"]), "--val-percent", str(args["val_percent"]),
        "--batch-size", str(args["batch_size"]), "--seed", args["seed"],
        "--field", "ncpus=2", "--field", "walltime=0:30:00", "--field", "mail_events=",
    ]
    env = dict(os.environ, PYTHONPATH=str(LIB), CUDA_VISIBLE_DEVICES="",
               IRIS_HOME=str(iris_home), PBS_JOBID=job_id, PBS_QUEUE="cpuq")
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)


class SyntheticRun(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dataset = Path(cls.tmp.name) / "dataset"
        cls.vol = make_volume()
        write_dataset(cls.dataset, cls.vol, two_class_labels())
        cls.iris_home = Path(cls.tmp.name) / "iris"
        cls.run_dir = cls.dataset / "runs" / "1234"
        cls.result = run_entry(cls.dataset, cls.run_dir, cls.iris_home, epochs=2)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_run_succeeds(self):
        self.assertEqual(self.result.returncode, 0, self.result.stderr)

    def test_label_volume_is_slice_compressed_uint8_bigtiff_of_full_shape(self):
        with tifffile.TiffFile(self.run_dir / "labels.tif") as tif:
            self.assertTrue(tif.is_bigtiff)
            self.assertEqual(tif.series[0].shape, SHAPE)
            self.assertEqual(len(tif.pages), SHAPE[0])
            for page in tif.pages:
                self.assertEqual(page.compression, tifffile.COMPRESSION.ADOBE_DEFLATE)
                one = page.asarray()  # one slice at a time
                self.assertEqual(one.dtype, np.uint8)
                self.assertEqual(one.shape, SHAPE[1:])
                self.assertTrue(set(np.unique(one)) <= {1, 2})

    def test_weights_written(self):
        self.assertGreater((self.run_dir / "model.pt").stat().st_size, 0)

    def test_params_record_the_seed_used(self):
        params = json.loads((self.run_dir / "params.json").read_text())
        self.assertIsInstance(params["seed"], int)
        self.assertEqual(params["experiment"], "microct-2d-segmentation")
        self.assertEqual(params["epochs"], 2)
        self.assertEqual(params["patch_size"], 32)
        self.assertEqual(params["n_classes"], 2)

    def test_params_record_the_form_fields_the_entry_point_does_not_use(self):
        params = json.loads((self.run_dir / "params.json").read_text())
        self.assertEqual(params["ncpus"], "2")
        self.assertEqual(params["walltime"], "0:30:00")
        self.assertEqual(params["mail_events"], "")

    def test_metrics_hold_per_class_dice_and_iou_per_epoch_and_final(self):
        metrics = json.loads((self.run_dir / "metrics.json").read_text())
        self.assertEqual([e["epoch"] for e in metrics["epochs"]], [1, 2])
        self.assertEqual(metrics["final"], metrics["epochs"][-1])
        for record in metrics["epochs"]:
            self.assertIsInstance(record["train_loss"], float)
            for name in ("dice", "iou"):
                self.assertEqual(sorted(record[name]), ["1", "2"])
                for v in record[name].values():
                    self.assertTrue(v is None or 0.0 <= v <= 1.0)

    def test_run_record_names_the_experiment_job_tags_and_ending(self):
        run = json.loads((self.run_dir / "run.json").read_text())
        self.assertEqual(run["experiment"], "microct-2d-segmentation")
        self.assertEqual(run["job_id"], "1234")
        self.assertEqual(run["status"], "FINISHED")
        self.assertLessEqual(run["start_time"], run["end_time"])
        tags = run["tags"]
        self.assertEqual(tags["slug"], "microct-2d-segmentation")
        self.assertEqual(tags["job_id"], "1234")
        self.assertEqual(tags["queue"], "cpuq")
        self.assertEqual(tags["gpu"], "none")
        self.assertEqual(tags["venv"], sys.prefix)
        self.assertEqual(tags["run_dir"], str(self.run_dir.resolve()))
        self.assertRegex(tags["commit"], r"^[0-9a-f]{40}$")
        self.assertEqual(list(self.run_dir.glob("*.tmp")), [])

    def test_run_index_points_at_the_run_directory(self):
        pointer = self.iris_home / "run-index" / "1234"
        self.assertEqual(pointer.read_text(), str(self.run_dir.resolve()) + "\n")
        self.assertEqual(sorted(p.name for p in pointer.parent.iterdir()), ["1234"])


class Import(unittest.TestCase):
    """The importer replays a finished run into a throwaway tracking store."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.iris_home = Path(cls.tmp.name) / "iris"
        cls.dataset = Path(cls.tmp.name) / "dataset"
        write_dataset(cls.dataset, make_volume(), two_class_labels())
        cls.run_dir = cls.dataset / "runs" / "1234"
        result = run_entry(cls.dataset, cls.run_dir, cls.iris_home, epochs=2, seed="7")
        assert result.returncode == 0, result.stderr
        cls.metrics = json.loads((cls.run_dir / "metrics.json").read_text())
        cls.first = import_runs(cls.iris_home)
        cls.client = mlflow.MlflowClient(store_uri(cls.iris_home))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def only_run(self):
        experiment = self.client.get_experiment_by_name("microct-2d-segmentation")
        self.assertIsNotNone(experiment)
        runs = self.client.search_runs([experiment.experiment_id])
        self.assertEqual(len(runs), 1)
        return runs[0]

    def test_one_run_named_by_job_id_under_its_experiment(self):
        self.assertEqual(self.first, {"imported": 1, "pending": 0})
        run = self.only_run()
        self.assertEqual(run.info.run_name, "1234")
        self.assertEqual(run.info.status, "FINISHED")

    def test_artifacts_go_next_to_the_store(self):
        experiment = self.client.get_experiment_by_name("microct-2d-segmentation")
        self.assertEqual(experiment.artifact_location, (self.iris_home / "artifacts").as_uri())

    def test_params_are_the_recorded_params(self):
        params = self.only_run().data.params
        self.assertEqual(params["seed"], "7")
        self.assertEqual(params["epochs"], "2")
        self.assertEqual(params["patch_size"], "32")
        self.assertEqual(params["experiment"], "microct-2d-segmentation")

    def test_metrics_history_replays_every_epoch(self):
        run = self.only_run()
        loss = self.client.get_metric_history(run.info.run_id, "train_loss")
        self.assertEqual([(m.step, m.value) for m in loss],
                         [(e["epoch"], e["train_loss"]) for e in self.metrics["epochs"]])
        for name in ("dice", "iou"):
            for cls_ in ("1", "2"):
                history = self.client.get_metric_history(run.info.run_id, f"{name}/{cls_}")
                expected = [e["epoch"] for e in self.metrics["epochs"] if e[name][cls_] is not None]
                self.assertEqual([m.step for m in history], expected)

    def test_tags_carry_the_environment(self):
        tags = self.only_run().data.tags
        for key in ("slug", "job_id", "commit", "venv", "gpu", "queue", "run_dir"):
            self.assertIn(key, tags)
        self.assertEqual(tags["job_id"], "1234")
        self.assertEqual(tags["run_dir"], str(self.run_dir.resolve()))

    def test_importing_again_adds_no_run(self):
        self.assertEqual(import_runs(self.iris_home), {"imported": 0, "pending": 0})
        self.only_run()

    def test_a_run_without_run_json_waits_for_the_next_import(self):
        pending = self.dataset / "runs" / "5678"
        pending.mkdir()
        (self.iris_home / "run-index" / "5678").write_text(str(pending) + "\n")
        try:
            self.assertEqual(import_runs(self.iris_home), {"imported": 0, "pending": 1})
        finally:
            (self.iris_home / "run-index" / "5678").unlink()
        self.only_run()

    def test_a_run_that_fails_to_import_leaves_no_run_behind(self):
        broken = self.dataset / "runs" / "999"
        broken.mkdir()
        (broken / "run.json").write_text(json.dumps({
            "experiment": "broken", "job_id": "999", "status": "FINISHED",
            "start_time": 1.0, "end_time": 2.0, "tags": {"job_id": "999"}}))
        (broken / "metrics.json").write_text('{"epochs": [{"epoch": 1, "train_loss": 0.5}]}')  # no time
        (self.iris_home / "run-index" / "999").write_text(str(broken) + "\n")
        try:
            self.assertEqual(import_runs(self.iris_home), {"imported": 0, "pending": 0})
            experiment = self.client.get_experiment_by_name("broken")
            self.assertEqual(self.client.search_runs([experiment.experiment_id]), [])
        finally:
            (self.iris_home / "run-index" / "999").unlink()


class UnwritableRunIndex(unittest.TestCase):

    def test_the_run_succeeds_with_every_json_file_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            blocker = Path(tmp) / "not-a-folder"
            blocker.write_text("")  # the IRIS home can't be created under a file
            run_dir = dataset / "runs" / "1234"
            result = run_entry(dataset, run_dir, blocker / "iris")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("WARNING", result.stderr)
            for name in ("params.json", "metrics.json", "run.json"):
                json.loads((run_dir / name).read_text())
            self.assertTrue((run_dir / "labels.tif").exists())


class VolumeReader(unittest.TestCase):

    def test_values_above_32767_read_the_same_every_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            vol = make_volume()
            write_dataset(Path(tmp), vol, two_class_labels())
            for _ in range(2):
                read = open_volume(tmp)
                self.assertEqual(read.dtype, np.uint16)
                np.testing.assert_array_equal(read.values, vol)


class TooManyClasses(unittest.TestCase):

    def test_more_than_255_classes_fails_before_training(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            labels = two_class_labels()
            labels[5] = labels[5].astype(np.uint16)
            labels[5][-1, -1] = 256
            write_dataset(dataset, make_volume(), labels)
            run_dir = dataset / "runs" / "1"
            result = run_entry(dataset, run_dir, Path(tmp) / "iris")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("255", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse((run_dir / "model.pt").exists())


class WrongBitDepth(unittest.TestCase):

    def test_training_images_at_another_bit_depth_fail_before_training(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            tifffile.imwrite(dataset / "train" / "images" / "slice0000.tif", np.zeros((NY, NX), dtype=np.uint8))
            run_dir = dataset / "runs" / "1"
            result = run_entry(dataset, run_dir, Path(tmp) / "iris")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("uint8", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse((run_dir / "model.pt").exists())


if __name__ == "__main__":
    unittest.main()
