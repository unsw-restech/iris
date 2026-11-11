# For workflow authors

This file is for workflow authors: anyone with a Katana account who adds or changes a workflow, whether you work in ResTech or not. It covers how IRIS is built, previewed, extended and deployed, and takes a new workflow from your fork to its DOI. Researchers running workflows want the [README](README.md) instead. The [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/) says who can contribute, what you get and what gets accepted, and owns the rules authors and owners keep: the [fit criteria](https://docs.restech.unsw.edu.au/iris/contribute/#criteria), [when you need a proposal](https://docs.restech.unsw.edu.au/iris/contribute/#proposal), [help while you build](https://docs.restech.unsw.edu.au/iris/contribute/#help) and [what an owner answers for](https://docs.restech.unsw.edu.au/iris/contribute/#owner). This file is the technical procedure behind them and links them rather than restating them.

## From fork to DOI

You need no write access to the repo. The route is fork and pull request, with who does each step:

1. **Check it fits** (you), against the contribute page's [fit criteria](https://docs.restech.unsw.edu.au/iris/contribute/#criteria), and whether you need a proposal ([When you need a proposal](#when-you-need-a-proposal)). Most workflows don't.
2. **Propose, only if you need to** (you): file a proposal through the proposal issue form on [GitHub Issues](https://github.com/unsw-restech/iris/issues/new/choose), before building what it asks for. The maintainer approves it with the `approved` label or declines it by closing it as `wontfix`. Proposals open at launch, and so do pull requests from authors outside the pilot.
3. **Build on a fork** (you): fork `unsw-restech/iris`, turn on Actions on your fork, make a branch and follow [Adding a new workflow](#adding-a-new-workflow), one section per step: [scaffold](#1-scaffold), [page](#2-page), [owner](#3-owner), [new environment versions](#4-new-environment-versions), [test instance](#5-test-instance), [run proof](#6-run-proof), [CI and `ready`](#7-ci-and-ready).
4. **Open a pull request** (you) from your fork's branch into `main`, filling in the PR template. The PR is the only routine approval.
5. **Review batch** (maintainer): about every fortnight, when the maintainer chooses, the maintainer reviews every ready PR together for safety and fit, never your science, and merges it or closes it naming the criterion it failed ([Review batch](#8-review-batch)). The maintainer doesn't help during the build or go back and forth on a PR: the [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#help) says where help comes from.
6. **Register and mint** (you, now the workflow owner): register the workflow on WorkflowHub and mint its first citable version ([WorkflowHub](#9-workflowhub)).

### When you need a proposal

The [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#proposal) lists the three things that need a proposal; anything else needs none, and its PR is its only approval. The technical side of each:

- **New packages**: an approved proposal, then your PR makes the lab's next environment version ([New environment versions](#4-new-environment-versions)).
- **A new modality or lab**: the card's tag or the lab's section ([Scaffold](#1-scaffold)). A new lab's first environment version is the maintainer's, built from the approved proposal; a lab with no packages of its own gets a lab table line in `lib/katana.sh` pointing at an existing environment version instead.
- **Adopting an unmaintained workflow**: [The workflow owner](#the-workflow-owner).

### What your workflow may rely on

IRIS promises one thing beyond your workflow's folder: the **run directory format, by version**. A run directory your workflow writes through its library copy stays readable by the shared side, which reads every run record format ever written (`lib/iris/record.py`'s `FORMAT`). Everything else shared, `lib/`, the shared side, `bin/`, `bin/check`'s rules, `envs/` and the site, is the maintainer's to change at any time. Your folder holds what your workflow runs: its code, its library copy, and the environment version its form pins, which is built once and never changes (`envs/README.md`).

The maintainer can change any workflow, at any time, in any detail. The maintainer's own workflows follow the same rules as everyone's.

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
├── .github/workflows/containers.yml  # CI: builds and checks each unpublished environment version; publishes it from main
├── .github/ISSUE_TEMPLATE/proposal.yml  # Issue form for a workflow author's proposal
├── .github/pull_request_template.md  # The checklist a workflow PR is ready for review on
├── .githooks/commit-msg              # Refuses AI attribution or git's conflict list in a commit message; AGENTS.md turns the hooks on
├── .githooks/pre-push                # Refuses a push to main whose forms, module, job library or library copies no passing bin/katana-test tested
├── ruff.toml                         # The Python lint rules bin/check applies
├── bin/
│   ├── check                         # Every check to pass before committing
│   ├── ciwait                        # Wait for a pushed commit's CI run, check or containers (desktop)
│   ├── envpull                       # Pull the containers live forms pin onto Katana; list those nothing pins (desktop)
│   ├── envpull-dm.sh                 # envpull's side on the data mover
│   ├── envrun                        # Run a command in an environment version's container: bin/check's Python tests (desktop, CI)
│   ├── pageswait                     # Wait for the live site to serve a change (desktop)
│   ├── issue-tick                    # Tick checkboxes in an issue's body or Agent Brief (desktop)
│   ├── iris-import                   # Import new runs into your MLflow tracking store
│   ├── iris-python                   # Runs an iris.* module in the researcher tools' container (`IRIS_TOOLS_ENV_VERSION`); the iris-* tools are shims over it
│   ├── iris-compare                  # Import, then compare runs in MLflow (in a Virtual Desktop)
│   ├── iris-rebuild                  # Rebuild a lost tracking store from run directories
│   ├── iris-view                     # View a run's labels over its volume in napari (in a Virtual Desktop)
│   ├── katana-test                   # Run the form, module and job-library tests on Katana (desktop)
│   ├── libcopy                       # Copy the library's job side into a workflow's lib/, recording the commit; check every copy (bin/check runs it)
│   ├── pilot-readable.py             # List what pilot testers can't read in the system clone (syspull runs it)
│   ├── syspull-pins.sh               # List the environment versions a commit pins whose container files aren't on Katana (syspull runs it)
│   ├── qwait                         # Wait for Katana jobs and show how they ended (desktop)
│   ├── syspull                       # Show, then deploy, what a pull brings the system clone (desktop)
│   └── workflowhub-microct-2d-segmentation  # Walkthrough registering it on WorkflowHub; copy it for another workflow (desktop)
├── envs/                             # Environment containers: the core list, each environment's packages and versions, CI's build and checks (see its README)
├── lib/
│   ├── iris-job.sh                   # Run-time steps every imaging job sources (container check, run dir, commit, container start), from its workflow's copy
│   ├── katana.sh                     # Katana's constants: the system clone, the imaging environment, the Python module, the environments' digest map and lab table, the environments folder and the researcher tools' version
│   ├── iris/                         # Shared Python for imaging workflows: volume reader, label writer, run record, importer, iris-compare, iris-rebuild, iris-view
│   └── tests/                        # The library's tests, run once (bin/check); the form helper and the rendered-form checks every imaging form gets; its Katana jobs in katana/ (bin/katana-test submits job_lib.pbs)
├── module/                           # `module load iris` (ADR-0003)
│   ├── modulefiles/iris              # The modulefile: puts the system clone's module/bin on the PATH
│   ├── bin/iris-view, iris-compare   # Links to the bin/ scripts: all the module exposes
│   └── tests/test_module.sh          # Loads the modulefile on Katana (bin/katana-test runs it)
└── workflows/
    ├── hello-world/                  # Test job — start here (onboarding, not in the catalogue)
    │   ├── index.html
    │   ├── form.yml.erb, manifest.yml  # OpenComposer form
    │   ├── src/hello_world.sh
    │   ├── katana/iris_hello_world.pbs
    │   └── local/run_local.sh, run_local.ps1
    └── microct-2d-segmentation/      # Reference workflow: copy it to start a new one
        ├── index.html
        ├── form.yml.erb, manifest.yml  # OpenComposer form
        ├── src/run.py                # Entry point: train, then segment into a run directory
        ├── lib/                      # Its own copy of the library's job side, which its jobs run (bin/libcopy; never edited by hand)
        └── tests/                    # This workflow's own tests: its synthetic-dataset run and its form tests (see AGENTS.md)
```

Plain static HTML — no build step, no dependencies. The landing page keeps its styles inline; the workflow detail pages and the guide share `assets/iris.css`. The `hello-world` page has its own styles — it's a deliberate variant, not a copy, so don't fold it into the shared sheet.

IRIS jobs use Katana **modules first**. Imaging jobs source `lib/iris-job.sh`, which runs the job's Python in the container of the environment version its form pins (`envs/README.md`), so nothing is installed when a run starts. The form names the version in its pane, `IRIS_ENV_VERSION=<env>/<n>`, and `bin/check` fails a version that isn't in `lib/katana.sh`'s digest map.

### The library's two sides

`lib/` has a job side and a shared side. The **job side** is what a job runs: the job library (`iris-job.sh`) and the constants it sources (`katana.sh`), the run record writer (`iris/record.py`), the code recorder (`iris/rundir.py`), the dataset record (`iris/dataset.py`) and the readers an entry script imports (`iris/volume.py`, `iris/labels.py`), with `iris/__init__.py`; `bin/libcopy`'s `JOB_SIDE` lists them. Each workflow carries its own copy of it in `workflows/<slug>/lib/`, so a change to `lib/` can't break a workflow that didn't ask for it, and its owner decides when to update. The **shared side**, the importer, `iris-view`, `iris-compare`, rebuild and tracking (`iris/runs.py`, `iris/tracking.py` and the rest), stays one copy in the clone's `lib/`, so a researcher compares runs from every workflow in one place; it reads every run record format a copy has written.

The copy is made by one command, `bin/libcopy <slug>`, when a workflow is made and whenever its owner chooses to update. It copies the job side as `HEAD` holds it into `workflows/<slug>/lib/`, keeping `lib/`'s layout, and writes the commit it was copied from, the full 40-character hash on one line, to `workflows/<slug>/lib/copied-from`; commit both. That commit is the last one that changed the job side, so a copy made on a branch that leaves `lib/` alone records a commit already on `main`. It refuses while the job side has uncommitted changes. `bin/check` (through `bin/libcopy --check`) fails an imaging form whose folder has no copy, and a copy that differs from `lib/` at the commit it records, holds a file the job side doesn't, or records a commit outside `HEAD`'s history. So a copy is never edited by hand: change `lib/`, commit, then copy again. A branch that changes `lib/` and copies it is merged, never rebased or squashed, so the commit its copy records reaches `main`; after rewriting a branch, copy again. The check reads history, so it needs a full clone (CI checks out full history).

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

The workflow author's checklist, one section per step. Each section names the ticket that turns it into a tool or a check, and says what to do until that ticket lands. Work on a branch of your fork, cloned on Katana as well as wherever you edit.

### 1. Scaffold

_#137 fills this step with `bin/new-workflow <slug>`, which makes the whole folder and prints what's left. Until then, by hand:_

- **Copy the reference folder**, `workflows/microct-2d-segmentation/`, to `workflows/<slug>/`. Its `tests/` holds only that workflow's own tests: the entry script's end-to-end synthetic run (`test_synthetic.py`, building its dataset and clone with `lib/tests/datasets.py` and `run_dirs.py`) and the form tests (`test_form.rb`, on `lib/tests/form_helper.rb`). The shared library's tests and the rendered-form checks, and the Katana jobs for the library, the module and the environment, are in `lib/tests/` and `lib/tests/katana/`, so the copy carries none of them, and `bin/check` and `bin/katana-test` run them once for every workflow. Then run `bin/libcopy <slug>` and commit, so the workflow's `lib/` is the library's job side as `main` has it now ([The library's two sides](#the-librarys-two-sides)). To build a Planned workflow, extend its existing folder instead, so its URL never changes.
- **Change the slug everywhere**: the folder name, `#PBS -A iris-<slug>` in the form's script header, the Experiment name default and the job name default. The folder name is also the OpenComposer URL segment.
- **Pin the environment version** in the form's `IRIS_ENV_VERSION`: a new workflow starts on the version `lib/katana.sh`'s lab table gives its lab, and `bin/check` fails a version that isn't in the digest map. If it needs packages that version lacks, see [New environment versions](#4-new-environment-versions); never change a built version.
- **Set the fields and `check:` rules** in `form.yml.erb`, and the entry point under `src/`. `check:` validates the dataset layout your page documents, so a researcher who picks the wrong folder is told before the job runs. Add a synthetic-dataset test under `tests/`, as the reference workflow's `tests/test_synthetic.py` does, so `bin/check` runs your workflow end to end on made-up data, on CPU in the container your form pins (`envs/README.md`). Defaults for memory, walltime and epochs cite the timing run that measured them.

  **Embed the entry script** in the form's `script:`, as the reference form does, so researchers can edit it for one run (ADR-0006): the form reads it from `src/` at render time into a quoted heredoc below the banner telling researchers to set the fields first, and the job writes it into the run directory as `run.py`, runs `iris_record_code` on the next line to record the run's code, writing its `commit.txt` and writing and printing its `run.diff`, and runs it from there. The form sources the job library from the workflow's own copy, `source "$CODE/lib/iris-job.sh"`, which keeps it out of the pane. The entry script may contain neither `#{` (OpenComposer substitutes a field there) nor `<%` (ERB); `bin/check` renders every imaging form as OpenComposer does and checks the script it submits (`lib/tests/imaging_form.rb`): the PBS header with the usage tag, `CODE` and its guard, the one `IRIS_ENV_VERSION=<env>/<n>` line, sourcing the job library from `$CODE/lib/`, the banner, the heredoc holding the entry script byte for byte, the `iris_record_code` line and the container start line, `iris_container python "$RUN_DIR/run.py"`, in that order, and that the entry script holds neither `#{` nor `<%`. So `bin/check` needs Ruby: `sudo apt install ruby` once in WSL. `hello-world` keeps its plain script.
- **Add the catalogue card** to `index.html`, in its lab's section, with its modality tag and compute tag, and the workflow's row in the tier table (see [Status](#status)): **Run, browser run pending**, so the card reads Testing until the maintainer's browser run ([Test instance](#5-test-instance)) moves it to **Run and verified**, citing that job ID. A new modality also needs a `.card-domain.<x>` style and the card's `<span class="card-domain <x>">` tag, and a new lab its own `<div class="lab" id="<x>">` section, which its pages' breadcrumbs link (`../../#<x>`), and its line in the lab table; each needs an approved proposal.

If the workflow ships a `local/run_local.ps1`, **keep it ASCII-only**. These files have no BOM, and Windows PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI — an em dash or box-drawing character decodes into a byte PowerShell treats as a string delimiter, and the script fails to parse before it runs a single line. Use `-` and `=` in banners. The `.sh` files are unaffected.

### 2. Page

_#135 fills this step with a page template of fixed sections and `bin/check` rules for it. Until then:_ write the page text in `index.html`, starting from the reference workflow's page. Document the dataset layout your workflow reads, since workflows differ, and link the guide (`../../guide/#stage` and `../../guide/#view`) for staging and viewing rather than repeating its steps. Use relative links only: root-absolute links like `href="/"` resolve outside `/iris/` and 404.

### 3. Owner

_#136 fills this step: the owner goes in the workflow's `manifest.yml`, and a small Action @-mentions them on every PR that touches its folder. Until then:_ name yourself as the workflow owner on the page, under the description (`<p class="wf-owner">`, linking your GitHub profile), and add a `/workflows/<slug>/ @<login>` line to `.github/CODEOWNERS`. `bin/check` keeps the two in step.

### 4. New environment versions

_#138 fills this step: CI on your fork builds your new version and publishes it under your own GitHub account, so you prove your workflow in it without waiting for the maintainer. Until then the maintainer publishes it from `main`._

You need a proposal for new packages first ([When you need a proposal](#when-you-need-a-proposal)). Then, in your PR, change your lab's environment recipe (`envs/<env>/requirements.in`) and make its next version, *n+1*, as `envs/README.md` describes: its lock, `envs/<env>/<n+1>/requirements.lock`, and `[<env>/<n+1>]=unpublished` in `lib/katana.sh`'s digest map. Your form pins *n+1* in its `IRIS_ENV_VERSION`, and your PR points your lab's lab table entry at it, so the maintainer's review of your PR is the maintainer moving the lab. A lab that shares another lab's environment keeps its entry until the maintainer moves that lab ([ADR-0010](docs/adr/0010-an-environment-version-may-change-its-labs-pins.md)).

- **A version that only adds packages is the cheap case**: its lock keeps every line of the one before, so it is built as one layer on it.
- **A version that changes or removes a package** is not declined: it is built fresh rather than as a layer, `bin/check` prints a `NOTE:` naming what it changes and removes, and it needs the maintainer's review ([ADR-0010](docs/adr/0010-an-environment-version-may-change-its-labs-pins.md)). It is still the lab's next version, never a second environment.

Either way, the lab's other workflows keep the version they pin until their owners prove them in the new one. _#150 fills in which of them would pass: the version's CI run reports it. Until then nothing does._ Until it is published, `bin/check` can't run your tests in it, so say in the PR what you ran them in.

### 5. Test instance

_#139 asks ResTech for the test instance, a second system OpenComposer that shows you the forms in your own clone and runs them as you. Until it exists, prove the workflow with `qsub`:_ `bin/check` clean, then a `qsub` run of the job script from your clone on Katana. The job script is the form's `script:` block: copy it into a `.pbs` file, fill in each `#{...}` with a value, and replace each `<%= ... %>` with what the form would render: `CODE` is your clone's `workflows/<slug>`, the commit is your clone's `HEAD`, and the heredoc holds your entry script. Run it on a real dataset in the layout your page documents, pass `-m abe` so PBS emails you, and check the run directory it writes.

Until then the maintainer also does a **browser run** from the dev clone on your PR's branch: the form opens, `check:` rejects one wrong dataset folder, and one real run finishes, opens with the `iris-view` line its job output prints and appears in MLflow through its `iris-compare` line. A dev run prints the dev clone's full paths, so it is viewed with the branch's code; `module load iris` would run the system clone's.

### 6. Run proof

_#140 fills this step with a tool, run on Katana after your test-instance run, that writes the run proof into your workflow's folder, and a CI check that fails a PR whose folder changed after the proof's commit. Until then:_ cite your `qsub` run's job ID in the PR. Any later change to your folder, updating its library copy or moving its environment version included, needs a new run.

### 7. CI and `ready`

Turn on Actions on your fork (its **Actions** tab), so the `check` workflow runs `bin/check` on every push there, and see it pass on your branch before you open a PR. Until the environment containers are public ([#132](https://github.com/unsw-restech/iris/issues/132)), your fork's CI can't pull them, so the tests that run in a container fail there; run `bin/check` on your own machine for those.

_#141 fills the rest of this step: CI on your PR runs every check and labels the PR `ready` when all pass. Until then the maintainer reads the PR's CI result._

### 8. Review batch

_#142 fills this step with the maintainer's review batch command, which lists every ready PR with its diff and anything flagged, merges the batch on one yes and deploys it. Until then the maintainer reviews and merges each PR, then pulls the dev clone (`git pull --ff-only`). Pushing `main` publishes the site._

Review covers safety and fit only, never your science. A PR that fails a criterion is closed with that criterion named; fix it and reopen it ([the contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#help)).

### 9. WorkflowHub

_#143 fills this step with one walkthrough for any workflow, reading its values from the workflow's manifest. Until then `bin/workflowhub-microct-2d-segmentation` is the worked example: run on the desktop (it needs `curl` and `python3`), it walks through steps 3 to 5 of the list below for the reference workflow, with every value filled in. Copy it for your workflow and change the values at the top of its stages._

Each catalogue workflow has its own WorkflowHub entry, and each citable version is a frozen snapshot of `main` with its own DOI. There are no git tags (ADR-0002, `docs/adr/0002-citable-versions-are-frozen-from-main.md`). The workflow owner does every step.

1. **Create an account** on [WorkflowHub](https://workflowhub.eu/) and link your ORCID to it.
2. **Ask to join Team 472**, [UNSW ResTech](https://workflowhub.eu/projects/472), from its page. The maintainer approves, and keeps edit rights over every entry in the team, so leave the team able to manage your entry.
3. **Register the workflow** in Team 472 by importing from git: repository `https://github.com/unsw-restech/iris`, branch `main`, main workflow file the workflow's entry point (`workflows/<slug>/src/run.py` for the reference workflow), workflow type `Other`.
4. **Fill in the metadata**: the title and description from the workflow's page, licence Apache-2.0, and as creators yourself, your co-authors (with ORCIDs where they have them) and UNSW Research Technology Services.
5. **Freeze** the entry's snapshot of `main` (WorkflowHub's Freeze button), **publish** it, then **mint** its DOI, which makes it a citable version. Neither publishing nor minting can be undone. Note the date and the commit of `main` it was frozen at.
6. **Open a PR** adding the citable version to the workflow's page: its DOI, its date and its commit, never a version number. Add its DOI to `identifiers` in `CITATION.cff` too, above that workflow's older ones.

**When to mint:** the first citable version straight after your workflow merges; after that, only when its code or defaults change in a way that changes results, not on every merge. A citable version's commit may include unrelated changes to other workflows; that is harmless, since each run's `commit.txt` pins exactly what ran.

## The workflow owner

Once your PR merges, you are the workflow's **workflow owner**, named on its page. Support for your workflow comes to you, not the maintainer: the guide's help routes and the README send researchers to the owner named on the workflow's page. Your duties:

- **Answer issues about your workflow**, on GitHub Issues and from researchers who contact you, and fix it when it breaks.
- **Review PRs that change its folder**; you are asked on each one ([Owner](#3-owner)).
- **Keep it working**: update its library copy or move it to a newer environment version only when you choose, each with a new run ([Run proof](#6-run-proof)), and keep its page accurate.
- **Register it on WorkflowHub and mint its citable versions** ([WorkflowHub](#9-workflowhub)).

The [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#unmaintained) owns the rules for an owner who stops answering, handing over and adoption. The mechanics:

- **Unmaintained**: the workflow moves to the Unmaintained row of the tier table ([Status](#status)).
- **Handing over**: a PR that names the new owner in place of you ([Owner](#3-owner)).
- **Adoption**: after the approved proposal, a PR that fixes the workflow, carries a run proof ([Run proof](#6-run-proof); a `qsub` job ID until then) and names the adopter as its workflow owner. It keeps its folder and its WorkflowHub entry.

## Licence

IRIS is Apache-2.0 ([LICENSE](LICENSE)), and so is everything you add to it: inbound = outbound, under the licence's own section 5. There is no separate licence agreement (CLA) to sign. Opening a PR confirms that you can license its contents this way, and anything you bring in from elsewhere must be Apache-2.0 compatible.

## Deployment

GitHub Pages is already configured and deploys from the `main` branch. Pushing to `main` publishes. The `check` Actions workflow runs `bin/check` on every push, but it doesn't gate the deploy: run `bin/check` before pushing.

The OpenComposer forms reach Katana separately: OpenComposer's `apps_dir` points at `workflows/` in a clone on Katana, and `git pull` in that clone deploys them. A form runs the entry script embedded in its script pane and the rest of its code, its own copy of the library's job side included, from the clone that served it, and records that clone's commit, as of when the form rendered, in `commit.txt`.

## Status

IRIS is in a **pilot**. The "Run on Katana" buttons point at the system OnDemand instance (`/pun/sys/OpenComposer/...`), whose workflows only pilot testers (members of `katana_ai_ro`) can reach. At launch, remove every pre-launch notice: the pilot notices in the README and on the landing page, and the line saying proposals open at launch on the contribute page, in step 2 of [From fork to DOI](#from-fork-to-doi) and in the proposal form. `bin/check` fails if only some are gone.

The catalogue is **imaging only**, grouped into one section per lab. Each card carries a modality tag and a compute tag; Planned cards are labelled Planned and have no Run button. A card reads Active only in the **Run and verified** tier, and Testing in **Run, browser run pending**, which has no workflows at present: a new workflow sits there until the maintainer's browser run ([Test instance](#5-test-instance)). `hello-world` sits outside the catalogue as onboarding.

| Tier | Workflows | What exists |
|---|---|---|
| **Run and verified** | `hello-world` (onboarding), `microct-2d-segmentation` (microCT) | Page, form, job script, executed end to end |
| **Planned** | `microct-denoising`, `microct-super-resolution`, `microct-reconstruction` (microCT), `mri-rat-brain-tumour-segmentation` (MRI) | Page only, describing what the workflow will do. No form, no Run button |
| **Unmaintained** | None | Page only, with the `unmaintained-banner` saying it can't be run, so its citable versions and cited commits still lead somewhere. No card, no Run button, form moved to `_archive/<slug>/`, and its `CODEOWNERS` line removed, since it has no workflow owner. When a workflow lands here, and how one is adopted: [The workflow owner](#the-workflow-owner) |

`hello-world` ran from the browser through the system OnDemand instance (job 9622779), and so did `microct-2d-segmentation` (job 9622783), both from `/pun/sys/` at `3fa4177`. Both had earlier run through the dev clone (`hello-world` job 9584951, #53; `microct-2d-segmentation` job 9577519, #46).

IRIS was called ARES until 2026-10-13; the old `patricktung.github.io/ares/` address does not redirect. The repo moved from `PatrickTung/iris` to `unsw-restech/iris` on 2026-10-23; GitHub redirects the old repo URL, but the old `patricktung.github.io/iris/` site address does not redirect. The catalogue used to list 28 workflows across 11 research domains. The removed pages are recoverable from the `pre-prune` tag, and their OpenComposer forms are kept in `_archive/`. `mnist-classification` was removed the same way on 2026-10-22 (#53): its form is in `_archive/`, the rest under the `pre-mnist-removal` tag. The two Planned workflows, `cellpose-segmentation` and `qupath-pathology`, were removed on 2026-10-27: their pages are in git history and their forms in `_archive/`.

