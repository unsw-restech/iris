# Experiment trackers that need no always-on server

Research for [issue #9](https://github.com/PatrickTung/iris/issues/9), map [issue #1](https://github.com/PatrickTung/iris/issues/1). All sources retrieved 2026-10-13.

This is a findings note, not a decision. It lives on the throwaway branch `research/experiment-trackers` and is never merged.

## How to read this

Each claim carries one of three marks:

- **[V]** verified today against the cited primary source (vendor docs, or the project's own source code on GitHub).
- **[I]** inference: follows from verified facts but no source states it directly.
- **[U]** could not be confirmed from a public source. Treat as unknown.

Web pages were read through a fetch tool that summarises and quotes; quoted strings are as the tool returned them. Source code facts were read directly with `gh api`.

## Short answer

All four trackers can log from a PBS job with no outbound internet, because all four write to local files first. They differ in what happens next.

- **MLflow, TensorBoard and Aim** are file-based end to end: the job writes to a directory on Katana, and a UI started on demand reads that directory. Each has a `mlflow server` / `tensorboard` / `aim up` process that only needs to exist while someone is looking. Published Open OnDemand interactive apps exist for MLflow and TensorBoard (OSC maintains both). None was found for Aim.
- **Weights & Biases** logs offline to a local directory, but comparison happens only in the hosted web app after `wandb sync` runs from a machine with internet. That adds a sync step and puts run metadata on a third-party service; no public UNSW position on that was found.
- **MLflow is the only one of the three file-based tools with a first-class dataset record** (`mlflow.data`: name, digest, source, schema, profile). Aim captures the most environment detail automatically. TensorBoard records neither.
- **The catch with MLflow:** its plain file store (`./mlruns`) is no longer a supported default. Since a change merged in April 2026 it raises an error unless `MLFLOW_ALLOW_FILE_STORE=true` is set; the supported serverless store is a SQLite file. SQLite's own documentation warns against concurrent writers on NFS, and several PBS jobs writing one shared database on Katana's network storage is exactly that case.

## Side by side

| | MLflow (SQLite or file store) | Weights & Biases | TensorBoard | Aim |
|---|---|---|---|---|
| Logs from a compute node with no internet | Yes, to a local SQLite file or directory [V] | Yes, `WANDB_MODE=offline` writes to `WANDB_DIR` [V]; must be synced later from a node with internet [V] | Yes, append-only `tfevents` files in a log directory [V] | Yes, to a local `.aim` repository [V] |
| Always-on server needed | No. `mlflow server` is started only to view [V] | No server of IRIS's own; relies on the vendor's hosted service [V] | No [V] | No for local logging [V]; `aim server` exists only for remote tracking [V] |
| Compare runs | Built-in UI [V]; detailed compare features not re-verified today [U] | Hosted workspace: run table sort and filter, parallel coordinates [V] | Scalars per run; HParams dashboard with table, parallel coordinates and scatter views [V] | Built-in UI with query, grouping and aggregation by parameter (project's own claim) [V] |
| UI as an Open OnDemand app | Yes, published: `OSC/bc_osc_mlflow` [V] | Not applicable, UI is the vendor's website | Yes, published: `OSC/bc_osc_tensorboard` and others [V] | No published app found [U]; `aim up --base-path` exists, so feasible [I] |
| Parameters and metrics | Yes [V] | Yes [V] | Metrics natively; parameters through the HParams plugin [V] | Yes [V] |
| Environment recorded automatically | Source name and type, user, git commit as tags [V]; optional system metrics (CPU, memory, GPU) with `psutil` [V]. No package list or module list unless logged as an artifact [I] | System metrics and stdout/stderr [V]; git commit and `requirements.txt` with code saving [V] | Nothing [I] | Opt-in `log_system_params=True`: installed packages, environment variables, executables, CLI arguments, git info [V]; system usage and terminal logs on by default [V] |
| Input dataset recorded | First-class: `mlflow.log_input` with name, digest, source, schema, profile [V] | Reference artifacts: `add_reference("file:///path")` records sizes and MD5 checksums, files stay put [V]; behaviour in offline mode not confirmed [U] | No concept [I] | No dataset concept in the docs [V]; would be a plain parameter such as a path and checksum [I] |
| Per researcher or shared in a lab | Whatever the file permissions on the store allow [I]; concurrent writers to one SQLite file on network storage are risky [V, SQLite docs] | Hosted teams and projects; academic plan lists up to 100 seats [V] | Whatever the file permissions on the log directory allow [I] | Whatever the file permissions on the repo allow [I] |
| On Katana as a module | No `mlflow` module [V, local module list] | No `wandb` module [V] | No `tensorboard` module; `tensorflow/2.11.0` exists and normally bundles it [V module exists, I bundling] | No `aim` module [V] |
| Project health | v3.17.0 released 2026-10-07 [V] | SDK v0.30.0 released 2026-09-09 [V] | 2.21.0 released 2026-06-29 [V] | Latest release v3.29.1 on 2025-05-08, about 17 months old; repo still receives pushes [V] |

## MLflow

### Logging with no server

- The MLflow client can write straight to a local store; a tracking server is optional. The tracking docs describe the localhost setup as "the simplest way to get started with MLflow Tracking, without setting up any external server, database, and storage." [V] https://mlflow.org/docs/latest/ml/tracking/
- A local SQLite database is selected with the `MLFLOW_TRACKING_URI` environment variable, for example `sqlite:///mlruns.db`. [V] https://mlflow.org/docs/latest/ml/tracking/tutorials/local-database/
- The UI is started against it on demand: `mlflow server --port 8080 --backend-store-uri sqlite:///mlruns.db`. [V] same page.

### Status of the file store: this changed, and the docs disagree with each other

- "SQLite is the default backend store. When you start MLflow without specifying a backend, it automatically creates and uses `sqlite:///mlflow.db`". [V] https://mlflow.org/docs/latest/self-hosting/architecture/backend-store/
- The same page says the file system backend is in "maintenance mode and will not receive further updates." [V]
- The default changed in MLflow 3.7.0 (released 2025-12-05): "[Tracking] SQLite is now the default backend for the MLflow Tracking server." [V] https://github.com/mlflow/mlflow/releases/tag/v3.7.0
- The main tracking page still says "By default, without any particular server/database configuration, MLflow Tracking logs data to the local `mlruns` directory." That page is stale relative to the two sources above. [V that the page says it] https://mlflow.org/docs/latest/ml/tracking/
- **The file store now raises an error by default.** In the v3.17.0 source, `FileStore.__init__` raises `MlflowException` unless `MLFLOW_ALLOW_FILE_STORE` is true. The message reads: "The filesystem tracking backend (e.g., './mlruns') is in maintenance mode and will not receive further updates. Please migrate to a database backend (e.g., 'sqlite:///mlflow.db') ... If the filesystem backend is required for your workflow, set `MLFLOW_ALLOW_FILE_STORE=true` to opt out of this exception." [V] https://github.com/mlflow/mlflow/blob/v3.17.0/mlflow/store/tracking/file_store.py and https://github.com/mlflow/mlflow/blob/v3.17.0/mlflow/environment_variables.py
- That behaviour came from PR #22773, "Raise error for filesystem backends with opt-out env var", merged 2026-04-25, whose release note says users can set the variable "to opt out temporarily". [V] https://github.com/mlflow/mlflow/pull/22773
- Which release first shipped it was not confirmed; by date it is most likely 3.12.0 (2026-05-05). [I]
- The client keeps using an existing `./mlruns` if it already holds experiment data, otherwise it defaults to SQLite. [V] `_get_default_tracking_uri` in https://github.com/mlflow/mlflow/blob/v3.17.0/mlflow/tracking/_tracking_service/utils.py. Whether that path still trips the error without the opt-out variable was not tested. [U]
- A migration tool exists: `mlflow migrate-filestore --source /path/to/mlruns --target sqlite:///path/to/mlflow.db`, requiring MLflow 3.10 or later, SQLite targets only. [V] https://mlflow.org/docs/latest/self-hosting/migrate-from-file-store/
- The file store does still implement dataset logging (`log_inputs`). Things it explicitly does not support are trace-related (linking traces to runs, prompts to traces, trace metrics), which IRIS does not need. [V] file_store.py at v3.17.0.

Consequence for IRIS: "MLflow with a file store" as the ticket phrases it is on a deprecation path. The word "temporarily" in the release note means the opt-out should not be designed around. The supported no-server option is MLflow with a SQLite file. [I]

### SQLite on shared HPC storage

- SQLite's FAQ: "Multiple processes can have the same database open at the same time ... But only one process can be making changes to the database at any moment in time". And: "this locking mechanism might not work correctly if the database file is kept on an NFS filesystem ... You should avoid putting SQLite database files on NFS if multiple processes might try to access the file at the same time." [V] https://www.sqlite.org/faq.html
- So one SQLite file per researcher, written by one job at a time, is low risk; one lab-wide file written by many concurrent PBS jobs on network storage is the case SQLite warns about. [I]
- What filesystem backs Katana home and `/srv/scratch`, and whether its locking is reliable, is not in the public docs read today. [U]
- Workarounds that avoid concurrent writers, none verified on Katana: one database per researcher; each job writes its own small database or file store and a later single-writer step merges; or jobs write to node-local disk and copy at the end. MLflow has no documented "merge two SQLite stores" command that was found today. [I, U]

### Comparing runs, and the UI as an Open OnDemand app

- `mlflow server` options include `--backend-store-uri` ("SQLAlchemy-compatible database connection strings (e.g. 'sqlite:///path/to/file.db') or local filesystem URIs"), `--host`, `--port` (default 5000), `--workers` (default 4), `--static-prefix` ("a prefix which will be prepended to the path of all static paths"), `--allowed-hosts` and `--cors-allowed-origins`. [V] https://mlflow.org/docs/latest/api_reference/cli.html
- OSC publishes a production Batch Connect app for exactly this: `OSC/bc_osc_mlflow`, "Batch Connect - OSC MLflow tracking UI", last pushed 2026-06-11. [V] https://github.com/OSC/bc_osc_mlflow
- Its whole launch script is, in effect: change to the directory the user picked on the form ("Tracking URI directory"), load a module that contains MLflow, then
  ```
  export MLFLOW_STATIC_PREFIX=/node/${host}/${port}
  mlflow server -h 0.0.0.0 -p ${port} --allowed-hosts ${HOSTNAME}.ten.osc.edu:*
  ```
  and the connect button links to `/node/<host>/<port>`. [V] https://github.com/OSC/bc_osc_mlflow/blob/master/template/script.sh.erb and `view.html.erb` in the same repo.
- Open OnDemand's `node_uri` proxies "using the **full** URI path", while `rnode_uri` strips the routing prefix. MLflow is served under `/node/` with a static prefix, which is why OSC sets `MLFLOW_STATIC_PREFIX`. [V] https://osc.github.io/ood-documentation/latest/reference/files/ood-portal-yml.html
- Interactive apps need the OnDemand reverse proxy enabled, with a host allowlist regex. [V] https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/setup/enable-reverse-proxy.html. Katana OnDemand already offers JupyterLab and RStudio, which use the same mechanism, so it is presumably enabled. [V apps exist: https://docs.restech.unsw.edu.au/using_katana/ondemand/ ; I that the proxy config suits MLflow]
- **Access control is a real gap.** OSC's MLflow app starts the server on `0.0.0.0` with no authentication step in the script. Another site that runs MLflow under Open OnDemand states it outright: "This implementation of MLflow does not come with authentication. Other Deucalion users can look at your MLflow dashboard." [V] https://docs.deucalion.macc.fccn.pt/openondemand/. By contrast OSC's TensorBoard app wraps the UI in an authenticating proxy inside a private network namespace (see below). Whether another Katana user can reach a port on a compute node directly is not public. [U]
- The detailed compare view (selecting runs, parallel coordinates, charts) was not found on the pages fetched today, so it is not re-verified here even though it is a long-standing feature. [U]

### Environment and dataset

- Automatic system tags: `mlflow.source.name`, `mlflow.source.type`, `mlflow.user`, and `mlflow.source.git.commit` "when running from a repository". [V] https://mlflow.org/docs/latest/ml/tracking/tracking-api/
- System metrics are opt-in (`MLFLOW_ENABLE_SYSTEM_METRICS_LOGGING=true`, `mlflow.enable_system_metrics_logging()`, or `log_system_metrics` on `start_run`), need `psutil`, and `nvidia-ml-py` for GPU. They cover CPU, memory, GPU utilisation and memory, network and disk. [V] https://mlflow.org/docs/latest/ml/tracking/system-metrics/
- Nothing on the pages read records the loaded environment modules, the Python package list or a container image for a plain tracking run. For IRIS that would be an explicit step: log the module name as a parameter or tag and attach `module list` / `pip freeze` output with `mlflow.log_artifact`. [I]
- Datasets: `mlflow.data` records a `Dataset` with "name, digest (hash) schema, profile, and source", attached to a run by `mlflow.log_input()`. Constructors include `mlflow.data.from_numpy(features, source=None, targets=None, name=None, digest=None)` and `from_pandas(...)`. [V] https://mlflow.org/docs/latest/api_reference/python_api/mlflow.data.html and https://mlflow.org/docs/latest/ml/dataset/
- Supported dataset classes: Pandas, Spark, NumPy, Polars, Hugging Face, TensorFlow, and `MetaDataset`, described as a "metadata-only dataset (no actual data stored)". [V] https://mlflow.org/docs/latest/ml/dataset/
- There is no netCDF or xarray dataset class in that list. A microCT `.nc` volume would go through `from_numpy` (which needs the array in memory to compute a digest unless `digest=` is passed) or `MetaDataset` with a path as the source. Which is cheaper for multi-gigabyte volumes was not tested. [I]
- The docs do not state in so many words that only metadata, not the data, is stored for the non-Meta classes. That is the commonly understood behaviour but is unconfirmed from today's reading. [U]

## Weights & Biases

Note on naming: `docs.wandb.ai` now redirects to `docs.coreweave.com`, and `wandb.ai/site/pricing` redirects to `coreweave.com/forge-pricing`, where the hosted product is presented as "CoreWeave Forge". The documentation body still says "Weights & Biases" and "W&B", and the Python package is still `wandb`. [V redirects and wording; the exact scope of the rename is U]

### Offline logging and sync

- `WANDB_MODE`: "If you set this to "offline" wandb will save your run metadata locally and not sync to the server." [V] https://docs.coreweave.com/guides/track/environment-variables/
- `wandb.init(mode=...)`: "`"offline"`: Suitable for air-gapped or offline environments; data is saved locally and can be synced later." [V] https://docs.coreweave.com/ref/python/functions/init/
- `WANDB_DIR`: "Where to store all generated files. If unset, defaults to the `wandb` directory relative to your training script." [V] environment variables page.
- `wandb sync`: "Upload existing local W&B run data to the cloud. Sync offline or incomplete runs to the W&B server." It takes run directories of the form `./wandb/run-YYYYMMDD_HHMMSS-RUN_ID`. [V] https://docs.coreweave.com/ref/cli/wandb-sync/
- Sync needs credentials: `WANDB_API_KEY` "must be set if `wandb login` hasn't been run on the remote machine." [V] environment variables page.
- The dedicated "run wandb offline" support page is behind an access-code prompt and could not be read. [U] https://docs.coreweave.com/support/run_wandb_offline/
- Consequence for IRIS: the sync has to run somewhere with outbound internet (a login node, or a compute node if those turn out to have it) and with the researcher's API key. Doing that without a terminal step means either the PBS script syncs at the end, which only works if compute nodes reach the internet, or something else runs it. Either way each researcher must create a W&B account and store an API key on Katana once. [I]

### Comparing, environment, dataset

- Comparison is in the hosted workspace: runs can be sorted and filtered by summary metrics, and parallel coordinates charts "summarize the relationship between large numbers of hyperparameters and model metrics at a glance." [V] https://docs.coreweave.com/guides/track/log/ and https://docs.coreweave.com/guides/app/features/panels/parallel-coordinates/
- Logged automatically: "System metrics: CPU and GPU utilization, network, etc." and "Command line: The stdout and stderr are picked up and show in the logs tab." With code saving: "Git commit" and "Dependencies: The requirements.txt file will be uploaded." [V] https://docs.coreweave.com/guides/track/log/
- Datasets by reference: "The reference artifacts only consists of metadata about the files, such as their sizes and MD5 checksums. The files themselves never leave your system." Local or mounted paths use `file:///path/to/dataset/`. Default limit of 10,000 objects per prefix, adjustable with `max_objects=`. [V] https://docs.coreweave.com/guides/artifacts/track-external-files/
- Whether reference artifacts are computed and queued correctly in offline mode was not confirmed. [U]
- Checksumming a large `.nc` file takes a full read of the file. [I]

### Licensing and data residency

- Marketing page: "Free for students, educators, and academic researchers. Always." [V] https://wandb.ai/site/research/
- Pricing page, academic plan: for "Students, professors and postdoctoral researchers at academic institutions pursuing research unrelated to a for-profit entity", with an academic email, by application; up to 100 seats and 200 GB cloud storage. The free personal tier lists 5 GB storage. [V] https://coreweave.com/forge-pricing
- Deployment options are a multi-tenant hosted service, a dedicated cloud, and self-managed W&B Server. [V] https://docs.coreweave.com/guides/hosting/. Self-managed is an always-on server and so is out under the map's constraints. [I]
- Where the multi-tenant service stores data (provider, region, country) is not stated on the public pages that could be read; the hosting detail page is behind an access-code prompt. A bring-your-own-bucket option exists at team level. [U for region; V for BYOB] https://docs.coreweave.com/guides/hosting/data-security/
- It should be assumed that data on the default hosted tier leaves Australia until shown otherwise. [I]

### UNSW position

- No public UNSW or ResTech page mentioning Weights & Biases, wandb, MLflow or TensorBoard was found. The Katana docs' Machine Learning and AI section covers Stable Diffusion and Ollama only. [V that nothing was found on https://docs.restech.unsw.edu.au/ ; absence elsewhere is U]
- Katana's own docs state: "Katana is NOT suitable for sensitive or highly sensitive data", and point to the Research Data Management Hub for classification. [V] https://docs.restech.unsw.edu.au/
- UNSW's Data Classification Standard makes data owners responsible for keeping data in systems classified at the same or a higher level than the data. This came from a search-result summary of the standard, not a direct read of the current version. [U] archive copy: https://unsw.edu.au/content/dam/pdfs/governance/policy/archive/datastandard2.1.pdf
- UNSW's "Data Storage and Tools" page, which lists approved platforms per classification, now redirects to a UNSW SharePoint site that needs a login. [V redirect; contents U] https://research.unsw.edu.au/node/132453
- Whether UNSW holds a W&B licence or has assessed it is therefore an open question for Patrick, not something to guess.

## TensorBoard

- Logging is file-only: "The data is written to an append-only record dump that will have "tfevents" in the filename." [V] https://github.com/tensorflow/tensorboard/blob/master/README.md
- Runs are subdirectories: TensorBoard "recursively walks the directory tree rooted at `logdir` looking for subdirectories that contain tfevents data. Every time it encounters such a subdirectory, it loads it as a new `run`." [V] same README.
- "In TensorBoard 2.0 and up, `--host localhost` is the default. Use `--bind_all` to restore the old behavior". [V] same README.
- Hyperparameters need the HParams plugin (`hp.hparams(hparams)` per run). Its dashboard has a Table View that "lists the runs, their hyperparameters, and their metrics", a Parallel Coordinates View and a Scatter Plot View. [V] https://www.tensorflow.org/tensorboard/hyperparameter_tuning_with_hparams
- Open OnDemand: `OSC/bc_osc_tensorboard` ("Batch Connect TensorBoard", pushed 2026-05-08) is one of at least five public TensorBoard apps (also `c3se/bc_tensorboard`, `FrancisCrickInstitute/bc_tensorboard`, `mcw-rcc/bc_rcc_tensorboard`, `unlhcc/bc-hcc-tensorboard`). [V] https://github.com/OSC/bc_osc_tensorboard
- OSC's form asks only for a log directory, hours and project. Its script runs TensorBoard inside `unshare -nr` with `slirp4netns` and an `authrevproxy.py` in front, connected through `/rnode/<host>/<port>/` with a password cookie, "so that only the proxy (on port 80) is accessable". That is OSC's answer to TensorBoard having no authentication of its own, and it is noticeably more machinery than their MLflow app. [V] https://github.com/OSC/bc_osc_tensorboard/blob/master/template/script.sh.erb , `template/bin/tensorboard.sh`, `view.html.erb`
- Environment and dataset: no concept of either in the pages read. They could be written as text summaries or hparams, by hand. [I]
- Sharing: a log directory is a directory. Because each run writes its own files, concurrent jobs do not contend on a shared file the way a SQLite store does. [I]
- TensorBoard works without TensorFlow for PyTorch users through `torch.utils.tensorboard`; not verified today. [U]

## Aim

- "Aim repository is the space where all your training runs are logged"; `aim init` creates a `.aim` directory. Tracking starts by creating an `aim.Run`. [V] https://aimstack.readthedocs.io/en/latest/quick_start/setup.html
- The project describes itself as a "self-hosted, free and open-source experiment tracking tool". [V] https://github.com/aimhubio/aim
- UI on demand: `aim up`, with `--host`, `--port` (default 43800), `--repo`, `--workers`, `--base-path` and `--read-only`. [V] https://aimstack.readthedocs.io/en/latest/refs/cli.html and https://github.com/aimhubio/aim/blob/main/aim/cli/up/commands.py
- `aim server` (default port 53800) is a separate remote-tracking server for multi-host logging; it is not needed when jobs write to a repo on a shared filesystem. [V] https://aimstack.readthedocs.io/en/latest/using/remote_tracking.html
- Environment capture is the strongest of the four: `log_system_params` enables "logging of system params such as installed packages, git info, environment variables, etc.", covering environment variables, executables, CLI arguments, installed packages with versions and git information. It is off by default. System usage tracking and terminal log capture are on by default. [V] https://aimstack.readthedocs.io/en/latest/using/configure_runs.html
- Capturing all environment variables may sweep up secrets such as API keys. [I]
- Artifacts: `run.set_artifacts_uri('file:///...')` then `run.log_artifact(...)`. No dataset-tracking concept appears in the docs. [V] https://aimstack.readthedocs.io/en/latest/using/artifacts.html
- Comparison: the README claims parameter-based search, grouping and aggregation that TensorBoard and MLflow lack. That is the project's own comparison. [V that it says so]
- Open OnDemand: no published Aim app was found in GitHub repository searches. `--base-path` suggests it could sit behind `/node/`, untested. [U, I]
- Maintenance: the latest release is v3.29.1 from 2025-05-08, with repository pushes as recent as 2026-10-13. A 17-month gap between releases is a risk signal for a tool IRIS would depend on. [V dates from the GitHub API; I the risk]
- Whether several jobs can safely write to one Aim repository at once on network storage was not checked. [U]

## Katana facts that bear on the choice

- No `mlflow`, `wandb`, `tensorboard` or `aim` module is in the local list of installed modules (`available-modules.md`, kept outside the repo). `tensorflow/2.11.0`, `pytorch/1.13.1`, `python/3.10.8` (default), `python/3.11.3`, `python/3.13.2` and `sqlite/3.39.4` are. [V against that file]
- So any tracker except possibly TensorBoard means a pip install into a virtual environment or a shared IRIS environment, prepared on a login node. This interacts with the environments ticket. [I]
- Katana OnDemand is at `https://kod.restech.unsw.edu.au` and offers a virtual desktop, JupyterLab, RStudio and a terminal. [V] https://docs.restech.unsw.edu.au/using_katana/ondemand/
- Whether compute nodes have outbound internet is not stated in the pages read. A search-result snippet attributed to the Katana docs says the login nodes and the Katana Data Mover "have no network restrictions in place", which implies compute nodes do; the sentence was not found on the FAQ page when fetched directly. `AGENTS.md` already treats compute nodes as having no outbound internet. [U]

## What this means for IRIS

These are inferences for the decision ticket, not decisions.

1. **Three options satisfy "no always-on server" outright**: MLflow on SQLite, TensorBoard, Aim. W&B satisfies the letter of the constraint (external hosted services are allowed) but adds an account, an API key, a sync step and an unanswered data-governance question.
2. **Only MLflow covers all three of the map's needs natively**: comparison, a dataset record, and some environment record, plus a published Open OnDemand app to copy. It costs a pip-installed dependency and a decision about where the SQLite file lives.
3. **TensorBoard is the fewest moving parts** if a TensorFlow or PyTorch module already provides it, and its one-directory-per-run layout has no shared-writer problem. It has no dataset or environment record and weaker parameter comparison, so IRIS would be writing those conventions itself.
4. **Aim fits technically** and captures the environment best, but has the weakest maintenance signal and no Open OnDemand precedent.
5. **The store layout drives the sharing answer more than the tool does.** Per-researcher stores are simple and safe for every file-based option. A lab-shared store is a matter of directory permissions for TensorBoard, but for MLflow on SQLite it runs into the concurrent-writer warning.
6. **A UI app with no authentication is a design point, not a detail.** OSC's two apps show both ends: a three-line MLflow launcher with no auth, and a TensorBoard launcher with a network namespace and an authenticating proxy.

## Open questions for Patrick

1. Does UNSW hold a Weights & Biases licence, or has UNSW IT or ResTech assessed W&B (now under CoreWeave) for research data? Nothing public was found.
2. What classification do microCT run metadata, parameters and dataset paths carry, and may they be stored on a hosted service outside Australia?
3. Do Katana compute nodes have outbound internet? This decides whether a job could `wandb sync` itself, and is assumed "no" in `AGENTS.md`.
4. What filesystem backs Katana home and `/srv/scratch`, and is file locking reliable there? This decides whether a shared MLflow SQLite store is safe.
5. Can one Katana user reach a port opened by another user's job on a compute node? This decides how much protection a tracking UI app needs.
6. Should the tracking store be per researcher, or shared within a lab? The findings favour per researcher for simplicity; sharing is a product decision.
7. Is a pip-installed tracker in a shared IRIS environment acceptable, or must tracking work with existing modules only (which leaves TensorBoard)?
8. Is depending on MLflow's `MLFLOW_ALLOW_FILE_STORE=true` opt-out acceptable for v1, given upstream calls it temporary? The findings suggest not.

## Not checked

- No tracker was installed or run; nothing here was tested on Katana.
- MLflow's compare view, W&B's offline support page and W&B's hosting region could not be read today (not on the fetched pages, or behind an access-code prompt).
- `tensorboard --path_prefix`, `torch.utils.tensorboard`, and concurrent-writer behaviour of Aim and of MLflow's file store were not verified.
- Other trackers (for example ClearML, Neptune, Comet, DVC experiments, Sacred) were out of the ticket's scope and not examined.
