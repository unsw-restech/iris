"""The shared library's tests: the importer, the store rebuild, iris-view's
recent runs, the volume reader and a run whose run index can't be written.

Their run directories are built as a job builds them, through the run
directory module and RunRecord (run_dirs.py). Only the volume reader's
synthetic dataset comes from the reference workflow's tests. Run from the
repo root in the desktop CPU venv (envs/imaging/desktop.sh):

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s lib/tests
"""

import contextlib
import io
import json
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

from run_dirs import clone_with_entry, finished_run  # noqa: E402  (it puts lib/ on the path)

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "workflows" / "microct-2d-segmentation" / "tests"))
from test_synthetic import make_volume, two_class_labels, write_dataset  # noqa: E402

from iris.compare import start_ui  # noqa: E402
from iris.tracking import StoreExists, import_runs, rebuild, store_uri  # noqa: E402
from iris.view import recent_runs  # noqa: E402
from iris.volume import open_volume  # noqa: E402

import mlflow  # noqa: E402  (after iris.tracking, which quiets its start-up hint)

EXPERIMENT = "microct-2d-segmentation"
DATASET_RECORD = {  # as iris.dataset describes a dataset, intensity added
    "train": {"images": {"files": 3}, "labels": {"files": 3}},
    "volume": {"shape": [6, 70, 50], "dtype": "uint16"},
    "intensity": {"min": 1000, "max": 65535, "mean": 20000.0, "std": 100.0},
}


def only_run(iris_home, experiment):
    """A client on `iris_home`'s tracking store and the one run in `experiment`."""
    client = mlflow.MlflowClient(store_uri(iris_home))
    [run] = client.search_runs([client.get_experiment_by_name(experiment).experiment_id])
    return client, run


def rewrite_run_json(run_dir, change):
    """Apply `change` to the run.json RunRecord wrote, as a run recorded
    differently would have it."""
    path = run_dir / "run.json"
    path.write_text(json.dumps(change(json.loads(path.read_text()))))


