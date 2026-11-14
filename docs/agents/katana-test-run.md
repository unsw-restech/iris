# Real-run acceptance on Katana

How to meet a ticket's "a real run shows…" criterion for `microct-2d-segmentation`. A spec's final real-run ticket runs from `/pun/sys/` ([below](#the-final-real-run-ticket)). So does a build ticket whose box names `/pun/sys/`: it follows those steps, its own review and push standing in for the integration branch's. Any other build ticket that needs its own real run follows steps 1–5: the committed code on the sample dataset, from a scratch copy, into a throwaway run index and tracking store, leaving your dev clone, run index and `tracking.db` untouched. A box that names `/pun/dev/OpenComposer-iris-test` runs from the test instance ([below](#a-test-instance-run)).

Name every `qsub` and its resources in chat as you submit it. Delete nothing without the IRIS maintainer's go-ahead naming the target.

## The final real-run ticket

It runs from `/pun/sys/`, since the pilot's only users are testers (Patrick, 2026-10-28), in a session with the IRIS maintainer:

1. The IRIS maintainer says the review of the integration branch is done.
2. Push the branch to `main` with the IRIS maintainer's push go-ahead (AGENTS.md, Deploying), then pull the dev clone.
3. Run `bin/syspull` and get its own go-ahead, quoting verbatim every commit it lists, before `--apply`. The push's go-ahead covers it when it named the system clone and quoted those commits (AGENTS.md, Deploying).
4. The IRIS maintainer reloads the form page, since a page loaded before `--apply` renders from the old commit (#147, job 9736586), then submits the runs from `https://kod.restech.unsw.edu.au/pun/sys/OpenComposer/<slug>` and gives you the job IDs: a session can't sign in to Katana OnDemand. A script rendered with `form_helper.rb` and sent with `qsub` runs the same code but skips OpenComposer's rendering, so it doesn't meet the box (job 9762182, #173). The runs land in the IRIS maintainer's own run index and store, not a throwaway home, so ask before removing any of them. Check each run as soon as its run directory has them, not when it ends: `commit.txt` names the deployed commit, with no `lib_commit.txt` beside it and no "the IRIS clone moved from commit" warning in the log, and `params.json`'s `device` is `cuda` for a GPU run and `cpu` for a CPU-only one. Job 9736586 trained on the CPU for 94 minutes before anyone looked. A run with `lib_commit.txt` or that warning came from a page loaded before the deploy: it ran the old form and entry script on the new library, so it doesn't test the deploy and doesn't count. Reload the page and submit it again.
5. Inspect with `inspect.pbs`: make `/srv/scratch/$USER/iris-test-<ticket>/`, copy the helper in from the system clone's `lib/tests/katana/`, and submit it from there with `CLONE` naming the system clone and `JOBS` naming the runs. It imports into Patrick's own tracking store, as `iris-compare` would, so the first import counts whatever is new and the second must import nothing. It must finish before Patrick opens `iris-compare`: both write `tracking.db`. Report as in [5. Report, then clean up](#5-report-then-clean-up), citing each job ID.

## A test-instance run

The test instance serves the IRIS maintainer's dev clone, `~/iris`, and runs as them (ADR-0012), so push and pull the dev clone first if the run needs new code:

1. Check it's linked: `ssh katana 'ls -l ~/ondemand/dev/'` lists `OpenComposer-iris-test`. If it doesn't, `ssh katana 'ln -s /srv/scratch/katana_ai/iris/OpenComposer-iris-test ~/ondemand/dev/'`; an existing `~/ondemand/dev` needs no web server restart (#174).
2. The IRIS maintainer submits from `https://kod.restech.unsw.edu.au/pun/dev/OpenComposer-iris-test/<slug>` and gives you the job ID. Its navbar reads "IRIS test instance", the IRIS instance's "IRIS".
3. Check the run came from the dev clone: the test instance's history holds the job, with `CODE` under `/home/<zID>/iris/workflows/`, and `commit.txt` is the dev clone's `HEAD`. Each instance's history is its own SQLite file, `~/composer/iris` and `~/composer/iris-test`, and Katana has no `sqlite3` command, so list each file's job IDs with Python:

   ```
   ssh katana 'for d in iris iris-test; do echo "$d:"; python3 -c "import sqlite3,sys; print(*[r[0] for r in sqlite3.connect(\"file:\"+sys.argv[1]+\"?mode=ro\",uri=True).execute(\"select _job_id from jobs\")])" ~/composer/$d/pbspro.sqlite3; done'
   ```

   `payload_json` holds the rendered script.

To see what an author with no clone gets, move `~/iris/workflows` aside, with the IRIS maintainer's go-ahead naming it, only once no job of theirs reads it, and move it back as soon as they've reloaded the pages. A Develop app runs in development mode, so its error page names the exception, which the fork's `misc/tests/serve`, in production mode, doesn't (#174).

## 1. Copy the committed tree to scratch

Commit first: the run records `git rev-parse HEAD` of the copy, so the copy is a clone of a bundle of `HEAD`, carried by the data mover. A bundle works from a worktree too, where `.git` is only a pointer back to the main clone. `rsync` there won't create a missing parent, so make the folder first:

```
git -C <clone or worktree> bundle create /tmp/iris-test-<n>.bundle HEAD
ssh katana 'mkdir /srv/scratch/$USER/iris-test-<n>'
rsync /tmp/iris-test-<n>.bundle katana-dm:/srv/scratch/z3224749/iris-test-<n>/
ssh katana 'cd /srv/scratch/$USER/iris-test-<n> && git clone -q iris-test-<n>.bundle iris'
```

If `mkdir` finds the folder already there, an earlier session started this ticket. Read its `.pbs` files and job logs before you submit anything.

## 2. Render the job script from the form

`lib/tests/form_helper.rb` renders a `form.yml.erb`, served from the clone holding it, as the fork commit the dev install and both instances run does (its header names the commit and what it leaves out), runs `check:` and prints the script. Fields are the form's keys. `time` is two numbers, `time_1` hours and `time_2` minutes. Unset fields take the form's defaults.

```
ssh katana 'cd /srv/scratch/$USER/iris-test-<n> && module load ruby/3.2.0 && \
  ruby iris/lib/tests/form_helper.rb \
    /srv/scratch/$USER/iris-test-<n>/iris/workflows/microct-2d-segmentation/form.yml.erb \
    dataset=/srv/scratch/z3224749/datasets/iris-microct-sample \
    experiment=iris-test-<n> epochs=5 time_1=1 time_2=0 > run.pbs'
```

The sample dataset is `/srv/scratch/z3224749/datasets/iris-microct-sample`: 32 netCDF blocks, 16 GB, a 1280 x 2520 x 2520 volume read as `uint16` with voxel spacing 0.008667522 mm, and 10 training pairs over 3 classes. Inference reads the whole volume whatever the epoch count, so 5 epochs is enough unless the ticket is about training.

## 3. Submit with a throwaway IRIS home

`IRIS_HOME` replaces `/srv/scratch/$USER/iris`, which holds the run index and the store:

```
ssh katana 'cd /srv/scratch/$USER/iris-test-<n> && qsub -m abe -v IRIS_HOME=/srv/scratch/$USER/iris-test-<n>/home,PYTHONUNBUFFERED=1 run.pbs'
```

`PYTHONUNBUFFERED=1` goes in every job you submit, this one and the helper jobs you write: Python block-buffers output to a file, so a job that is killed or stalls leaves an empty log (job 9553213). Write a helper job on the desktop with a quoted heredoc, then send it with `ssh katana 'cat > <path>' < <file>`. A heredoc inside `ssh katana '...'` ends at the first apostrophe in its text, and the rest runs on the desktop (#133's GPU probe).

The form's `#PBS -o` is a folder, so the log is `<dataset>/runs/<job number>.kman.restech.unsw.edu.au.OU`, not `<job name>.o<number>`. The run directory is `<dataset>/runs/<job number>/`.

Wait with `bin/qwait <job id>…` from the desktop, run in the background. When each job finishes, it prints `Exit_status`, the real log path and the log's last lines. It exits 2 at once if a job can't be queried.

Timing on a V100 for the sample at the form's defaults (job 9577519, 50 epochs): 16 min in all, about 6 s per epoch of training and about 605 s of inference, split by the run directory's file times. Logs now print the two as "Set up and trained ... in N s" and "Wrote labels.tif ... in N s"; in older logs, 9577519's included, the "Wrote" line counts both. Before #31 read one slice per chunk, 5 epochs and inference took 1370 s (job 9551129), nearly all of it inference. Both fit the form's 2 h default.

## 4. Import and inspect

A second job runs `bin/iris-import` twice against the same `IRIS_HOME`, expecting `Imported 1`, then `Imported 0`. It then prints what the ticket asks about, through `MlflowClient(store_uri(Path(IRIS_HOME)))` in the researcher tools' container, `apptainer exec --cleanenv` on `<IRIS_ENVS_FOLDER>/<IRIS_TOOLS_ENV_VERSION>.sif` from `lib/katana.sh`, as `inspect.pbs` does. Read `tracking.db` directly with that container's Python too: Katana's system `python3` has SQLite 3.26.0 (found in #46's real run, 2026-10-21, commit 634aac5), which can't parse the `spans` table's generated column (it needs 3.31) and fails with "malformed database schema (spans)". 1 CPU, 4 GB and 15 min are plenty: the #36 import took 45 s.

Committed helper jobs live in `lib/tests/katana/`, beside the shared library's tests in `lib/tests/`, since they test the library, the module and the environment rather than one workflow; a workflow's own `tests/` holds only its entry script's synthetic run and its form tests. Each job's header gives its `qsub` line. Copy them into the test folder and submit from there. Each takes the environments folder, the researcher tools' version and the Python module from a clone's `lib/katana.sh`: `T/iris`'s for the jobs given `T`, `CLONE`'s for `canary.pbs` and `inspect.pbs`. `canary.pbs`, `compare.pbs` and `inspect.pbs` run their Python in the researcher tools' container; `job_lib.pbs` runs jobs in the stand-in container (`stand-in.sh`). They are `canary.pbs`, `job_lib.pbs` (`test_job_lib`, which needs Katana's modules; `bin/katana-test` submits it too, so submit it by hand only beside a real run), `compare.pbs` (`iris-compare` end to end, against a run-index pointer, by default the fixture's), `inspect.pbs` (a final real-run ticket's import into Patrick's own store, then each run's tags and artifacts) and `viewers.pbs` (the guide's Fiji and ParaView steps, headless, on a run directory, by default the fixture's).

### Before a Virtual Desktop session

Submit `viewers.pbs` first, and fix the guide wherever it fails. It runs the guide's readers and properties without a window: Bio-Formats on `labels.tif`, the range import and crop, then ParaView's TIFF Series Reader with custom spacing and a contour. A desktop session then tests only what a script can't: menu labels, speed and how it looks.

### The fixture run

`/srv/scratch/z3224749/iris-fixtures/` keeps one finished run with a `run.json`, so a check that needs one doesn't spend a training run first. It is job 9573671, a 5-epoch run of the form on the sample dataset:

- `microct-sample/` is the dataset the form was given. Its `volume` and `train` are links to the sample's, and the run is in its `runs/9573671/`, with the `.OU` log beside it.
- `home/` was the run's `IRIS_HOME`, so its pointer is `home/run-index/9573671`. Copy the pointer into your own test home, as `compare.pbs` does. Don't import into `home/` or write in the fixture.

Its run record is format 1, which the shared tools keep reading (`lib/iris/runs.py`), so a new format leaves it usable; a check of what a newer format records needs a new fixture. It breaks if the sample dataset moves, since its links point there. To make a new one, in a fresh `iris-fixtures/`, make `microct-sample/` with its `runs/` folder and links named `volume` and `train` to the sample's. Render as in step 2 with `dataset=/srv/scratch/z3224749/iris-fixtures/microct-sample`, and submit as in step 3 with `IRIS_HOME=/srv/scratch/z3224749/iris-fixtures/home`. Then update the job number here and in `compare.pbs` and `viewers.pbs`.

## 5. Report, then clean up

Post results on the ticket in the shape of #35's and #36's closing comments: what landed, each acceptance box with its job IDs and evidence, the submissions with their resources, and what is known but not fixed. Then ask Patrick before removing `/srv/scratch/$USER/iris-test-<n>/` and the run's folder and `.OU` log in the sample's `runs/`. The fixture, `/srv/scratch/z3224749/iris-fixtures/`, stays: it is not part of any ticket's cleanup.

## When a job hangs or dies

Before resubmitting, submit a **canary**, `lib/tests/katana/canary.pbs`, which times `import mlflow` in an environment's container: `qsub -m abe -v CLONE=<clone>,PYTHONUNBUFFERED=1 canary.pbs`, where `CLONE` is the clone whose `lib/katana.sh` names the environments folder, the system clone or a test folder's `T/iris`. It uses the researcher tools' version; add `VERSION=<env>/<n>` for the one the hung job's form pins. If the canary hangs too, compute nodes can't read the environments folder: stop submitting and tell Patrick, as it goes to ResTech, not into code. On 2026-10-19 from 14:39 this stalled four jobs on k192, k216 and k217 while the login node read the same venv files in milliseconds.

Whenever you stop with the ticket unfinished, comment on it first with each job's ID, node and outcome and the test folder's path, so the next session can pick up from there.

To trace a script, put `set -x` after its `module load`. `bash -x` over the whole script traces the module system too and floods the log with its environment.
