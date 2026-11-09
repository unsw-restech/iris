"""Reading a run's record, in every run record format ever written.

The shared tools (the importer, rebuild, iris-view and so iris-compare)
read run directories only through here, so the runs of every workflow,
whichever copy of the library wrote them, show up together. run.json
states its record's format in "format"; one without is format 1, so every
run recorded before formats were numbered reads unchanged. The format
covers the whole run record: run.json, params.json, metrics.json and
dataset.json.

Format 1, written until #127:
  run.json      {"experiment", "job_id", "status", "start_time",
                "end_time", "tags": {slug, job_id, commit, lib_commit if
                the clone moved, venv, queue, run_dir, and the workflow's
                own tags, such as gpu}, "edited" (absent before edited
                runs)}
  metrics.json  {"epochs": [{"epoch", "time", <metric>...}], "final"}
  dataset.json  {"path", and microCT's "train", "volume" and "intensity"}

Format 2, which iris.record and iris.dataset write now, describe it in
full.

Both: params.json a flat {name: value}. A record whose format is newer than this library knows is
refused with UnknownFormat, naming its format, rather than read wrong.

    run = read_run(run_dir)      # FileNotFoundError until run.json exists
    run.tags, run.params(), run.metric_points()
    run.dataset(), run.dataset_extras(), run.dataset_stable()
"""

import json
from dataclasses import dataclass, field
from pathlib import Path

from iris import rundir

FORMATS = (1, 2)  # every format this library reads; lib/tests/samples keeps one of each
UNKNOWN = rundir.UNKNOWN


class UnknownFormat(ValueError):
    """A run record in a format this library does not know."""


def _read_json(path, empty):
    """`path`'s contents, or `empty` if the run ended before writing it."""
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return empty


def _tag_value(value):
    return value if isinstance(value, str) else json.dumps(value)


@dataclass
class Run:
    """One run's record, the same whatever format wrote it.

    tags are the run's tags as the importer logs them, strings by name:
    its workflow (slug), job ID, queue, commit, lib_commit if the clone
    moved, run directory and environment (venv in format 1, env_version and
    env_digest in format 2), plus the workflow's own details. edited is
    run.json's edited flag (true, false or "unknown"), or None for a run
    recorded before edited runs."""

    run_dir: Path
    format: int
    experiment: str
    job_id: str
    status: str
    start_time: float
    end_time: float
    tags: dict = field(default_factory=dict)
    edited: object = None

    def params(self):
        """params.json: every form field and what the run derived."""
        return _read_json(self.run_dir / rundir.PARAMS, {})

    def metric_points(self):
        """Every metric the run logged, as (name, value, time in ms, step)
        in the order logged. A class's metric {"1": 0.9} becomes name/1;
        values that are not numbers, such as an absent class's None, are
        left out. The step is the epoch, or 0 for metrics logged without
        one (format 2)."""
        metrics = _read_json(self.run_dir / rundir.METRICS, {})
        entries = metrics.get("epochs", []) if self.format == 1 else metrics.get("log", [])
        points = []
        for entry in entries:
            for name, value in _flat_metrics(entry):
                points.append((name, value, int(entry["time"] * 1000), entry.get("epoch", 0)))
        return points

    def dataset(self):
        """The dataset record (iris.dataset) as the run wrote it, or None if
        the run wrote none."""
        return _read_json(self.run_dir / rundir.DATASET, None)

    def dataset_extras(self):
        """The workflow's own details in the dataset record, such as the
        microCT volume's "intensity", or {} if it wrote none. Format 1 held
        them beside "path"; format 2 holds them under "extras"."""
        record = self.dataset() or {}
        if self.format == 1:
            return {k: v for k, v in record.items() if k != "path"}
        return record.get("extras", {})

    def dataset_stable(self):
        """The part of the dataset record that holds still while the run
        goes on, which the importer's digest hashes, or None if the run
        wrote no record. Format 2: what is true of any folder (path, files,
        size_bytes, mtime). Format 1: all but the intensity statistics,
        added once inference had read the whole volume, so existing runs
        keep the digest they were imported with. The two hash different
        fields, since format 1 recorded no folder totals, so one dataset
        gets one digest in format 1 runs and another in format 2 runs, and
        the change can't be undone without reading the data again."""
        record = self.dataset()
        if record is None:
            return None
        if self.format == 1:
            return {k: v for k, v in record.items() if k != "intensity"}
        return {k: v for k, v in record.items() if k != "extras"}


def _flat_metrics(entry):
    for key, value in entry.items():
        if key in ("epoch", "time"):
            continue
        for name, v in (value.items() if isinstance(value, dict) else [(None, value)]):
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                yield (f"{key}/{name}" if name is not None else key), float(v)


def read_run(run_dir):
    """The record of the run in `run_dir`. Raises FileNotFoundError if it
    has no run.json yet, ValueError if run.json is not JSON, and
    UnknownFormat if its format is newer than this library."""
    run_dir = Path(run_dir)
    record = json.loads((run_dir / rundir.RUN_JSON).read_text())
    fmt = record.get("format", 1)
    if fmt == 1:
        return _format_1(run_dir, record)
    if fmt == 2:
        return _format_2(run_dir, record)
    raise UnknownFormat(f"{run_dir / rundir.RUN_JSON} is in run record format {fmt}, newer than this "
                        f"library reads ({', '.join(map(str, FORMATS))}): update IRIS to read it")


def _format_1(run_dir, record):
    return Run(run_dir, 1, record["experiment"], record["job_id"], record["status"],
               record["start_time"], record["end_time"],
               {k: str(v) for k, v in record["tags"].items()}, record.get("edited"))


def _format_2(run_dir, record):
    run, job, code, env = record["run"], record["job"], record["code"], record["environment"]
    tags = {k: _tag_value(v) for k, v in record.get("extras", {}).items()}
    tags.update({
        "slug": run["workflow"],
        "job_id": job["id"],
        "queue": job["queue"],
        "commit": code["commit"],
        "env_version": env.get("version") or UNKNOWN,
        "env_digest": env.get("digest") or UNKNOWN,
        "run_dir": run["dir"],
    })
    if code.get("lib_commit"):
        tags["lib_commit"] = code["lib_commit"]
    return Run(run_dir, 2, run["experiment"], job["id"], run["status"], run["start_time"], run["end_time"],
               tags, code["edited"])
