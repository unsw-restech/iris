# IRIS — the ResTech AI Imaging Gateway

Landing page and catalogue of UNSW ResTech imaging workflows on Katana.

**Live site**: https://patricktung.github.io/iris

## Structure

```
iris/
├── index.html                        # Landing page (GitHub Pages root)
├── .nojekyll                         # Empty — disables Jekyll processing
├── .gitignore                        # Python bytecode, stray outputs, OS cruft
├── assets/
│   └── iris.css                      # Shared styles for workflow detail pages
├── _archive/<slug>/                  # Retired OpenComposer forms, never served by OpenComposer
├── .github/workflows/check.yml       # CI: runs bin/check on every push
├── ruff.toml                         # The Python lint rules bin/check applies
├── bin/
│   ├── check                         # Every check to pass before committing
│   ├── ciwait                        # Wait for a pushed commit's CI run (desktop)
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
    ├── mnist-classification/         # PyTorch module example
    │   ├── index.html
    │   ├── form.yml.erb, manifest.yml  # OpenComposer form
    │   ├── katana/iris_mnist_classification.pbs, prepare.sh
    │   ├── src/train_mnist.py
    │   └── local/run_local.sh, run_local.ps1
    ├── microct-2d-segmentation/      # Reference workflow, in progress (no page yet)
    │   ├── form.yml.erb, manifest.yml  # OpenComposer form
    │   ├── src/run.py                # Entry point: train, then segment into a run directory
    │   └── tests/                    # Synthetic-dataset, job-library and form tests (see AGENTS.md)
    ├── cellpose-segmentation/index.html   # Planned
    └── qupath-pathology/index.html        # Planned
```

Plain static HTML — no build step, no dependencies. The landing page keeps its styles inline; the workflow detail pages share `assets/iris.css`. The `hello-world` page has its own styles — it's a deliberate variant, not a copy, so don't fold it into the shared sheet.

`hello-world` and `mnist-classification` are the two workflows that ship runnable scripts. `mnist-classification` is the reference for how IRIS provides an environment on Katana: **use a module**. It runs `module purge && module load pytorch/1.13.1` — nothing is installed, nothing large is downloaded, and the module name is a single editable variable at the top of the PBS script.

`torch` is its only dependency. MNIST is parsed straight from the IDX files with the standard library rather than via `torchvision`, which keeps the module sufficient on its own and reduces the download to the 11 MB dataset. Run `katana/prepare.sh` on a login node first — it fetches that dataset where the network is reliable, leaving the job able to run offline.

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

1. Create a folder under `workflows/your-workflow-name/`
2. Add `index.html` — copy the `mnist-classification` page and link `../../assets/iris.css`
3. **Use relative links only** (`../../`, `../../#workflows`). Root-absolute links like `href="/"` resolve outside `/iris/` and 404.
4. Add a card to the workflow grid in `index.html`, with its modality tag
5. Push to `main` — GitHub Pages redeploys automatically

If the workflow ships a `local/run_local.ps1`, **keep it ASCII-only**. These files have no BOM, and Windows PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI — an em dash or box-drawing character decodes into a byte PowerShell treats as a string delimiter, and the script fails to parse before it runs a single line. Use `-` and `=` in banners. The `.sh` files are unaffected.

## Deployment

GitHub Pages is already configured and deploys from the `main` branch. Pushing to `main` publishes. The `check` Actions workflow runs `bin/check` on every push, but it doesn't gate the deploy: run `bin/check` before pushing.

The OpenComposer forms reach Katana separately: OpenComposer's `apps_dir` points at `workflows/` in a clone on Katana, and `git pull` in that clone deploys them. A form runs the code of the clone that served it and records that clone's commit in `commit.txt`.

## Status

`v0.1-alpha`. The "Run on Katana" buttons currently point at the **development** OnDemand instance (`/pun/dev/OpenComposer/...`) while workflows are being validated. Switch these to `/pun/sys/` at launch.

The catalogue is **imaging only**. Each card carries a modality tag and a compute tag; Planned cards are dimmed, labelled Planned and have no Run button. `hello-world` sits outside the catalogue as onboarding.

| Tier | Workflows | What exists |
|---|---|---|
| **Run and verified** | `hello-world` (onboarding), `mnist-classification` (Teaching) | Page, form, job script, executed end to end |
| **Planned** | `cellpose-segmentation` (Microscopy), `qupath-pathology` (Pathology) | Page only, describing what the workflow will do. No form, no Run button |

Both forms moved into the repo on 2026-10-16 and have not yet run from a clone; the runs above were from the old out-of-repo copies.

The microCT reference workflow, `microct-2d-segmentation`, gets its card when its page lands.

IRIS was called ARES until 2026-10-13; the old `patricktung.github.io/ares/` address does not redirect. The catalogue used to list 28 workflows across 11 research domains. The removed pages are recoverable from the `pre-prune` tag, and their OpenComposer forms (with the Planned entries' forms) are kept in `_archive/`.

## Contact

restech@unsw.edu.au
