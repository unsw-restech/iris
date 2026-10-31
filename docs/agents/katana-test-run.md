# Real-run acceptance on Katana

How to meet a ticket's "a real run shows…" criterion for `microct-2d-segmentation`. A spec's final real-run ticket runs from `/pun/sys/` ([below](#the-final-real-run-ticket)). A build ticket that needs its own real run follows steps 1–5: the committed code on the sample dataset, from a scratch copy, into a throwaway run index and tracking store, leaving your dev clone, run index and `tracking.db` untouched.

Name every `qsub` and its resources in chat as you submit it. Delete nothing without Patrick's go-ahead naming the target.

## The final real-run ticket

It runs from `/pun/sys/`, since the pilot's only users are testers (Patrick, 2026-10-28), in a session with Patrick:

1. Patrick says the review of the integration branch is done.
2. Push the branch to `main` with Patrick's push go-ahead (AGENTS.md, Deploying), then pull the dev clone.
3. Run `bin/syspull` and get its own go-ahead, quoting the listing, before `--apply`.
4. Submit the runs from `https://kod.restech.unsw.edu.au/pun/sys/OpenComposer/<slug>`. They land in Patrick's own run index and store, not a throwaway home, so ask before removing any of them.
5. Inspect with `inspect.pbs`: make `/srv/scratch/$USER/iris-test-<ticket>/`, copy the helper in from the system clone's `lib/tests/katana/`, and submit it from there with `CLONE` naming the system clone and `JOBS` naming the runs. It imports into Patrick's own tracking store, as `iris-compare` would, so the first import counts whatever is new and the second must import nothing. It must finish before Patrick opens `iris-compare`: both write `tracking.db`. Report as in step 5, citing each job ID.

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

`lib/tests/form_helper.rb` renders a `form.yml.erb`, served from the clone holding it, as OpenComposer 1.9.0 does, runs `check:` and prints the script. Fields are the form's keys. `time` is two numbers, `time_1` hours and `time_2` minutes. Unset fields take the form's defaults.

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

`PYTHONUNBUFFERED=1` goes in every job you submit, this one and the helper jobs you write: Python block-buffers output to a file, so a job that is killed or stalls leaves an empty log (job 9553213).

The form's `#PBS -o` is a folder, so the log is `<dataset>/runs/<job number>.kman.restech.unsw.edu.au.OU`, not `<job name>.o<number>`. The run directory is `<dataset>/runs/<job number>/`.

Wait with `bin/qwait <job id>…` from the desktop, run in the background. When each job finishes, it prints `Exit_status`, the real log path and the log's last lines. It exits 2 at once if a job can't be queried.

Timing on a V100 for the sample at the form's defaults (job 9577519, 50 epochs): 16 min in all, about 6 s per epoch of training and about 605 s of inference, split by the run directory's file times. Logs now print the two as "Set up and trained ... in N s" and "Wrote labels.tif ... in N s"; in older logs, 9577519's included, the "Wrote" line counts both. Before #31 read one slice per chunk, 5 epochs and inference took 1370 s (job 9551129), nearly all of it inference. Both fit the form's 2 h default.

## 4. Import and inspect

A second job runs `bin/iris-import` twice against the same `IRIS_HOME`, expecting `Imported 1`, then `Imported 0`. It then prints what the ticket asks about, through `MlflowClient(store_uri(Path(IRIS_HOME)))` in the pinned environment `/srv/scratch/katana_ai/iris/envs/imaging/1`, after `module load python/3.13.2`. Read `tracking.db` directly with that Python too: Katana's system `python3` has SQLite 3.26.0, which can't parse the `spans` table's generated column (it needs 3.31; the environment has 3.39.4, checked 2026-10-21) and fails with "malformed database schema (spans)". 1 CPU, 4 GB and 15 min are plenty: the #36 import took 45 s.

Committed helper jobs live in `lib/tests/katana/`, beside the shared library's tests in `lib/tests/`, since they test the library, the module and the environment rather than one workflow; a workflow's own `tests/` holds only its entry script's synthetic run and its form tests. Each job's header gives its `qsub` line. Copy them into the test folder and submit from there. Each takes the environment and Python module from a clone's `lib/katana.sh`: `T/iris`'s for the jobs given `T`, `CLONE`'s for `canary.pbs` and `inspect.pbs`. They are `canary.pbs`, `job_lib.pbs` (`test_job_lib`, which needs Katana's modules; `bin/katana-test` submits it too, so submit it by hand only beside a real run), `compare.pbs` (`iris-compare` end to end, against a run-index pointer, by default the fixture's), `inspect.pbs` (a final real-run ticket's import into Patrick's own store, then each run's tags and artifacts) and `viewers.pbs` (the guide's Fiji and ParaView steps, headless, on a run directory, by default the fixture's).

### Before a Virtual Desktop session

Submit `viewers.pbs` first, and fix the guide wherever it fails. It runs the guide's readers and properties without a window: Bio-Formats on `labels.tif`, the range import and crop, then ParaView's TIFF Series Reader with custom spacing and a contour. A desktop session then tests only what a script can't: menu labels, speed and how it looks.

### The fixture run

`/srv/scratch/z3224749/iris-fixtures/` keeps one finished run with a `run.json`, so a check that needs one doesn't spend a training run first. It is job 9573671, a 5-epoch run of the form on the sample dataset:

- `microct-sample/` is the dataset the form was given. Its `volume` and `train` are links to the sample's, and the run is in its `runs/9573671/`, with the `.OU` log beside it.
- `home/` was the run's `IRIS_HOME`, so its pointer is `home/run-index/9573671`. Copy the pointer into your own test home, as `compare.pbs` does. Don't import into `home/` or write in the fixture.

The fixture goes stale if the run record's format changes, and breaks if the sample dataset moves, since its links point there. To make a new one, in a fresh `iris-fixtures/`, make `microct-sample/` with its `runs/` folder and links named `volume` and `train` to the sample's. Render as in step 2 with `dataset=/srv/scratch/z3224749/iris-fixtures/microct-sample`, and submit as in step 3 with `IRIS_HOME=/srv/scratch/z3224749/iris-fixtures/home`. Then update the job number here and in `compare.pbs` and `viewers.pbs`.

## 5. Report, then clean up

Post results on the ticket in the shape of #35's and #36's closing comments: what landed, each acceptance box with its job IDs and evidence, the submissions with their resources, and what is known but not fixed. Then ask Patrick before removing `/srv/scratch/$USER/iris-test-<n>/` and the run's folder and `.OU` log in the sample's `runs/`. The fixture, `/srv/scratch/z3224749/iris-fixtures/`, stays: it is not part of any ticket's cleanup.

## When a job hangs or dies

Before resubmitting, submit a **canary**, `lib/tests/katana/canary.pbs`, which times `import mlflow` from the pinned environment. If the canary hangs too, compute nodes can't read the shared environment: stop submitting and tell Patrick, as it goes to ResTech, not into code. On 2026-10-19 from 14:39 this stalled four jobs on k192, k216 and k217 while the login node read the same files in milliseconds.

Whenever you stop with the ticket unfinished, comment on it first with each job's ID, node and outcome and the test folder's path, so the next session can pick up from there.

To trace a script, put `set -x` after its `module load`. `bash -x` over the whole script traces the module system too and floods the log with its environment.
