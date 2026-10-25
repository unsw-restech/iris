# For workflow authors

How IRIS is built, previewed, extended and deployed. Researchers running workflows want the [README](README.md) instead.

## Structure

```
iris/
├── index.html                        # Landing page (GitHub Pages root)
├── .nojekyll                         # Empty — disables Jekyll processing
├── .gitignore                        # Python bytecode, stray outputs, OS cruft
├── README.md                         # For researchers: what IRIS is and how a run goes
├── CONTRIBUTING.md                   # For workflow authors: this file, with the tier table bin/check reads
├── GLOSSARY.md                       # The domain's terms
├── LICENSE                           # Apache-2.0, for the code and the site
├── CITATION.cff                      # How to cite IRIS; GitHub's "Cite this repository"
├── assets/
│   └── iris.css                      # Shared styles for workflow detail pages and the guide
├── guide/index.html                  # "Using IRIS on Katana": staging and viewing, shared by imaging workflows
├── _archive/<slug>/                  # Retired OpenComposer forms, never served by OpenComposer
├── .github/workflows/check.yml       # CI: runs bin/check on every push
├── .github/ISSUE_TEMPLATE/proposal.yml  # Issue form for a workflow author's proposal
├── .github/pull_request_template.md  # The checklist a workflow PR is ready for review on
├── .githooks/commit-msg              # Refuses AI attribution in a commit message; AGENTS.md turns it on
├── ruff.toml                         # The Python lint rules bin/check applies
├── bin/
│   ├── check                         # Every check to pass before committing
│   ├── ciwait                        # Wait for a pushed commit's CI run (desktop)
│   ├── pageswait                     # Wait for the live site to serve a change (desktop)
│   ├── iris-import                   # Import new runs into your MLflow tracking store
│   ├── iris-compare                  # Import, then compare runs in MLflow (in a Virtual Desktop)
│   ├── iris-rebuild                  # Rebuild a lost tracking store from run directories
│   ├── iris-view                     # View a run's labels over its volume in napari (in a Virtual Desktop)
│   └── qwait                         # Wait for Katana jobs and show how they ended (desktop)
├── envs/imaging/                     # Recipe for the shared imaging environment on Katana (see its README)
├── lib/
│   ├── iris-job.sh                   # Run-time steps every imaging job sources (environment check, venv, run dir, commit)
│   └── iris/                         # Shared Python for imaging workflows: volume reader, label writer, run record, importer, iris-compare, iris-rebuild, iris-view
└── workflows/
    ├── hello-world/                  # Test job — start here (onboarding, not in the catalogue)
    │   ├── index.html
    │   ├── form.yml.erb, manifest.yml  # OpenComposer form
    │   ├── src/hello_world.sh
    │   ├── katana/iris_hello_world.pbs
    │   └── local/run_local.sh, run_local.ps1
    ├── microct-2d-segmentation/      # Reference workflow: copy it to start a new one
    │   ├── index.html
    │   ├── form.yml.erb, manifest.yml  # OpenComposer form
    │   ├── src/run.py                # Entry point: train, then segment into a run directory
    │   └── tests/                    # Synthetic-dataset, job-library and form tests (see AGENTS.md)
    ├── cellpose-segmentation/index.html   # Planned
    └── qupath-pathology/index.html        # Planned
```

Plain static HTML — no build step, no dependencies. The landing page keeps its styles inline; the workflow detail pages and the guide share `assets/iris.css`. The `hello-world` page has its own styles — it's a deliberate variant, not a copy, so don't fold it into the shared sheet.

IRIS jobs use Katana **modules first**. Imaging jobs source `lib/iris-job.sh`, which loads Katana's `python/3.13.2` module and tops it up with the pinned imaging venv from `envs/imaging/`, so nothing is installed when a run starts.

Keep `.nojekyll` in place. Without it, Pages runs Jekyll and would silently drop any future directory beginning with an underscore.

## Local preview

The site is served from the `/iris/` subpath, so preview it that way — serve the **parent** directory:

```
cd ..            # the directory containing iris/
python -m http.server 8000
# open http://localhost:8000/iris/
```

