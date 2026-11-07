# Imaging environment

The shared, versioned venv that imaging workflows run in. Nothing is installed when a run starts. Each version is built once on Katana, made read-only and never changed again; any change to its packages means a new version.

| Version | Path on Katana | PyTorch | Compiled GPU archs | Status |
|---|---|---|---|---|
| 1 | `/srv/scratch/katana_ai/iris/envs/imaging/1/` | `2.10.0+cu128` | `sm_70 sm_75 sm_80 sm_86 sm_90 sm_100 sm_120` | Built (job 9543171), smoke-tested on V100 (9544165) and A100 (9544166), sealed 2026-10-17 |

Everything lives under `/srv/scratch/katana_ai/iris/`, an existing group scratch whose only member is Patrick and which researchers can read. IRIS stays there; there is no separate `/srv/scratch/iris` (Patrick, 2026-10-21). A venv can't be moved, because its paths are written into it. Moving means rebuilding each version from its lock at the new path, changing the paths in these scripts, and repointing the workflows' job scripts.

The arch list for version 1 was read from the `torch-2.10.0+cu128` cp313 wheel itself. `torch 2.9.1+cu128` has no `sm_70`, so it would not run on the V100s. The `cu128` build needs NVIDIA driver 570 or newer. Katana's V100s run 580 and every other GPU node runs 610. L40S (sm_89) runs the `sm_86` code. `build.pbs` records the arch list in `build-info.txt` and fails without `sm_70`. The smoke test checks `sm_70` again on a real V100.

## Files

Version 1's lock is now `microct/1`'s, so the container holds exactly what the venv does ([`../README.md`](../README.md)). Its top-level packages are split between `../core.in` and `../microct/requirements.in`, and `check_imports.py` is in `../`, which the container checks use too.

- `../microct/1/requirements.lock`: the `pip freeze` of version 1, copied from the environment after `build.pbs`. A rebuild installs exactly this.
- `build-info.txt`: the Python, PyTorch, CUDA and compiled GPU archs of the built version, copied alongside the lock.
- `download.sh`, `build.pbs`, `smoke.pbs`, `test.pbs`, `seal.sh`: the five build steps, in order.
- `desktop.sh`: the desktop CPU venv for the synthetic-dataset test.

## Building version *n* on Katana

All five steps run from `envs/imaging/` in a clone on Katana. Each takes the environments' folder and the Python module from the clone's `lib/katana.sh`. To build a version on another Python module, before `lib/katana.sh` switches to it, give that module to every step: `PYTHON_MODULE=<module> ./download.sh <n>`, and `PYTHON_MODULE=<module>` added to each `qsub -v`.

1. **Download** on the data mover, never a login node: `ssh katana-dm`, then `./download.sh <n>`. This puts every wheel into `/srv/scratch/katana_ai/iris/wheelhouse/imaging/<n>/`. It reads `../microct/1/requirements.lock`.
2. **Build** in a short CPU job (2 CPUs, 8 GB, 1 h): `qsub -v VERSION=<n> build.pbs`. This creates the venv at its final path with `pip install --no-index`, then writes `requirements.lock` and `build-info.txt` into it and imports every package in the lock. It fails if PyTorch has no `sm_70`, or if a rebuild from the lock installs anything different. It refuses to touch an environment that already exists, so after a failed build the half-built folder has to be deleted before retrying. That deletion is Patrick's call, by name.
3. **Smoke test** in two 5-minute GPU jobs (2 CPUs, 8 GB, 1 GPU each), a V100 and one other type:
   ```
   qsub -v VERSION=<n> -l select=1:ncpus=2:ngpus=1:mem=8gb:gpu_model=V100 smoke.pbs
   qsub -v VERSION=<n> -l select=1:ncpus=2:ngpus=1:mem=8gb:gpu_model=A100 smoke.pbs
   ```
   Each job passes if `sm_70` is in `torch.cuda.get_arch_list()` and a small forward pass on the GPU matches the CPU.
4. **Test** in a short CPU job (2 CPUs, 8 GB, 20 min): `qsub -v VERSION=<n> test.pbs`. This runs the shared library's tests (`lib/tests`), then each workflow's (`workflows/*/tests`), against the environment, including the `lib/iris-job.sh` tests that need Katana's module system and so are skipped on the desktop.
5. **Seal** on the data mover: `./seal.sh <n>`. This makes the environment readable by everyone and writable by no one.

Version 1's `requirements.lock` and `build-info.txt` were copied from `/srv/scratch/katana_ai/iris/envs/imaging/1/` into the repo. The lock pins the packages; `build-info.txt` records the PyTorch version, CUDA version and arch list. A rebuild installs from the lock and `build.pbs` checks that nothing changed. New versions are containers ([`../README.md`](../README.md)), not venvs.

A version stays as long as any workflow on `main` pins it, plus a grace period for queued jobs. Deleting one is Patrick's call. Scratch has no backup, so this recipe is what makes any version rebuildable.

## Desktop CPU venv

The synthetic-dataset test runs on Patrick's desktop in WSL, against the same packages with CPU PyTorch:

```
uv python install 3.13.2      # once
envs/imaging/desktop.sh       # builds ~/.venvs/iris-imaging from microct/1's lock
```

`desktop.sh` changes the lock's `torch==…+cu128` line to `+cpu` and drops the CUDA-only `nvidia-*`, `cuda-*` and `triton` packages. It ends by importing every remaining package.

## Model weights (convention only)

Nothing in version 1 uses pretrained weights; the reference workflow trains from scratch. When a workflow does need them:

- Stage them once, on the data mover, into `/srv/scratch/katana_ai/iris/models/<name>/<version>/`, and make that folder read-only like an environment.
- The job script points the library caches there (`TORCH_HOME`, `HF_HOME`, and any tool-specific variable such as `CELLPOSE_LOCAL_MODELS_PATH`) and sets `HF_HUB_OFFLINE=1`. That way an unexpected download fails loudly instead of fetching at run time.
- The weights' version is part of the job script, like the environment version.
