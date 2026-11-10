# Each lab uses one environment, and labs may share

**Superseded in part by ADR-0010**: its rule that a new version only adds packages, and its Consequence that a package that conflicts with its lab's pins is declined. A later version may now add, change or remove packages. The rest of this ADR holds, including one environment per lab and labs sharing one.

A form pins the environment its lab uses, and one table maps each lab to its environment, rather than every form pinning one shared environment. Under one shared environment, a workflow author's package request moved every workflow to a new version, including workflows that author doesn't own, which could change their results. Packages tend to follow the discipline, which follows the lab, so a new version now reaches one lab's forms at most. Every environment is a shared core list, which `lib/iris` needs, plus its own packages, and a new version only adds packages. Each version is pinned to one exact container (ADR-0008). Whether a lock file still pins its packages depends on how containers are built; closed PR #106's recipe installed from one. The maintainer builds a lab's environment for its first workflow. A later workflow that needs more packages changes it, making a new version, and its author proves the workflow in that version; the previous version is kept (Patrick, 2026-11-06). Each form pins the version it was proved in, so a new version reaches only the workflows whose owners move to it; how versions are built and kept is in ADR-0008.

## Considered Options

- **One environment, batched additive versions**: the least to build, but one lab's packages still reach every lab, and every request has to fit one set of pins.
- **One environment per workflow**: the most isolated, but it means a build for every workflow, and the shared `lib/` would have to work on every one of them.
- **Workflow authors host their own environments**: no work for the maintainer, but nothing would stop an environment changing under a cited run, or vanishing when its author leaves.

## Consequences

- A lab with no packages of its own points at an existing environment, so it costs no disk or build until a workflow needs more.
- `iris-view` and `iris-compare` stay on one environment whatever the run's lab, since they read run directories and never run workflow code.
- A new version is built from the author's pull request and proved before it merges, so a workflow's proof names the exact container the review batch then publishes (ADR-0008).
- A package that conflicts with its lab's pins is declined, so two workflows in one lab that can't share pins can't both join.
