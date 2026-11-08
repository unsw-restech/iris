"""The record a run leaves in its run directory, for the importer to replay.

A job never opens the tracking store (docs/adr/0001). Instead, once the job
has recorded the run's code in the run directory (iris.rundir, which names
every file there), the entry script's RunRecord writes the run record, in
run record format FORMAT. It holds only what is true of any run; the
shared tools read every format ever written (iris.runs).

  params.json   the run's parameters: every form field plus the seed, and
                what the run derived, as a flat {name: value}
  metrics.json  {"log": [{"time", "epoch" if logged per epoch,
                <metric>: number or {<class>: number or null}}...],
                "final": {<metric>: its latest value}}; a run that logs no
                metrics writes none
  dataset.json  the dataset record (iris.dataset): which dataset the run
                read
  run.json      written last:
                  "format"       FORMAT
                  "run"          its identity and how it ended:
                                 {"experiment", "workflow" (the slug),
                                 "dir", "status", "start_time", "end_time"}
                  "job"          {"id", "queue"}: the PBS job number, or
                                 outside PBS the run directory's name, and
                                 its queue or "none"
                  "code"         {"commit", "lib_commit" only if the clone
                                 moved, "edited": true, false or
                                 "unknown"}, as iris.rundir reads them
                  "environment"  {"version", "digest"}: the environment it
                                 ran in, from IRIS_ENV_VERSION and
                                 IRIS_ENV_DIGEST, which the job library
                                 exports; null for either it leaves unset
                  "extras"       the workflow's own details, such as the
                                 GPU it ran on: {} if it adds none

and then the pointer file /srv/scratch/$USER/iris/run-index/<job ID>, one
line naming the run directory ($IRIS_HOME replaces /srv/scratch/$USER/iris
in tests). Every file is written atomically. Only dataset.json, run.json
and the pointer can fail without failing the run: they warn instead.

The label volume and the trained weights are the workflow's to write, if
it writes them; a run with no parameters or metrics is still a valid run.
The entry script records the run:

    with RunRecord(run_dir, experiment, code_dir, extras={"gpu": gpu}) as record:
        record.write_params(params)
        record.log_epoch(1, train_loss=0.4, dice={"1": 0.9})
        record.log_metrics(voxels=123456)    # no epoch
"""

import json
import os
import signal
import sys
import time
from pathlib import Path

from iris import rundir

FORMAT = 2  # the run record format this writes (iris.runs reads every one)


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


def write_json(path, obj):
    rundir.write_atomic(path, json.dumps(obj, indent=2) + "\n")


class Killed(BaseException):
    """PBS sent SIGTERM: the walltime ran out or the job was deleted."""


def _on_sigterm(signum, frame):
    raise Killed()


class RunRecord:
    """One run's record. Use it as a context manager around the run: on exit
    it writes run.json with how the run ended, then the pointer file."""

    def __init__(self, run_dir, experiment, code_dir, extras=None):
        self.run_dir = Path(run_dir).resolve()
        self.experiment = experiment
        self.code_dir = Path(code_dir)
        self.job_id = job_id() or self.run_dir.name
        self.extras = dict(extras or {})
        self.log = []
        self.final = {}

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
            print(f"WARNING: could not write {self.run_dir / rundir.RUN_JSON}, so this run "
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
        write_json(self.run_dir / rundir.PARAMS, params)

    def log_epoch(self, epoch, **metrics):
        """Record one epoch's metrics, rewriting metrics.json."""
        self._log({"epoch": epoch}, metrics)

    def log_metrics(self, **metrics):
        """Record metrics that belong to no epoch, rewriting metrics.json."""
        self._log({}, metrics)

    def _log(self, step, metrics):
        self.log.append({**step, "time": time.time(), **metrics})
        self.final.update(metrics)
        write_json(self.run_dir / rundir.METRICS, {"log": self.log, "final": self.final})

    def write_dataset(self, describe):
        """Write dataset.json from describe(), which builds the dataset record
        (iris.dataset), and return that record. A failure in either
        warns and returns None: the run goes on without it."""
        try:
            dataset = describe()
            write_json(self.run_dir / rundir.DATASET, dataset)
            return dataset
        except Exception as e:  # noqa: BLE001 - the record must never fail the run
            print(f"WARNING: could not write {self.run_dir / rundir.DATASET}, so MLflow will "
                  f"not show which dataset this run used: {e}", file=sys.stderr)
            return None

    def code(self):
        code = {"commit": rundir.recorded_commit(self.run_dir, self.code_dir)}
        moved = rundir.lib_commit(self.run_dir)
        if moved is not None:
            code["lib_commit"] = moved
        code["edited"] = rundir.edited_to_record(rundir.edited(self.run_dir))
        return code

    def write_run(self, status):
        run = {
            "format": FORMAT,
            "run": {
                "experiment": self.experiment,
                "workflow": self.code_dir.name,
                "dir": str(self.run_dir),
                "status": status,
                "start_time": self.start_time,
                "end_time": time.time(),
            },
            "job": {"id": self.job_id, "queue": os.environ.get("PBS_QUEUE", "none")},
            "code": self.code(),
            "environment": {"version": os.environ.get("IRIS_ENV_VERSION") or None,
                            "digest": os.environ.get("IRIS_ENV_DIGEST") or None},
            "extras": self.extras,
        }
        write_json(self.run_dir / rundir.RUN_JSON, run)

    def write_pointer(self):
        index = run_index(iris_home())
        index.mkdir(parents=True, exist_ok=True)
        rundir.write_atomic(index / self.job_id, str(self.run_dir) + "\n")

