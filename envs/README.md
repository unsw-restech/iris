# Environments

Workflows run in environments packaged as containers ([ADR-0008](../docs/adr/0008-environments-move-from-venvs-to-containers.md)). Each lab uses one environment, and labs may share one ([ADR-0007](../docs/adr/0007-each-lab-uses-one-environment.md)). An environment is named after the lab it was first built for, and its versions count from 1: `microct/1` is the microCT Lab's first. A version is built once by CI, never on Katana, and never changes: a change to its packages is a new version, which only adds packages.

| Version | Built from | PyTorch | Compiled GPU archs | Status |
|---|---|---|---|---|
| `microct/1` | `imaging/1`'s lock, unchanged, on Python 3.13.2 (closed PR #106's recipe) | `2.10.0+cu128` | `sm_70 sm_75 sm_80 sm_86 sm_90 sm_100 sm_120` | Recipe committed; not yet published |

## Files

- `core.in`: the shared core list, the top-level packages `lib/iris` needs (numpy, xarray, dask, tifffile, mlflow). Every environment holds them.
- `<env>/requirements.in`: an environment's own top-level packages, beyond the core list.
- `<env>/<n>/requirements.lock`: version *n*'s `pip freeze`, the core list and the environment's packages with every dependency pinned. The container installs exactly this, and `pip freeze` inside it lists the lock and nothing else.
- `<env>/1/Dockerfile`: an environment's first version: a digest-pinned Python, the system libraries its packages need, and the lock in a venv at `/opt/iris-env`, whose `python` is first on the PATH.
- `next.Dockerfile`: every later version: the version before it, pulled by digest, plus one layer installing what its lock adds. The registry stores what versions share only once.
- `build-container.sh <env>/<n> <local name>`: builds a version with Docker, as CI does.
- `check-container.sh <local name> <env>/<n>`: CI's checks on a built container: the installed packages are exactly the lock, every package imports (`check_imports.py`), PyTorch has `sm_70` for the V100s, and, for a version with napari, Qt finds its libraries and napari draws a frame under Xvfb. Offscreen Qt has no OpenGL and draws nothing, so the check needs an X display.
- `imaging/`: the `imaging/1` venv's build steps on Katana, kept until the move to containers is done.

## The digest map and the lab table

Both are in `lib/katana.sh`, the one place every script takes Katana's constants from. A script that can source bash reads the arrays. Any other reads them with a regex, one entry per line, in the formats below.

- **Digest map** `IRIS_ENV_DIGESTS`: every environment version, `<env>/<n>`, and its container's digest in `IRIS_ENV_REGISTRY` (`ghcr.io/unsw-restech/iris-env`), one `    [<env>/<n>]=<digest>` line each. `<digest>` is `sha256:<64 hex>`, or `unpublished` until CI first publishes the version. `iris_env_ref <env>/<n>` prints `ghcr.io/unsw-restech/iris-env@sha256:<hex>`, the container by digest alone, or fails with one line for a version that is unpublished or not in the map.
- **Researcher tools' version** `IRIS_TOOLS_ENV_VERSION`: the version `iris-view`, `iris-compare`, the importer and rebuild run in, `microct/1`. `bin/check` fails it if it isn't in the digest map.
- **Lab table** `IRIS_LAB_ENVS`: each lab, by its section id in `index.html`, and the version its new workflows start on, one `    [<lab>]=<env>/<n>` line each. Adding a lab is one line, and a lab with no packages of its own points at another lab's environment.

A form pins its version with an `  IRIS_ENV_VERSION=<env>/<n>` line in its script. `bin/check`'s "environment versions match the digest map" check fails:

- a digest that isn't `sha256:<64 hex>` or `unpublished`, a version that isn't `<env>/<n>`, or a version whose number skips one;
- a version without its lock in `envs/<env>/<n>/`, or a lock there that isn't in the map;
- a lab that isn't a section of `index.html`, or one that starts on a version not in the map;
- a form whose `IRIS_ENV_VERSION` isn't in the map. An unpublished version is in the map, so it passes; a job pinning it stops at once because its container file isn't on Katana;
- a later version whose lock removes or changes a line of the lock before it. Versions only add packages, so a change goes in a new environment.

## Publishing a version

