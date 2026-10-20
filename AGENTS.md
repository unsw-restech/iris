# IRIS — project instructions

`AGENTS.md` is the source of truth for agent instructions. Edit this file.

IRIS is a static GitHub Pages site: hand-edited HTML with no build system, and it stays that way. `README.md` covers structure, previewing, adding a workflow and the **tier table** of which workflows actually run. Read the tier table before telling anyone a workflow "works".

## Layout

```
IRIS_github_pages\               <- parent directory, not a git repo
├── available-modules.md         <- what is installed on Katana
└── iris\                        <- the git repo (github.com/PatrickTung/iris)
    └── _archive\                <- retired forms, public but never served by OpenComposer
```

Working plans go in `plan.md` at the repo root. Delete it when the work is done.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `PatrickTung/iris`, via the `gh` CLI. Read `docs/agents/issue-tracker.md` before the first `gh` call.

### Triage labels

The five default labels, each named for its role: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.

### Tickets

- **Keep the ticket graph wide.** A ticket is blocked only by a ticket whose output it uses, never by one that just comes before it in the plan. Tickets that touch separate files don't block each other, so `/implement-spec` can build them in parallel (Patrick, 2026-10-20).

## Checks before shipping

Run `bin/check` before committing; CI runs it on every push. It covers the link and URL greps, the form and manifest rules, executable bits, shellcheck, ruff and the synthetic-dataset test, which needs the desktop CPU venv (`envs/imaging/desktop.sh` builds it).

A change to `microct-2d-segmentation/form.yml.erb` also needs its form test, which runs on Katana because `check:` looks inside `/srv/scratch/$USER`. Run it from a copy of the working tree in scratch, so the dev clone is never touched:

```
module load ruby/3.2.0 && ruby workflows/microct-2d-segmentation/tests/test_form.rb
```

## Deploying

Pushing `main` is an immediate public deploy to https://patricktung.github.io/iris/. Confirm with Patrick before pushing unless they've already said to. If auto mode blocks the push, give Patrick the exact `! git push origin <sha>:main` to run, then take the dev-clone pull and the live check yourself. Live-check every push on one changed file outside `.github/`: Pages serves every other file, `_archive/` and dotfiles included (`.nojekyll`). Pages takes 40–60 seconds; run `bin/pageswait <path> <marker>` in the background.

- **CI:** `bin/ciwait <commit>` waits for that commit's `check` run and prints the failed log. Push a change to `.github/` to a branch first. Merge `origin/main` into that branch before its run, so the green run is on the commit `main` becomes, then push that commit to `main`.
- **Dev clone:** after pushing a change to `workflows/` or `lib/`, run `ssh katana 'cd ~/iris && git pull --ff-only'` as its own command, so the `ssh katana` allow rule matches it. That pull is the OpenComposer deploy.

**Push auth:** the repo is owned by `PatrickTung`, over HTTPS + Git Credential Manager (no SSH keys). A stale `patricktung-unsw` credential has caused a 403 before, and retrying cannot fix that. Check with `cmdkey /list:git:https://github.com`; clearing it is Patrick's call.

## Deliberate, leave as is

- **`hello-world` is onboarding, not a catalogue entry**: excluded from the grid, and kept on its own styles rather than `assets/iris.css`.
- **Katana links point at `/pun/dev/`** while pre-launch. Switching to `/pun/sys/` is a known launch task; its clone goes in `/srv/scratch/katana_ai/iris/` (Patrick, 2026-10-19), since the dev clone's home folder is unreadable to researchers.
- **Planned cards still link to their pages**, keeping the dimmed `.planned` style with no hover lift.

**Adding a modality** takes a `.card-domain.<x>` rule in `index.html` and `<span class="card-domain <x>">` as the modality tag on the card. There is no filter bar.

## Katana

- **Login nodes stay light**: editing, `qsub`, short checks (Patrick, 2026-10-14). Anything that loads CPU, memory or I/O runs as a PBS job. Transfers over 10 GB go through the data mover (`katana-dm`), never a login node or the OnDemand Files app.
- **Modules first.** Check `..\available-modules.md` before designing an environment or naming a module. `workflows/mnist-classification/` is the reference.
- **`module` in batch scripts**: source `/etc/profile.d/modules.sh` first, and run it without `set -u`.
- **Containers** are for software that genuinely isn't installed. Apptainer/Singularity are on the path, not modules, so there is no `module load apptainer`. Docker is unsupported. Cache images in `/srv/scratch/$USER/.images`. Executor is `pbspro`.
- **GPU models for queued jobs**: A100, H100, H200, L40S, V100. `RP6000` in `pbsnodes` is ResTech's in-house development node and never runs queued jobs (Patrick, 2026-10-14).
- **Limits** (confirmed by Patrick, 2026-08-05): walltime 200 hours, memory 1 TB, no fixed CPU cap. The 24 cpus / 248 GB / 100 h in nf-core's `unsw_katana.config` are that config's own ceilings, not Katana's. Size requests to the job anyway; oversized ones queue longer.
- **Downloads run on the data mover (`katana-dm`) before the job** (Patrick, 2026-10-14). A download needed only mid-run goes in the job script itself. `mnist-classification`'s `prepare.sh` still assumes a login node.
- **Real-run acceptance** (a ticket's "a real run shows…"): follow `docs/agents/katana-test-run.md`. Build tickets are accepted on what runs without a real run (`bin/check`, the form test, unit tests). Every "a real run shows…" criterion goes in one final real-run ticket (create it under the spec if it has none), blocked by all the others, that does a single real run on the integration branch. `/implement-spec` builds everything else and leaves that ticket open; it runs in a session with Patrick, once they've reviewed the integration branch. A build ticket gets its own real run only when a later ticket depends on what that run shows; that run is part of the build, and the ticket keeps that blocking edge (Patrick, 2026-10-20).
- **Usage tag**: every form's generated header sets `#PBS -A iris-<slug>`, `hello-world` included. It is never a form field. Jobs write nothing for counting; ResTech counts runs per tag from PBS accounting.

## OpenComposer forms

Each live form is `workflows/<slug>/form.yml.erb`, beside its `manifest.yml`, page and code: `hello-world`, `mnist-classification` and `microct-2d-segmentation`. The folder name is the OnDemand URL segment each "Run on Katana" button points at. Patrick's dev OpenComposer's `apps_dir` points at his dev clone's `workflows/`, and a `git pull` there is the deploy. Planned workflows have no form, so OpenComposer never lists them.

- **A form runs its own clone's code.** It sets `CODE` from `@apps_dir` at render time, the job runs `$CODE/src/...` and writes `git -C "$CODE" rev-parse HEAD` to `commit.txt` in its output directory. No job downloads its own code. Researchers' commands run from that clone too: the job output and the Experiment help print `<clone>/bin/iris-view` and `<clone>/bin/iris-compare` in full, and nothing goes on the PATH.

`_archive\<slug>\` in the repo keeps the forms of the 25 pruned workflows and of the two Planned ones. It is public and OpenComposer never serves it.

- **Written is not installed.** A form counts as working only once a real job from the dev clone has run; cite its job ID.
- **Start a new form from `hello-world`**, the reference schema.
- **Imaging forms fail `check:` with `oc_assert(cond, msg)`**, which re-renders the form with the values kept; `halt 500`, as in `hello-world`, shows a bare error page. Katana's dev OpenComposer is 1.9.0, and `oc_assert` needs 1.4.0.
