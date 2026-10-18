"""The importer: replays run directories into the researcher's tracking store.

Jobs never open the store (docs/adr/0001). Each finished run leaves a record
in its run directory and a pointer in /srv/scratch/$USER/iris/run-index/
(see iris.record). This replays every indexed run not yet in
/srv/scratch/$USER/iris/tracking.db, creating the store on first import
with its artifact root, artifacts/, next to it. Each becomes one MLflow run
named by its job ID, under its experiment, with its params, metrics history
and tags, and its dataset.json, if it wrote one, as its dataset input.

Runs with no run.json yet are left for the next import. A run is marked
complete only once everything is logged; one whose import fails is deleted
at once, and one whose import was interrupted is deleted next time, so
either is redone. A lock file keeps it to one importer per store at a time.

    python -m iris.tracking        # or bin/iris-import
"""

import fcntl
import hashlib
import json
import os
import sys
from pathlib import Path

os.environ.setdefault("MLFLOW_DISABLE_AGENT_HINT", "1")

from mlflow import MlflowClient  # noqa: E402
from mlflow.entities import Dataset, DatasetInput, Metric, Param, RunTag, ViewType  # noqa: E402
from mlflow.store.tracking.sqlalchemy_store import SqlAlchemyStore  # noqa: E402

from iris.record import iris_home, run_index  # noqa: E402

IMPORT_TAG = "iris_import"  # "incomplete" until every value is logged, then "complete"
PARAMS_TAGS_PER_CALL = 100  # MLflow's caps per log_batch call
METRICS_PER_CALL = 1000


def store_uri(home):
    return "sqlite:///" + str(home / "tracking.db")


def open_store(home):
    """A client on the tracking store in `home`, creating it if it is new."""
    home.mkdir(parents=True, exist_ok=True)
    uri = store_uri(home)
    # Created through the store itself so even its Default experiment's
    # artifacts land next to it, not in whatever folder the importer ran from.
    SqlAlchemyStore(uri, artifact_root(home))
    return MlflowClient(uri)


def artifact_root(home):
    return (home / "artifacts").as_uri()


def experiment_id(client, name, home):
    experiment = client.get_experiment_by_name(name)
    if experiment is None:
        return client.create_experiment(name, artifact_location=artifact_root(home))
    if experiment.lifecycle_stage == "deleted":
        client.restore_experiment(experiment.experiment_id)
    return experiment.experiment_id


def tagged_runs(client, status):
    """Every active run whose import tag is `status`, in any experiment,
    deleted ones included: experiment_id() restores those."""
    ids = [e.experiment_id for e in client.search_experiments(view_type=ViewType.ALL)]
    runs, token = [], None
    while ids:
        page = client.search_runs(ids, f"tags.{IMPORT_TAG} = '{status}'", page_token=token)
        runs.extend(page)
        token = page.token
        if not token:
            break
    return runs


def param_value(value):
    return value if isinstance(value, str) else json.dumps(value)


def metric_values(epoch):
    """One epoch's record as flat MLflow metrics: dice {"1": 0.9} becomes
    dice/1. Values that are not numbers, such as an absent class's None,
    are left out."""
    for key, value in epoch.items():
        if key in ("epoch", "time"):
            continue
        for name, v in (value.items() if isinstance(value, dict) else [(None, value)]):
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                yield (f"{key}/{name}" if name is not None else key), float(v)


def dataset_input(record):
    """A run's dataset record (iris.dataset) as an MLflow dataset input,
    named after the dataset folder, with the whole record as its profile.
    The digest hashes the record, never the volume's contents: everything
    but the intensity statistics, so a run killed before inference finished gets the same
    digest as a finished one on the same, unchanged dataset."""
    stable = {k: v for k, v in record.items() if k != "intensity"}
    digest = hashlib.sha256(json.dumps(stable, sort_keys=True).encode()).hexdigest()[:8]
    return DatasetInput(Dataset(
        name=Path(record["path"]).name,
        digest=digest,
        source_type="local",
        source=json.dumps({"uri": record["path"]}),
        profile=json.dumps(record),
    ))


def read_json(path, empty):
    """`path`'s contents, or `empty` if the run ended before writing it."""
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return empty


def log_in_batches(client, run_id, kind, values, per_call):
    for i in range(0, len(values), per_call):
        client.log_batch(run_id, **{kind: values[i:i + per_call]})


def replay(client, home, run_dir, record):
    """Log one run directory into the store as a single MLflow run. If any
    step fails, the half-logged run is deleted."""
    params = read_json(run_dir / "params.json", {})
    epochs = read_json(run_dir / "metrics.json", {"epochs": []})["epochs"]
    dataset = read_json(run_dir / "dataset.json", None)
    run = client.create_run(
        experiment_id(client, record["experiment"], home),
        start_time=int(record["start_time"] * 1000),
        tags={IMPORT_TAG: "incomplete"},
        run_name=record["job_id"],
    )
    run_id = run.info.run_id
    try:
        log_in_batches(client, run_id, "params",
                       [Param(k, param_value(v)) for k, v in params.items()], PARAMS_TAGS_PER_CALL)
        log_in_batches(client, run_id, "tags",
                       [RunTag(k, str(v)) for k, v in record["tags"].items()], PARAMS_TAGS_PER_CALL)
        log_in_batches(client, run_id, "metrics",
                       [Metric(name, value, int(epoch["time"] * 1000), epoch["epoch"])
                        for epoch in epochs for name, value in metric_values(epoch)], METRICS_PER_CALL)
        if dataset is not None:
            client.log_inputs(run_id, datasets=[dataset_input(dataset)])
        client.set_terminated(run_id, record["status"], int(record["end_time"] * 1000))
        client.set_tag(run_id, IMPORT_TAG, "complete")
    except Exception:
        client.delete_run(run_id)
        raise


def import_runs(home=None):
    """Import every indexed run not yet in the store. Returns the number
    imported and the number still waiting for their run.json."""
    home = Path(home) if home else iris_home()
    index = run_index(home)
    home.mkdir(parents=True, exist_ok=True)
    with open(home / "import.lock", "w") as lock:
        try:
            fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print("Waiting for another import into this store to finish...", file=sys.stderr)
            fcntl.lockf(lock, fcntl.LOCK_EX)

        client = open_store(home)
        for run in tagged_runs(client, "incomplete"):
            client.delete_run(run.info.run_id)  # interrupted: redo it
        done = {run.data.tags.get("job_id") for run in tagged_runs(client, "complete")}

        imported = pending = 0
        pointers = sorted(index.iterdir()) if index.is_dir() else []
        for pointer in pointers:
            if pointer.name.endswith(".tmp") or pointer.name in done:
                continue
            run_dir = Path(pointer.read_text().strip())
            try:
                record = json.loads((run_dir / "run.json").read_text())
            except FileNotFoundError:
                pending += 1
                continue
            if record["job_id"] in done:
                continue
            try:
                replay(client, home, run_dir, record)
            except Exception as e:  # noqa: BLE001 - one bad run must not block the rest
                print(f"WARNING: could not import {run_dir}: {e}", file=sys.stderr)
                continue
            done.add(record["job_id"])
            imported += 1
    return {"imported": imported, "pending": pending}


def main():
    result = import_runs()
    print(f"Imported {result['imported']} new run(s) into {iris_home() / 'tracking.db'}."
          + (f" Skipped {result['pending']} indexed run(s) with no run.json yet." if result["pending"] else ""))


if __name__ == "__main__":
    main()
