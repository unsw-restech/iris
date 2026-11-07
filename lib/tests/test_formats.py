"""The shared tools read a run directory of every run record format ever
written. samples/format-<n>/ keeps one dataset per format, holding the run
directory 1001 as the run record writer of that format left it, frozen:
nothing rewrites it, so a change to the shared tools that drops a format
fails here. Each sample's dataset folder is /srv/scratch/z0000000/dataset
in its records. Run from the repo root in the desktop CPU venv:

    ~/.venvs/iris-imaging/bin/python -m unittest discover -s lib/tests
"""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import run_dirs  # noqa: F401  (it puts lib/ on the path)

from iris import runs  # noqa: E402
from iris.record import FORMAT  # noqa: E402
from iris.tracking import rebuild, store_uri  # noqa: E402
from iris.view import recent_runs  # noqa: E402

import mlflow  # noqa: E402

SAMPLES = Path(__file__).resolve().parent / "samples"

# What each sample's run shows once imported, per format.
TAGS = {
    1: {"slug": "microct-2d-segmentation", "job_id": "1001", "queue": "gpu",
        "commit": "2de6ff0c97ab56a6cab2343a9e6058b842034c51",
        "venv": "/home/z0000000/.venvs/iris-imaging",
        "run_dir": "/srv/scratch/z0000000/dataset/runs/1001", "gpu": "Tesla V100-SXM2-32GB",
        "iris.edited": "false"},
    2: {"slug": "microct-2d-segmentation", "job_id": "1001", "queue": "gpu",
        "commit": "2de6ff0c97ab56a6cab2343a9e6058b842034c51",
        "env_version": "microct/1", "env_digest": "sha256:" + "0123456789abcdef" * 4,
        "run_dir": "/srv/scratch/z0000000/dataset/runs/1001", "gpu": "Tesla V100-SXM2-32GB",
        "iris.edited": "false"},
}


def sample_formats():
    return sorted(int(p.name.split("-")[1]) for p in SAMPLES.glob("format-*"))


class EveryFormatHasASample(unittest.TestCase):

    def test_one_sample_per_format_the_reader_knows_including_the_one_written_now(self):
        self.assertEqual(sample_formats(), list(runs.FORMATS))
        self.assertIn(FORMAT, runs.FORMATS)


class SharedToolsReadEverySample(unittest.TestCase):

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)

    def copy(self, fmt):
        dataset = self.tmp / f"format-{fmt}" / "dataset"
        shutil.copytree(SAMPLES / f"format-{fmt}" / "dataset", dataset)
        return dataset

    def test_the_reader_reads_the_format_it_was_written_in(self):
        for fmt in sample_formats():
            with self.subTest(format=fmt):
                run = runs.read_run(self.copy(fmt) / "runs" / "1001")
                self.assertEqual(run.format, fmt)
                self.assertEqual((run.experiment, run.job_id, run.status), ("bone", "1001", "FINISHED"))

    def test_rebuild_from_the_dataset_folder_imports_the_run_whole(self):
        for fmt in sample_formats():
            with self.subTest(format=fmt):
                store = self.tmp / f"store-{fmt}"
                self.assertEqual(rebuild(store, datasets=[self.copy(fmt)]), {"imported": 1, "pending": 0})
                client = mlflow.MlflowClient(store_uri(store))
                [run] = client.search_runs([client.get_experiment_by_name("bone").experiment_id])
                self.assertEqual(run.info.run_name, "1001")
                self.assertEqual(run.info.status, "FINISHED")
                self.assertEqual(run.data.params, {"experiment": "bone", "lr": "0.001", "epochs": "2", "seed": "7"})
                tags = {k: v for k, v in run.data.tags.items() if not k.startswith("mlflow.")}
                self.assertEqual(tags, {**TAGS[fmt], "iris_import": "complete"})
                history = client.get_metric_history(run.info.run_id, "train_loss")
                self.assertEqual([(m.step, m.value) for m in history], [(1, 0.6), (2, 0.4)])
                self.assertEqual([(m.step, m.value) for m in client.get_metric_history(run.info.run_id, "dice/2")],
                                 [(2, 0.2)])
                [dataset] = run.inputs.dataset_inputs
                self.assertEqual(dataset.dataset.name, "dataset")
                self.assertEqual(json.loads(dataset.dataset.source), {"uri": "/srv/scratch/z0000000/dataset"})

    def test_iris_view_lists_the_run_and_reads_its_intensity_range(self):
        from iris.view import intensity_range
        for fmt in sample_formats():
            with self.subTest(format=fmt):
                run_dir = self.copy(fmt) / "runs" / "1001"
                home = self.tmp / f"home-{fmt}"
                (home / "run-index").mkdir(parents=True)
                (home / "run-index" / "1001").write_text(f"{run_dir}\n")
                self.assertEqual([r for r, _ in recent_runs(home)], [run_dir])
                self.assertEqual(intensity_range(run_dir), (1000, 65535))


if __name__ == "__main__":
    unittest.main()
