"""The record a run leaves in its run directory, for the importer to replay.

A job never opens the tracking store (docs/adr/0001). Instead it writes:

  params.json   every form field plus the seed, and what the run derived
  metrics.json  {"epochs": [{"epoch", "time", <metric>: number or
                {<class>: number or null}}...], "final": <last epoch>}
  dataset.json  which dataset the run read (iris.dataset)
  run.diff      written first, by record_edits(): how the run.py this run
                ran differs from the entry script at the commit in
                commit.txt; empty for an unedited run
  run.json      written last: experiment, job ID, whether the run is an
                edited run, the run's tags (venv, commit, slug, job ID, GPU,
                queue, run directory) and how the run ended

and then the pointer file /srv/scratch/$USER/iris/run-index/<job ID>, one
line naming the run directory ($IRIS_HOME replaces /srv/scratch/$USER/iris
in tests). Every file is written atomically. Only dataset.json, run.diff,
run.json and the pointer can fail without failing the run: they warn
instead.

    edited = record_edits(run_dir, __file__, code_dir, "src/run.py")
    with RunRecord(run_dir, experiment, code_dir, edited=edited) as record:
        record.write_params(params)
        record.log_epoch(1, train_loss=0.4, dice={"1": 0.9})
"""

import difflib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def iris_home():
    """The folder holding the run index and the tracking store."""
    if os.environ.get("IRIS_HOME"):
        return Path(os.environ["IRIS_HOME"])
    return Path("/srv/scratch", os.environ.get("USER", ""), "iris")


def run_index(home):
    return home / "run-index"


def indexed_runs(index):
    """(job ID, run directory) for each pointer in the run index, leaving
    out pointers still being written."""
    for pointer in sorted(index.iterdir()) if index.is_dir() else []:
        if not pointer.name.endswith(".tmp"):
            yield pointer.name, Path(pointer.read_text().strip())


def job_id():
    """The PBS job number (9544838 of 9544838.kman...), or None outside PBS."""
    full = os.environ.get("PBS_JOBID", "")
    return full.split(".")[0] or None


