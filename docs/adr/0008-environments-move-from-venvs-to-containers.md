# Environments move from venvs to containers

**Superseded in part by ADR-0010**: its rule that a new version can only add packages, never remove them. A later version may now add, change or remove packages. The rest of this ADR holds, including one container per lab.

Environments move from venvs on Katana to containers, which supersedes ADR-0005. IRIS calls them containers, never images, since an image in IRIS is imaging data (Patrick, 2026-11-06). Patrick expects cleanly defined containers to be less of a headache as outside workflow authors arrive (Patrick, 2026-11-05). Each lab has one container, and authors don't bring their own: the maintainer builds a lab's container for its first workflow, and a later workflow that needs more packages changes that container, making a new version. The author of that workflow proves it works in the new version, and the previous version is kept, in as little space as possible. `microct-2d-segmentation` moves from `imaging/1` to a container during the pilot, so no venv route is kept beside containers (Patrick, 2026-11-06).

Nothing has moved yet: `imaging/1` is still a venv, and every form, `lib/iris-job.sh` and `bin/check` still assume one. Before anything is built, one test decides whether the move goes ahead (below).

## Why ADR-0005 went back to venvs, and what still applies

None of the four extra steps goes away. Only the org owner can be avoided outright.

- **A CI build per version: still applies.** Closed PR #106 has a working build and checks to start from, but something has to run them for every version. Who runs them is open.
- **A digest map: still applies.** Each version has to be pinned to one exact container. Where that pin lives is open.
- **A launcher: still applies, possibly smaller.** Something has to start the job in the container with the GPU and the right folders. ADR-0004's `iris-run` also served researchers' shells off Katana, which isn't promised here, so the job library may be enough. That is untested.
- **A pull onto Katana: still applies.** A pull on the data mover worked (2026-11-05). Who runs it, and when, is open.
- **An org owner to make a GHCR package public: applies only under `unsw-restech`.** Publishing somewhere other than the org avoids it, for example under a personal GitHub account, at the cost of tying the container to that account. Asking an owner is the other way. Neither is chosen.

