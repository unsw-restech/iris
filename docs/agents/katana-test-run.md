# Real-run acceptance on Katana

How to meet a ticket's "a real run shows…" criterion for `microct-2d-segmentation`: run the committed code on the sample dataset, from a scratch copy, into a throwaway run index and tracking store. Your dev clone, run index and `tracking.db` stay untouched.

Name every `qsub` and its resources in chat as you submit it. Delete nothing without Patrick's go-ahead naming the target.

## 1. Copy the committed tree to scratch

Commit first: the run records `git rev-parse HEAD` of the copy, so a clean tree makes `commit.txt` mean something. Copy `.git` too, through the data mover. `rsync` there won't create a missing parent, so make the folder first:

```
ssh katana 'mkdir /srv/scratch/$USER/iris-test-<n>'
rsync -a --exclude __pycache__ iris/ katana-dm:/srv/scratch/z3224749/iris-test-<n>/iris/
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
ssh katana 'cd /srv/scratch/$USER/iris-test-<n> && qsub -v IRIS_HOME=/srv/scratch/$USER/iris-test-<n>/home run.pbs'
```

The form's `#PBS -o` is a folder, so the log is `<dataset>/runs/<job number>.kman.restech.unsw.edu.au.OU`, not `<job name>.o<number>`. The run directory is `<dataset>/runs/<job number>/`.

Timing on a V100 for the sample: about 9 s per epoch of training and about 1370 s of inference (job 9551129), within the form's 2 h default.

## 4. Import and inspect

A second job runs `bin/iris-import` twice against the same `IRIS_HOME`, expecting `Imported 1`, then `Imported 0`. It then prints what the ticket asks about, through `MlflowClient(store_uri(Path(IRIS_HOME)))` in the pinned environment `/srv/scratch/katana_ai/iris/envs/imaging/1`, after `module load python/3.13.2`. 1 CPU, 4 GB and 15 min are plenty: the #36 import took 45 s.

## 5. Report, then clean up

Post results on the ticket in the shape of #35's and #36's closing comments: what landed, each acceptance box with its job IDs and evidence, the submissions with their resources, and what is known but not fixed. Then ask Patrick before removing `/srv/scratch/$USER/iris-test-<n>/` and the run's folder and `.OU` log in the sample's `runs/`.