def write_atomic(path, text):
    """Write via a temp file and a rename, so a reader, or a run killed
    mid-write, leaves all or nothing."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def write_json(path, obj):
    write_atomic(path, json.dumps(obj, indent=2) + "\n")


def record_edits(run_dir, script, code_dir, entry):
    """Compare `script`, the entry script this run is running, with `entry`
    (a path in `code_dir`, such as src/run.py) at the commit in
    run_dir/commit.txt. Writes the unified diff to run_dir/run.diff, empty
    for an unedited run, prints it, and returns whether the run is edited:
    True, False, or "unknown" when there is no commit to compare with. That
    only warns: the run goes on, and run.diff is not written."""
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    try:
        commit = (run_dir / "commit.txt").read_text().strip()
        if not commit:
            raise ValueError("commit.txt is empty")
        committed = _git(code_dir, "show", f"{commit}:./{entry}")
        path = _git(code_dir, "rev-parse", "--show-prefix").strip() + entry
    except (OSError, ValueError, subprocess.CalledProcessError) as e:
        detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else e
        print(f"WARNING: could not compare run.py with {entry} at the commit this run recorded, "
              f"so whether it was edited is unknown: {detail}", file=sys.stderr)
        return "unknown"
    diff = "".join(difflib.unified_diff(
        committed.splitlines(keepends=True), Path(script).read_text().splitlines(keepends=True),
        f"a/{path}", f"b/{path}"))
    try:
        write_atomic(run_dir / "run.diff", diff)
    except OSError as e:
        print(f"WARNING: could not write {run_dir / 'run.diff'}: {e}", file=sys.stderr)
    if diff:
        print(f"EDITED RUN: run.py differs from {entry} at commit {commit}:\n{diff}", flush=True)
    else:
        print(f"run.py is {entry} at commit {commit}, unedited.", flush=True)
    return bool(diff)


def _git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout


class Killed(BaseException):
    """PBS sent SIGTERM: the walltime ran out or the job was deleted."""


def _on_sigterm(signum, frame):
    raise Killed()


class RunRecord:
    """One run's record. Use it as a context manager around the run: on exit
    it writes run.json with how the run ended, then the pointer file.
    `edited` is what record_edits() returned; left None, run.json has no
    `edited` field."""

    def __init__(self, run_dir, experiment, code_dir, tags=None, edited=None):
        self.run_dir = Path(run_dir).resolve()
        self.experiment = experiment
        self.code_dir = Path(code_dir)
        self.job_id = job_id() or self.run_dir.name
        self.tags = dict(tags or {})
        self.edited = edited
        self.epochs = []

    def __enter__(self):
        self.start_time = time.time()
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self._previous_sigterm = signal.signal(signal.SIGTERM, _on_sigterm)
        return self

    def __exit__(self, exc_type, exc, tb):
        signal.signal(signal.SIGTERM, self._previous_sigterm)
        if exc_type is None:
            status = "FINISHED"
        elif issubclass(exc_type, (Killed, KeyboardInterrupt)):
            status = "KILLED"
        else:
            status = "FAILED"
        try:
            self.write_run(status)
        except Exception as e:  # noqa: BLE001 - the record must never fail the run
            print(f"WARNING: could not write {self.run_dir / 'run.json'}, so this run "
                  f"will not appear in MLflow: {e}", file=sys.stderr)
        else:
            try:
                self.write_pointer()
            except Exception as e:  # noqa: BLE001
                print(f"WARNING: could not add this run to the run index, so it will "
                      f"not appear in MLflow: {e}", file=sys.stderr)
        if exc_type is Killed:
            sys.exit(143)  # what an unhandled SIGTERM exits with
        return False

    def write_params(self, params):
        write_json(self.run_dir / "params.json", params)

    def log_epoch(self, epoch, **metrics):
        """Record one epoch's metrics, rewriting metrics.json."""
        self.epochs.append({"epoch": epoch, "time": time.time(), **metrics})
        write_json(self.run_dir / "metrics.json", {"epochs": self.epochs, "final": self.epochs[-1]})

    def write_dataset(self, describe):
        """Write dataset.json from describe(), which builds the dataset record
        (iris.dataset), and return that record. A failure in either
        warns and returns None: the run goes on without it."""
        try:
            dataset = describe()
            write_json(self.run_dir / "dataset.json", dataset)
            return dataset
        except Exception as e:  # noqa: BLE001 - the record must never fail the run
            print(f"WARNING: could not write {self.run_dir / 'dataset.json'}, so MLflow will "
                  f"not show which dataset this run used: {e}", file=sys.stderr)
            return None

    def run_tags(self):
        return {
            "slug": self.code_dir.name,
            "job_id": self.job_id,
            "commit": self._commit(),
            "venv": sys.prefix,
            "queue": os.environ.get("PBS_QUEUE", "none"),
            "run_dir": str(self.run_dir),
            **self.tags,
        }

    def _commit(self):
        recorded = self.run_dir / "commit.txt"  # written by lib/iris-job.sh
        if recorded.exists():
            return recorded.read_text().strip()
        try:
            return subprocess.run(["git", "-C", str(self.code_dir), "rev-parse", "HEAD"],
                                  capture_output=True, text=True, check=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            return "unknown"

    def write_run(self, status):
        run = {
            "experiment": self.experiment,
            "job_id": self.job_id,
            "status": status,
            "start_time": self.start_time,
            "end_time": time.time(),
            "tags": self.run_tags(),
        }
        if self.edited is not None:
            run["edited"] = self.edited
        write_json(self.run_dir / "run.json", run)

    def write_pointer(self):
        index = run_index(iris_home())
        index.mkdir(parents=True, exist_ok=True)
        write_atomic(index / self.job_id, str(self.run_dir) + "\n")
