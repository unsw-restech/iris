# IRIS — project instructions

`AGENTS.md` is the source of truth for agent instructions. Edit this file.

IRIS is a static GitHub Pages site: hand-edited HTML with no build system, and it stays that way. `README.md` is for researchers. `CONTRIBUTING.md` covers structure, previewing, adding a workflow and the **tier table** of which workflows actually run. Read the tier table before telling anyone a workflow "works".

## Layout

```
IRIS_github_pages\               <- parent directory, not a git repo
├── available-modules.md         <- what is installed on Katana
└── iris\                        <- the git repo (github.com/unsw-restech/iris)
    └── _archive\                <- retired forms, public but never served by OpenComposer
```

Working plans go in `plan.md` at the repo root. Delete it when the work is done.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `unsw-restech/iris`, via the `gh` CLI. Read `docs/agents/issue-tracker.md` before the first `gh` call.

### Triage labels

The five default labels, each named for its role: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.

### Tickets

- **Keep the ticket graph wide.** A ticket is blocked only by a ticket whose output it uses, never by one that just comes before it in the plan. Tickets that touch separate files don't block each other, so the implement-spec skill can build them in parallel (Patrick, 2026-10-20).

## Checks before shipping

Run `bin/check` before committing; CI runs it on every push. It covers the link and URL greps, the form and manifest rules, executable bits, shellcheck, ruff and the synthetic-dataset test, which needs the desktop CPU venv (`envs/imaging/desktop.sh` builds it). Its attribution check reads commit messages, so it sees a message only once committed; `.githooks/commit-msg` refuses one first. Turn the hook on once per clone: `git config core.hooksPath .githooks`.

A change to a `form.yml.erb` or to `module/` also needs `bin/katana-test`, which runs every form test and the module test on Katana, since `check:` looks inside `/srv/scratch/$USER` and the module test needs Environment Modules and `katana_ai_ro` membership.

## Deploying

Pushing `main` is an immediate public deploy to https://docs.restech.unsw.edu.au/iris/. The org serves its Pages sites under its docs domain, and `unsw-restech.github.io/iris/` redirects there. Confirm with Patrick before pushing unless they've already said to. If your sandbox or permissions block the push, give Patrick the exact `git push origin <sha>:main` to run, then do the dev-clone pull and the live check yourself. Live-check every push on one changed file outside `.github/`: Pages serves every other file, `_archive/` and dotfiles included (`.nojekyll`). Pages takes 40–60 seconds; run `bin/pageswait <path> <marker>` in the background.

- **CI:** `bin/ciwait <commit>` waits for that commit's `check` run and prints the failed log. Push a change to `.github/` to a branch first. Merge `origin/main` into that branch before its run, so the green run is on the commit `main` becomes, then push that commit to `main`.
- **Dev clone:** after pushing a change to `workflows/`, `lib/` or `bin/iris-*` (researchers run those from the clone), run `ssh katana 'cd ~/iris && git pull --ff-only'` as its own command, so a permission rule scoped to `ssh katana` can match it. The dev clone is Patrick's test bed: a change goes push, dev pull, `bin/katana-test` where it applies, then the system clone.
- **System clone:** `/srv/scratch/katana_ai/iris/code/`, beside `envs/` and `wheelhouse/`, since the dev clone's home folder is unreadable to researchers (Patrick, 2026-10-23). The system OpenComposer's `apps_dir` is its `workflows/`, and every Run button opens `https://kod.restech.unsw.edu.au/pun/sys/OpenComposer/<slug>` (Patrick, 2026-10-27). Any git change there (pull, reset, checkout) deploys to the pilot, so it is the OpenComposer deploy. Run `bin/syspull` to list what a pull would deploy, get Patrick's go-ahead naming that path and quoting the list, then run the `bin/syspull --apply <sha>` line it prints.

**Push auth:** the repo is owned by the `unsw-restech` org and pushed as `PatrickTung` over HTTPS + Git Credential Manager (no SSH keys). A stale `patricktung-unsw` credential has caused a 403 before, and retrying cannot fix that. Check with `cmdkey /list:git:https://github.com`; clearing it is Patrick's call.

**Org rights:** Patrick is an admin of the repo but only a member of the org. Anything org-level, such as a package's visibility or deletion, org settings or an org-owned secret, needs one of the org's owners (`gh api 'orgs/unsw-restech/members?role=admin' --jq '.[].login'`). Name that dependency before a design rests on it: #99's image was built and published, then dropped, because only an owner could make it public (ADR-0005). GitHub answers a package delete Patrick lacks the right for with 404, not 403 (Patrick, 2026-10-27).

## Deliberate, leave as is