1. **Recipe**: commit the version's lock, `envs/<env>/<n>/requirements.lock`, with `[<env>/<n>]=unpublished` added to the digest map. A first version also needs its `Dockerfile`; a later one uses `next.Dockerfile`.
2. **Build and check**: the `containers` workflow (`.github/workflows/containers.yml`) runs on any push that changes `envs/`, `lib/katana.sh` or the workflow itself, on any branch, and can be started by hand from the Actions tab. It builds and checks every version whose digest is `unpublished`, and nothing else. A container that fails a check is never published. A later version needs the one before it published first.
3. **Publish**: on `main` only, a container that passes is pushed to `ghcr.io/unsw-restech/iris-env`, tagged `<env>-<n>` (`microct-1`). GHCR starts the package as private, which needs no org owner; making it public is its own step, done once by an org owner. Until then, pulling it needs a read-only token.
4. **Pin the digest**: the run's summary prints the line to put in `lib/katana.sh`, `    [<env>/<n>]=sha256:<hex>`, in place of `[<env>/<n>]=unpublished`. Commit it, with the version's Status above, as its own commit. From then on CI never builds that version again, and its lock never changes. Until the digest is pinned, each push that triggers the workflow on `main` rebuilds the version and moves its tag, so pin it after the first green run.

5. **Put it on Katana**: once the digest is on `main`, run `bin/envpull` from the desktop (below), before `bin/syspull` deploys a form that pins the version.

The digest on GHCR is the version. Its tag is only a label, and rebuilding the same recipe gives a different digest. **A version that a citable version's commit pins is never deleted from the registry** ([ADR-0002](../docs/adr/0002-citable-versions-are-frozen-from-main.md)).

## Containers on Katana

Jobs never touch the registry: they run the container files in the IRIS environments folder, `IRIS_ENVS_FOLDER` in `lib/katana.sh` (`/srv/scratch/katana_ai/iris/envs`). Version `<env>/<n>`'s file is `<folder>/<env>/<n>.sif`, and `<folder>/<env>/<n>.digest` beside it holds the digest it was pulled by, so `microct/1` is `microct/1.sif` and `microct/1.digest`. Katana keeps a file for each version a live form pins, plus `IRIS_TOOLS_ENV_VERSION`, the one the researcher tools (`iris-view`, `iris-compare`, the importer, rebuild) run in, whichever lab a run is from.

`bin/envpull`, run from the desktop, makes the folder hold exactly those, over `ssh katana-dm`:

```
bin/envpull                      pull each pinned version missing from the folder, and list files nothing pins
bin/envpull --pull <env>/<n>     pull one version by digest, pinned or not
bin/envpull --remove <env>/<n>   remove a version's file and its digest file, if nothing pins it
```

- A version is pinned by a form in the checkout it runs from, by one in the system clone, or by `IRIS_TOOLS_ENV_VERSION`. Digests come from the checkout's digest map, so run it from `main`.
- An unpublished version is skipped. A pull is `apptainer pull docker://ghcr.io/unsw-restech/iris-env@sha256:<hex>`, by digest alone, and never replaces a file already there: one whose digest file disagrees with the map is reported, and replacing it needs Patrick's go-ahead naming that file.
- **Removing needs Patrick's go-ahead naming the file.** The listing prints each unpinned file and its `--remove` line, and `--remove` refuses a version anything pins. It is not a one-way door: `--pull` brings any published version back by digest.
- **Until the package is public, pulls need a read-only token** on Katana, in `~/.config/iris/ghcr-token`, mode 600: one line, `<GitHub login>:<token>`, from a classic token with `read:packages` alone. `bin/envpull-dm.sh` passes it to Apptainer as `APPTAINER_DOCKER_USERNAME` and `APPTAINER_DOCKER_PASSWORD`, never on a command line, and refuses a file others can read. Without the file, it pulls without a login, which works once the package is public; the token can then go.

## Building on the desktop

A local build is optional, since CI builds every version. In WSL, with Docker Desktop:

```
envs/build-container.sh microct/1 iris-env-build:local
Xvfb :99 -ac &
DISPLAY=:99 envs/check-container.sh iris-env-build:local microct/1
```

Docker Desktop's Windows credential helper breaks the base pull unless the build runs with a home folder that lacks it, such as `HOME=$(mktemp -d)`.
