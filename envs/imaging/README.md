# Imaging environment

From version 2, each version ships as an environment image that CI builds and publishes, and Katana runs the same image as everyone else: [ADR-0004](../../docs/adr/0004-workflows-run-anywhere-from-one-apptainer-image.md).

The shared, versioned environment that imaging workflows run in. Nothing is installed when a run starts. Each version is built once and never changed again; any change to its packages, or to the system libraries an image adds, means a new version. Version 1 is a venv built on Katana. Version 2 is version 1's lock, unchanged, shipped as an environment image that runs with Apptainer on Katana and on any Linux x86_64 machine.

| Version | Built as | Where | PyTorch | Compiled GPU archs | Status |
|---|---|---|---|---|---|
| 1 | venv, on Katana ([steps](#building-a-venv-version-on-katana)) | `/srv/scratch/katana_ai/iris/envs/imaging/1/` | `2.10.0+cu128` | `sm_70 sm_75 sm_80 sm_86 sm_90 sm_100 sm_120` | Built (job 9543171), smoke-tested on V100 (9544165) and A100 (9544166), sealed 2026-10-17 |
| 2 | image, by CI ([steps](#image-versions)) | `ghcr.io/unsw-restech/iris-imaging@sha256:decf6e5581a3486f1483c98322a051626408efd67f09dc0707d0be2b1b8f7c6b` | `2.10.0+cu128` | `sm_70 sm_75 sm_80 sm_86 sm_90 sm_100 sm_120` | Built from commit `5bd083e` and checked (CI run 40436966575), published 2026-10-27; not yet on Katana (#101) |

Everything lives under `/srv/scratch/katana_ai/iris/`, an existing group scratch whose only member is Patrick and which researchers can read. IRIS stays there; there is no separate `/srv/scratch/iris` (Patrick, 2026-10-21). Version 1's venv can't be moved, because its paths are written into it. Moving means rebuilding each version from its lock at the new path, changing the paths in these scripts, and repointing the workflows' job scripts.

The arch list for version 1 was read from the `torch-2.10.0+cu128` cp313 wheel itself. `torch 2.9.1+cu128` has no `sm_70`, so it would not run on the V100s. The `cu128` build needs NVIDIA driver 570 or newer. Katana's V100s run 580 and every other GPU node runs 610. L40S (sm_89) runs the `sm_86` code. `build.pbs` records the arch list in `build-info.txt` and fails without `sm_70`. The smoke test checks `sm_70` again on a real V100.

## Files

- `requirements.in`: the top-level packages we ask for.
- `requirements.lock`: the `pip freeze` of the version actually built, copied from the environment after `build.pbs`. A rebuild installs exactly this, and so does the image.
- `build-info.txt`: the Python, PyTorch, CUDA and compiled GPU archs of version 1, copied alongside the lock.
- `download.sh`, `build.pbs`, `smoke.pbs`, `test.pbs`, `seal.sh`: the five venv build steps, in order.
- `Dockerfile`: the image recipe: the lock in a venv on a digest-pinned `python:3.13.2-slim-bookworm`, plus the system libraries napari's Qt needs for `iris-view` and the `git` that mlflow's GitPython imports. It holds no workflow code.
- `check-image.sh`: the checks CI runs on each image it builds.
- `images.txt`: each image version and its digest, the map `iris-run` reads (#100).
- `check_imports.py`: imports every package listed in a requirements file. Used by `build.pbs`, `check-image.sh` and `desktop.sh`.
- `desktop.sh`: the desktop CPU venv for the synthetic-dataset test.

## Image versions

CI builds and checks an image; a commit to `images.txt` makes one a version.

1. **Build**: change the recipe on a branch and push it. The `image` workflow (`.github/workflows/image.yml`) runs on any push that changes the recipe, as its `paths:` list names it. It builds the image, then `check-image.sh` fails it unless `pip freeze` inside it matches `requirements.lock` exactly, every package imports, PyTorch lists `sm_70`, Qt finds every library it links, and napari draws a frame under Xvfb. A pull request from a fork is built and checked, never published.
2. **Publish**: a build that passes on a branch in this repo is pushed to `ghcr.io/unsw-restech/iris-imaging`, tagged with its commit. The run's summary prints the image's digest. GHCR starts a new package as private, so a GitHub org owner makes `iris-imaging` public once, under **Change visibility** in its package settings; every later push inherits that.
3. **Pin**: add `<n> ghcr.io/unsw-restech/iris-imaging@sha256:<digest>` to `images.txt`, add the version's row to the table above, and commit both. Workflows pin a version, and `iris-run` looks its digest up here. Only the digest counts: the commit tag is a label, and rebuilding the same recipe gives a different digest, so a version is never rebuilt and its line never changes.
4. **On Katana**: the image is pulled once by digest on the data mover into a sealed SIF beside the venv versions, then smoke-tested and tested as version 1 was (#101).

The digest on GHCR is the durable copy of a version; the lock stays the fallback recipe. **A digest that a citable version's commit pins is never deleted** (ADR-0002): a citation has to keep running the software it names. Images that no version pins, such as a branch's trial builds, can be deleted from the package's settings, and that is Patrick's call.

## Building a venv version on Katana

Version 1 was built this way, and these steps are its rebuild recipe. All five steps run from `envs/imaging/` in a clone on Katana. Name every `qsub` and its resources in chat before submitting it.

1. **Download** on the data mover, never a login node: `ssh katana-dm`, then `./download.sh <n>`. This puts every wheel into `/srv/scratch/katana_ai/iris/wheelhouse/imaging/<n>/`. It reads `requirements.lock` if present, otherwise `requirements.in`.
2. **Build** in a short CPU job (2 CPUs, 8 GB, 1 h): `qsub -v VERSION=<n> build.pbs`. This creates the venv at its final path with `pip install --no-index`, then writes `requirements.lock` and `build-info.txt` into it and imports every package in the lock. It fails if PyTorch has no `sm_70`, or if a rebuild from the lock installs anything different. It refuses to touch an environment that already exists, so after a failed build the half-built folder has to be deleted before retrying. That deletion is Patrick's call, by name.
3. **Smoke test** in two 5-minute GPU jobs (2 CPUs, 8 GB, 1 GPU each), a V100 and one other type:
   ```
   qsub -v VERSION=<n> -l select=1:ncpus=2:ngpus=1:mem=8gb:gpu_model=V100 smoke.pbs
   qsub -v VERSION=<n> -l select=1:ncpus=2:ngpus=1:mem=8gb:gpu_model=A100 smoke.pbs
   ```
   Each job passes if `sm_70` is in `torch.cuda.get_arch_list()` and a small forward pass on the GPU matches the CPU.
4. **Test** in a short CPU job (2 CPUs, 8 GB, 20 min): `qsub -v VERSION=<n> test.pbs`. This runs the reference workflow's tests (`workflows/microct-2d-segmentation/tests`) against the environment, including the `lib/iris-job.sh` tests that need Katana's module system and so are skipped on the desktop.
5. **Seal** on the data mover: `./seal.sh <n>`. This makes the environment readable by everyone and writable by no one.

Then copy `requirements.lock` and `build-info.txt` from `/srv/scratch/katana_ai/iris/envs/imaging/<n>/` into this folder, update the table above, and commit all three. The lock pins the packages; `build-info.txt` records the PyTorch version, CUDA version and arch list. The first build of a version resolves `requirements.in` and freezes the result into the lock. A rebuild installs from the lock and `build.pbs` checks that nothing changed.

A version stays as long as any workflow on `main` pins it, plus a grace period for queued jobs. Deleting one is Patrick's call. Scratch has no backup, so this recipe is what makes any version rebuildable.

## Desktop CPU venv

The synthetic-dataset test runs on Patrick's desktop in WSL, against the same packages with CPU PyTorch:

```
uv python install 3.13.2      # once
envs/imaging/desktop.sh       # builds ~/.venvs/iris-imaging from requirements.lock
```

`desktop.sh` changes the lock's `torch==…+cu128` line to `+cpu` and drops the CUDA-only `nvidia-*`, `cuda-*` and `triton` packages. It ends by importing every remaining package. Until the lock exists, `envs/imaging/desktop.sh envs/imaging/requirements.in <dir>` builds a trial venv from the top-level list instead.

## Model weights (convention only)

Nothing in version 1 uses pretrained weights; the reference workflow trains from scratch. When a workflow does need them:

- Stage them once, on the data mover, into `/srv/scratch/katana_ai/iris/models/<name>/<version>/`, and make that folder read-only like an environment.
- The job script points the library caches there (`TORCH_HOME`, `HF_HOME`, and any tool-specific variable such as `CELLPOSE_LOCAL_MODELS_PATH`) and sets `HF_HUB_OFFLINE=1`. That way an unexpected download fails loudly instead of fetching at run time.
- The weights' version is part of the job script, like the environment version.
