# Workflows run anywhere from one Apptainer image

**Superseded by [ADR-0005](0005-environments-stay-venvs-on-katana.md)**: environments stay venvs on Katana (Patrick, 2026-10-27).

Researchers need to run IRIS workflows on other HPCs and on their own desktops, not only on Katana. The shared imaging venv can't follow them: a venv only works at the path it was built at, on Katana's `python/3.13.2` module. So from imaging environment version 2, an environment is an Apptainer image, and Katana runs the same image as everyone else. This reverses decision 12 of #12 ("Off Katana: no promise"), which chose the venv while naming Apptainer as the route if IRIS ever had to leave Katana (Patrick, 2026-10-27).

- The image holds the environment only. The code comes from a git clone bound in at run time, so a form still runs its own clone's code and `commit.txt` still identifies it.
- GitHub Actions builds it from a Dockerfile on a digest-pinned `python:3.13.2-slim-bookworm`, installing the environment's lock. CUDA comes from the lock's wheels and the driver from the host (`--nv`). It is published publicly to `ghcr.io/unsw-restech/iris-imaging`, and the repo maps each environment version to its digest.
- Katana pulls each version once, on the data mover, into a sealed SIF beside the venv versions.
- One launcher, `iris-run`, starts a run from a form job or from a researcher's shell. It writes `environment.txt` (version and digest) beside `commit.txt`.
- The promise covers Linux x86_64 with Apptainer: other HPCs, Linux workstations, and Windows through WSL2, on an NVIDIA GPU or the CPU.

## Considered Options

- **Keep the venv, with no promise off Katana**: the earlier decision. It's the lightest option, but researchers on other machines couldn't run IRIS at all.
- **The venv on Katana and an image elsewhere, both built from one lock**: rejected. Two builds drift in what the lock doesn't pin (system libraries, the Python build, the CUDA runtime), so a Katana run and an off-Katana run could differ.
- **An Apptainer `.def` built on Katana**: rejected. Unprivileged builds on Katana are unconfirmed, and off-Katana researchers would still need a public download.
- **One image per workflow, with its code baked in**: rejected. That means an image per workflow per commit, and it would break "a form runs its own clone's code".
- **macOS and Docker Desktop support**: not promised. Macs have no CUDA, and the cu128 PyTorch image is x86_64 only, so they would need a second, CPU-only arm64 image.

## Consequences

- Version 2 is version 1's lock unchanged, so the switch changes only the packaging. Version 1 stays until no workflow on `main` pins it.
- The GHCR digest, not a rebuild, is now the durable copy of an environment, which scratch never was. The lock stays the fallback recipe. A digest that a citable version's commit pins is never deleted (ADR-0002).
- An image is one compressed file of about 4–5 GB, instead of a venv's 8.3 GB in 73,000 files (version 1). Researchers off Katana download it once per version.
- `iris-view` and `iris-compare` run from the image too. Off Katana, the importer reads datasets' `runs/` folders, and the run index stays Katana-only. ADR-0001 holds.
- Runs off Katana have no usage count: jobs still write nothing for counting.
- `bin/check`'s synthetic-dataset test keeps the desktop CPU venv, since it tests the workflow code, not the image.
