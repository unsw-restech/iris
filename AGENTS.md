# IRIS — project instructions

`AGENTS.md` is the source of truth for agent instructions. Edit this file.

IRIS is a static GitHub Pages site: hand-edited HTML with no build system, and it stays that way. `README.md` is for researchers. `CONTRIBUTING.md` covers structure, previewing, adding a workflow and the **tier table** of which workflows actually run. Read the tier table before telling anyone a workflow "works".

**Names:** in chat and in everything you write, the user is "the IRIS maintainer" and ResTech's sysadmin is "the sysadmin". Text from before 2026-11-12 keeps its names, and `IRIS_github_pages\.claude\hooks\people-names.py` refuses an edit, tracker post or commit message that adds one (IRIS maintainer, 2026-11-12).

## Layout

```
IRIS_github_pages\               <- parent directory, not a git repo
├── available-modules.md         <- what is installed on Katana
├── OpenComposer\                <- IRIS's OpenComposer fork (github.com/unsw-restech/OpenComposer), with its own AGENTS.md
└── iris\                        <- this repo (github.com/unsw-restech/iris)
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

Run `bin/check` before committing; CI runs it on every push. It covers the link and URL greps, the form and manifest rules, executable bits, shellcheck, actionlint, ruff and the Python tests, the synthetic-dataset test among them, run on CPU in each workflow's pinned container through `bin/envrun`, whose first run pulls the container with `gh`'s token (`envs/README.md`). Its attribution and conflict-list checks read commit messages, so they see a message only once committed; `.githooks/commit-msg` refuses one first. `.githooks/pre-push` refuses a push to `main` of a tree no full `bin/check` passed on, a merge of a newer `main` included; `IRIS_UNCHECKED=<reason>` lets one through once the IRIS maintainer agrees. Turn the hooks on once per clone: `git config core.hooksPath .githooks`.

A change to a file `bin/katana-test` tests also needs it before committing: the forms, `module/`, the job library and its copies, and the form and job-library tests themselves (its header lists them). It sends the working tree, uncommitted edits included, from any clone or worktree over `ssh katana`, so no push is needed. It runs every form test and the module test, and submits the library's `lib/tests/katana/job_lib.pbs` once and waits for it, since `check:` looks inside `/srv/scratch/$USER` and the module and job-library tests need Environment Modules and `katana_ai_ro` membership. A passing run records the tree it tested, and `.githooks/pre-push` refuses a push to `main` that changes those files untested; `IRIS_KATANA_UNTESTED=<reason>` lets one through once the IRIS maintainer agrees.

## Deploying

Pushing `main` is an immediate public deploy to https://docs.restech.unsw.edu.au/iris/. The org serves its Pages sites under its docs domain, and `unsw-restech.github.io/iris/` redirects there. Confirm with the IRIS maintainer before pushing unless they've already said to. If your sandbox or permissions block the push, give the IRIS maintainer the exact `git push origin <sha>:main` to run, then do the dev-clone pull and the live check yourself. Pushes go `<sha>:main`, so local `main` lags: fetch, then merge, compare and delete branches against `origin/main`. Live-check every push on one changed file outside `.github/`: Pages serves every other file, `_archive/` and dotfiles included (`.nojekyll`). Pages takes 40–60 seconds; run `bin/pageswait <path> <marker>` in the background.

- **CI:** `bin/ciwait <commit>` waits for that commit's `check` run and prints the failed log; `--workflow containers` waits for the container build, printing the digest a publish run pins. Push a change to `.github/` to a branch first. Merge `origin/main` into that branch before its run, so the green run is on the commit `main` becomes, then push that commit to `main`.
- **Dev clone:** after pushing a change to `workflows/`, `lib/` or `bin/iris-*` (researchers run those from the clone), run `ssh katana 'cd ~/iris && git pull --ff-only'` as its own command, so a permission rule scoped to `ssh katana` can match it. The dev clone is the IRIS maintainer's test bed: a change goes `bin/katana-test` where it applies, push, dev pull, then the system clone.
- **System clone:** `/srv/scratch/katana_ai/iris/code/`, beside `envs/` and `wheelhouse/`, since the dev clone's home folder is unreadable to researchers (Patrick, 2026-10-23). The IRIS instance, Katana OnDemand's `OpenComposer` app, serves its `workflows/`, and every Run button opens `https://kod.restech.unsw.edu.au/pun/sys/OpenComposer/<slug>` (ADR-0012). Any git change there (pull, reset, checkout) deploys to the pilot, so it is the OpenComposer deploy. Run `bin/syspull` to list what a pull would deploy, get the IRIS maintainer's go-ahead naming that path and quoting verbatim every commit it lists, then run the `bin/syspull --apply <sha>` line it prints. Run `bin/syspull` before every push request too, and make that request the clone's go-ahead as well: name its path and quote every commit it lists along with the pushed commits. A push whose request skips it leaves the clone behind until some later request asks: on 2026-11-14 it was two doc-only pushes behind (IRIS maintainer, 2026-11-14). After the push, run `bin/syspull` again and ask again only if it lists other commits or names a missing container (Patrick, 2026-11-10).
- **Fork checkouts:** the IRIS instance's and the test instance's checkouts of the fork, `OpenComposer-iris` and `OpenComposer-iris-test` beside the system clone (`lib/katana.sh`), run one pinned fork commit, detached, each with its own `manifest.yml` kept by `skip-worktree` (#170). Katana OnDemand's `OpenComposer` system app serves the first, as the sysadmin set it up, though its folder keeps the `-iris` name; the second is a dev app each workflow author links into their own `~/ondemand/dev` (ADR-0012). Moving them deploys OpenComposer itself to both instances, so they move together, forward along the fork's `main`. Run `bin/ocpull` to list what a move would deploy to each, get the IRIS maintainer's go-ahead naming both paths and quoting verbatim every commit it lists, then run the `bin/ocpull --apply <sha>` line it prints. It moves neither unless both can move, and when a move changes a file a checkout keeps its own copy of, it refuses and prints, for every checkout at once, the steps to take the change by hand. It leaves the dev install alone (#159, #162).
- **Clean up:** the push's last step, once CI is green, the live check has passed and any dev-clone pull is done. From the main clone, run `bin/prune-merged`; it lists the branches and worktrees whose work is in `origin/main`, names each one it skips and why, and ends with the `bin/prune-merged --apply <sha>` line to run, or with `Nothing to remove.` and no `--apply` line, which ends the step. If `--apply` refuses because `origin/main` moved, list again.

**Push auth:** the repo is owned by the `unsw-restech` org and pushed as `PatrickTung` over HTTPS + Git Credential Manager (no SSH keys). A stale `patricktung-unsw` credential has caused a 403 before, and retrying cannot fix that. Check with `cmdkey /list:git:https://github.com`; clearing it is the IRIS maintainer's call.

**Org rights:** the IRIS maintainer is an admin of the repo but only a member of the org. Anything org-level, such as a package's visibility or deletion, org settings or an org-owned secret, needs one of the org's owners (`gh api 'orgs/unsw-restech/members?role=admin' --jq '.[].login'`). Name that dependency before a design rests on it: #99's image was built and published, then dropped, because only an owner could make it public (ADR-0005). GitHub answers a package delete the IRIS maintainer lacks the right for with 404, not 403 (Patrick, 2026-10-27).

## Deliberate, leave as is

- **`AGENTS.md` is the only instructions file** in this repo, in the fork and in `IRIS_github_pages\`: no tool-specific instructions file sits beside one (Patrick, 2026-10-26; the fork's own, 2026-11-11).
- **`hello-world` is onboarding, not a catalogue entry**: excluded from the grid, and kept on its own styles rather than `assets/iris.css`.
- **Planned cards still link to their pages**, keeping the `.planned` style: full colour like Active cards, with no hover lift (Patrick, 2026-10-28).
- **No version tags** on cards: nothing versions a workflow, and each run's `commit.txt` records the code it ran (Patrick, 2026-10-22). A workflow page lists its citable versions by DOI, date and commit, never as a version number (ADR-0002).

**Adding a modality or a lab**: CONTRIBUTING's Scaffold step, after an approved proposal. The catalogue has one section per lab and no filter bar or tabs, so every lab shows at once.

## Katana

- **Pilot until launch.** ResTech set `other::---` on `/srv/scratch/katana_ai`, so only `katana_ai_ro` members (pilot testers) can run IRIS; it opens to everyone once it runs securely (Patrick, 2026-10-23). Securely includes the sysadmin's rule: an app every user can open, the IRIS instance's checkout, is deployed from where no user can write, and perhaps the system clone's forms with it (ADR-0012). Launch removes the pre-launch notices CONTRIBUTING.md's Status lists, all in one commit.
- **Confirm one-way doors first.** Get the IRIS maintainer's explicit go-ahead in chat, naming the exact target, before any one-way door or large blast radius action, on the desktop or on Katana: deleting, overwriting or moving files, `qdel`, `rsync --delete`, or anything recursive over a directory this session did not create (Patrick, 2026-10-14). The exception is what `bin/prune-merged --apply` removes, a worktree with no uncommitted or untracked files, harness worktrees included, and a local branch whose tip is in `origin/main`, which runs as Deploying's **Clean up** step without one. Anything it skips, and any `--force`, still needs the go-ahead (IRIS maintainer, 2026-11-13).
- **`qsub` needs no go-ahead**: name each job and its resources in chat (Patrick, 2026-10-17). Every `qsub` passes `-m abe`, so PBS emails the IRIS maintainer when the job begins, ends or aborts; a local hook may block a `qsub` without it (Patrick, 2026-10-19).
- **Login nodes stay light**: editing, `qsub`, short checks (Patrick, 2026-10-14). Anything that loads CPU, memory or I/O runs as a PBS job. Transfers over 10 GB go through the data mover (`katana-dm`), never a login node or **Files** in Katana OnDemand. The data mover holds each user to 4 GB of memory (its `memory.max`, which killed `microct/1`'s first pull, 2026-11-10), and Katana's `apptainer.conf` gives `mksquashfs` all 64 CPUs, so a container build there passes `--mksquashfs-args`, as `bin/envpull-dm.sh` does.
- **Modules first.** Check `..\available-modules.md` before designing an environment or naming a module. Workflows and the researcher tools run their Python in the environment containers `envs/README.md` describes. `lib/katana.sh` names those, the Python module and the system clone's path once for every script that can source bash; `bin/check` compares the copies that must stay literal with it.
- **`module` in batch scripts**: source `/etc/profile.d/modules.sh` first, and run it without `set -u`.
- **Containers** are for software that genuinely isn't installed. Apptainer/Singularity are on the path, not modules, so there is no `module load apptainer`. Docker is unsupported. Cache containers in `/srv/scratch/$USER/.envs` (Patrick, 2026-11-06). Executor is `pbspro`.
- **GPU models for queued jobs**: A100, H100, H200, L40S, V100. `RP6000` in `pbsnodes` is ResTech's in-house development node and never runs queued jobs (Patrick, 2026-10-14).
- **Limits** (confirmed by Patrick, 2026-08-05): walltime 200 hours, memory 1 TB, no fixed CPU cap. The 24 cpus / 248 GB / 100 h in nf-core's `unsw_katana.config` are that config's own ceilings, not Katana's. Size requests to the job anyway; oversized ones queue longer.
- **Downloads run on the data mover (`katana-dm`) before the job** (Patrick, 2026-10-14). A download needed only mid-run goes in the job script itself.
- **Real-run acceptance** (a ticket's "a real run shows…"): build tickets are accepted on what runs without a real run (`bin/check`, the form test, unit tests). Every "a real run shows…" criterion goes in one final real-run ticket (create it under the spec if it has none), blocked by all the others. The implement-spec skill builds everything else and leaves that ticket open; the IRIS maintainer and a session run it from `/pun/sys/`, after the IRIS maintainer's review, in the order `docs/agents/katana-test-run.md` gives (Patrick, 2026-10-28). A build ticket gets its own real run, from a scratch copy as that doc describes or from `/pun/sys/` when its box names it, only when a later ticket depends on what that run shows; that run is part of the build, and the ticket keeps that blocking edge (Patrick, 2026-10-20).
- **Usage tag**: every form's generated header sets `#PBS -A iris-<slug>`, `hello-world` included. It is never a form field. The library's test jobs in `lib/tests/katana/` set `iris-tests`, so they count towards no workflow (Patrick, 2026-11-03). Jobs write nothing for counting; ResTech counts runs per tag from PBS accounting.

## OpenComposer forms

Each live form is `workflows/<slug>/form.yml.erb`, beside its `manifest.yml`, page and code: `hello-world` and `microct-2d-segmentation`. The folder name is the OnDemand URL segment each "Run on Katana" button points at. The IRIS instance's `apps_dir` is the system clone's `workflows/`, and `bin/syspull` is the deploy; the IRIS maintainer's dev install, `~/ondemand/dev/OpenComposer` on Katana, serves their dev clone's `workflows/` to test a change first. It is a checkout of the fork on the instances' commit, with the test instance's settings and its own `data_dir`, `~/composer/iris-dev` (#170). OnDemand lists a dev app under **Develop**, so a manifest's menu name and category show only on the IRIS instance. Planned workflows have no form, so OpenComposer never lists them.

- **Each workflow runs its own copy of the library's job side** (ADR-0009, superseding part of ADR-0006): `workflows/<slug>/lib/`, which its form sources as `$CODE/lib/iris-job.sh`. `bin/libcopy <slug>` makes or updates it from `HEAD` and records the commit in `lib/copied-from`; `bin/check` fails a copy that differs from `lib/` at that commit, so never edit a copy: change `lib/`, commit, then copy again. A change to the job side reaches a workflow only when it is copied in, so say which workflows you copied it into. The shared side (importer, `iris-view`, `iris-compare`, rebuild, tracking) stays one copy in the clone's `lib/`. CONTRIBUTING.md's "The library's two sides" has the detail.
- **The entry script runs from the pane** (ADR-0006). Each imaging form reads its entry script (`src/run.py`) at render time into a quoted heredoc in `script:`; the job writes it to the run directory as `run.py` and runs that, so a researcher's edit is what runs. The form sets `CODE` from `@apps_dir` and records the clone's commit at render time; between writing `run.py` and running it, the job's `iris_record_code` writes that commit to `commit.txt` and the edits to `run.diff`, through `iris.rundir`, which names every file in a run directory. `hello-world` keeps its plain script. No job downloads its own code, and no job loads the `iris` module.
- **`module load iris` puts `iris-view` and `iris-compare` on the PATH**, from the system clone's `module/bin` and nothing else (ADR-0003). Researchers can't read the dev clone, so the module never points at it. `iris-rebuild` and the maintainer tools in `bin/` stay off the PATH and are given as full paths.

`_archive\<slug>\` in the repo keeps the forms of the 28 retired workflows (`mnist-classification`, `cellpose-segmentation` and `qupath-pathology` included). It is public and OpenComposer never serves it.

- **Written is not installed.** A form counts as working only once a real job from `/pun/sys/` has run; cite its job ID.
- **Start a new form from `hello-world`**, the reference schema.
- **Imaging forms fail `check:` with `oc_assert(cond, msg)`**, which re-renders the form with the values kept; `halt 500`, as in `hello-world`, shows a bare error page. `oc_assert` needs 1.4.0, which the fork passes.