ADR-0005's other reason still stands too: the venv already runs every workflow. Before the test below, a container had passed only CI's checks (#106, 9.06 GB unpacked), had never run on a Katana GPU, and those trial builds were deleted.

## Off Katana

Workflows can be run off Katana, but IRIS isn't optimised for it and doesn't support it (Patrick, 2026-11-06). Containers were not chosen for that reason.

## ADR-0004's rejected options

- **The venv on Katana and a container elsewhere, both from one lock**: does not come back, as nothing is promised elsewhere. Its worry, that the two differ in what the lock doesn't pin, does return in another form: `microct-2d-segmentation`'s results could change when it moves from `imaging/1` to a container, which the test below checks.
- **An Apptainer `.def` built on Katana**: stays rejected, now on evidence. A build failed on the data mover, with and without `--fakeroot` (2026-11-05). A compute node is untested.
- **One container per workflow, with its code baked in**: stays rejected. Baking in the code would break ADR-0006, where a form runs its own clone's code, and each lab has one container rather than each workflow (ADR-0007).
- **macOS and Docker Desktop support**: stays not promised.

## The test before building

A container built from #106's recipe runs the reference workflow on Katana before any of the move is built (Patrick, 2026-11-06). #106's recipe installs the same `requirements.lock` as `imaging/1` on the same Python, so only the system libraries and Python's own build differ. On each of a V100 and an A100, the same dataset and settings run twice in the venv and once in the container. The test passes if all six jobs finish and the container's results differ from the venv's by no more than the venv runs differ from each other. One pair of venv runs proved too narrow a baseline: on the V100 the container was 2.32% of voxels from one venv run and 1.46% from the other, against 2.16% between the two. So the V100 baseline becomes the range across five venv runs (Patrick, 2026-11-06).

**Result: passed (2026-11-06).** A container built from #106's recipe in WSL held exactly `requirements.lock`, and its jobs saw their GPU and trained on CUDA, with only the `apptainer exec --nv` line changed in the job script. On the A100 (venv jobs 9680450 and 9680451, container job 9680570), the container was 1.47% and 2.53% of voxels from the venv runs, against 2.56% between them. On the V100 (venv jobs 9680448, 9680449 and 9681581–9681583, container job 9680569), the container was 1.46–2.32% from the five venv runs, whose ten pairs ranged 1.54–2.95%. Its final Dice per class sat within or above the venv runs' on both. Napari drew a run's labels under Xvfb in the container and in the venv alike (job 9681794). Two runs with the same seed in the same venv differ by 1.5–3% of voxels, so no run, venv or container, repeats another's labels exactly. If it fails, this decision reopens.

## Versions, publishing and storage

- **Workflows stay on the version they were proved in.** Each form pins one exact version. A lab's newest version is for new workflows, and an owner moves up only by choice, with a new proof (Patrick, 2026-11-06).
- **The author makes each new version.** Their pull request changes the lab's recipe, adding packages and updating its lock; a new version can only add packages, never remove them. CI on their fork builds the container and publishes it under their own GitHub account, and they prove their workflow in it on the test instance. The maintainer builds only a lab's first version (Patrick, 2026-11-06).
- **One public package holds every version**: `ghcr.io/unsw-restech/iris-env`, tagged by lab and version. An org owner makes it public once. The package is private for now, and pulls log in with a read-only token (below). The review batch copies the exact container the author proved, by digest, into it, rather than rebuilding. GHCR keeps every version, sharing their common layers, and a version a citable version's commit pins is never deleted (Patrick, 2026-11-06).
- **Katana keeps only what live forms pin**, in `/srv/scratch/katana_ai/iris/envs/`, one container file per version. Any other version is pulled again by digest when needed (Patrick, 2026-11-06).
- **The `imaging/1` venv and its wheelhouse are deleted** once `microct-2d-segmentation` has had a real run from `/pun/sys/` in its container (Patrick, 2026-11-06).
- **Each environment is named after the lab it was first built for**, with versions counting from 1: the first is `microct/1`, tagged `iris-env:microct-1` and kept on Katana as `envs/microct/1.sif`. A lab that shares another's environment points at it (Patrick, 2026-11-06).
- **`iris-view` and `iris-compare` run in the microCT container**, at one version named in `lib/katana.sh`, once the venv is gone; the test adds a headless napari check (Patrick, 2026-11-06).
- **Each workflow carries its own copy of the shared library**, about 50 KB in 12 files, copied in when the workflow is made. Its owner updates the copy only by choice, with a new proof, so a library change can't break workflows that didn't ask for it, and a fix reaches a workflow only when its owner updates (Patrick, 2026-11-06).
- **The copy is only the job side of the library**: writing the run record and recording the code. `iris-view`, `iris-compare` and the importer stay one shared copy in the system clone, since a researcher compares runs from different workflows in one place. Each run record states its format version, the shared tools read every version ever written, and CI keeps a sample run directory per version to prove it. The format holds only what is true of any run, and a workflow adds its own details on top (Patrick, 2026-11-06).

## Still open

- Whether the package can be public. Making it public is disabled by the org's package policy ("Setting is disabled by organization administrators", 2026-11-09), so it needs an org owner to change that policy or make an exception, not only to flip one package. Nothing waits for it: jobs run the container files on Katana and never touch the registry, `bin/envpull` pulls with a read-only token, CI with the workflow's own token and `bin/envrun` with `gh`'s. If it stays private, two things are lost: pulls depend on a person's token, and readers outside the org can't pull the container a citable version pins, though its lock stays public. GHCR stays the registry either way; publishing under a personal account instead would tie every cited container to that account, which is worse than the token (Patrick, 2026-11-09).

## Consequences

- `AGENTS.md`, `CONTRIBUTING.md`, `envs/imaging/README.md`, `lib/iris-job.sh`, `lib/katana.sh` and `bin/check` keep describing venvs until the move is built, and change with it.
  - Done in #131 (2026-11-09): `envs/imaging/`, its build, seal, smoke and test jobs and the desktop CPU venv are gone from the repo, `lib/katana.sh` no longer names the venv, and `bin/check` runs each workflow's tests on CPU in the container its form pins (`bin/envrun`), in CI as on the desktop. The `imaging/1` venv and its wheelhouse stay on Katana until the deletion above.
