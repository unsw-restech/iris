"""Synthetic-dataset test for the microCT reference workflow (seam 2 in #24).

Builds a tiny dataset on the fly, runs the entry point on CPU for one epoch
and asserts only on what lands in the run directory. Run from the repo root
in the desktop CPU venv (envs/imaging/desktop.sh):

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s workflows/microct-2d-segmentation/tests

The shared library's tests are in lib/tests, so copying this folder for a
new workflow copies none of them. The dataset and the clone come from the
library's test helpers there (datasets.py, run_dirs.py), so a job's run
directory is built here the way the library's tests build it.
"""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime
from pathlib import Path

import numpy as np
import tifffile

WORKFLOW = Path(__file__).resolve().parents[1]
REPO = WORKFLOW.parents[1]
LIB = REPO / "lib"
ENTRY = WORKFLOW / "src" / "run.py"

sys.path.insert(0, str(LIB / "tests"))
import run_dirs  # noqa: E402  (it puts lib/ on the path)
from datasets import NX, NY, SHAPE, VOXEL_SIZE_XYZ, make_volume, two_class_labels, write_dataset  # noqa: E402

from iris import rundir  # noqa: E402
from iris.tracking import import_runs, store_uri  # noqa: E402
from iris.view import load_run  # noqa: E402
from iris.volume import open_volume  # noqa: E402

import mlflow  # noqa: E402  (after iris.tracking, which quiets its start-up hint)


def clone_with_entry_script(root):
    """A throwaway clone holding the workflow's entry script as it is now,
    committed (run_dirs.clone_with_entry). Returns its workflow folder,
    which the job sets as CODE, and the commit, which the form records."""
    return run_dirs.clone_with_entry(root, ENTRY.read_text(), WORKFLOW.name)


def record_run_code(run_dir, code, commit, edit=None):
    """Do what the job does before it runs run.py, through
    run_dirs.record_code: write the entry script from `code` into `run_dir`
    as run.py, changed by `edit` (old, new) if given, then record the run's
    code as lib/iris-job.sh's iris_record_code does. `commit` is the form's
    COMMIT, None for none. Returns run.py's path and the record step's
    result."""
    script = (code / run_dirs.ENTRY).read_text()
    if edit is not None:
        old, new = edit
        assert old in script, old
        script = script.replace(old, new, 1)
    return run_dir / rundir.RUN_PY, run_dirs.record_code(run_dir, code, commit, run_py=script)


def run_entry(dataset, run_dir, iris_home, job_id="1234.kman.restech.unsw.edu.au", **overrides):
    """Run the entry point as a job would, with PBS's variables set and the
    IRIS home (run index and tracking store) pointed at `iris_home`."""
    cmd, env = entry_command(dataset, run_dir, iris_home, job_id, **overrides)
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)


def entry_command(dataset, run_dir, iris_home, job_id="1234.kman.restech.unsw.edu.au",
                  script=ENTRY, code=None, **overrides):
    """The command line and environment run_entry() runs the entry point
    with: `script`, the clone's by default, or a copy in the run directory
    with `code`, the workflow folder in the clone, as the job sets them."""
    args = {"epochs": 1, "patch_size": 32, "lr": 0.001, "val_percent": 20, "batch_size": 4, "seed": ""}
    args.update(overrides)
    cmd = [
        sys.executable, str(script),
        "--dataset", str(dataset), "--run-dir", str(run_dir),
        "--experiment", "microct-2d-segmentation",
        "--epochs", str(args["epochs"]), "--patch-size", str(args["patch_size"]),
        "--lr", str(args["lr"]), "--val-percent", str(args["val_percent"]),
        "--batch-size", str(args["batch_size"]), "--seed", args["seed"],
        "--field", "ncpus=2", "--field", "walltime=0:30:00", "--field", "mail_events=",
    ]
    env = dict(os.environ, PYTHONPATH=str(LIB), CUDA_VISIBLE_DEVICES="",
               IRIS_HOME=str(iris_home), PBS_JOBID=job_id, PBS_QUEUE="cpuq")
    if code is not None:
        env["IRIS_CODE"] = str(code)
    return cmd, env


