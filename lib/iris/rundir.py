"""The run directory: one run's folder, <dataset>/runs/<job number>.

This module owns what a run directory holds and where it is. Every file in
one is named here, and the job, the run record (iris.record), the importer
(iris.tracking), iris-view and the entry scripts go through these names.
The format on disk is fixed: runs recorded before this module import
unchanged.

  run.py          the entry script as the form's script pane held it,
                  written by the job before Python runs it (ADR-0006)
  commit.txt      the commit of the IRIS clone the run recorded: the
                  form's, at render time, or the clone's at job start if
                  the form recorded none
  lib_commit.txt  only if the clone moved between the form rendering and
                  the job starting: its commit at job start, which lib/
                  was read at
  run.diff        how run.py differs from the entry script at that commit:
                  empty for an unedited run, absent if it can't be told
  params.json, metrics.json, dataset.json, run.json
                  the run's record (iris.record), run.json last
  labels.tif, model.pt
                  the label volume and the trained weights

Recording a run's code writes commit.txt, lib_commit.txt and run.diff and
prints the edit report. lib/iris-job.sh's iris_record_code runs it in a
Python of its own once the script has written run.py, so a run.py that
can't even start still leaves its diff:

    python -m iris.rundir <run dir> <workflow folder> src/run.py <commit>

It is a record step: it warns, and never fails the run.
"""

import difflib
import os
import subprocess
import sys
from pathlib import Path

RUNS = "runs"  # the folder in a dataset holding its run directories
RUN_PY = "run.py"
COMMIT = "commit.txt"
LIB_COMMIT = "lib_commit.txt"
RUN_DIFF = "run.diff"
PARAMS = "params.json"
METRICS = "metrics.json"
DATASET = "dataset.json"
RUN_JSON = "run.json"
LABELS = "labels.tif"
MODEL = "model.pt"

UNKNOWN = "unknown"  # how run.json and the iris.edited tag write an unknown edited flag


def runs_folder(dataset):
    """The folder in `dataset` that holds its run directories."""
    return Path(dataset) / RUNS


def run_dir(dataset, job):
    """The run directory of job number `job` on `dataset`."""
    return runs_folder(dataset) / str(job)


def dataset_of(run_dir):
    """The dataset folder a run directory belongs to."""
    return Path(run_dir).parents[1]


def _git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout


def _head(code_dir):
    """The commit `code_dir`'s clone is at, or None if git can't tell."""
    try:
        return _git(code_dir, "rev-parse", "HEAD").strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def write_atomic(path, text):
    """Write via a temp file and a rename, so a reader, or a run killed
    mid-write, sees all or nothing. Every file the run directory, its
    record and the run index hold is written this way."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def _warn(message):
    print(f"WARNING: {message}", file=sys.stderr, flush=True)


def record_code(run_dir, code_dir, entry, commit):
    """Record the code of the run in `run_dir`, whose run.py the job has
    written from the form's script pane. `code_dir` is the workflow folder
    in the clone, `entry` the entry script's path in it (src/run.py) and
    `commit` the clone's commit when the form rendered ("" or None if the
    form recorded none).

    Writes commit.txt: `commit`, or with none the clone's commit now, with a
    warning that whether the run is edited is unknown. If the clone has
    moved since `commit`, writes its commit now to lib_commit.txt and warns.
    Then compares run.py with `entry` at `commit`, writes the diff to
    run.diff, empty for an unedited run, and prints it; with no commit, or
    one git can't read, it warns and writes no run.diff. It never raises."""
    run_dir = Path(run_dir)
    head = _head(code_dir)
    try:
        _record_commits(run_dir, commit, head)
    except OSError as e:
        _warn(f"could not record the IRIS commit in {run_dir}: {e}")
    try:
        if not commit:
            raise ValueError("the form recorded no commit")
        committed = _git(code_dir, "show", f"{commit}:./{entry}")
        path = _git(code_dir, "rev-parse", "--show-prefix").strip() + entry
        diff = "".join(difflib.unified_diff(
            committed.splitlines(keepends=True), (run_dir / RUN_PY).read_text().splitlines(keepends=True),
            f"a/{path}", f"b/{path}"))
    except Exception as e:  # noqa: BLE001 - the record must never fail the run
        detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else e
        _warn(f"could not compare run.py with {entry} at the commit the form was opened at, "
              f"so whether this run is edited is unknown: {detail}")
        return
    try:
        write_atomic(run_dir / RUN_DIFF, diff)
    except OSError as e:
        _warn(f"could not write {run_dir / RUN_DIFF}, so whether this run is edited is unknown: {e}")
    if diff:
        print(f"EDITED RUN: the workflow code in this job's script was edited on the form, or restored "
              f"with its edits by Load parameters, so run.py differs from {entry} at commit {commit}. "
              f"To change a field for another run, set the form's fields first and edit the code last: "
              f"changing a field rewrites the script and discards the edits. The edits, also in run.diff:\n"
              f"{diff}", flush=True)
    else:
        print(f"run.py is {entry} at commit {commit}, unedited.", flush=True)


def _record_commits(run_dir, commit, head):
    """commit.txt and, if the clone moved, lib_commit.txt, for record_code()."""
    if not commit:
        if head is None:
            _warn("the form did not record the IRIS clone's commit and git could not read it either, "
                  "so this run records no commit and whether it is edited is unknown.")
            return
        write_atomic(run_dir / COMMIT, head + "\n")
        _warn(f"the form did not record the IRIS clone's commit, so commit.txt holds its commit at job start, "
              f"{head}, and whether this run is edited is unknown.")
        return
    write_atomic(run_dir / COMMIT, commit + "\n")
    if head is None:
        _warn(f"could not read the IRIS clone's commit at job start, so whether it moved from {commit}, "
              f"when the form was opened, is unknown.")
    elif head != commit:
        write_atomic(run_dir / LIB_COMMIT, head + "\n")
        _warn(f"the IRIS clone moved from commit {commit}, when the form was opened, to {head}. "
              f"The workflow code in this script is from {commit}; the library it uses (lib/) is from {head}, "
              f"recorded in {run_dir / LIB_COMMIT}.")


def recorded_commit(run_dir, code_dir):
    """The commit the run in `run_dir` recorded, from commit.txt. A run
    whose code was never recorded, such as an entry script run by hand,
    falls back to `code_dir`'s clone's commit now, as record_code() does
    when the form recorded none; UNKNOWN if git can't tell either."""
    try:
        return (Path(run_dir) / COMMIT).read_text().strip()
    except OSError:
        return _head(code_dir) or UNKNOWN


def lib_commit(run_dir):
    """The commit lib/ was read at, if the clone moved after the form
    rendered (lib_commit.txt), else None."""
    try:
        return (Path(run_dir) / LIB_COMMIT).read_text().strip()
    except OSError:
        return None


def edited(run_dir):
    """Whether the run in `run_dir` is an edited run, from the run.diff
    record_code() left: True, False, or None for unknown, with no run.diff."""
    try:
        return bool((Path(run_dir) / RUN_DIFF).read_text())
    except OSError:
        return None


def edited_to_record(value):
    """An edited flag (True, False or None) as run.json writes it: true,
    false or "unknown"."""
    return UNKNOWN if value is None else value


def edited_tag(value):
    """run.json's `edited` (true, false or anything else for unknown) as the
    importer's iris.edited tag writes it: true, false or unknown."""
    return str(value).lower() if isinstance(value, bool) else UNKNOWN


if __name__ == "__main__":
    record_code(*sys.argv[1:5])  # run dir, workflow folder, entry script, commit