class Import(unittest.TestCase):
    """The importer replays a finished run into a throwaway tracking store."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.tmp.name)
        cls.iris_home = cls.root / "iris"
        cls.dataset = cls.root / "dataset"
        cls.code, cls.commit = clone_with_entry(cls.root)
        cls.dataset_record = dict(DATASET_RECORD, path=str(cls.dataset))
        cls.run_dir = finished_run(cls.iris_home, cls.dataset / "runs" / "1234", cls.code, cls.commit,
                                   experiment=EXPERIMENT, lr=0.001, dataset=cls.dataset_record,
                                   tags={"gpu": "none"})
        cls.metrics = json.loads((cls.run_dir / "metrics.json").read_text())
        cls.first = import_runs(cls.iris_home)
        cls.client = mlflow.MlflowClient(store_uri(cls.iris_home))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def only_run(self):
        experiment = self.client.get_experiment_by_name(EXPERIMENT)
        self.assertIsNotNone(experiment)
        runs = self.client.search_runs([experiment.experiment_id])
        self.assertEqual(len(runs), 1)
        return runs[0]

    def another_run(self, job_id, experiment, **kwargs):
        """A home of its own holding one finished run, `job_id`, imported."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name) / "iris"
        run_dir = finished_run(home, Path(tmp.name) / "dataset" / "runs" / job_id, self.code, self.commit,
                               experiment=experiment, **kwargs)
        return home, run_dir

    def test_one_run_named_by_job_id_under_its_experiment(self):
        self.assertEqual(self.first, {"imported": 1, "pending": 0})
        run = self.only_run()
        self.assertEqual(run.info.run_name, "1234")
        self.assertEqual(run.info.status, "FINISHED")

    def test_artifacts_go_next_to_the_store(self):
        experiment = self.client.get_experiment_by_name(EXPERIMENT)
        self.assertEqual(experiment.artifact_location, (self.iris_home / "artifacts").as_uri())

    def test_params_are_the_recorded_params(self):
        self.assertEqual(self.only_run().data.params, {"experiment": EXPERIMENT, "lr": "0.001", "epochs": "2"})

    def test_metrics_history_replays_every_epoch(self):
        run = self.only_run()
        loss = self.client.get_metric_history(run.info.run_id, "train_loss")
        self.assertEqual([(m.step, m.value) for m in loss], [(1, 0.6), (2, 0.4)])
        self.assertEqual([m.timestamp for m in loss], [int(e["time"] * 1000) for e in self.metrics["epochs"]])
        self.assertEqual([(m.step, m.value) for m in self.client.get_metric_history(run.info.run_id, "dice/1")],
                         [(1, 0.5), (2, 0.7)])
        self.assertEqual([(m.step, m.value) for m in self.client.get_metric_history(run.info.run_id, "dice/2")],
                         [(2, 0.2)])

    def test_tags_carry_the_environment(self):
        tags = self.only_run().data.tags
        for key in ("slug", "job_id", "commit", "venv", "gpu", "queue", "run_dir"):
            self.assertIn(key, tags)
        self.assertEqual(tags["job_id"], "1234")
        self.assertEqual(tags["commit"], self.commit)
        self.assertEqual(tags["run_dir"], str(self.run_dir.resolve()))

    def test_an_unedited_run_is_tagged_not_edited_with_its_run_py_and_empty_run_diff(self):
        run = self.only_run()
        self.assertEqual(run.data.tags["iris.edited"], "false")
        self.assertEqual(artifact_texts(self.client, run), {"run.diff": "", "run.py": "print('as committed')\n"})

    def test_an_edited_run_is_tagged_edited_with_its_run_py_and_run_diff(self):
        home, run_dir = self.another_run("4444", "edited", run_py="print('edited')\n")
        self.assertEqual(import_runs(home), {"imported": 1, "pending": 0})
        client, run = only_run(home, "edited")
        self.assertEqual(run.data.tags["iris.edited"], "true")
        artifacts = artifact_texts(client, run)
        self.assertEqual(artifacts["run.py"], "print('edited')\n")
        self.assertTrue(artifacts["run.diff"].endswith("-print('as committed')\n+print('edited')\n"), artifacts)

    def test_a_run_whose_edits_are_unknown_is_tagged_unknown(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        home = Path(tmp.name) / "iris"
        finished_run(home, Path(tmp.name) / "dataset" / "runs" / "5555", self.code, None, experiment="unknown",
                     run_py="print('maybe edited')\n")  # no commit, so no run.diff
        self.assertEqual(import_runs(home), {"imported": 1, "pending": 0})
        client, run = only_run(home, "unknown")
        self.assertEqual(run.data.tags["iris.edited"], "unknown")
        self.assertEqual(artifact_texts(client, run), {"run.py": "print('maybe edited')\n"})

    def test_the_dataset_record_is_the_runs_dataset_input(self):
        inputs = self.only_run().inputs.dataset_inputs
        self.assertEqual(len(inputs), 1)
        dataset = inputs[0].dataset
        self.assertEqual(dataset.name, "dataset")
        self.assertEqual(dataset.source_type, "local")
        self.assertEqual(json.loads(dataset.source), {"uri": str(self.dataset)})
        self.assertEqual(json.loads(dataset.profile), self.dataset_record)
        self.assertRegex(dataset.digest, r"^[0-9a-f]{8}$")

    def test_a_run_without_dataset_json_imports_without_a_dataset(self):
        home, run_dir = self.another_run("777", "bare")
        (run_dir / "dataset.json").unlink()
        self.assertEqual(import_runs(home), {"imported": 1, "pending": 0})
        _, run = only_run(home, "bare")
        self.assertEqual(run.inputs.dataset_inputs, [])

    def test_a_run_recorded_before_edited_runs_imports_with_no_edited_tag(self):
        home, run_dir = self.another_run("666", "older")
        for name in ("run.py", "run.diff"):
            (run_dir / name).unlink()
        rewrite_run_json(run_dir, lambda run: {k: v for k, v in run.items() if k != "edited"})
        self.assertEqual(import_runs(home), {"imported": 1, "pending": 0})
        client, run = only_run(home, "older")
        self.assertNotIn("iris.edited", run.data.tags)
        self.assertEqual(run.data.params["lr"], "0.01")
        self.assertEqual(artifact_texts(client, run), {})

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
        broken = finished_run(self.iris_home, self.dataset / "runs" / "999", self.code, self.commit,
                              experiment="broken")
        (broken / "metrics.json").write_text('{"epochs": [{"epoch": 1, "train_loss": 0.5}]}')  # no time
        try:
            self.assertEqual(import_runs(self.iris_home), {"imported": 0, "pending": 0})
            experiment = self.client.get_experiment_by_name("broken")
            self.assertEqual(self.client.search_runs([experiment.experiment_id]), [])
        finally:
            (self.iris_home / "run-index" / "999").unlink()

    def test_an_import_that_will_not_wait_leaves_a_held_store_alone(self):
        finished_run(self.iris_home, self.dataset / "runs" / "4321", self.code, self.commit, experiment="held")
        holder = subprocess.Popen(  # lockf locks belong to a process, so hold it from another
            [sys.executable, "-c", HOLD_LOCK, str(self.iris_home / "import.lock")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline(), "held\n")
            self.assertIsNone(import_runs(self.iris_home, wait=False))
            self.assertIsNone(self.client.get_experiment_by_name("held"))
        finally:
            holder.communicate("")
            (self.iris_home / "run-index" / "4321").unlink()

    def test_the_ui_shows_the_imported_run_on_localhost_only(self):
        server, url = start_ui(self.iris_home)
        try:
            self.assertTrue(url.startswith("http://127.0.0.1:"), url)
            client = mlflow.MlflowClient(url)
            experiment = client.get_experiment_by_name(EXPERIMENT)
            [run] = client.search_runs([experiment.experiment_id])
            self.assertEqual(run.info.run_name, "1234")
            address = outward_address()
            if address is None:
                self.skipTest("no non-loopback address to try")
            with self.assertRaises(ConnectionRefusedError):
                socket.create_connection((address, int(url.rsplit(":", 1)[1])), timeout=5).close()
        finally:
            server.terminate()
            server.wait(30)


def outward_address():
    """This machine's address on its default route, or None if it has none.
    Connecting a UDP socket sends nothing."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
        except OSError:
            return None
        address = s.getsockname()[0]
    return None if address.startswith("127.") else address


HOLD_LOCK = """
import fcntl, sys
with open(sys.argv[1], "w") as lock:
    fcntl.lockf(lock, fcntl.LOCK_EX)
    print("held", flush=True)
    sys.stdin.read()
"""


class Rebuild(unittest.TestCase):
    """Rebuilding a lost tracking store from run directories alone."""

    RUNS = {"1001": ("bone", "a", 0.01), "1002": ("bone", "a", 0.001), "2001": ("teeth", "b", 0.01)}

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name).resolve()
        self.iris_home = self.tmp / "iris"
        self.code, self.commit = clone_with_entry(self.tmp)
        for job_id, (experiment, dataset, lr) in self.RUNS.items():
            self.finished(job_id, experiment, dataset, lr)

    def finished(self, job_id, experiment, dataset, lr):
        return finished_run(self.iris_home, self.tmp / dataset / "runs" / job_id, self.code, self.commit,
                            experiment=experiment, lr=lr)

    def assert_every_run_is_back(self, store):
        client = mlflow.MlflowClient(store_uri(store))
        found = {}
        for experiment in ("bone", "teeth"):
            for run in client.search_runs([client.get_experiment_by_name(experiment).experiment_id]):
                found[run.info.run_name] = (experiment, run)
        self.assertEqual(sorted(found), sorted(self.RUNS))
        for job_id, (experiment, run) in found.items():
            expected_experiment, dataset, lr = self.RUNS[job_id]
            self.assertEqual(experiment, expected_experiment)
            self.assertEqual(run.info.status, "FINISHED")
            self.assertEqual(run.data.params, {"experiment": experiment, "lr": str(lr), "epochs": "2"})
            self.assertEqual(run.data.tags["job_id"], job_id)
            self.assertEqual(run.data.tags["slug"], "microct-2d-segmentation")
            self.assertEqual(run.data.tags["commit"], self.commit)
            self.assertEqual(run.data.tags["iris.edited"], "false")
            self.assertEqual(run.data.tags["run_dir"], str(self.tmp / dataset / "runs" / job_id))
            self.assertEqual([(m.step, m.value) for m in client.get_metric_history(run.info.run_id, "train_loss")],
                             [(1, 0.6), (2, 0.4)])
            self.assertEqual([m.step for m in client.get_metric_history(run.info.run_id, "dice/2")], [2])
            [dataset_input] = run.inputs.dataset_inputs
            self.assertEqual(dataset_input.dataset.name, dataset)
            self.assertEqual(json.loads(dataset_input.dataset.profile)["volume"], {"shape": [6, 70, 50]})

    def test_from_the_run_index(self):
        store = self.tmp / "rebuilt"
        self.assertEqual(rebuild(store, index_home=self.iris_home), {"imported": 3, "pending": 0})
        self.assert_every_run_is_back(store)

    def test_from_named_dataset_folders_once_the_run_index_is_gone_too(self):
        for pointer in (self.iris_home / "run-index").iterdir():
            pointer.unlink()
        (self.iris_home / "run-index").rmdir()
        (self.tmp / "a" / "runs" / "1003").mkdir()  # still running: no run.json yet
        store = self.tmp / "rebuilt"
        self.assertEqual(rebuild(store, datasets=[self.tmp / "a", self.tmp / "b"]), {"imported": 3, "pending": 1})
        self.assert_every_run_is_back(store)

    def test_refuses_to_write_into_an_existing_store(self):
        import_runs(self.iris_home)
        self.finished("1004", "bone", "a", 0.1)
        with self.assertRaises(StoreExists):
            rebuild(self.iris_home)
        with self.assertRaises(StoreExists):
            rebuild(self.iris_home, datasets=[self.tmp / "a"])
        client = mlflow.MlflowClient(store_uri(self.iris_home))
        bone = client.get_experiment_by_name("bone").experiment_id
        self.assertEqual(sorted(r.info.run_name for r in client.search_runs([bone])), ["1001", "1002"])

    def test_a_rebuild_that_dies_partway_leaves_no_store_and_can_be_run_again(self):
        broken = self.tmp / "b" / "runs" / "2002" / "run.json"
        broken.parent.mkdir()
        broken.write_text("{")  # not JSON: the importer stops on it
        store = self.tmp / "rebuilt"
        with self.assertRaises(ValueError):
            rebuild(store, datasets=[self.tmp / "a", self.tmp / "b"])
        self.assertFalse((store / "tracking.db").exists())
        broken.unlink()
        self.assertEqual(rebuild(store, datasets=[self.tmp / "a", self.tmp / "b"]), {"imported": 3, "pending": 1})
        self.assert_every_run_is_back(store)

    def test_a_missing_source_fails_before_creating_a_store(self):
        store = self.tmp / "rebuilt"
        with self.assertRaises(FileNotFoundError):
            rebuild(store, datasets=[self.tmp / "a", self.tmp / "typo"])
        with self.assertRaises(FileNotFoundError):
            rebuild(store, index_home=self.tmp / "nowhere")
        self.assertFalse((store / "tracking.db").exists())


def artifact_texts(client, run):
    """{name: text} for each top-level artifact the run has."""
    with tempfile.TemporaryDirectory() as tmp:
        return {a.path: Path(client.download_artifacts(run.info.run_id, a.path, tmp)).read_text()
                for a in client.list_artifacts(run.info.run_id)}


class RecentRuns(unittest.TestCase):
    """What iris-view lists when it is given no run directory."""

    def test_finished_runs_newest_first_from_the_run_index_once_each_skipping_runs_since_deleted(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            home = tmp / "iris"
            code, commit = clone_with_entry(tmp)
            for job_id, end_time in (("1001", 30.0), ("1002", 10.0), ("1003", 20.0), ("1004", 40.0)):
                run_dir = finished_run(home, tmp / "dataset" / "runs" / job_id, code, commit)
                rewrite_run_json(run_dir, lambda run: dict(run, end_time=end_time))
            index = home / "run-index"
            (index / "1005").write_text(str(tmp / "deleted" / "runs" / "1005") + "\n")
            # Newest, but failed, so with no label volume to show.
            failed = finished_run(home, tmp / "dataset" / "runs" / "1006", code, commit, status="FAILED")
            rewrite_run_json(failed, lambda run: dict(run, end_time=50.0))
            (index / "1004.tmp").write_text(str(tmp / "dataset" / "runs" / "1004") + "\n")  # a pointer mid-write
            recent = recent_runs(home, limit=3)
            self.assertEqual([run_dir.name for run_dir, _ in recent], ["1004", "1001", "1003"])
            self.assertEqual([run_dir.name for run_dir, _ in recent_runs(home)], ["1004", "1001", "1003", "1002"])
            self.assertEqual(recent[0][1]["experiment"], "bone")
            self.assertEqual(recent_runs(tmp / "nowhere"), [])


class UnwritableRunIndex(unittest.TestCase):

    def test_the_run_ends_cleanly_with_every_json_file_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, commit = clone_with_entry(Path(tmp))
            blocker = Path(tmp) / "not-a-folder"
            blocker.write_text("")  # the IRIS home can't be created under a file
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                run_dir = finished_run(blocker / "iris", Path(tmp) / "dataset" / "runs" / "1234", code, commit)
            self.assertIn("WARNING: could not add this run to the run index", stderr.getvalue())
            for name in ("params.json", "metrics.json", "dataset.json"):
                json.loads((run_dir / name).read_text())
            self.assertEqual(json.loads((run_dir / "run.json").read_text())["status"], "FINISHED")


class VolumeReader(unittest.TestCase):

    def test_values_above_32767_read_the_same_every_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            vol = make_volume()
            write_dataset(Path(tmp), vol, two_class_labels())
            for _ in range(2):
                read = open_volume(tmp)
                self.assertEqual(read.dtype, np.uint16)
                np.testing.assert_array_equal(read.values, vol)


if __name__ == "__main__":
    unittest.main()