class SyntheticRun(unittest.TestCase):
    """An unedited run: the entry script, written into the run directory as
    the job writes it, run from there."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dataset = Path(cls.tmp.name) / "dataset"
        cls.vol = make_volume()
        write_dataset(cls.dataset, cls.vol, two_class_labels())
        cls.iris_home = Path(cls.tmp.name) / "iris"
        cls.run_dir = cls.dataset / "runs" / "1234"
        cls.code, commit = clone_with_entry_script(Path(cls.tmp.name))
        script, _ = record_run_code(cls.run_dir, cls.code, commit)
        cls.result = run_entry(cls.dataset, cls.run_dir, cls.iris_home, epochs=2, script=script, code=cls.code)

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

    def test_an_unedited_run_writes_an_empty_run_diff_and_edited_false(self):
        self.assertEqual((self.run_dir / "run.diff").read_text(), "")
        self.assertIs(json.loads((self.run_dir / "run.json").read_text())["edited"], False)

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
        self.assertNotIn("lib_commit", tags)
        self.assertEqual(list(self.run_dir.glob("*.tmp")), [])

    def test_dataset_record_names_the_training_folders_and_the_volume(self):
        dataset = json.loads((self.run_dir / "dataset.json").read_text())
        root = self.dataset.resolve()
        self.assertEqual(dataset["path"], str(root))
        self.assertEqual(dataset["train"], {
            "images": {"path": str(root / "train" / "images"), "files": 3},
            "labels": {"path": str(root / "train" / "labels"), "files": 3},
        })
        volume = dataset["volume"]
        blocks = sorted((root / "volume").glob("*.nc"))
        self.assertEqual(volume["path"], str(root / "volume"))
        self.assertEqual(volume["size_bytes"], sum(f.stat().st_size for f in blocks))
        newest = max(f.stat().st_mtime for f in blocks)
        self.assertAlmostEqual(datetime.fromisoformat(volume["mtime"]).timestamp(), newest, delta=1e-3)
        self.assertEqual(volume["shape"], list(SHAPE))
        self.assertEqual(volume["dtype"], "uint16")
        self.assertEqual(volume["voxel_spacing"], {"xyz": VOXEL_SIZE_XYZ, "unit": "mm"})

    def test_dataset_record_holds_the_volumes_intensity_statistics(self):
        intensity = json.loads((self.run_dir / "dataset.json").read_text())["intensity"]
        self.assertEqual(intensity["min"], int(self.vol.min()))
        self.assertEqual(intensity["max"], 65535)
        self.assertAlmostEqual(intensity["mean"], float(self.vol.mean()), places=6)
        self.assertAlmostEqual(intensity["std"], float(self.vol.std()), places=6)
        self.assertEqual(sorted(intensity), ["max", "mean", "min", "std"])

    def test_the_volume_reader_chunks_one_slice_per_chunk(self):
        # Whole-block chunks made every slice read its whole block, in the job
        # and in iris-view alike (740 MB to read one 18 MB slice, #31).
        self.assertEqual(set(open_volume(self.dataset).data.chunks[0]), {1})

    def test_iris_view_loads_the_raw_volume_as_inference_read_it_and_the_labels(self):
        raw, labels = load_run(self.run_dir)
        self.assertEqual(raw.dtype, np.uint16)
        np.testing.assert_array_equal(np.asarray(raw), self.vol)  # values above 32767 included
        self.assertEqual(labels.shape, SHAPE)
        self.assertEqual(labels.dtype, np.uint8)
        expected = tifffile.imread(self.run_dir / "labels.tif")
        np.testing.assert_array_equal(np.asarray(labels[3]), expected[3])  # one slice on its own
        np.testing.assert_array_equal(np.asarray(labels), expected)

    def test_run_index_points_at_the_run_directory(self):
        pointer = self.iris_home / "run-index" / "1234"
        self.assertEqual(pointer.read_text(), str(self.run_dir.resolve()) + "\n")
        self.assertEqual(sorted(p.name for p in pointer.parent.iterdir()), ["1234"])


class EditedRun(unittest.TestCase):
    """A run whose researcher changed the model on the form before submitting."""

    EDIT = ("    def __init__(self, n_classes, base=32):", "    def __init__(self, n_classes, base=16):")

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dataset = Path(cls.tmp.name) / "dataset"
        write_dataset(cls.dataset, make_volume(), two_class_labels())
        cls.iris_home = Path(cls.tmp.name) / "iris"
        cls.run_dir = cls.dataset / "runs" / "1234"
        cls.code, cls.commit = clone_with_entry_script(Path(cls.tmp.name))
        cls.moved = run_dirs.move_clone(cls.code)  # after the form rendered
        script, cls.recorded = record_run_code(cls.run_dir, cls.code, cls.commit, edit=cls.EDIT)
        cls.result = run_entry(cls.dataset, cls.run_dir, cls.iris_home, script=script, code=cls.code)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_run_succeeds(self):
        self.assertEqual(self.result.returncode, 0, self.result.stderr)

    def test_run_diff_holds_the_change_against_the_recorded_commit(self):
        diff = (self.run_dir / "run.diff").read_text()
        path = f"workflows/{WORKFLOW.name}/src/run.py"
        self.assertTrue(diff.startswith(f"--- a/{path}\n+++ b/{path}\n"), diff)
        removed = [line for line in diff.splitlines() if line.startswith("-") and not line.startswith("---")]
        added = [line for line in diff.splitlines() if line.startswith("+") and not line.startswith("+++")]
        self.assertEqual(removed, ["-" + self.EDIT[0]])
        self.assertEqual(added, ["+" + self.EDIT[1]])

    def test_run_json_says_edited(self):
        self.assertIs(json.loads((self.run_dir / "run.json").read_text())["edited"], True)

    def test_the_job_prints_the_diff_before_python_runs_run_py(self):
        out = self.recorded.stdout
        self.assertEqual(self.recorded.returncode, 0, self.recorded.stderr)
        self.assertIn("EDITED RUN", out)
        self.assertIn(self.commit, out)
        self.assertIn("+" + self.EDIT[1], out)
        self.assertIn("WARNING: the IRIS clone moved", self.recorded.stderr)

    def test_the_output_says_the_script_was_edited_and_to_set_the_fields_first(self):
        out = self.recorded.stdout
        self.assertIn("Load parameters", out)
        self.assertIn("set the form's fields first and edit the code last", out)

    def test_run_json_records_the_lib_commit(self):
        tags = json.loads((self.run_dir / "run.json").read_text())["tags"]
        self.assertEqual(tags["commit"], self.commit)
        self.assertEqual(tags["lib_commit"], self.moved)

    def test_a_run_py_that_python_cannot_parse_still_leaves_run_py_and_run_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            code, commit = clone_with_entry_script(Path(tmp))
            breaks = ("    model.train()\n", "    model.train(\n")
            script, recorded = record_run_code(run_dir, code, commit, edit=breaks)
            result = run_entry(dataset, run_dir, Path(tmp) / "iris", script=script, code=code)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("SyntaxError", result.stderr)
            self.assertIn("+    model.train(\n", (run_dir / "run.diff").read_text())
            self.assertIn("+    model.train(\n", recorded.stdout)
            self.assertIn("    model.train(\n", (run_dir / "run.py").read_text())

    def test_an_edit_that_fails_training_still_leaves_its_run_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            code, commit = clone_with_entry_script(Path(tmp))
            breaks = ("    model.train()\n", "    model.train()\n    raise RuntimeError('broken by the edit')\n")
            script, _ = record_run_code(run_dir, code, commit, edit=breaks)
            result = run_entry(dataset, run_dir, Path(tmp) / "iris", script=script, code=code)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("broken by the edit", result.stderr)
            self.assertFalse((run_dir / "model.pt").exists())
            self.assertIn("+    raise RuntimeError('broken by the edit')\n", (run_dir / "run.diff").read_text())
            run = json.loads((run_dir / "run.json").read_text())
            self.assertEqual(run["status"], "FAILED")
            self.assertIs(run["edited"], True)


class UnknownEdits(unittest.TestCase):
    """A run with no render-time commit to compare its run.py with, or one
    git cannot read, goes on, and records that whether it was edited is
    unknown, never that it was not."""

    def run_without(self, commit):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            code, _ = clone_with_entry_script(Path(tmp))
            script, recorded = record_run_code(run_dir, code, commit)
            self.assertEqual(recorded.returncode, 0, recorded.stderr)
            self.assertIn("WARNING", recorded.stderr)
            self.assertIn("edited is unknown", recorded.stderr)
            self.assertNotIn("Traceback", recorded.stderr)
            result = run_entry(dataset, run_dir, Path(tmp) / "iris", script=script, code=code)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((run_dir / "run.diff").exists())
            run = json.loads((run_dir / "run.json").read_text())
            self.assertEqual(run["status"], "FINISHED")
            self.assertEqual(run["edited"], "unknown")

    def test_without_a_render_time_commit(self):
        self.run_without(None)

    def test_with_a_commit_git_cannot_read(self):
        self.run_without("0123456789abcdef0123456789abcdef01234567")


def only_run(iris_home, experiment="microct-2d-segmentation"):
    """A client on `iris_home`'s tracking store and the one run in `experiment`."""
    client = mlflow.MlflowClient(store_uri(iris_home))
    [run] = client.search_runs([client.get_experiment_by_name(experiment).experiment_id])
    return client, run


