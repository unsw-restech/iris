# Jobs never write the tracking store

A researcher's tracking store is one SQLite file on GPFS (`/srv/scratch/$USER/iris/tracking.db`), and their runs usually land on different nodes. Two jobs on different nodes can't share it: one writer holds the lock and the other's writes time out after MLflow's 20 s busy timeout, so runs are lost (#34: jobs 9550158/9550159 and 9550174/9550175, against a clean pass for two jobs on the same node). Two jobs creating the store at the same time also race through MLflow's schema migrations. So a job never opens the tracking store. It writes its record as plain files into its own run directory, plus a one-line pointer file `/srv/scratch/$USER/iris/run-index/<job ID>` naming that directory, and a single importer process (run by `iris-compare`, and by the rebuild script into a fresh store) replays new run directories into `tracking.db` through the MLflow client.

## Considered Options

- **Each job writes `tracking.db`, with retries or a longer busy timeout**: rejected. Across nodes the waiting job is starved for as long as the other job writes, so a longer timeout turns lost runs into training jobs stalled for minutes.
- **An `mlflow server` that every job writes through**: rejected for v1. It needs a long-running service on Katana that jobs can reach, and a researcher's runs would depend on it being up.
- **One SQLite store per job**: `mlflow ui` reads a single backend, so these would need importing anyway. That is this decision with a heavier per-run format.

## Consequences

- The tracking store only shows a run once something has imported it. `iris-compare` imports before it opens `mlflow ui`.
- A job can't learn its MLflow run ID. The run directory records the job ID, and the MLflow run is named after it.
- Nothing a job does with tracking can fail or slow the run, apart from writing its own files.
- The rebuild script is the same importer pointed at a fresh store, so it gets exercised every time `iris-compare` runs.
