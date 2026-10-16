# IRIS — project instructions

`AGENTS.md` is the source of truth for agent instructions. Edit this file.

IRIS is a static GitHub Pages site: hand-edited HTML with no build system, and it stays that way. `README.md` covers structure, previewing, adding a workflow and the **tier table** of which workflows actually run. Read the tier table before telling anyone a workflow "works": the catalogue has one Run-able workflow (`mnist-classification`) and two Planned ones with no form, and only `mnist-classification` and the onboarding `hello-world` have ever run.

## Layout

```
IRIS_github_pages\               <- parent directory, not a git repo
├── available-modules.md         <- what is installed on Katana
├── katana-forms-and-manifests\  <- OpenComposer forms, not in the repo
└── iris\                        <- the git repo (github.com/PatrickTung/iris)
    └── _archive\                <- retired forms, kept but never served
```

Renamed from ARES on 2026-10-13. Pruned to imaging on 2026-10-16: the 25 removed workflow pages are recoverable from the `pre-prune` tag. The old `patricktung.github.io/ares/` address does not redirect.

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
perl -ne 'if (/[^\x00-\x7f]/) { print "$ARGV\n"; close ARGV }' $(find . -name '*.ps1' -not -path './.git/*')  # non-ASCII breaks PowerShell 5.1

for p in $(grep -oE 'href="workflows/[a-z0-9-]+/"' index.html | sed 's/href="//;s/"//' | sort -u); do
  [ -f "$p/index.html" ] || echo "BROKEN CARD LINK: $p"
done
```

Check non-ASCII with perl, not grep. `grep -P` exits 2 in Git Bash, which a `||` chain reads as clean. `[^ -~]` flags every line of a CRLF working copy (`core.autocrlf` is on). And WSL's grep missed a real non-ASCII byte with both `[^[:print:][:space:]]` and a `\x80-\xff` range.

## Deploying

Pushing `main` is an immediate public deploy to https://patricktung.github.io/iris/. Confirm with Patrick before pushing unless they've already said to. Pages takes 40–60 seconds; verify against the live site.

**Push auth:** the repo is owned by `PatrickTung`, over HTTPS + Git Credential Manager (no SSH keys). A stale `patricktung-unsw` credential has caused a 403 before, and retrying cannot fix that. Check with `cmdkey /list:git:https://github.com`; clearing it is Patrick's call.

## Deliberate, leave as is

- **`hello-world` is onboarding, not a catalogue entry**: excluded from the grid, and kept on its own styles rather than `assets/iris.css`.
- **Katana links point at `/pun/dev/`** while pre-launch. Switching to `/pun/sys/` is a known launch task.
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
- **Usage logging** targets `/srv/scratch/iris/usage-log`, which has never existed, so no usage has been logged.

## OpenComposer forms

`..\katana-forms-and-manifests\<slug>\` is where the live forms come from, `hello-world` and `mnist-classification` (it still holds copies of the archived ones too): the directory name is the OnDemand URL segment each "Run on Katana" button points at. They are copied to the OnDemand host. Planned workflows have no form.

`_archive\<slug>\` in the repo keeps the forms of the 25 pruned workflows and of the two Planned ones. It is public and OpenComposer never serves it. Their originals are still in `..\katana-forms-and-manifests\`; deleting them is Patrick's call.

- **Exception:** `hello-world` is deployed as `IRIS`, so its page links `OpenComposer/IRIS`.
- **Written is not installed.** Only `hello-world` and `mnist-classification` are confirmed opening (Patrick, 2026-08-06).
- **`hello-world` is the reference schema.** Match its structure exactly.
- **Every line inside `script: |` stays indented**, which rules out heredocs. Build embedded files with `printf '%s\n'`, as `_archive\vllm-inference` does.
- **Use string concatenation inside `check:`.** Ruby `#{}` collides with OpenComposer's own substitution.
