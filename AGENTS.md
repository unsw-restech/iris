# IRIS — project instructions

`AGENTS.md` is the source of truth for agent instructions. Edit this file.

IRIS is a static GitHub Pages site: hand-edited HTML with no build system, and it stays that way. `README.md` covers structure, previewing, adding a workflow and the **tier table** of which workflows actually run. Read the tier table before telling anyone a workflow "works": the catalogue has one Run-able workflow (`mnist-classification`) and two Planned ones with no form, and only `mnist-classification` and the onboarding `hello-world` have ever run.

## Layout

```
IRIS_github_pages\               <- parent directory, not a git repo
├── available-modules.md         <- what is installed on Katana
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

for f in $(find workflows -name form.yml.erb); do                                # usage tag matches the folder
  d=$(basename "$(dirname "$f")")
  tr -d '\r' < "$f" | grep -qx "  #PBS -A iris-$d" || echo "MISSING USAGE TAG: $f"
done

for p in $(grep -oE 'href="workflows/[a-z0-9-]+/"' index.html | sed 's/href="//;s/"//' | sort -u); do
  [ -f "$p/index.html" ] || echo "BROKEN CARD LINK: $p"
done
```

Any change to `lib/` or to an imaging workflow's `src/` also needs the synthetic-dataset test to pass in the desktop CPU venv (`envs/imaging/desktop.sh` builds it):

```
~/.venvs/iris-imaging/bin/python -m unittest discover -s workflows/microct-2d-segmentation/tests
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
- **Usage tag**: every form's generated header sets `#PBS -A iris-<slug>`, `hello-world` included. It is never a form field. Jobs write nothing for counting; ResTech counts runs per tag from PBS accounting.

## OpenComposer forms

Each live form is `workflows/<slug>/form.yml.erb`, beside its `manifest.yml`, page and code: `hello-world` and `mnist-classification`. The folder name is the OnDemand URL segment each "Run on Katana" button points at. Patrick's dev OpenComposer's `apps_dir` points at his dev clone's `workflows/`, and a `git pull` there is the deploy. Planned workflows have no form, so OpenComposer never lists them.

- **A form runs its own clone's code.** It sets `CODE` to `File.expand_path(File.join(@apps_dir, @OC_DIR_NAME))` at render time, the job runs `$CODE/src/...` and writes `git -C "$CODE" rev-parse HEAD` to `commit.txt` in its output directory. Guard the expression: OpenComposer re-reads the form on submit with `@apps_dir` unset (it submits the script rendered on GET). No job downloads its own code.
- **Manifests use built-in icon names** (`bi-...`). Local icon files don't resolve with an absolute `apps_dir`.

`_archive\<slug>\` in the repo keeps the forms of the 25 pruned workflows and of the two Planned ones. It is public and OpenComposer never serves it.

- **Written is not installed.** `hello-world` is confirmed opening and running from the dev clone (job 9543031, 2026-10-17). `mnist-classification` was confirmed only from the old out-of-repo copy (Patrick, 2026-08-06).
- **`hello-world` is the reference schema.** Match its structure exactly.
- **Every line inside `script: |` stays indented**, which rules out heredocs. Build embedded files with `printf '%s\n'`, as `_archive\vllm-inference` does.
- **Use string concatenation inside `check:`.** Ruby `#{}` collides with OpenComposer's own substitution.