Opening `index.html` directly over `file://` will not reproduce the real base path and will hide broken links.

## Adding a new workflow

The workflow-author checklist. Work on a branch; the dev clone on Katana can check out any branch.

1. **Copy the reference folder**, `workflows/microct-2d-segmentation/`, to `workflows/<slug>/`. To build a Planned workflow, extend its existing folder instead, so its URL never changes.
2. **Change the slug everywhere**: the folder name, `#PBS -A iris-<slug>` in the form's script header, the Experiment name default and the job name default. The folder name is also the OpenComposer URL segment.
3. **Set the environment version** in the form's `ENV_DIR`. If the workflow needs packages the environment lacks, build version *n+1* (`envs/imaging/README.md`); never change a built version.
4. **Set the fields and `check:` rules** in `form.yml.erb`, and the entry point under `src/`. Defaults for memory, walltime and epochs cite the timing run that measured them.
5. **Write the page text** in `index.html`, linking the guide (`../../guide/#stage` and `../../guide/#view`) for staging and viewing rather than repeating its steps. Use relative links only: root-absolute links like `href="/"` resolve outside `/iris/` and 404.
6. **Add the catalogue card** to `index.html`, with its modality tag and compute tag. A new modality also needs a `.card-domain.<x>` style.
7. **Test on dev**: `bin/check` clean, then from the dev clone the form opens, `check:` rejects one wrong dataset folder, and one real run finishes, appears in MLflow after `iris-compare` and opens with its `iris-view` line. Cite the job ID.
8. **Merge to `main` and pull** the dev clone (`git pull --ff-only`). Pushing `main` publishes the site.

If the workflow ships a `local/run_local.ps1`, **keep it ASCII-only**. These files have no BOM, and Windows PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI — an em dash or box-drawing character decodes into a byte PowerShell treats as a string delimiter, and the script fails to parse before it runs a single line. Use `-` and `=` in banners. The `.sh` files are unaffected.

## Deployment

GitHub Pages is already configured and deploys from the `main` branch. Pushing to `main` publishes. The `check` Actions workflow runs `bin/check` on every push, but it doesn't gate the deploy: run `bin/check` before pushing.

The OpenComposer forms reach Katana separately: OpenComposer's `apps_dir` points at `workflows/` in a clone on Katana, and `git pull` in that clone deploys them. A form runs the code of the clone that served it and records that clone's commit in `commit.txt`.

## Status

`v0.1-alpha`. The "Run on Katana" buttons currently point at the **development** OnDemand instance (`/pun/dev/OpenComposer/...`) while workflows are being validated. Switch these to `/pun/sys/` at launch, and remove the README's pre-launch notice; `bin/check` fails if only one is done.

The catalogue is **imaging only**. Each card carries a modality tag and a compute tag; Planned cards are dimmed, labelled Planned and have no Run button. A card reads Active only in the **Run and verified** tier, and Testing in **Run, browser run pending**, which has no workflows at present. `hello-world` sits outside the catalogue as onboarding.

| Tier | Workflows | What exists |
|---|---|---|
| **Run and verified** | `hello-world` (onboarding), `microct-2d-segmentation` (microCT) | Page, form, job script, executed end to end |
| **Planned** | `cellpose-segmentation` (Microscopy), `qupath-pathology` (Pathology) | Page only, describing what the workflow will do. No form, no Run button |

`hello-world` ran from the browser through the dev clone (job 9584951, #53), and so did `microct-2d-segmentation` (job 9577519, #46).

IRIS was called ARES until 2026-10-13; the old `patricktung.github.io/ares/` address does not redirect. The repo moved from `PatrickTung/iris` to `unsw-restech/iris` on 2026-10-23; GitHub redirects the old repo URL, but the old `patricktung.github.io/iris/` site address does not redirect. The catalogue used to list 28 workflows across 11 research domains. The removed pages are recoverable from the `pre-prune` tag, and their OpenComposer forms (with the Planned entries' forms) are kept in `_archive/`. `mnist-classification` was removed the same way on 2026-10-22 (#53): its form is in `_archive/`, the rest under the `pre-mnist-removal` tag.

