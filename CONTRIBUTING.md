# For workflow authors

This file is for workflow authors: anyone with a Katana account who adds or changes a workflow, whether you work in ResTech or not. It covers how IRIS is built, previewed, extended and deployed, and takes a new workflow from your fork to its DOI. Researchers running workflows want the [README](README.md) instead. The [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/) says who can contribute, what you get and what gets accepted, and owns the rules authors and owners keep: the [fit criteria](https://docs.restech.unsw.edu.au/iris/contribute/#criteria), [when you need a proposal](https://docs.restech.unsw.edu.au/iris/contribute/#proposal), [help while you build](https://docs.restech.unsw.edu.au/iris/contribute/#help) and [what an owner answers for](https://docs.restech.unsw.edu.au/iris/contribute/#owner). This file is the technical procedure behind them and links them rather than restating them.

## From fork to DOI

You need no write access to the repo. The route is fork and pull request, with who does each step:

1. **Check it fits** (you), against the contribute page's [fit criteria](https://docs.restech.unsw.edu.au/iris/contribute/#criteria), and whether you need a proposal ([When you need a proposal](#when-you-need-a-proposal)). Most workflows don't.
2. **Propose, only if you need to** (you): file a proposal through the proposal issue form on [GitHub Issues](https://github.com/unsw-restech/iris/issues/new/choose), before building what it asks for. The maintainer approves it with the `approved` label or declines it by closing it as `wontfix`. Proposals open at launch, and so do pull requests from authors outside the pilot.
3. **Build on a fork** (you): fork `unsw-restech/iris`, turn on Actions on your fork, make a branch and follow [Adding a new workflow](#adding-a-new-workflow), one section per step: [scaffold](#1-scaffold), [page](#2-page), [owner](#3-owner), [new environment versions](#4-new-environment-versions), [test instance](#5-test-instance), [run proof](#6-run-proof), [CI and `ready`](#7-ci-and-ready).
4. **Open a pull request** (you) from your fork's branch into `main`, filling in the PR template. The PR is the only routine approval.
5. **Review batch** (maintainer): when the [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#steps) says, the maintainer reviews every ready PR together for safety and fit, never your science, and merges it or closes it naming the criterion it failed ([Review batch](#8-review-batch)). The maintainer doesn't help during the build or go back and forth on a PR: the [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#help) says where help comes from.
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
├── guide/index.html                  # "Using IRIS on Katana": transfer and viewing, shared by imaging workflows
├── templates/workflow-page.html      # The page template every workflow page is written from (Page)
├── _archive/<slug>/                  # The forms of workflows removed from the catalogue and of unmaintained ones, never served by OpenComposer
├── .github/workflows/check.yml       # CI: runs bin/check on every push and pull request
├── .github/workflows/ready.yml       # CI: labels a pull request ready once check passes, and outside-folder if bin/outside-folder flags it
├── .github/workflows/containers.yml  # CI: builds and checks each unpublished environment version; publishes it from main, and on a fork under its owner's account
├── .github/workflows/owner-mention.yml  # CI: mentions each touched workflow's owner, from its manifest, on a PR
├── .github/ISSUE_TEMPLATE/proposal.yml  # Issue form for a workflow author's proposal
├── .github/pull_request_template.md  # The checklist a workflow PR is ready for review on
├── .githooks/pre-commit              # Refuses a commit while git's index holds a script run by path without its executable bit (bin/exec-bits), printing the command that sets it
├── .githooks/commit-msg              # Refuses AI attribution, git's conflict list or a glossary Avoid word in a commit message; AGENTS.md turns the hooks on
├── .githooks/avoid-names(.pl)        # The glossary Avoid words bin/check fails in tracked files and commit-msg refuses in a message, and the script matching them
├── .githooks/pre-push                # Refuses a push to main of a tree no full bin/check passed on, or whose forms, module, job library, library copies or the tests bin/katana-test runs no passing bin/katana-test tested, or whose digest map names an author's container, or with no bin/syspull listing since main last moved or the system clone was last deployed
├── ruff.toml                         # The Python lint rules bin/check applies
├── bin/
│   ├── check                         # Every check to pass before committing
│   ├── check-passed                  # Record the tree a full bin/check passed on; say whether a commit's tree passed (pre-push runs it)
│   ├── ciwait                        # Wait for a pushed commit's CI run, check or containers (desktop)
│   ├── exec-bits                     # List the scripts run by path git's index doesn't hold as 100755 (bin/check and pre-commit run it)
│   ├── envpull                       # Pull the containers live forms pin onto Katana; list those nothing pins; --own pulls an author's into their own scratch (desktop)
│   ├── envpull-dm.sh                 # envpull's side on the data mover
│   ├── envrun                        # Run a command in an environment version's container: bin/check's Python tests (desktop, CI)
│   ├── outside-folder                # List what a PR changes beyond its workflow's folder, its card and its lab's recipe (the ready workflow runs it)
│   ├── pageswait                     # Wait for the live site to serve a change (desktop)
│   ├── issue-tick                    # Tick checkboxes in an issue's body or Agent Brief (desktop)
│   ├── github-repo.sh                # IRIS's GitHub repo, unsw-restech/iris, which every repo-scoped gh call in bin/ names, not the current directory's
│   ├── iris-import                   # Import new runs into your MLflow tracking store
│   ├── iris-python                   # Runs an iris.* module in the researcher tools' container (`IRIS_TOOLS_ENV_VERSION`); the iris-* tools are shims over it
│   ├── iris-compare                  # Import, then compare runs in MLflow (in a Virtual Desktop)
│   ├── iris-rebuild                  # Rebuild a lost tracking store from run directories
│   ├── iris-view                     # View a run's labels over its volume in napari (in a Virtual Desktop)
│   ├── katana-test                   # Run the form, module and job-library tests on Katana (desktop)
│   ├── manifest-owner                # Read a workflow owner from its manifest.yml, checking the owner block's shape
│   ├── new-workflow                  # Make a new workflow from the reference workflow, with its library copy, page, manifest, card and tier row, and print what's left
│   ├── owner-mentions                # The comment the owner-mention Action posts on a PR (CI)
│   ├── libcopy                       # Copy the library's job side into a workflow's lib/, recording the commit; check every copy (bin/check runs it)
│   ├── ocpull                        # Show, then deploy, what moving the fork's two checkouts to its main brings the instances (desktop)
│   ├── ocpull-checkouts.sh           # ocpull's side on Katana: list a move, or move both checkouts or neither
│   ├── pilot-readable.py             # List what pilot testers can't read in the system clone or a fork checkout (syspull and ocpull run it)
│   ├── prune-merged                  # List, then remove, the local branches and worktrees whose work is already in origin/main (desktop)
│   ├── syspull-pins.sh               # List the environment versions a commit pins whose container files aren't on Katana (syspull runs it)
│   ├── qwait                         # Wait for Katana jobs and show how they ended (desktop)
│   ├── review-batch                  # List every ready PR, then merge the batch on one yes and print its deploy, copying authors' containers by digest (desktop)
│   ├── run-proof                     # Write a workflow's run proof from a test-instance run (Katana); check a PR's proofs (bin/check runs it)
│   ├── syspull                       # Show, then deploy, what a pull brings the system clone (desktop); a listing records the main it ran against, which --listed tells pre-push, until a deploy clears it
│   ├── tracked-tree                  # Print the tree a commit of every uncommitted edit would hold (check-passed and katana-test run it)
│   └── workflowhub                   # Walkthrough registering a workflow on WorkflowHub and minting its citable versions, from its manifest (desktop)
├── envs/                             # Environment containers: the core list, each environment's packages and versions, CI's build and checks (see its README)
├── lib/
│   ├── iris-job.sh                   # Run-time steps every imaging job sources (container check, run dir, commit, container start), from its workflow's copy
│   ├── katana.sh                     # Katana's constants: the system clone, the fork's two checkouts, the imaging environment, the Python module, the environments' digest map and lab table, the environments folder and the researcher tools' version
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
    └── microct-2d-segmentation/      # Reference workflow: bin/new-workflow copies it to start a new one
        ├── index.html
        ├── form.yml.erb, manifest.yml  # OpenComposer form; the manifest names the workflow owner
        ├── src/run.py                # Entry point: train, then segment into a run directory
        ├── lib/                      # Its own copy of the library's job side, which its jobs run (bin/libcopy; never edited by hand)
        ├── run-proof.json            # Its run proof, from a test-instance run (bin/run-proof), once it has one
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

The workflow author's checklist, one section per step. Each section names the ticket that turns it into a tool or a check, and says what to do until that ticket lands. Work on a branch of your fork, cloned on Katana at `~/iris`, where the [test instance](#5-test-instance) looks for it, as well as wherever you edit.

### 1. Scaffold

One command makes the whole workflow, from your clone:

```bash
bin/new-workflow <slug> --title "<title>" --lab <lab> \
    --owner-name "<your name>" --owner-github <your login> --owner-email <your email> \
    [--owner-orcid <your ORCID iD>]
```

`<slug>` is the folder name and the OpenComposer URL segment: lowercase words joined by hyphens. `<lab>` is your lab's section id in `index.html`, such as `microct-lab`; `--modality <x>` sets the card's modality tag when it isn't the first in your lab's section. The owner is you, the workflow owner, as `bin/manifest-owner` reads it ([Owner](#3-owner)). It makes `workflows/<slug>/` from the reference workflow, `workflows/microct-2d-segmentation/`:

- **The form, `src/` and `tests/`**, the reference's, with its slug changed to yours everywhere it appears: the usage tag `#PBS -A iris-<slug>`, the Experiment name default and the job name default, `iris_<slug>`. The form pins, in `IRIS_ENV_VERSION`, the environment version `lib/katana.sh`'s lab table gives your lab. `tests/` holds only the workflow's own tests: the entry script's end-to-end synthetic run (`test_synthetic.py`, building its dataset and clone with `lib/tests/datasets.py` and `run_dirs.py`) and the form tests (`test_form.rb`, on `lib/tests/form_helper.rb`). The shared library's tests and the rendered-form checks, and the Katana jobs for the library, the module and the environment, are in `lib/tests/` and `lib/tests/katana/`, so it copies none of them, and `bin/check` and `bin/katana-test` run them once for every workflow.
- **Its library copy**, `lib/`, made by `bin/libcopy <slug>`, so the workflow's `lib/` is the library's job side as your clone has it now ([The library's two sides](#the-librarys-two-sides)).
- **Its manifest**, naming you as its workflow owner, **its page**, from the page template ([Page](#2-page)), **its card**, reading Active, in its lab's section of `index.html`, before the lab's Planned cards, and **its row** in the tier table ([Status](#status)): Run and verified, with a line under the table citing the job of your test-instance run.

To build a Planned workflow, give its slug: it keeps its folder, so its URL never changes, and takes its title, lab, modality and card text from its card; it rewrites its page from the template, turns its card Active in place and moves its tier row. It refuses, writing nothing, a slug that is taken, an unmaintained workflow's (adopt it instead: [The workflow owner](#the-workflow-owner)), one whose form `_archive/<slug>/` keeps from a workflow removed from the catalogue, or a malformed one, a lab with no section or no lab table line, an owner `bin/manifest-owner` refuses, and `lib/` with uncommitted changes, since the copy records a commit.

It ends by printing what's left for you, which is:

- **Write each `{{TODO: ...}}`** it leaves as it says, braces and all: on the page ([Page](#2-page)), on the card, its description and compute tag, and in the manifest, its `tags:` and `description:`. `bin/check` fails each one left. The line citing your job holds one too, which you fill with the job ID of your test-instance run once you have it ([Run proof](#6-run-proof)): until then `bin/check` fails it, as it fails any Run and verified workflow without a cited job. The form treats the manifest's description as HTML, so spell a placeholder there `{like this}`: `bin/check` fails a `<` in it.
- **Make the form, `src/` and `tests/` your workflow's**: they are still the reference workflow's, for its dataset. Then `git add` the folder, `index.html` and `CONTRIBUTING.md`, commit and run `bin/check`.
- **Pin a newer environment version** only if your workflow needs packages its lab's version lacks: see [New environment versions](#4-new-environment-versions); never change a built version. `bin/check` fails a version that isn't in the digest map.
- **Set the fields and `check:` rules** in `form.yml.erb`, and the entry point under `src/`. `check:` validates the dataset layout your page documents, so a researcher who picks the wrong folder is told before the job runs. Add a synthetic-dataset test under `tests/`, as the reference workflow's `tests/test_synthetic.py` does, so `bin/check` runs your workflow end to end on made-up data, on CPU in the container your form pins (`envs/README.md`). Defaults for memory, walltime and epochs cite the timing run that measured them. A select's, radio's or checkbox's `value:` names its default by an option's label, and a script line names a checkbox or multi_select as `#{field}`, never `#{:field}`: its line drops when nothing is chosen, colon or not, so a field a run must record goes in a select or a radio (#184). `bin/check` checks both (`lib/tests/form_fields.rb`).

  **Embed the entry script** in the form's `script:`, as the reference form does, so researchers can edit it for one run (ADR-0006): the form reads it from `src/` at render time into a quoted heredoc below the one-line hint `# Edit the workflow code below`, and the job writes it into the run directory as `run.py`, runs `iris_record_code` on the next line to record the run's code, writing its `commit.txt` and writing and printing its `run.diff`, and runs it from there. Beside `script:`, the form's `editable_region` key names the heredoc's opener and its end marker, as the reference form's does, so on the IRIS fork the entry script is the only part of the pane a researcher can edit. The form sources the job library from the workflow's own copy, `source "$CODE/lib/iris-job.sh"`, which keeps it out of the pane. The entry script may contain neither `#{` (OpenComposer substitutes a field there) nor `<%` (ERB); `bin/check` renders every imaging form as OpenComposer does and checks the script it submits, in order, its `editable_region` and the workflow page's quote of the hint, against what `lib/tests/imaging_form.rb`'s header lists. So `bin/check` needs Ruby: `sudo apt install ruby` once in WSL. `hello-world` keeps its plain script.
- **A new modality or lab** needs an approved proposal first, and its parts in place before `bin/new-workflow` takes it: a new modality a `.card-domain.<x>` style in `index.html`, and a new lab its own `<div class="lab" id="<x>">` section there, which its pages' breadcrumbs link (`../../#<x>`), and its line in the lab table.

If the workflow ships a `local/run_local.ps1`, **keep it ASCII-only**. These files have no BOM, and Windows PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI — an em dash or box-drawing character decodes into a byte PowerShell treats as a string delimiter, and the script fails to parse before it runs a single line. Use `-` and `=` in banners. The `.sh` files are unaffected.

### 2. Page

Your workflow's `index.html` is written from the page template, `templates/workflow-page.html`, so every workflow page has the same sections and looks like IRIS; you write the words. Its placeholders come in two kinds: `{{NAME}}`, a value `bin/new-workflow` fills ([Scaffold](#1-scaffold)) (`{{SLUG}}`, `{{TITLE}}`, `{{LAB_ID}}`, `{{LAB_NAME}}`, `{{OWNER_LOGIN}}`, `{{OWNER_NAME}}`, `{{OWNER_EMAIL}}`), and `{{TODO: ...}}`, which says what you write in its place. Replace each with your text, braces and all.

The template's fixed sections, each with its `id`, are what the workflow does (`what`, under the title), its workflow owner with their contact (`owner`), how to run it (`run`, the Run button and the "You're ready when" checklist, then `fields`, what each form field does), the data it needs (`data`, the dataset layout your form's `check:` validates, since workflows differ), what a run writes (`run-directory`) and how to cite it (`cite`). Keep them all, keep the owner section's line saying IRIS reviewed the workflow for safety and fit and its owner answers for its science word for word, and add sections of your own if your workflow needs them, as the reference workflow's page does. Link the guide (`../../guide/#stage` and `../../guide/#view`) for transfer and viewing rather than repeating its steps. Use relative links only: root-absolute links like `href="/"` resolve outside `/iris/` and 404.

`bin/check`'s page template rules fail a workflow page with a placeholder left, a script (a `<script>`, an `on...=` attribute or a `javascript:` link), an `<iframe>`, `<object>` or `<embed>`, or styles from outside IRIS (a `<style>`, a `style=` attribute, or a `<link>` the template doesn't have), and a page with a form that lacks one of the template's sections or its review line.

### 3. Owner

Name yourself as the workflow owner in two places, with the same GitHub login, name and email in both, which `bin/check` keeps in step; `bin/new-workflow` writes both from its `--owner-` options ([Scaffold](#1-scaffold)). Your login and email are the contact researchers reach you by:

- **The manifest**, `workflows/<slug>/manifest.yml`, in an `owner:` block beside its menu entry, as the reference workflow's has it:

  ```yaml
  owner:
    name: Jane Doe                  # as the page shows it
    github: jdoe                    # your GitHub login, without the @
    email: jdoe@example.org         # the page links it; no mailto:
    orcid: 0000-0002-1825-0097      # optional: your ORCID iD, for WorkflowHub
  ```

  `bin/manifest-owner` reads it, and its header gives the rules.
- **The page**, in its owner section: the template's owner line, with `{{OWNER_LOGIN}}`, `{{OWNER_NAME}}` and `{{OWNER_EMAIL}}` filled in, `<p class="wf-owner">Workflow owner: <a href="https://github.com/<login>" target="_blank"><name></a> · <a href="mailto:<email>"><email></a></p>`.

On every PR that touches the folder, the `owner-mention` Action (`.github/workflows/owner-mention.yml`) mentions the owner the manifest on `main` names, so you hear of every change without write access to the repo. It mentions each owner once per PR and never the PR's author, so your own PRs and your first one, whose folder isn't on `main` yet, mention no one. `CODEOWNERS` plays no part, since GitHub asks only people with write access for a review there, and `bin/check` fails a `workflows/` line in it.

### 4. New environment versions

CI on your fork builds your new version and publishes it under your own GitHub account, so you prove your workflow in it without waiting for the maintainer. You need a proposal for new packages first ([When you need a proposal](#when-you-need-a-proposal)). Then, in your PR, change your lab's environment recipe (`envs/<env>/requirements.in`) and make its next version, *n+1*, as `envs/README.md` describes: its lock, `envs/<env>/<n+1>/requirements.lock`, and `[<env>/<n+1>]=unpublished` in `lib/katana.sh`'s digest map. Your form pins *n+1* in its `IRIS_ENV_VERSION`, and your PR points your lab's lab table entry at it, so the maintainer's review of your PR is the maintainer moving the lab. A lab that shares another lab's environment keeps its entry until the maintainer moves that lab ([ADR-0010](docs/adr/0010-an-environment-version-may-change-its-labs-pins.md)).

- **A version that only adds packages is the cheap case**: its lock keeps every line of the one before, so it is built as one layer on it.
- **A version that changes or removes a package** is not declined: it is built fresh rather than as a layer, `bin/check` prints a `NOTE:` naming what it changes and removes, and it needs the maintainer's review ([ADR-0010](docs/adr/0010-an-environment-version-may-change-its-labs-pins.md)). It is still the lab's next version, never a second environment.

Then build it and pin it, all on your fork:

1. **Push the branch**, with Actions on for your fork ([CI and `ready`](#7-ci-and-ready)). The `containers` workflow builds every unpublished version with the checks every version gets (`envs/README.md`) and publishes yours to your own account's package, `ghcr.io/<your login>/iris-env`, tagged `<env>-<n+1>`, your login lowercased. Its run's summary prints the digest map line, `    [<env>/<n+1>]=ghcr.io/<your login>/iris-env@sha256:<hex>`.
2. **Pin it**: put that line in `lib/katana.sh` in place of `[<env>/<n+1>]=unpublished`, and commit and push it. The digest is the version: CI never builds it again, and `bin/check` runs your workflow's tests in that container, on your fork and on your own machine.
3. **Make the package public**: under **Packages** on your GitHub profile, open `iris-env`, then **Package settings**, **Change visibility**, **Public**. Your PR's CI and the review batch pull it from there.
4. **Put it on Katana**: `bin/envpull --own <env>/<n+1>`, from your clone, pulls it by digest through the data mover into your own scratch, `/srv/scratch/<zID>/.envs/<env>/<n+1>.sif`. `bin/envpull` reaches the data mover as `ssh katana-dm`, so give your SSH config a `Host katana-dm` entry for `kdm.restech.unsw.edu.au` with your zID as `User`. A run from your own clone, the test instance's, finds the container there when the IRIS environments folder has none, and a researcher's run from IRIS never looks there. The lookup is in the library's job side, so a library copy made before it finds only the environments folder: copy the library again first ([The library's two sides](#the-librarys-two-sides)).
5. **Prove your workflow in it** on the test instance ([Test instance](#5-test-instance)): its job output's `Environment :` line names the version and its digest, and its run proof records them.

A change to the lock after that is a rebuild with a new digest: put the version back to `unpublished`, push, pin the new line, run `bin/envpull --own` again, which replaces your own file, and prove the workflow again. The review batch copies the container you proved, by that digest, into IRIS's package, `ghcr.io/unsw-restech/iris-env`, and writes its digest alone in the map ([Review batch](#8-review-batch)); it never rebuilds it.

Either way, the lab's other workflows keep the version they pin until their owners prove them in the new one: moving a workflow to a newer version is a change to its folder, which needs a new run proof ([Run proof](#6-run-proof)), and its owner's choice. To show them where they stand, the `containers` run that builds your version also runs the tests of every workflow pinning an earlier version of your environment, any lab's, in the new container, and its summary lists each with passed or failed and a failure's first lines. A failure there never stops your version or your PR: it tells that workflow's owner what moving would take.

### 5. Test instance

**Until launch, every workflow author is a pilot tester.** The test instance, its checkout in `katana_ai` scratch, and so the [run proof](#6-run-proof), which only a test-instance run gives, need `katana_ai_ro` membership, which only pilot testers have, and no other route proves a workflow, a `qsub` run included. Proposals and pull requests from authors outside the pilot open at launch, so before then no one outside it needs these steps; launch removes this notice with the others ([Status](#status)).

The test instance is an OpenComposer you add to your own Katana OnDemand, under **Develop**, on the same fork commit as the IRIS instance, that shows you the forms in your own clone and runs them as you ([ADR-0012](docs/adr/0012-the-iris-instance-replaces-the-shared-opencomposer.md)). You prove your workflow there. Add it once, from a shell on Katana:

1. `mkdir -p ~/ondemand/dev`
2. `ln -s /srv/scratch/katana_ai/iris/OpenComposer-iris-test ~/ondemand/dev/`
3. If step 1 made `~/ondemand/dev`, choose **Help → Restart Web Server** in Katana OnDemand, since it turns **Develop** on for anyone who has that folder when their web server starts. If the folder was already there, the test instance shows up without a restart.

It opens at `https://kod.restech.unsw.edu.au/pun/dev/OpenComposer-iris-test/<slug>`, its navbar reading "IRIS test instance" where the IRIS instance's reads "IRIS", and keeps its own history, `~/composer/iris-test`, so your test runs stay out of your IRIS instance history (#174, job 9774480). It finds your clone only at `~/iris` ([ADR-0011](docs/adr/0011-iris-runs-its-own-opencomposer-fork.md)): with no `~/iris/workflows`, the test instance's list and each form read "No forms: `/home/<zID>/iris/workflows` doesn't exist." (the fork at `c50a682`, #179).

To prove the workflow: `bin/check` clean, your branch checked out in `~/iris`, then submit your form from the test instance on a real dataset in the layout your page documents, and check the run directory it writes: `commit.txt` is your clone's `HEAD`.

### 6. Run proof

The run proof shows your workflow's current code ran and finished, from a form on the [test instance](#5-test-instance). Only a run from the test instance proves a workflow: not a `qsub` run, nor one from any other OpenComposer.

1. **Commit** your workflow's folder as you want it proved, in your clone at `~/iris`, and run `bin/check`.
2. **Run the form** from the test instance, `https://kod.restech.unsw.edu.au/pun/dev/OpenComposer-iris-test/<slug>`, on a real dataset in the layout your page documents, with its script as it opens: an edited run proves nothing.
3. **Write the proof** once the job has ended and its job output, `runs/<job ID>.<server>.OU`, is in your dataset's `runs/` folder: on Katana, `~/iris/bin/run-proof <run dir>`. It writes `workflows/<slug>/run-proof.json`: the job ID, its exit status, the commit the run recorded, the environment version and digest from its run record, and your form tests' results, which it runs. It writes nothing, and says why, unless the job is in the test instance's job history, finished with exit status 0, ran unedited code at one commit in the environment version your form pins, your clone's copy of the folder is still that commit's, and your form tests (`tests/test_form.rb`) pass with none skipped. PBS forgets a finished job after 24 hours, which is why the proof is a file.
4. **Commit the proof** and push it with your branch.

CI checks it on your PR: `bin/check` runs `bin/run-proof --check`, which fails a PR that changes a workflow's folder, anything in it but the proof, after the proof's commit, or changes it with no proof. Any later change, updating its library copy or moving its environment version included, needs a new run and proof. Before you push, `bin/run-proof --check <base>` checks your branch against `<base>`, such as `upstream/main` if that remote is `unsw-restech/iris`. Only a PR is checked: the maintainer's pushes to `main` are not.

### 7. CI and `ready`

Turn on Actions on your fork (its **Actions** tab), so the `check` workflow runs `bin/check` on every push there, and see it pass on your branch before you open a PR. The environment containers are public, so your fork's CI pulls them with no login.

Then open the PR. CI runs the `check` workflow on it, `bin/check` as on your fork: every rule, the page rules among them, your workflow's synthetic-dataset test on CPU in the container your form pins, with no network and two minutes for each workflow's tests, and the run proof check ([Run proof](#6-run-proof)). If your GitHub account is new and this is your first PR to the repo, that run waits for the maintainer to approve it, as GitHub's "Require approval for first-time contributors who are new to GitHub" setting has it; anyone else's runs at once. When it passes, the `ready` workflow labels the PR `ready`, which puts it in the queue for the next [review batch](#8-review-batch). A push to the PR takes `ready` off until `check` passes again, and a failing run leaves it off: read the run's log, fix what it names and push.

The same workflow labels a PR `outside-folder` when it changes anything beyond your workflow's folder, its card in `index.html`, the tier table lines `bin/new-workflow` writes for it, your lab's recipe (`envs/<env>/`, the environment the lab table gives your lab) and that environment's new versions in `lib/katana.sh`, their digest map lines and your lab's lab table line, or more than one workflow's folder; the run's summary lists what. That label doesn't hold `ready` back: the maintainer reads what it lists in the review batch, so leave shared files alone unless your PR needs them. `bin/outside-folder <base>`, such as `upstream/main`, lists the same for your branch before you push.

### 8. Review batch

The maintainer runs one with one command on the desktop; the contribute page's [From fork to DOI](https://docs.restech.unsw.edu.au/iris/contribute/#steps) says how often, and how to ask for a quick fix. The batch shows the maintainer each PR's description.

1. **List the batch**: `bin/review-batch` shows every open PR into `main` labelled `ready`, oldest first, each with its description, its diff and what it flags: a conflict with `main`, each digest map line it adds (an author's container to copy, or a version left `unpublished`), a run proof whose digest isn't the one its version's line names, and what `bin/outside-folder` lists. It changes nothing, and ends with the batch's `--apply` line, each PR pinned at the head it showed.
2. **One yes**: the maintainer drops any PR that fails a criterion from that line, closes it naming the criterion, and runs the line. `bin/review-batch --apply` checks each PR is still open, `ready` and at that head, merges them in order into a branch of its own from `origin/main` (`review-batch-<main>`, in a worktree under `.claude/worktrees/`), writes each author's container line as its digest alone, `    [<env>/<n>]=sha256:<hex>`, and runs `bin/check` on the result. It pushes and copies nothing; a merge that fails leaves nothing behind.
3. **Deploy**: it then prints the rest, one command a step, which the yes covers: `bin/review-batch --copy <env>/<n> <author's container>` for each container, which copies it by its digest into `ghcr.io/unsw-restech/iris-env`, tagged `<env>-<n>`, never rebuilding it, and checks the digest is kept (it pushes with the maintainer's own docker login, so the maintainer's account needs write access to that org package, which may need one of the org's owners to grant); `bin/katana-test` if the batch changes what it tests; `bin/syspull`, whose listing the push hook needs; the push to `main`, which publishes the site and marks each PR merged; `bin/ciwait`; the dev clone's pull; `bin/envpull`, which puts the new containers on Katana; and last `bin/syspull`, whose listing, quoting each commit, is the usual go-ahead for the system clone's deploy. The push hook refuses a `main` whose digest map still names an author's container.

A version that arrived `unpublished` is published from `main` after the merge and pinned there ([Publishing a version](envs/README.md#publishing-a-version)) before a form that pins it can deploy.

Review covers safety and fit only, never your science. A PR that fails a criterion is closed with that criterion named, never iterated on; fix it and reopen it ([the contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#help)).

### 9. WorkflowHub

Each catalogue workflow has its own WorkflowHub entry, and each citable version is a frozen snapshot of `main` with its own DOI. There are no git tags (ADR-0002, `docs/adr/0002-citable-versions-are-frozen-from-main.md`). The workflow owner does every step, through one walkthrough run on the desktop from a clone at `main` (it needs `curl` and `python3`):

```bash
bin/workflowhub --values <slug>    # what it will enter, read from your workflow's folder
bin/workflowhub <slug>             # the walkthrough
```

It reads every value from `workflows/<slug>/`: the title from the manifest's `name:`, the description from its `description:`, the tags from its `tags:` (one comma-separated line, which you add), you as creator from its owner, the main workflow file `src/run.py`, and the entry itself from the newest DOI the page's **Cite this workflow** lists. With none listed it registers a new entry; with one, it adds a new version to that entry. It asks for your ORCID if the manifest lacks it, and keeps your answers outside the repo, so a re-run offers them back.

1. **Create an account** on [WorkflowHub](https://workflowhub.eu/) and link your ORCID to it.
2. **Ask to join Team 472**, [UNSW ResTech](https://workflowhub.eu/projects/472), with **Request Membership** at the top right of its page, giving your organisation. The maintainer approves, and keeps edit rights over every entry in the team, so leave the team able to manage your entry.
3. **Run `bin/workflowhub <slug>`.** It does every step WorkflowHub documents with you: registration in Team 472 by importing from git (repository `https://github.com/unsw-restech/iris`, branch `main`, workflow type `Other`), then the metadata, with each value printed to paste: title, description, licence Apache-2.0, sharing, tags, and as creators yourself, your co-authors (with ORCIDs where they have them) and UNSW Research Technology Services.
4. **Make your two clicks**, which it lists in order and stops for a yes before each: **Register** (**Update** for a new version), which publishes the version and freezes it, then **Generate a DOI**, which makes it a citable version and can't be undone. Between them it reads the published entry back to check its title, licence and commit, and it reads the DOI back after.
5. **Open a PR** adding the citable version to the workflow's page: its DOI, its date and its commit, never a version number, and its DOI to `identifiers` in `CITATION.cff`, above that workflow's older ones. The walkthrough ends by printing both lines.

To try it without minting anything, run it against WorkflowHub's development instance, which mints no DOIs, so it stops after Register or Update, once it has checked the published entry's title, licence and commit: `IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=<a team there> bin/workflowhub <slug>`. That instance's entries are its own, so `IRIS_WORKFLOWHUB_ENTRY=<its entry URL>` adds a new version to one.

**When to mint:** the first citable version straight after your workflow merges; after that, only when its code or defaults change in a way that changes results, not on every merge. A citable version's commit may include unrelated changes to other workflows; that is harmless, since each run's `commit.txt` pins exactly what ran.

## The workflow owner

Once your PR merges, you are the workflow's **workflow owner**, named on its page and in its manifest. Support for your workflow comes to you, not the maintainer: the guide's help routes and the README send researchers to the owner named on the workflow's page. Your duties:

- **Answer issues about your workflow**, on GitHub Issues and from researchers who contact you, and fix it when it breaks.
- **Review PRs that change its folder**; you are mentioned on each one ([Owner](#3-owner)).
- **Keep it working**: update its library copy or move it to a newer environment version only when you choose, each with a new run ([Run proof](#6-run-proof)), and keep its page accurate.
- **Register it on WorkflowHub and mint its citable versions** ([WorkflowHub](#9-workflowhub)).

The [contribute page](https://docs.restech.unsw.edu.au/iris/contribute/#unmaintained) owns the rules for an owner who stops answering, handing over and adoption. The mechanics:

- **Unmaintained**: the workflow moves to the Unmaintained row of the tier table ([Status](#status)).
- **Handing over**: a PR that names the new owner in place of you, in the manifest and on the page ([Owner](#3-owner)).
- **Adoption**: after the approved proposal, a PR that fixes the workflow, carries a run proof ([Run proof](#6-run-proof)) and names the adopter as its workflow owner, moving its manifest back from `_archive/<slug>/` with its form. It keeps its folder and its WorkflowHub entry.

## Licence

IRIS is Apache-2.0 ([LICENSE](LICENSE)), and so is everything you add to it: inbound = outbound, under the licence's own section 5. There is no separate licence agreement (CLA) to sign. Opening a PR confirms that you can license its contents this way, and anything you bring in from elsewhere must be Apache-2.0 compatible.

## Deployment

GitHub Pages is already configured and deploys from the `main` branch. Pushing to `main` publishes. The `check` Actions workflow runs `bin/check` on every push, but it doesn't gate the deploy: run `bin/check` before pushing.

The OpenComposer forms reach Katana separately: OpenComposer's `apps_dir` points at `workflows/` in a clone on Katana, and `git pull` in that clone deploys them. A form runs the entry script embedded in its script pane and the rest of its code, its own copy of the library's job side included, from the clone that served it, and records that clone's commit, as of when the form rendered, in `commit.txt`.

## Status

IRIS is in a **pilot**. The "Run on Katana" buttons point at the system OnDemand instance (`/pun/sys/OpenComposer/...`), whose workflows only pilot testers (members of `katana_ai_ro`) can reach. At launch, remove every pre-launch notice: the pilot notices in the README and on the landing page, the line saying proposals open at launch on the contribute page, in step 2 of [From fork to DOI](#from-fork-to-doi) and in the proposal form, and the notice that every workflow author is a pilot tester at the top of [Test instance](#5-test-instance). `bin/check` fails if only some are gone.

The catalogue is **imaging only**, grouped into one section per lab. Each card carries a modality tag and a compute tag; Planned cards are labelled Planned and have no Run button. Every card reads Active or Planned: Active in the **Run and verified** tier, which a new workflow joins with its test-instance run ([Test instance](#5-test-instance)), and Planned in **Planned**. An Unmaintained workflow has no card. `hello-world` sits outside the catalogue as onboarding.

| Tier | Workflows | What exists |
|---|---|---|
| **Run and verified** | `hello-world` (onboarding), `microct-2d-segmentation` (microCT) | Page, form, job script, executed end to end |
| **Planned** | `microct-denoising`, `microct-super-resolution`, `microct-reconstruction` (microCT), `mri-rat-brain-tumour-segmentation` (MRI), `microscopy-cell-segmentation` (microscopy) | Page only, describing what the workflow will do. No form, no Run button |
| **Unmaintained** | None | Page only, with the `unmaintained-banner` saying it can't be run, so its citable versions and cited commits still lead somewhere. No card, no Run button, form and manifest moved to `_archive/<slug>/`, since it has no workflow owner to mention on a PR. When a workflow lands here, and how one is adopted: [The workflow owner](#the-workflow-owner) |

`hello-world` ran from the browser through the system OnDemand instance (job 9622779), and so did `microct-2d-segmentation` (job 9622783), both from `/pun/sys/` at `3fa4177`. Both had earlier run through the dev clone (`hello-world` job 9584951, #53; `microct-2d-segmentation` job 9577519, #46). Since 2026-11-12, `/pun/sys/OpenComposer/` is the IRIS instance, on the fork ([ADR-0012](docs/adr/0012-the-iris-instance-replaces-the-shared-opencomposer.md)): `hello-world` has run there on the fork at `88d45b1` (job 9751644), and so has `microct-2d-segmentation` (job 9752576).

IRIS was called ARES until 2026-10-13; the old `patricktung.github.io/ares/` address does not redirect. The repo moved from `PatrickTung/iris` to `unsw-restech/iris` on 2026-10-23; GitHub redirects the old repo URL, but the old `patricktung.github.io/iris/` site address does not redirect. The catalogue used to list 28 workflows across 11 research domains. The removed pages are recoverable from the `pre-prune` tag, and their OpenComposer forms are kept in `_archive/`. `mnist-classification` was removed the same way on 2026-10-22 (#53): its form is in `_archive/`, the rest under the `pre-mnist-removal` tag. The two Planned workflows, `cellpose-segmentation` and `qupath-pathology`, were removed on 2026-10-27: their pages are in git history and their forms in `_archive/`.

