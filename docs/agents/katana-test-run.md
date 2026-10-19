# Real-run acceptance on Katana

How to meet a ticket's "a real run shows…" criterion for `microct-2d-segmentation`: run the committed code on the sample dataset, from a scratch copy, into a throwaway run index and tracking store. Your dev clone, run index and `tracking.db` stay untouched.

Name every `qsub` and its resources in chat as you submit it. Delete nothing without Patrick's go-ahead naming the target.

## 1. Copy the committed tree to scratch

Commit first: the run records `git rev-parse HEAD` of the copy, so the copy is a clone of a bundle of `HEAD`, carried by the data mover. A bundle works from a worktree too, where `.git` is only a pointer back to the main clone. `rsync` there won't create a missing parent, so make the folder first:

```
git -C <clone or worktree> bundle create /tmp/iris-test-<n>.bundle HEAD
ssh katana 'mkdir /srv/scratch/$USER/iris-test-<n>'
rsync /tmp/iris-test-<n>.bundle katana-dm:/srv/scratch/z3224749/iris-test-<n>/
ssh katana 'cd /srv/scratch/$USER/iris-test-<n> && git clone -q iris-test-<n>.bundle iris'
```

## 2. Render the job script from the form

`tests/form_helper.rb` renders `form.yml.erb` as OpenComposer 1.9.0 does, runs `check:` and prints the script. Fields are the form's keys. `time` is two numbers, `time_1` hours and `time_2` minutes. Unset fields take the form's defaults.

```
ssh katana 'cd /srv/scratch/$USER/iris-test-<n> && module load ruby/3.2.0 && \
  ruby iris/workflows/microct-2d-segmentation/tests/form_helper.rb \
    /srv/scratch/$USER/iris-test-<n>/iris/workflows \
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

Timing on a V100 for the sample: about 9 s per epoch of training and about 1370 s of inference (job 9551129), within the form's 2 h default.

## 4. Import and inspect

A second job runs `bin/iris-import` twice against the same `IRIS_HOME`, expecting `Imported 1`, then `Imported 0`. It then prints what the ticket asks about, through `MlflowClient(store_uri(Path(IRIS_HOME)))` in the pinned environment `/srv/scratch/katana_ai/iris/envs/imaging/1`, after `module load python/3.13.2`. 1 CPU, 4 GB and 15 min are plenty: the #36 import took 45 s.

## 5. Report, then clean up

Post results on the ticket in the shape of #35's and #36's closing comments: what landed, each acceptance box with its job IDs and evidence, the submissions with their resources, and what is known but not fixed. Then ask Patrick before removing `/srv/scratch/$USER/iris-test-<n>/` and the run's folder and `.OU` log in the sample's `runs/`.

## When a job hangs or dies

Before resubmitting, submit a **canary**: 1 CPU, 1 GB, 5 min, running only `. /etc/profile.d/modules.sh; module load python/3.13.2; timeout 120 /srv/scratch/katana_ai/iris/envs/imaging/1/bin/python -c 'import mlflow'`. If the canary hangs too, compute nodes can't read the shared environment: stop submitting and tell Patrick, as it goes to ResTech, not into code. On 2026-10-19 from 14:39 this stalled four jobs on k192, k216 and k217 while the login node read the same files in milliseconds.

To trace a script, put `set -x` after its `module load`. `bash -x` over the whole script traces the module system too and floods the log with its environment.
