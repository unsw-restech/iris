# For workflow authors

This file is for workflow authors: anyone with a Katana account who adds or changes a workflow, whether you work in ResTech or not. It covers how IRIS is built, previewed, extended and deployed, and takes a new workflow from an approved proposal to its DOI. Researchers running workflows want the [README](README.md) instead. Deciding whether to propose a workflow? The [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/) says who can, what you get and what gets accepted; this file is the technical checklist behind it.

## From proposal to DOI

You need no write access to the repo. The flow, with who does each step:

1. **Propose** (you): file a proposal through the proposal issue form on [GitHub Issues](https://github.com/unsw-restech/iris/issues/new/choose), before building anything. Proposals open at launch.
2. **Approve** (maintainer): the maintainer approves it with a comment and the `approved` label, or declines it by closing it as `wontfix`.
3. **Build on a fork** (you): fork `unsw-restech/iris`, make a branch on your fork, and follow [Adding a new workflow](#adding-a-new-workflow) below. Run `bin/check`, and `qsub` the job from your own clone on Katana.
4. **Open a PR** (you) from your fork's branch into `main`, citing the approved proposal's number and your `qsub` run's job ID, and filling in the PR template's checklist.
5. **Review, browser run and merge** (maintainer): the maintainer reviews the PR, builds a new environment version if it asked for packages, does the browser run from the dev clone and merges.
6. **Register and mint** (you, now the workflow owner): register the workflow on WorkflowHub and mint its first citable version ([below](#registering-on-workflowhub)).

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
│   ├── qwait                         # Wait for Katana jobs and show how they ended (desktop)
│   └── workflowhub-microct-2d-segmentation  # Walkthrough registering it on WorkflowHub; copy it for another workflow (desktop)
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

The workflow-author checklist. Work on a branch of your fork, cloned on Katana as well as wherever you edit; the maintainer's dev clone fetches your PR's branch for the browser run.

1. **Copy the reference folder**, `workflows/microct-2d-segmentation/`, to `workflows/<slug>/`. To build a Planned workflow, extend its existing folder instead, so its URL never changes.
2. **Change the slug everywhere**: the folder name, `#PBS -A iris-<slug>` in the form's script header, the Experiment name default and the job name default. The folder name is also the OpenComposer URL segment.
3. **Set the environment version** in the form's `ENV_DIR`. If the workflow needs packages the environment lacks, request them ([Requesting packages](#requesting-packages)); never change a built version.
4. **Set the fields and `check:` rules** in `form.yml.erb`, and the entry point under `src/`. Add a synthetic-dataset test under `tests/`, as the reference workflow's `tests/test_synthetic.py` does, so `bin/check` runs your workflow end to end on made-up data. Defaults for memory, walltime and epochs cite the timing run that measured them.
5. **Write the page text** in `index.html`, linking the guide (`../../guide/#stage` and `../../guide/#view`) for staging and viewing rather than repeating its steps. Name yourself as the workflow owner on the page, and add a `CODEOWNERS` line for the folder. Use relative links only: root-absolute links like `href="/"` resolve outside `/iris/` and 404.
6. **Add the catalogue card** to `index.html`, with its modality tag and compute tag, and the workflow's row in the tier table (see [Status](#status)): **Run, browser run pending**, so the card reads Testing until the maintainer's browser run. A new modality also needs a `.card-domain.<x>` style, and the maintainer's OK in the proposal.
7. **Test from your own clone** (you): `bin/check` clean, then a `qsub` run of the job script from your clone on Katana. The job script is the form's `script:` block: copy it into a `.pbs` file, fill in each `#{...}` with a value, and set `CODE` to your clone's `workflows/<slug>`. Run it on a real dataset in the standard layout, pass `-m abe` so PBS emails you, and check the run directory it writes. Cite the job ID in the PR.
8. **Browser run on dev** (maintainer): from the dev clone, on your PR's branch, the form opens, `check:` rejects one wrong dataset folder, and one real run finishes, appears in MLflow after `module load iris` and `iris-compare` and opens with its `iris-view` line. The maintainer cites that job ID and moves the workflow to **Run and verified**.
9. **Merge to `main` and pull** the dev clone (maintainer, `git pull --ff-only`). Pushing `main` publishes the site.

If the workflow ships a `local/run_local.ps1`, **keep it ASCII-only**. These files have no BOM, and Windows PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI — an em dash or box-drawing character decodes into a byte PowerShell treats as a string delimiter, and the script fails to parse before it runs a single line. Use `-` and `=` in banners. The `.sh` files are unaffected.

### Requesting packages

Only the maintainer builds environments. If your workflow needs packages the shared imaging environment lacks, add them to `envs/imaging/requirements.in` in your PR and list them in its description. The maintainer builds version *n+1* from it (`envs/imaging/README.md`), commits its lock, and your form's `ENV_DIR` points at *n+1* before merge. Until then, test against a venv of your own built from that `requirements.in`, and say so in the PR.

## The workflow owner

Once your PR merges, you are the workflow's **workflow owner**: named on its page and in `CODEOWNERS` for its folder. Your duties:

- **Answer issues about your workflow**, on GitHub Issues, and fix it when it breaks.
- **Review PRs that change its folder**; `CODEOWNERS` asks you to.
- **Keep it working**: moving it to a new environment version when its old one goes, and keeping its page accurate.
- **Register it on WorkflowHub and mint its citable versions**, as below.

If your workflow breaks and you don't answer about it for six months, it becomes an unmaintained workflow: it leaves the catalogue and can no longer be run, though its page stays. Anyone can adopt it through a proposal (see [Status](#status)). To hand a workflow over, open a PR that names the new owner on its page and in `CODEOWNERS`.

## Registering on WorkflowHub

Each catalogue workflow has its own WorkflowHub entry, and each citable version is a frozen snapshot of `main` with its own DOI. There are no git tags (ADR-0002, `docs/adr/0002-citable-versions-are-frozen-from-main.md`). The workflow owner does every step. `bin/workflowhub-microct-2d-segmentation` is the worked example: run on the desktop (it needs `curl` and `python3`), it walks through steps 3 to 5 for the reference workflow, with every value filled in. Copy it for your workflow and change the values at the top of its stages.

1. **Create an account** on [WorkflowHub](https://workflowhub.eu/) and link your ORCID to it.
2. **Ask to join Team 472**, [UNSW ResTech](https://workflowhub.eu/projects/472), from its page. The maintainer approves, and keeps edit rights over every entry in the team, so leave the team able to manage your entry.
3. **Register the workflow** in Team 472 by importing from git: repository `https://github.com/unsw-restech/iris`, branch `main`, main workflow file the workflow's entry point (`workflows/<slug>/src/run.py` for the reference workflow), workflow type `Other`.
4. **Fill in the metadata**: the title and description from the workflow's page, licence Apache-2.0, and as creators yourself, your co-authors (with ORCIDs where they have them) and UNSW Research Technology Services.
5. **Freeze** the entry's snapshot of `main` (WorkflowHub's Freeze button), **publish** it, then **mint** its DOI, which makes it a citable version. Neither publishing nor minting can be undone. Note the date and the commit of `main` it was frozen at.
6. **Open a PR** adding the citable version to the workflow's page: its DOI, its date and its commit, never a version number. Add its DOI to `identifiers` in `CITATION.cff` too, above that workflow's older ones.

**When to mint:** the first citable version straight after your workflow merges; after that, only when its code or defaults change in a way that changes results, not on every merge. A citable version's commit may include unrelated changes to other workflows; that is harmless, since each run's `commit.txt` pins exactly what ran.

## Licence

IRIS is Apache-2.0 ([LICENSE](LICENSE)), and so is everything you add to it: inbound = outbound, under the licence's own section 5. There is no separate licence agreement (CLA) to sign. Opening a PR confirms that you can license its contents this way, and anything you bring in from elsewhere must be Apache-2.0 compatible.

## Deployment

GitHub Pages is already configured and deploys from the `main` branch. Pushing to `main` publishes. The `check` Actions workflow runs `bin/check` on every push, but it doesn't gate the deploy: run `bin/check` before pushing.

The OpenComposer forms reach Katana separately: OpenComposer's `apps_dir` points at `workflows/` in a clone on Katana, and `git pull` in that clone deploys them. A form runs the code of the clone that served it and records that clone's commit in `commit.txt`.

## Status

`v0.1-alpha`. The "Run on Katana" buttons currently point at the **development** OnDemand instance (`/pun/dev/OpenComposer/...`) while workflows are being validated. Switch these to `/pun/sys/` at launch, and remove every pre-launch notice: the README's, and the line saying proposals open at launch on the contribute page, in step 1 of [From proposal to DOI](#from-proposal-to-doi) and in the proposal form. `bin/check` fails if only some are done.

The catalogue is **imaging only**. Each card carries a modality tag and a compute tag; Planned cards are dimmed, labelled Planned and have no Run button. A card reads Active only in the **Run and verified** tier, and Testing in **Run, browser run pending**, which has no workflows at present. `hello-world` sits outside the catalogue as onboarding.

| Tier | Workflows | What exists |
|---|---|---|
| **Run and verified** | `hello-world` (onboarding), `microct-2d-segmentation` (microCT) | Page, form, job script, executed end to end |
| **Planned** | `cellpose-segmentation` (Microscopy), `qupath-pathology` (Pathology) | Page only, describing what the workflow will do. No form, no Run button |
| **Unmaintained** | None | Page only, with the `unmaintained-banner` saying it can't be run, so its citable versions and cited commits still lead somewhere. No card, no Run button, form moved to `_archive/<slug>/`, and its `CODEOWNERS` line removed, since it has no workflow owner. A workflow lands here when it breaks and its workflow owner hasn't answered for six months. To adopt one, file a proposal; once it's approved, open a PR that fixes the workflow, cites a `qsub` run's job ID and names you as its workflow owner on its page and in `CODEOWNERS`. It returns as the same folder and WorkflowHub entry |

`hello-world` ran from the browser through the dev clone (job 9584951, #53), and so did `microct-2d-segmentation` (job 9577519, #46).

IRIS was called ARES until 2026-10-13; the old `patricktung.github.io/ares/` address does not redirect. The repo moved from `PatrickTung/iris` to `unsw-restech/iris` on 2026-10-23; GitHub redirects the old repo URL, but the old `patricktung.github.io/iris/` site address does not redirect. The catalogue used to list 28 workflows across 11 research domains. The removed pages are recoverable from the `pre-prune` tag, and their OpenComposer forms (with the Planned entries' forms) are kept in `_archive/`. `mnist-classification` was removed the same way on 2026-10-22 (#53): its form is in `_archive/`, the rest under the `pre-mnist-removal` tag.

