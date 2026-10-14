# IRIS — project instructions

`AGENTS.md` is the source of truth; `AGENTS.md` is a one-line `@AGENTS.md` import. Edit this file.

IRIS is a static GitHub Pages site: hand-edited HTML with no build system, and it stays that way. `README.md` covers structure, previewing, adding a workflow and the **tier table** of which workflows actually run. Read the tier table before telling anyone a workflow "works": all 28 cards look identical and are marked Active by Patrick's deliberate choice (2026-08-06), but only two have been run.

## Layout

```
IRIS_github_pages\               <- parent directory, not a git repo
├── .agent\available-modules.md <- what is installed on Katana
├── katana-forms-and-manifests\  <- OpenComposer forms, not in the repo
└── ares\                        <- the git repo (github.com/PatrickTung/iris); local directory keeps the old name
```

Renamed from ARES on 2026-10-13. The catalogue still spans 11 domains, most of them not imaging. The old `patricktung.github.io/ares/` address does not redirect.

Working plans go in `plan.md` at the repo root. Delete it when the work is done.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `PatrickTung/iris`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, each named for its role: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.

## Checks before shipping

The site is served from the `/iris/` subpath, so every link is relative (`../../` from a workflow page). Run from the repo root; all should return nothing:

```
grep -rn 'href="/'  . --include=*.html                                           # root-absolute links
grep -n  'href="#"' index.html                                                   # dead placeholder cards
grep -rn 'unsw-restech' . --exclude-dir=.git --exclude=AGENTS.md                 # wrong repo URL
grep -rn 'patricktung-unsw\|ares-pages' . --exclude-dir=.git --exclude=AGENTS.md # stale account / old repo
grep -rn 'workflowhub.eu/projects/24' . --include=*.html                         # wrong project; ours is 472
LC_ALL=C grep -rl '[^ -~]' . --include=*.ps1                                     # non-ASCII breaks PowerShell 5.1

for p in $(grep -oE 'href="workflows/[a-z0-9-]+/"' index.html | sed 's/href="//;s/"//' | sort -u); do
  [ -f "$p/index.html" ] || echo "BROKEN CARD LINK: $p"
done
```

Use `LC_ALL=C` with `[^ -~]` for non-ASCII: `grep -P` exits 2 in this Git Bash, which a `||` chain reads as clean.

## Deploying

Pushing `main` is an immediate public deploy to https://patricktung.github.io/iris/. Confirm with Patrick before pushing unless they've already said to. Pages takes 40–60 seconds; verify against the live site.

**Push auth:** the repo is owned by `PatrickTung`, over HTTPS + Git Credential Manager (no SSH keys). A stale `patricktung-unsw` credential has caused a 403 before, and retrying cannot fix that. Check with `cmdkey /list:git:https://github.com`; clearing it is Patrick's call.

## Deliberate, leave as is

- **`hello-world` is onboarding, not a catalogue entry**: excluded from the grid, the filters and the workflow count, and kept on its own styles rather than `assets/iris.css`.
- **Katana links point at `/pun/dev/`** while pre-launch. Switching to `/pun/sys/` is a known launch task.
- **Two DFT workflows**: `dft-materials` (periodic solids, Quantum ESPRESSO) and `orca-dft` (molecular) are different physics.

**Adding a domain** changes four things together: a `.card-domain.<x>` rule in `index.html`, a matching `.wf-domain.<x>` rule in `iris.css`, a `filterCards('<x>', this)` button, and `data-domain="<x>"` on the card.

## Katana

- **Modules first.** Check `..\.agent\available-modules.md` before designing an environment or naming a module. `workflows/mnist-classification/` is the reference.
- **`module` in batch scripts**: source `/etc/profile.d/modules.sh` first, and run it without `set -u`.
- **Containers** are for software that genuinely isn't installed. Apptainer/Singularity are on the path, not modules, so there is no `module load apptainer`. Docker is unsupported. Cache images in `/srv/scratch/$USER/.images`. Executor is `pbspro`.
- **Limits** (confirmed by Patrick, 2026-08-05): walltime 200 hours, memory 1 TB, no fixed CPU cap. The 24 cpus / 248 GB / 100 h in nf-core's `unsw_katana.config` are that config's own ceilings, not Katana's. Size requests to the job anyway; oversized ones queue longer.
- **Downloads go in a `prepare.sh` run on a login node**; compute nodes may have no outbound internet.
- **Usage logging** targets `/srv/scratch/iris/usage-log`, which has never existed, so no usage has been logged.

## OpenComposer forms

`..\katana-forms-and-manifests\<slug>\` holds one form per workflow, a strict 1:1 match with `workflows\`: the directory name is the OnDemand URL segment each "Run on Katana" button points at. They are copied to the OnDemand host, never published.

- **Exception:** `hello-world` is deployed as `IRIS`, so its page links `OpenComposer/IRIS`.
- **Written is not installed.** Only `hello-world`, `whisper-transcription` and `mnist-classification` are confirmed opening (Patrick, 2026-08-06). The other 26 have never been loaded.
- **`hello-world` is the reference schema.** Match its structure exactly.
- **Every line inside `script: |` stays indented**, which rules out heredocs. Build embedded files with `printf '%s\n'`, as `vllm-inference` does.
- **Use string concatenation inside `check:`.** Ruby `#{}` collides with OpenComposer's own substitution.

## Overclaims in `index.html`

Left because product copy is Patrick's call. Raise them before adding new copy: the hero and step 03 name **Gadi**, and there is a Gadi compute card, but nothing targets Gadi; step 02 describes a params file no workflow ships; step 03 says **Nextflow** handles scheduling, and there is none in the repo.
