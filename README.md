# ARES — AI & Research Execution Stack

Landing page and workflow catalogue for UNSW ResTech research workflows.

**Live site**: https://patricktung.github.io/ares

## Structure

```
ares/
├── index.html                        # Landing page (GitHub Pages root)
├── .nojekyll                         # Empty — disables Jekyll processing
├── .gitignore                        # Python bytecode, stray outputs, OS cruft
├── assets/
│   └── ares.css                      # Shared styles for workflow detail pages
└── workflows/
    ├── hello-world/                  # Test job — start here
    │   ├── index.html
    │   ├── katana/ares_hello_world.pbs
    │   └── local/run_local.sh, run_local.ps1
    ├── mnist-classification/         # PyTorch module example
    │   ├── index.html
    │   ├── katana/ares_mnist_classification.pbs, prepare.sh
    │   ├── src/train_mnist.py
    │   └── local/run_local.sh, run_local.ps1
    ├── whisper-transcription/        # Whisper module example
    │   ├── index.html
    │   └── katana/ares_whisper_transcription.pbs
    ├── openfoam-cavity/              # OpenFOAM module example
    │   ├── index.html
    │   └── katana/ares_openfoam_cavity.pbs
    ├── r-statistics/                 # R module example
    │   ├── index.html
    │   ├── katana/ares_r_statistics.pbs
    │   └── src/fit_models.R
    ├── dft-materials/                # Quantum ESPRESSO module example
    │   ├── index.html
    │   ├── katana/ares_dft_materials.pbs
    │   └── inputs/si_scf.in
    ├── rna-seq-pipeline/index.html
    ├── variant-calling/index.html
    ├── alphafold-batch/index.html
    └── climate-downscaling/index.html
```

Plain static HTML — no build step, no dependencies. The landing page keeps its styles inline; the five workflow detail pages share `assets/ares.css`. The `hello-world` page has its own styles — it's a deliberate variant, not a copy, so don't fold it into the shared sheet.

`hello-world` and `mnist-classification` are the two workflows that ship runnable scripts. `mnist-classification` is the reference for how ARES provides an environment on Katana: **use a module**. It runs `module purge && module load pytorch/1.13.1` — nothing is installed, nothing large is downloaded, and the module name is a single editable variable at the top of the PBS script.

`torch` is its only dependency. MNIST is parsed straight from the IDX files with the standard library rather than via `torchvision`, which keeps the module sufficient on its own and reduces the download to the 11 MB dataset. Run `katana/prepare.sh` on a login node first — it fetches that dataset where the network is reliable, leaving the job able to run offline.

Keep `.nojekyll` in place. Without it, Pages runs Jekyll and would silently drop any future directory beginning with an underscore.

## Local preview

The site is served from the `/ares/` subpath, so preview it that way — serve the **parent** directory:

```
cd ..            # the directory containing ares/
python -m http.server 8000
# open http://localhost:8000/ares/
```

Opening `index.html` directly over `file://` will not reproduce the real base path and will hide broken links.

## Adding a new workflow

1. Create a folder under `workflows/your-workflow-name/`
2. Add `index.html` — copy the RNA-seq example and link `../../assets/ares.css`
3. **Use relative links only** (`../../`, `../../#workflows`). Root-absolute links like `href="/"` resolve outside `/ares/` and 404.
4. Add a card to the workflow grid in `index.html`
5. Push to `main` — GitHub Pages redeploys automatically

If the workflow ships a `local/run_local.ps1`, **keep it ASCII-only**. These files have no BOM, and Windows PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI — an em dash or box-drawing character decodes into a byte PowerShell treats as a string delimiter, and the script fails to parse before it runs a single line. Use `-` and `=` in banners. The `.sh` files are unaffected.

## Deployment

GitHub Pages is already configured and deploys from the `main` branch. There is no Actions workflow; pushing to `main` publishes.

## Status

`v0.1-alpha`. The "Run on Katana" buttons currently point at the **development** OnDemand instance (`/pun/dev/OpenComposer/...`) while workflows are being validated. Switch these to `/pun/sys/` at launch.

The catalogue lists 28 workflows across 11 research domains: **9 Active** with detail pages, **19 Planned** placeholders with no page yet. The Planned entries exist to show intended breadth across UNSW's faculties; every one names software that is genuinely installed on Katana (see the module list), but none has been built.

Of the Active ones, only `mnist-classification` and `hello-world` have been run end to end. `whisper-transcription`, `openfoam-cavity`, `r-statistics` and `dft-materials` were written against real Katana modules (`whisper/20230314`, `openfoam/2506`, `r/4.5.1`, `quantum-espresso/7.1`) and are self-contained by design — each generates, ships or downloads its own input — but **none has been executed on Katana yet**.

Note there are two DFT workflows and they are not duplicates: `dft-materials` (Engineering) is plane-wave DFT for periodic solids via Quantum ESPRESSO; the Planned ORCA entry (Chemistry) is molecular DFT for isolated systems. Different codes, different problems.

`mnist-classification` needs its OpenComposer form built before the **Run on Katana** button works; until then the page's "Run it without OnDemand" section is the working path (`prepare.sh` + `qsub`).

The UNSW ResTech WorkflowHub project is [472](https://workflowhub.eu/projects/472) and currently holds **0 workflows**, so nothing here has a DOI yet. The site previously linked project 24 (`usegalaxy-eu`, the European Galaxy Team) and advertised DOIs that do not exist; both were corrected on 2026-08-05.

Remaining overclaims in `index.html`, not yet fixed: the hero and "How it works" still describe **Gadi** as a compute target and **Nextflow** as the execution engine, and tell users to "clone the workflow repo and edit the params file". None of that exists yet — there is no `main.nf` or `params.example.yml` in this repo, and `mnist-classification` runs on plain PBS + Apptainer.

## Planned

Not yet implemented, but intended per workflow:

- `main.nf` — Nextflow workflow
- `nextflow.config` — compute profiles
- `params.example.yml` — example parameters
- `ro-crate-metadata.json` — WorkflowHub metadata

## Contact

restech@unsw.edu.au
