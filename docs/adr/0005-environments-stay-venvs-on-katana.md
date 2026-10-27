# Environments stay venvs on Katana

Imaging environments stay venvs built on Katana from `envs/imaging/`, and IRIS again makes no promise off Katana, as decision 12 of #12 ("Off Katana: no promise") had it. This reverses ADR-0004 before anything used it. An image needed more than the venv for every version: a CI build, a digest map, a launcher and a pull onto Katana. Publishing it also needed a GitHub org owner to make the GHCR package public, which is work the maintainer can't do alone. Meanwhile the venv already runs every workflow (Patrick, 2026-10-27).

## Considered Options

- **Keep ADR-0004's image**: researchers could run workflows on other Linux machines. Version 2 was built and passed CI's checks on a branch (#99, PR #106, never merged), so the image itself worked. Rejected for the cost above.

## Consequences

- Researchers run IRIS on Katana only. Running anywhere else means reopening ADR-0004. Its design and the closed PR #106 (Dockerfile, CI checks, digest map) are the starting point.
- Version 1 stays the current environment, and the next version is a venv built by the steps in `envs/imaging/README.md`.
- The tickets for the image (#99–#105) are closed as not planned. GHCR's trial images of version 2 are deleted, since nothing pins them.
