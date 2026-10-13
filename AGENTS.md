# IRIS — project instructions

This file is project knowledge only. `AGENTS.md` is the source of truth; `AGENTS.md` beside it is a one-line `@AGENTS.md` import, so edit this file and never the mirror.

## Name

The platform is **IRIS — the ResTech AI Imaging Gateway**. It was called ARES ("AI & Research Execution Stack") until 2026-10-13, when Patrick renamed it because that scope was too large. The catalogue itself was not narrowed: it still spans 11 domains, most of them not imaging.

The GitHub repo was renamed `PatrickTung/ares` → `PatrickTung/iris` the same day, which moved the site to `patricktung.github.io/iris/`. The old `/ares/` Pages address does not redirect.

The old name survives only in the parent directory `ARES_github_pages\`, which is outside the repo. The PBS scripts log usage to `/srv/scratch/iris/usage-log`; that directory has never existed under either name, so no usage has been logged yet.

## Layout

```
ARES_github_pages\      <- parent directory, NOT a git repo
├── .agent\            <- the coding agent settings + available-modules.md
├── katana-forms-and-manifests\   <- OpenComposer apps, NOT in the repo
└── iris\               <- THE GIT REPO (github.com/PatrickTung/iris)
    ├── AGENTS.md       <- this file
    ├── AGENTS.md       <- mirror: imports AGENTS.md
    └── docs\agents\    <- config the engineering skills read
```

Paths below written as `iris/...` or `iris\...` are relative to the parent directory; `..\` paths are relative to the repo root.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `PatrickTung/iris`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, each named for its role: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.

## OpenComposer forms

`..\katana-forms-and-manifests\<slug>\` holds `form.yml.erb` + `manifest.yml` for every workflow, one directory per site slug — **29 of each, a strict 1:1 match with `iris\workflows\`**. Keep that match: the directory name becomes the OnDemand URL segment, which is what each page's "Run on Katana" button points at.

**One exception:** `hello-world`'s page links `OpenComposer/IRIS`, not `OpenComposer/hello-world`. That is correct — the app is deployed under the name `IRIS` (confirmed by Patrick, 2026-10-13; it was `ARES` before the rename). So the local form directory `hello-world` is copied to the host as `IRIS`. Every other page matches its directory exactly.

These are **not** in the git repo and are not published. They get copied to the OnDemand host's OpenComposer `apps` directory.

**Install status matters and differs from the files existing.** All 29 form definitions are written; only **three** are confirmed installed and opening in OpenComposer — `hello-world`, `whisper-transcription`, `mnist-classification` (verified by Patrick, 2026-08-06). The other 26 were generated on 2026-08-06 and have never been loaded, so their tool invocations are best-effort from documentation.

`hello-world` is the reference schema. Match it exactly:

- top-level keys are `form`, `script`, `check` — nothing else
- validation uses `halt 500, "..."`, not `oc_assert(...)`
- `script: |` is a flat block scalar, not nested under `label:`/`content:`
- form values interpolate as `#{field}`; ERB (`<%= %>`) is evaluated when the page renders
- paired widgets expose `_1`/`_2` suffixes — `time_1`, `time_2`, `logname_1`, `logname_2`

Three traps, all of which cost real time:

1. **Everything inside `script: |` must stay indented.** A line at column 0 ends the block and YAML parsing fails. This rules out heredocs for embedded Python — build the file with `printf '%s\n'` instead, as `vllm-inference` does.
2. **Avoid Ruby `#{}` interpolation inside `check:`.** It collides with OpenComposer's own substitution. Use string concatenation.
3. **`module` trips `set -u`.** The generated scripts use `set -eo pipefail`, deliberately without `-u`.

To regenerate en masse, the throwaway generator lives in the session scratchpad (`gen_forms.py` + `gen_forms_data.py`), not the repo. Hand-editing a single form is fine and expected.

