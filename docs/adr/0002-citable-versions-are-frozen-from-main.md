# Citable versions are frozen from `main`, not from git tags

Each catalogue workflow has its own WorkflowHub entry, imported from this repo, and every citable version is a snapshot of `main` at the commit current when its owner freezes it and mints the DOI. IRIS has no release tags because nothing versions a workflow: a run's `commit.txt` records the code it ran, and tags would bring back the version numbers the catalogue deliberately avoids. Owners also work from forks and can't push tags, so tag-based versions would route every DOI through the maintainer. A workflow page lists its citable versions by DOI, date and commit, and a researcher cites the latest one at or before the commit in their `commit.txt`, alongside that commit.

## Considered Options

- **A git tag per citable version (`<slug>-vN`)**: rejected. Only the maintainer can push tags, and the tags would become de facto version numbers.
- **One WorkflowHub entry for all of IRIS**: rejected. Its DOI wouldn't say which workflow ran, or credit that workflow's owner.
- **Minting a DOI only when a paper needs one**: rejected. A researcher at publication time would be waiting on someone else.

## Consequences

- A citable version's commit can include unrelated changes to other workflows. That is harmless, since the run's own commit still pins exactly what ran.
- Owners mint a new citable version only when their workflow's code or defaults change in a way that changes results, not on every merge.
