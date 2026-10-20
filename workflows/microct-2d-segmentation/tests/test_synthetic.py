"""Synthetic-dataset test for the microCT reference workflow (seam 2 in #24).

Builds a tiny dataset on the fly, runs the entry point on CPU for one epoch
and asserts only on what lands in the run directory. Run from the repo root
in the desktop CPU venv (envs/imaging/desktop.sh):

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s workflows/microct-2d-segmentation/tests
"""

import json
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

import netCDF4
import numpy as np
import tifffile

WORKFLOW = Path(__file__).resolve().parents[1]
REPO = WORKFLOW.parents[1]
LIB = REPO / "lib"
ENTRY = WORKFLOW / "src" / "run.py"

sys.path.insert(0, str(LIB))
from iris.compare import start_ui  # noqa: E402
from iris.tracking import StoreExists, import_runs, rebuild, store_uri  # noqa: E402
from iris.volume import open_volume  # noqa: E402

import mlflow  # noqa: E402  (after iris.tracking, which quiets its start-up hint)

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
        cls.dataset_record = json.loads((cls.run_dir / "dataset.json").read_text())
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

    def test_the_dataset_record_is_the_runs_dataset_input(self):
        inputs = self.only_run().inputs.dataset_inputs
        self.assertEqual(len(inputs), 1)
        dataset = inputs[0].dataset
        self.assertEqual(dataset.name, "dataset")
        self.assertEqual(dataset.source_type, "local")
        self.assertEqual(json.loads(dataset.source), {"uri": str(self.dataset.resolve())})
        self.assertEqual(json.loads(dataset.profile), self.dataset_record)
        self.assertEqual(sorted(self.dataset_record), ["intensity", "path", "train", "volume"])
        self.assertRegex(dataset.digest, r"^[0-9a-f]{8}$")

    def test_a_run_without_dataset_json_imports_without_a_dataset(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, bare = Path(tmp) / "iris", Path(tmp) / "777"
            bare.mkdir()
            (bare / "run.json").write_text(json.dumps({
                "experiment": "bare", "job_id": "777", "status": "FINISHED",
                "start_time": 1.0, "end_time": 2.0, "tags": {"job_id": "777"}}))
            (home / "run-index").mkdir(parents=True)
            (home / "run-index" / "777").write_text(str(bare) + "\n")
            self.assertEqual(import_runs(home), {"imported": 1, "pending": 0})
            client = mlflow.MlflowClient(store_uri(home))
            [run] = client.search_runs([client.get_experiment_by_name("bare").experiment_id])
            self.assertEqual(run.inputs.dataset_inputs, [])

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

    def test_an_import_that_will_not_wait_leaves_a_held_store_alone(self):
        ready = self.dataset / "runs" / "4321"
        ready.mkdir()
        (ready / "run.json").write_text(json.dumps({
            "experiment": "held", "job_id": "4321", "status": "FINISHED",
            "start_time": 1.0, "end_time": 2.0, "tags": {"job_id": "4321"}}))
        (self.iris_home / "run-index" / "4321").write_text(str(ready) + "\n")
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
            experiment = client.get_experiment_by_name("microct-2d-segmentation")
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


def write_run_dir(run_dir, experiment, job_id, lr):
    """A finished run's record, written by hand as RunRecord would leave it."""
    run_dir.mkdir(parents=True)
    (run_dir / "params.json").write_text(json.dumps({"experiment": experiment, "lr": lr, "epochs": 2}))
    (run_dir / "metrics.json").write_text(json.dumps({"epochs": [
        {"epoch": 1, "time": 10.0, "train_loss": 0.6, "dice": {"1": 0.5, "2": None}},
        {"epoch": 2, "time": 20.0, "train_loss": 0.4, "dice": {"1": 0.7, "2": 0.2}},
    ]}))
    (run_dir / "dataset.json").write_text(json.dumps({"path": str(run_dir.parents[1]), "volume": {"shape": [6, 70, 50]}}))
    (run_dir / "run.json").write_text(json.dumps({
        "experiment": experiment, "job_id": job_id, "status": "FINISHED",
        "start_time": 5.0, "end_time": 25.0,
        "tags": {"job_id": job_id, "slug": "microct-2d-segmentation", "run_dir": str(run_dir)}}))


class Rebuild(unittest.TestCase):
    """Rebuilding a lost tracking store from run directories alone."""

    RUNS = {"1001": ("bone", "a", 0.01), "1002": ("bone", "a", 0.001), "2001": ("teeth", "b", 0.01)}

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.iris_home = self.tmp / "iris"
        (self.iris_home / "run-index").mkdir(parents=True)
        for job_id, (experiment, dataset, lr) in self.RUNS.items():
            run_dir = self.tmp / dataset / "runs" / job_id
            write_run_dir(run_dir, experiment, job_id, lr)
            (self.iris_home / "run-index" / job_id).write_text(str(run_dir) + "\n")

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
        write_run_dir(self.tmp / "a" / "runs" / "1004", "bone", "1004", 0.1)
        (self.iris_home / "run-index" / "1004").write_text(str(self.tmp / "a" / "runs" / "1004") + "\n")
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