`iris\.gitignore` exists (added 2026-08-05, at Patrick's request) and covers build and OS artifacts only — `__pycache__/`, stray workflow outputs, `.DS_Store`. It does not ignore any agent file, so plans and scratch files show up as untracked. `__pycache__/` was the real driver: the MNIST workflow ships a Python script users run from a checkout, and it reappeared three times in one session.

Patrick wants working plans at `plan.md` (lowercase, repo root, beside this file) rather than left in `~\.agent\plans\` under an auto-generated name. Delete `plan.md` once the work is done — a stale plan is worse than none, and anything durable belongs here or in memory instead.

## What this is

IRIS ("the ResTech AI Imaging Gateway") — a static landing page and workflow catalogue for UNSW ResTech. Researchers browse validated pipelines (RNA-seq, variant calling, AlphaFold2, climate downscaling, MNIST image classification) and launch them on the Katana HPC via Open OnDemand / OpenComposer.

Static HTML5. **No build system, no dependencies, no CI, no tests.** Editing means editing `.html` files directly, and the repo must stay that way. (Nineteen pages were emitted on 2026-08-06 by a one-off script kept *outside* the repo — the committed output is still plain hand-editable HTML. Don't add a generator to the repo, and don't assume a page can be regenerated: edit it directly.) Google Fonts is the only external dependency.

Deployed by GitHub Pages from branch `main` of `PatrickTung/iris` → **https://patricktung.github.io/iris/**. There is no Actions workflow; pushing to `main` deploys.

## Hard rule: no root-absolute links

The site is served from the **`/iris/` subpath**, not a domain root. So `href="/"` resolves to `patricktung.github.io/` — a 404, not the IRIS home page.

**Always use relative paths.** From a workflow page (2 levels down) that means `../../` and `../../#workflows`. This was the cause of a production bug where every workflow page's nav logo, breadcrumb and "Back to catalogue" link was dead. Don't reintroduce it.

## Previewing

```
cd C:\Users\Patrick\Downloads\ARES_github_pages
python -m http.server 8000
# open http://localhost:8000/iris/
```

Serve the **parent** directory, not `iris\`. That puts the site at `/iris/`, reproducing the real base path exactly. Opening `index.html` over `file://` does not reproduce it and will hide link bugs.

Useful checks before shipping — all should return nothing:

```
grep -rn 'href="/'  iris/ --include=*.html                      # root-absolute links
grep -rn 'href="#"' iris/index.html                             # dead placeholder cards
grep -rn 'unsw-restech' iris/ --exclude-dir=.git --exclude=AGENTS.md                # wrong repo URL
grep -rn 'patricktung-unsw\|ares-pages' iris/ --exclude-dir=.git --exclude=AGENTS.md  # stale account / old repo (404s)
grep -rn 'workflowhub.eu/projects/24' iris/ --include=*.html    # wrong WorkflowHub project
LC_ALL=C grep -rl '[^ -~]' iris/ --include=*.ps1                # non-ASCII breaks PowerShell 5.1

# every card links to a page that exists (28 cards, 29 dirs — hello-world isn't carded)
for p in $(grep -oE 'href="workflows/[a-z0-9-]+/"' iris/index.html | sed 's/href="//;s/"//' | sort -u); do
  [ -f "iris/$p/index.html" ] || echo "BROKEN CARD LINK: $p"
done
```

The last three each correspond to a bug that actually shipped. Note the flags — they are not decoration:

- `--exclude-dir=.git` matters because commit messages in `.git/` mention the very strings being grepped for, and match otherwise.
- `--exclude=AGENTS.md` is there for the same reason: this file names those strings and now sits inside `iris/`.
- `--include=*.html` on the WorkflowHub check keeps it from matching `README.md`, which documents the bug.
- `LC_ALL=C` with `[^ -~]` is the portable non-ASCII test. **`grep -P` does not work here** — this Git Bash build reports "`-P` supports only unibyte and UTF-8 locales" and exits 2, which a `||` chain silently reads as "clean". A check that can't fail is worse than no check.

## Deploying

Pushing `main` publishes; there's no Actions workflow and no staging. Pages takes roughly 40–60 seconds to serve the new build, so verify against the live site rather than assuming — poll for a file the commit changed, then check the actual fix:

```
curl -s -o /dev/null -w '%{http_code}' https://patricktung.github.io/iris/assets/iris.css
```

Because a push is an immediate public deploy, confirm with Patrick before pushing unless they've already said to.

**Push auth:** two GitHub accounts are in play. The repo is owned by **`PatrickTung`**; a stale `patricktung-unsw` credential in Windows Credential Manager caused `403 Permission to PatrickTung/ares.git denied` on 2026-08-05. There are no SSH keys (`~/.ssh` holds only `known_hosts`), so HTTPS + Git Credential Manager is the only path. If a push 403s, check what's stored before retrying — retrying cannot fix it:

```
cmdkey /list:git:https://github.com     # empty output = cleared, next push will prompt
```

Clearing it is Patrick's call, not something to do unasked.

## Conventions

- **Shared CSS** is `iris/assets/iris.css`, linked by all 28 workflow detail pages (every one except `hello-world`). `index.html` keeps its landing-specific styles inline. Workflow pages are thin templates (~43 lines) — if you're editing CSS in more than one workflow page, it belongs in the stylesheet instead.
- **`hello-world` is deliberately NOT on the shared stylesheet.** It looks similar but is a genuine variant: 800px page width vs 900px, `.badge`/`.desc`/`h1` instead of `.wf-domain`/`.wf-desc`/`.wf-title`, a 3-column meta grid, and `.output-box` instead of `.param-table`. Folding it in would mean changing its appearance or piling on overrides. This was checked by diff on 2026-08-04 — don't redo it.
- **Adding a workflow**: create `workflows/<name>/index.html` (copy an existing one), link `../../assets/iris.css`, add a card to the grid in `index.html`, and bump the stats-bar count. Relative links only. If it introduces a **new domain**, four things must change together or it renders wrong: a `.card-domain.<x>` rule in `index.html`, a matching `.wf-domain.<x>` in `iris.css`, a `filterCards('<x>', this)` button, and `data-domain="<x>"` on the card. Check the module actually exists in `..\.agent\available-modules.md` before naming it.
- **`.nojekyll`** (empty file, repo root) turns off Jekyll processing so Pages serves the tree as-is. Don't delete it — without it any future `_`-prefixed directory would be silently dropped.
- **Canonical repo URL** is `github.com/PatrickTung/iris`. Not `unsw-restech/ares` — that org doesn't hold this repo.
- **Katana links intentionally point at `/pun/dev/`** (the development OnDemand instance), not `/pun/sys/`. This is deliberate pre-launch, confirmed 2026-08-04 — don't "fix" it. Switching all 28 workflow pages to `/pun/sys/` is a known launch task.
- **WorkflowHub**: the UNSW ResTech project is **`https://workflowhub.eu/projects/472`**. Verified against the WorkflowHub API on 2026-08-05: id 472 is titled "UNSW ResTech", 1 member, **0 workflows**. This file previously said project **24** — that is `usegalaxy-eu`, the European Galaxy Team, an unrelated org. All three links in `iris/index.html` were corrected on 2026-08-05. The old `workflowhub.eu/projects/ares` slug never existed.
- **PowerShell scripts must be ASCII-only.** Windows PowerShell 5.1 reads a UTF-8 file without a BOM as ANSI, so an em dash or box-drawing character decodes into a byte it treats as a string delimiter — the script fails to parse and can never run. `hello-world/local/run_local.ps1` shipped broken this way until 2026-08-05. Use `-` and `=` in `.ps1` banners, never `—` or `═`. The `.sh` files are unaffected; leave their box drawing alone.
- **Environments on Katana: modules first.** `..\.agent\available-modules.md` is the list of what is actually installed — **check it before designing an environment**. It already carries `pytorch/1.13.1`, `tensorflow/2.11.0`, `python/3.10.8(default)`, `cuda/*`, `cudnn/*`, `opencv/4.6.0`, `nextflow/22.10.1`–`25.10.4` and much else. A module costs nothing to download; prefer it to anything you have to fetch. `workflows/mnist-classification/` is the reference: `module purge && module load pytorch/1.13.1`, with the module name as a single editable variable at the top of the PBS script. Two gotchas that cost real time: `module` is a shell function and may not exist in a batch shell (source `/etc/profile.d/modules.sh` first), and module scripts reference unset variables, so wrap `module` calls in `set +u` / `set -u`.
- **Containers on Katana** — verified 2026-08-05 against `https://nf-co.re/configs/unsw_katana/`, which is nf-core's institutional config for this cluster:
  - Apptainer/Singularity **are** available, but **not as modules** — `available-modules.md` has zero matches for apptainer, singularity, podman or docker. Never write `module load apptainer`; it silently does nothing useful.
  - **Docker is not supported on Katana at all.**
  - If a container is genuinely required, cache it to **`/srv/scratch/$USER/.images`** — the established convention — not a bespoke path.
  - Executor is `pbspro`.
- **Katana resource limits** — confirmed by Patrick (UNSW ResTech), 2026-08-05:
  - **Walltime: 200 hours**
  - **Memory: 1 TB**
  - **CPU cores: no fixed cap**
  - Do **not** quote the numbers in nf-core's `unsw_katana.config` (24 cpus / 248 GB / 100 h) as the cluster's limits — I made that mistake. Those are `max_cpus`/`max_memory`/`max_time` *ceilings that config imposes on its own pipelines*, deliberately conservative, not what Katana permits. Same for its GPU block (6 CPU / 125 GB): that is one profile's request shape, not a cap.
  - Being able to ask for a lot is not a reason to. `mnist-classification` requests `ncpus=4:mem=16gb:ngpus=1` with 30 min walltime, which is right for a job that finishes in under a minute — oversized requests just queue longer.
  - Prefer a module. A container is justified when the software genuinely isn't installed, not by default — `mnist-classification` shipped a 3.8 GB image to process 11 MB of data before this was checked.
- Ship a `prepare.sh` that does any download on a **login node**, so the job itself survives a compute node with no outbound internet.
- Contact is `restech@unsw.edu.au`.

## Page structure

The landing page runs: hero → stats bar → **Start here** (`#start-here`, links `workflows/hello-world/` as onboarding) → **Workflow catalogue** (`#workflows`) → How it works → Compute.

`hello-world` is onboarding, not a catalogue entry — it's deliberately excluded from the workflow grid, the domain filters and the "validated workflows" count.

Cards for workflows without a detail page use `<div class="workflow-card planned">`, not `<a href="#">`, and are labelled **Planned**. `filterCards()` selects by class rather than tag, so filtering still works on them.

## State

`v0.1-alpha`, single author. Expanded for an MVP demo: **28 catalogue cards across 11 domains, all marked Active**, every one clickable to a detail page. Stats bar reads 28 / 11 / 3.

**All 28 look identical on the site, but three very different things sit behind them. Know which is which before telling anyone a workflow "works":**

1. **Run and verified** — `hello-world`, `mnist-classification`.
2. **Scripted, never executed** — `whisper-transcription`, `openfoam-cavity`, `r-statistics`, `dft-materials`. Real PBS scripts against real modules; `bash -n` passes; nobody has run them on Katana.
3. **Page only, no code** — the remaining 23. Nineteen of these were generated on 2026-08-06 by a throwaway script (`gen_pages.py`, kept in the session scratchpad, not the repo) from a data table, so a demo could click every card. They are specifications: module-accurate and plausible, but nothing runs. The other **four** (`rna-seq-pipeline`, `variant-calling`, `alphafold-batch`, `climate-downscaling`) predate this and never had code either.

Patrick chose all-Active on 2026-08-06 knowing the trade-off, after being shown the alternative of keeping them Planned. That is a deliberate decision, not an oversight — don't "fix" it back. But it does mean the site no longer distinguishes tiers, so this file and `iris/README.md` are the only record.

`cellpose-segmentation` is the one entry whose tool has **no** Katana module — Cellpose is pip-only, and its page says so. Every other page names a module verified present in `..\.agent\available-modules.md`.

Domains and their accent colours are defined twice and must be kept in step: `.card-domain.*` in `index.html` and `.wf-domain.*` in `assets/iris.css`.

**Two DFT workflows exist and are not duplicates.** `dft-materials` (Engineering) is plane-wave DFT for periodic solids with Quantum ESPRESSO; `orca-dft` (Chemistry) is molecular DFT for isolated systems. Different codes, different physics — don't merge them.

**Fixed 2026-08-05** (audit): the WorkflowHub links now point at `projects/472` (all three: nav, catalogue header, footer); the fabricated **DOI** stat was removed from the stats bar, which now reads 5 / 4 / 3; and the two "How it works" DOI claims were corrected. Step 01 also claimed searching "by tool, or compute target" and "example inputs" — the filter bar only filters by domain, and `params.example.yml` is still Planned, so that copy was rewritten too.

**Still overclaiming in `iris/index.html` — not fixed, because rewriting product copy is Patrick's call:**

1. Line ~527 (hero): "Find, cite, and run validated pipelines on Katana, **Gadi**, or your own hardware — with no setup required." Nothing targets Gadi.
2. Line ~724 (step 02): "**Clone the workflow repo and edit the params file.** Every parameter is documented with defaults and valid ranges." No workflow ships a params file — `params.example.yml` is Planned. The real flow is the OnDemand form.
3. Line ~729 (step 03): "One command to run on Katana or Gadi. **Nextflow** handles job scheduling, retries, and resource allocation automatically." There is no Nextflow anywhere in the repo; `main.nf` is Planned. `mnist-classification` uses plain PBS + a module. Note though that this claim is more achievable than the others: Katana carries `nextflow/22.10.1`–`25.10.4` modules and nf-core already publishes a working `unsw_katana` profile, so `nextflow run <pipeline> -profile singularity,unsw_katana` is a real option if IRIS ever wants it.
4. Line ~757: a Gadi compute card.

These are the same class of overclaim as the DOI stat. Raise them before adding new copy.

**Also open:** `mnist-classification` has no OpenComposer form yet, so its "Run on Katana" button is a dead end; the page documents a working `prepare.sh` + `qsub` path instead. Its PBS resource line (`ncpus=4:mem=16gb:ngpus=1`) is an unverified guess at Katana's GPU node shape.
