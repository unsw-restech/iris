"""Run directories for the library's tests, built the way a job builds them:
a scratch git clone holding an entry script, run.py written as the form's
script writes it, the run's code recorded through iris.rundir, as
lib/iris-job.sh's iris_record_code does, and the rest written by RunRecord.
Nothing here writes a run directory's file by hand.
"""

import os
import subprocess
import sys
from pathlib import Path
from unittest import mock

LIB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LIB))

from iris import rundir  # noqa: E402
from iris.record import RunRecord  # noqa: E402

ENTRY = "src/run.py"
COMMITTED = "print('as committed')\n"
SLUG = "microct-2d-segmentation"


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


def commit_all(clone, message):
    git(clone, "add", ".")
    git(clone, "-c", "user.name=IRIS test", "-c", "user.email=iris@example.org", "commit", "--quiet", "-m", message)
    return git(clone, "rev-parse", "HEAD")


def clone_with_entry(root, entry_text=COMMITTED, slug=SLUG):
    """A throwaway clone holding `entry_text` as a workflow's src/run.py,
    committed. Returns its workflow folder, which the job sets as CODE, and
    the commit, which the form records as COMMIT."""
    clone = Path(root) / "clone"
    code = clone / "workflows" / slug
    (code / "src").mkdir(parents=True)
    (code / ENTRY).write_text(entry_text)
    git(clone, "init", "--quiet")
    return code, commit_all(clone, "The entry script")


def move_clone(code):
    """Commit something else in `code`'s clone, as a bin/syspull between the
    form rendering and the job starting does. Returns the new HEAD."""
    clone = Path(git(code, "rev-parse", "--show-toplevel"))
    (clone / "lib.txt").write_text("a newer library\n")
    return commit_all(clone, "A newer library")


def record_code(run_dir, code, commit, run_py=None):
    """Write run.py into `run_dir` as the form's script does, `run_py` or the
    entry script as `code` holds it, then record the run's code by running
    iris.rundir as a module, as iris_record_code does. `commit` is the
    form's COMMIT, None for none. Returns the finished process."""
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / rundir.RUN_PY).write_text((Path(code) / ENTRY).read_text() if run_py is None else run_py)
    return subprocess.run(
        [sys.executable, "-m", "iris.rundir", str(run_dir), str(code), ENTRY, commit or ""],
        env=dict(os.environ, PYTHONPATH=str(LIB)), capture_output=True, text=True, timeout=60)


def finished_run(home, run_dir, code, commit, experiment="bone", lr=0.01, run_py=None, status=None,
                 dataset=None, tags=None):
    """A run directory as a finished job leaves it, its job ID its folder's
    name: its code recorded, then a RunRecord around two epochs, which adds
    it to the run index in `home`. `dataset` is a dataset record
    (iris.dataset) for dataset.json, or None for one naming the run's
    dataset folder. `status` "FAILED" ends the run with an error. Returns
    the run directory."""
    run_dir = Path(run_dir)
    recorded = record_code(run_dir, code, commit, run_py)
    assert recorded.returncode == 0, recorded.stderr
    env = {k: v for k, v in os.environ.items() if k != "PBS_JOBID"}
    try:
        with mock.patch.dict(os.environ, dict(env, IRIS_HOME=str(home)), clear=True), RunRecord(run_dir, experiment, code, tags=tags) as record:
            record.write_params({"experiment": experiment, "lr": lr, "epochs": 2})
            record.write_dataset(lambda: dataset or {"path": str(rundir.dataset_of(run_dir)),
                                                     "volume": {"shape": [6, 70, 50]}})
            record.log_epoch(1, train_loss=0.6, dice={"1": 0.5, "2": None})
            record.log_epoch(2, train_loss=0.4, dice={"1": 0.7, "2": 0.2})
            if status == "FAILED":
                raise RuntimeError("the run failed")
    except RuntimeError:
        pass
    return run_dir