- **No `CLAUDE.md`**, in the repo or in `IRIS_github_pages\`: `AGENTS.md` is the only instructions file (Patrick, 2026-10-26). Claude Code loads it on the first Read of a file in the repo, so read with the Read tool before working through Bash.
- **`hello-world` is onboarding, not a catalogue entry**: excluded from the grid, and kept on its own styles rather than `assets/iris.css`.
- **Planned cards still link to their pages**, keeping the dimmed `.planned` style with no hover lift.
- **No version tags** on cards: nothing versions a workflow, and each run's `commit.txt` records the code it ran (Patrick, 2026-10-22). A workflow page lists its citable versions by DOI, date and commit, never as a version number (ADR-0002).

**Adding a modality** takes a `.card-domain.<x>` rule in `index.html` and `<span class="card-domain <x>">` as the modality tag on the card. There is no filter bar.

## Katana

- **Pilot until launch.** ResTech set `other::---` on `/srv/scratch/katana_ai`, so only `katana_ai_ro` members (pilot testers) can run IRIS; it opens to everyone once it runs securely (Patrick, 2026-10-23). Launch removes the pre-launch notices CONTRIBUTING.md's Status lists, all in one commit.
- **Confirm one-way doors first.** Get Patrick's explicit go-ahead in chat, naming the exact target, before any one-way door or large blast radius action, on the desktop or on Katana: deleting, overwriting or moving files, `qdel`, `rsync --delete`, or anything recursive over a directory this session did not create (Patrick, 2026-10-14).
- **`qsub` needs no go-ahead**: name each job and its resources in chat (Patrick, 2026-10-17). Every `qsub` passes `-m abe`, so PBS emails Patrick when the job begins, ends or aborts; a local hook may block a `qsub` without it (Patrick, 2026-10-19).
- **Login nodes stay light**: editing, `qsub`, short checks (Patrick, 2026-10-14). Anything that loads CPU, memory or I/O runs as a PBS job. Transfers over 10 GB go through the data mover (`katana-dm`), never a login node or **Files** in Katana OnDemand.
- **Modules first.** Check `..\available-modules.md` before designing an environment or naming a module. `lib/iris-job.sh` shows the pattern: a module (`python/3.13.2`) topped up with the pinned imaging venv.
- **`module` in batch scripts**: source `/etc/profile.d/modules.sh` first, and run it without `set -u`.
- **Containers** are for software that genuinely isn't installed. Apptainer/Singularity are on the path, not modules, so there is no `module load apptainer`. Docker is unsupported. Cache images in `/srv/scratch/$USER/.images`. Executor is `pbspro`.
- **GPU models for queued jobs**: A100, H100, H200, L40S, V100. `RP6000` in `pbsnodes` is ResTech's in-house development node and never runs queued jobs (Patrick, 2026-10-14).
- **Limits** (confirmed by Patrick, 2026-08-05): walltime 200 hours, memory 1 TB, no fixed CPU cap. The 24 cpus / 248 GB / 100 h in nf-core's `unsw_katana.config` are that config's own ceilings, not Katana's. Size requests to the job anyway; oversized ones queue longer.
- **Downloads run on the data mover (`katana-dm`) before the job** (Patrick, 2026-10-14). A download needed only mid-run goes in the job script itself.
- **Real-run acceptance** (a ticket's "a real run shows…"): follow `docs/agents/katana-test-run.md`. Build tickets are accepted on what runs without a real run (`bin/check`, the form test, unit tests). Every "a real run shows…" criterion goes in one final real-run ticket (create it under the spec if it has none), blocked by all the others, that does a single real run on the integration branch. The implement-spec skill builds everything else and leaves that ticket open; it runs in a session with Patrick, once they've reviewed the integration branch. A build ticket gets its own real run only when a later ticket depends on what that run shows; that run is part of the build, and the ticket keeps that blocking edge (Patrick, 2026-10-20).
- **Usage tag**: every form's generated header sets `#PBS -A iris-<slug>`, `hello-world` included. It is never a form field. Jobs write nothing for counting; ResTech counts runs per tag from PBS accounting.

## OpenComposer forms

Each live form is `workflows/<slug>/form.yml.erb`, beside its `manifest.yml`, page and code: `hello-world` and `microct-2d-segmentation`. The folder name is the OnDemand URL segment each "Run on Katana" button points at. The system OpenComposer's `apps_dir` points at the system clone's `workflows/`, and `bin/syspull` is the deploy; Patrick's dev OpenComposer serves his dev clone's `workflows/` to test a change first. Planned workflows have no form, so OpenComposer never lists them.

- **A form runs its own clone's code.** It sets `CODE` from `@apps_dir` at render time, the job runs `$CODE/src/...` and writes `git -C "$CODE" rev-parse HEAD` to `commit.txt` in its output directory. No job downloads its own code, and no job loads the `iris` module.
- **`module load iris` puts `iris-view` and `iris-compare` on the PATH**, from the system clone's `module/bin` and nothing else (ADR-0003). Researchers can't read the dev clone, so the module never points at it. `iris-rebuild` and the maintainer tools in `bin/` stay off the PATH and are given as full paths.

`_archive\<slug>\` in the repo keeps the forms of the 28 retired workflows (`mnist-classification`, `cellpose-segmentation` and `qupath-pathology` included). It is public and OpenComposer never serves it.

- **Written is not installed.** A form counts as working only once a real job from `/pun/sys/` has run; cite its job ID.
- **Start a new form from `hello-world`**, the reference schema.
- **Imaging forms fail `check:` with `oc_assert(cond, msg)`**, which re-renders the form with the values kept; `halt 500`, as in `hello-world`, shows a bare error page. Katana's dev OpenComposer is 1.9.0, and `oc_assert` needs 1.4.0.
