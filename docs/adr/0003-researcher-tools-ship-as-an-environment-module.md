# Researcher tools ship as an environment module

Researchers reached `iris-view`, `iris-compare` and `iris-rebuild` by pasting their full path in the clone, such as `/srv/scratch/katana_ai/iris/code/bin/iris-view <run directory>`, and long paths put off researchers who don't code. So `module load iris` puts `iris-view` and `iris-compare`, the two they use routinely, on the PATH, and the job output, form help and pages give the short form. The modulefile's source is in the repo and is symlinked into Katana's system module tree, so `module load iris` needs no `module use` first, and a `git pull` in the system clone also deploys the module. It always runs the system clone, `/srv/scratch/katana_ai/iris/code/`, since researchers can't read the dev clone. This reverses the earlier rule that nothing goes on the PATH.

## Considered Options

- **Full paths, with nothing on the PATH**: the earlier rule. It's exact and needs no install, but it's the very thing that intimidates researchers.
- **OnDemand interactive apps (Batch Connect)**, one each for compare (MLflow through OnDemand's proxy) and view (napari in a desktop that opens on the run): deferred, not rejected. They take the terminal away completely, and they're the planned next step. The module comes first because it's smaller, and the apps can call the same `bin/iris-*` scripts.
- **A modulefile only in the repo, loaded after `module use <clone>/modulefiles`**: rejected, since it brings back one more line to type.

## Consequences

- The module exposes a symlink folder holding those two commands, not `bin/`, which also holds maintainer tools.
- `iris-rebuild` stays out of the module. It is a rare recovery step, run in a Virtual Desktop or a job, so the guide gives it as a full path.
- There is one unversioned `iris` module. Each run's `commit.txt` records its code, since nothing versions a workflow.
- During the pilot, only members of `katana_ai_ro` can read the clone, and so only they can read the symlinked modulefile. Anyone else who tries `module load iris` gets Environment Modules' own permission error, `ERROR: Permission denied on '<modulefile>'` (Environment Modules 5.3.1 on Katana, through a symlink into an unreadable folder, 2026-10-26). That is accepted, because IRIS opens to every Katana user at launch. A world-readable copy in `/apps` could have shown them a pilot message, but would then need reinstalling whenever it changed.
- Installing into `/apps/Modules` goes through ResTech's install route (Patrick, spec #83, 2026-10-26), since the tree belongs to `apps` (`ls -ld /apps/Modules`: owner and group `apps`, 2026-10-26). That happens once: later changes arrive with the pull.