def logged_histories(run_dir):
    """{metric: [(epoch, value)]} as the run logged them in metrics.json,
    named as the importer names them."""
    epochs = json.loads((run_dir / "metrics.json").read_text())["epochs"]
    logged = {"train_loss": [(e["epoch"], e["train_loss"]) for e in epochs]}
    for name in ("dice", "iou"):
        for cls_ in ("1", "2"):
            logged[f"{name}/{cls_}"] = [(e["epoch"], e[name][cls_]) for e in epochs if e[name][cls_] is not None]
    return logged


def imported_histories(client, run, names):
    """{metric: [(step, value)]} for each of `names` as the tracking store holds them."""
    return {name: [(m.step, m.value) for m in client.get_metric_history(run.info.run_id, name)] for name in names}


def wait_for_first_epoch(job, metrics, timeout=300):
    """Return once `metrics` holds an epoch; fail if `job` ends or time runs out first."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if job.poll() is not None:
            raise AssertionError(f"the run ended before its first epoch: {job.stderr.read()}")
        if metrics.exists() and json.loads(metrics.read_text())["epochs"]:
            return
        time.sleep(0.1)
    raise AssertionError(f"no epoch in {metrics} after {timeout} s")


class FailedRun(unittest.TestCase):
    """A run that fails after training reaches MLflow as FAILED."""

    def test_reaches_mlflow_with_its_params_and_metrics_so_far(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            (run_dir / "labels.tif").mkdir(parents=True)  # segmentation can't write the label volume
            iris_home = Path(tmp) / "iris"
            result = run_entry(dataset, run_dir, iris_home, epochs=2, seed="7")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("labels.tif", result.stderr)
            self.assertTrue((run_dir / "model.pt").exists())  # it failed after training
            self.assertEqual(json.loads((run_dir / "run.json").read_text())["status"], "FAILED")
            self.assertEqual((iris_home / "run-index" / "1234").read_text(), str(run_dir.resolve()) + "\n")

            self.assertEqual(import_runs(iris_home), {"imported": 1, "pending": 0})
            client, run = only_run(iris_home)
            self.assertEqual(run.info.run_name, "1234")
            self.assertEqual(run.info.status, "FAILED")
            self.assertEqual(run.data.params["seed"], "7")
            self.assertEqual(run.data.params["epochs"], "2")
            self.assertEqual(run.data.params["patch_size"], "32")
            logged = logged_histories(run_dir)
            self.assertEqual([epoch for epoch, _ in logged["train_loss"]], [1, 2])
            self.assertEqual(imported_histories(client, run, logged), logged)


class KilledRun(unittest.TestCase):
    """A run sent SIGTERM mid-training, as walltime or qdel does, reaches
    MLflow as KILLED with the epochs it got through."""

    def test_reaches_mlflow_with_the_epochs_it_completed(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            iris_home = Path(tmp) / "iris"
            cmd, env = entry_command(dataset, run_dir, iris_home, epochs=10000)
            job = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            try:
                wait_for_first_epoch(job, run_dir / "metrics.json")
                job.send_signal(signal.SIGTERM)
                _, stderr = job.communicate(timeout=120)
            finally:
                job.kill()
            self.assertEqual(job.returncode, 143, stderr)
            self.assertEqual(json.loads((run_dir / "run.json").read_text())["status"], "KILLED")
            completed = [e["epoch"] for e in json.loads((run_dir / "metrics.json").read_text())["epochs"]]
            self.assertGreaterEqual(len(completed), 1)
            self.assertLess(len(completed), 10000)
            self.assertFalse((run_dir / "labels.tif").exists())

            self.assertEqual(import_runs(iris_home), {"imported": 1, "pending": 0})
            client, run = only_run(iris_home)
            self.assertEqual(run.info.run_name, "1234")
            self.assertEqual(run.info.status, "KILLED")
            self.assertEqual(run.data.params["epochs"], "10000")
            logged = logged_histories(run_dir)
            self.assertEqual(imported_histories(client, run, logged), logged)


class UnwritableDatasetRecord(unittest.TestCase):

    def test_the_run_succeeds_and_warns(self):
        with tempfile.TemporaryDirectory() as tmp:
            dataset = Path(tmp) / "dataset"
            write_dataset(dataset, make_volume(), two_class_labels())
            run_dir = dataset / "runs" / "1234"
            (run_dir / "dataset.json").mkdir(parents=True)  # a folder can't be replaced by a file
            result = run_entry(dataset, run_dir, Path(tmp) / "iris")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("dataset.json", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertEqual(json.loads((run_dir / "run.json").read_text())["status"], "FINISHED")


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
