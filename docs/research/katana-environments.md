# Options for software Katana has no module for

Research for [issue #7](https://github.com/PatrickTung/iris/issues/7). Researched 2026-10-13. Throwaway branch `research/katana-environments`; never merged.

**Question.** Cellpose and similar imaging tools are pip-only; today the form builds a venv inside the user's output directory on first run. What are the supported ways to hand every researcher a ready-made environment, and for each: who can create it, how it is pinned and updated, GPU and CUDA compatibility with Katana's nodes, and whether compute nodes need outbound internet?

## How to read this

Each claim carries one of three marks.

- **[V]** Verified today against the cited primary source.
- **[I]** Inference: reasoned from verified facts, not stated by any source. Test before relying on it.
- **[?]** Could not be confirmed from public sources. Listed again under "Open questions for Patrick".

Katana's public documentation was read from its source repository (`unsw-restech/unsw-restech.github.io`, branch `main`), which is what `docs.restech.unsw.edu.au` is built from. "The Katana docs" below means all 22 Markdown pages in that repository.

## Short answer

All four options are workable on Katana, and none needs outbound internet at run time provided the tool's model weights are staged beforehand. They differ in who has to act and how many moving parts they add.

- **Shared venv in the shared IRIS directory** is the option the Katana docs support most directly (venv on top of a `python/*` module is their recommended route for pip software) and the one with the fewest moving parts. IRIS can build it without ResTech admin action.
- **Apptainer image in the shared directory** is the most self-contained (one immutable file, independent of Katana's Python modules) but Apptainer is entirely undocumented in the public Katana docs, so several facts needed to rely on it are unconfirmed.
- **Custom modulefile** is documented and any user can make one, but it is a wrapper, not an environment: it still needs a venv or image behind it.
- **ResTech-installed module** is the cleanest at run time (`module load`), but only ResTech admins can create or update it.
- **Shared conda environment** is discouraged for multi-user use by the Katana docs and adds an installer Katana does not provide; it is only needed for the ARM (GH200) node or non-Python dependencies.

The largest finding is not about packaging. **Katana's GPU fleet spans more generations than any single current PyTorch build is stated to cover**, so whichever option is chosen, the environment must pin a PyTorch CUDA variant deliberately, or the form must restrict `gpu_model`. See "GPU and CUDA compatibility".

## What Katana's documentation establishes

### Software policy

- **[V]** Research software is delivered as environment modules; nodes run Rocky Linux 8.9, x86_64. ([operating systems](https://docs.restech.unsw.edu.au/software/operating_systems/), [installing software](https://docs.restech.unsw.edu.au/software/installing_software/))
- **[V]** For pip-installable software the docs recommend a venv: "if this is an option, we recommend you use python virtual environments". The documented recipe is `module load python/3.10.8` then `python3 -m venv <path>`. ([python](https://docs.restech.unsw.edu.au/software/python/))
- **[V]** A venv can sit on top of a module's packages: load the module, then create the venv with `--system-site-packages`. ([python, "Special Cases"](https://docs.restech.unsw.edu.au/software/python/))
- **[V]** Conda: "neither are designed to be installed in multi-user environments but you can install them into your home or scratch directories." The docs point at Anaconda and Miniconda; there is no mention of mamba, micromamba or Miniforge. ([python](https://docs.restech.unsw.edu.au/software/python/))
- **[V]** There is no conda, miniconda, mamba or anaconda module in the installed module list (`available-modules.md`, zero matches). Nor is there a `cellpose`, `apptainer` or `singularity` module.
- **[V]** Users may write their own modulefiles. The docs give a template at `/apps/modules/templates/module_file` and say to add `module use --append $HOME/apps/Modules` to `~/.bashrc`. ([installing software, "Creating module files"](https://docs.restech.unsw.edu.au/software/installing_software/))
- **[V]** Requesting a module: "send an email to restech.support@unsw.edu.au from your UNSW email account with details of what software change you require." ([FAQ](https://docs.restech.unsw.edu.au/help_support/faq/))
- **[V]** For language ecosystems the docs steer users to the language's own package system rather than modules: "Perl, Python and R all have their own library/module systems: CPAN, PyPI and CRAN." ([environment modules](https://docs.restech.unsw.edu.au/software/environment_modules/))
- **[V]** Users must not run `yum install`, `su` or `sudo`. Software should be installed "using an interactive session, qsub -I, not directly on the login node." Login nodes cap each user at 4 GB of memory. ([installing software](https://docs.restech.unsw.edu.au/software/installing_software/), [FAQ](https://docs.restech.unsw.edu.au/help_support/faq/))
- **[V]** "GPU-enabled software should be installed on a GPU node within an interactive session, in case the software is probing for GPU hardware or libraries." ([about Katana](https://docs.restech.unsw.edu.au/using_katana/about_katana/))

### Containers

- **[V]** The words "apptainer", "singularity" and "docker" do not appear anywhere in the Katana docs. The only container mention is Neurodesk, which is offered as modules: "To install Neurodesk containers as modules to be used in Katana, please contact our service desk". ([neurodesk source](https://github.com/unsw-restech/unsw-restech.github.io/blob/main/docs/imaging/neurodesk.md))
- **[V]** `neurodesk/*` modules are installed (30 or so, for example `neurodesk/fmriprep/23.0.0`, `neurodesk/qsmxt/7.2.2`). This is a working precedent for ResTech shipping container-backed software as a module.
- **[V]** nf-core's Katana profile enables Apptainer and Singularity, disables Docker ("Docker is not supported on this cluster"), caches images in `/srv/scratch/$USER/.images`, and passes `--nv` for GPU processes. ([unsw_katana.config](https://github.com/nf-core/configs/blob/master/conf/unsw_katana.config)) This is a third-party config maintained by a Katana user, not a ResTech statement.
- **[?]** Which Apptainer version is installed, whether it is present on every compute node (including GPU nodes), whether `/srv/scratch` is bound into containers by default, and whether unprivileged builds work on Katana.

### Storage for a shared environment

- **[V]** Shared scratch: `/srv/scratch/group_name`, purpose "Data files and programs shared by a team", **not backed up**, size "Upon group requirements", access "All users in the group", usable anywhere. ([storage locations](https://docs.restech.unsw.edu.au/storage/storage_locations/))
- **[V]** Home is 10 GB and backed up; user scratch is 128 GB and not backed up. ([storage locations](https://docs.restech.unsw.edu.au/storage/storage_locations/))
- **[?]** Whether shared scratch can be made world-readable (the docs describe group access only; the map records Patrick's confirmation that a world-readable IRIS directory is obtainable), whether scratch has a purge policy or a file-count quota (neither is documented), and whether anything outside `/srv/scratch` and `/apps` is available for shared software.

### GPU nodes

- **[V]** 35 GPU nodes, 186 cards: 80 H200 141 GB (13 nodes), 1 H100 94 GB, 1 GH200 (1 node), 32 L40S 48 GB (7 nodes), 24 A100 40 GB (3 nodes), 32 V100 32 GB (8 nodes), 16 RTX Pro 6000 96 GB (2 nodes). 15 nodes are general use; 20 give priority to the group that bought them. ([about Katana](https://docs.restech.unsw.edu.au/using_katana/about_katana/))
- **[V]** GPUs are requested with `ngpus=N`; a model can be pinned with `gpu_model=A100` and the valid names listed with `pbsnodes -av | grep gpu_model`. With no `gpu_model`, "the scheduler will assign any available GPU". ([running jobs](https://docs.restech.unsw.edu.au/using_katana/running_jobs/))
- **[V]** The GH200 node is ARM (`aarch64`): "Regular Katana binaries and modules will not work here" and users should "Install your own Python environment using Conda for ARM". It is only reached by asking for `cpu_arch=aarch64`. ([tips](https://docs.restech.unsw.edu.au/using_katana/tips_katana/))
- **[V]** CUDA toolkit modules `cuda/10.1.243` through `cuda/13.0.0` are installed (default `cuda/11.8.0`), with `cudnn/8.0.5` through `cudnn/9.5.1`. (`available-modules.md`)
- **[?]** The NVIDIA driver version on each node type. The Katana docs do not state it. Everything in "GPU and CUDA compatibility" hangs on this number.

### Outbound internet from compute nodes

- **[V]** The Katana docs contain no policy statement either way: no page mentions internet access, proxies or firewalls for compute nodes.
- **[V]** ResTech's own guides download from the internet inside compute jobs. The Ollama guide starts `qsub -I ... ngpus=1` and then runs `ollama pull phi3`. The Stable Diffusion guide's batch PBS script calls `StableDiffusionPipeline.from_pretrained("CompVis/stable-diffusion-v1-4")` with `HF_HOME` on scratch. The install guidance tells users to `pip`/`conda` install inside `qsub -I` sessions. ([Ollama](https://docs.restech.unsw.edu.au/AI_in_Katana/Ollama/), [Stable Diffusion](https://docs.restech.unsw.edu.au/AI_in_Katana/StableDiffusion/))
- **[I]** So compute nodes, GPU nodes included, can currently reach PyPI, Hugging Face and the Ollama registry. This is observed behaviour in guides, not a guarantee.
- **[?]** A `netsandbox/0.1.0` module is installed and the Ollama guide loads it before `safe_ollama`. Its purpose is undocumented; the name suggests network restriction for a process. Whether ResTech intends to restrict compute-node egress is not public.

Whatever the answer, the standing constraint ("clicking run must never install anything") means no option should depend on it.

## The options

### A. Shared venv in the shared IRIS directory

Example shape: `/srv/scratch/iris/envs/cellpose-4.2.1-cu128/`, built once with `module load python/3.11.3 && python3 -m venv <that path>` and `pip install` from a pinned requirements file. The job runs `<path>/bin/python -m cellpose ...` directly.

- **Who can create it.** **[V]** Any user can build a venv; it is the documented route. **[I]** For a shared one, whoever has write access to the shared IRIS directory. No ResTech admin action beyond granting that directory.
- **Pinning and updates.** **[I]** Pin with an exact requirements file (`torch==X`, `cellpose==Y`, plus the `--index-url` for the CUDA variant) kept beside the environment; record `pip freeze`. Treat each environment directory as immutable: an update is a new directory with the version in its name, and the form changes one path. Old runs stay reproducible because the old directory still exists.
- **Must be built at its final path.** **[V]** "environments are inherently non-portable ... If you move an environment because you moved a parent directory of it, you should recreate the environment in its new location." ([Python venv docs](https://docs.python.org/3/library/venv.html))
- **No activation needed.** **[V]** "You don't specifically need to activate a virtual environment, as you can just specify the full path to that environment's Python interpreter." ([Python venv docs](https://docs.python.org/3/library/venv.html))
- **Depends on the Katana Python module staying installed.** **[V]** A venv's `pyvenv.cfg` has "a `home` key pointing to the Python installation from which the command was run", here `/apps/python/3.x.y/bin`. **[I]** If ResTech removes or rebuilds that `python/*` module, every venv built on it breaks. The job should still `module load` the same Python module so its shared libraries resolve.
- **GPU.** **[V]** PyTorch's Linux wheels declare the CUDA runtime, cuDNN and NCCL as pip dependencies (`cuda-toolkit[...]==13.0.3`, `nvidia-cudnn-cu13==9.24.0.43` for torch 2.14.1), so the venv carries its own CUDA libraries. ([PyPI torch metadata](https://pypi.org/pypi/torch/json)) **[V]** Cellpose: "as long as the NVIDIA drivers are installed, the GPU version is installed by default with pip." ([Cellpose README](https://github.com/MouseLand/cellpose/blob/main/README.md)) **[I]** No `cuda/*` or `cudnn/*` module needs loading; only the host driver matters.
- **Internet at run time.** **[I]** None for the code. Model weights are a separate matter; see "Model weights".
- **Costs.** **[V]** Shared scratch is not backed up, so the requirements file is the real artefact and must live somewhere that is (the IRIS repo). **[I]** A PyTorch venv is several GB and tens of thousands of small files. Build it on a GPU node in an interactive session, as the docs ask.

### B. Shared conda environment in the shared IRIS directory

- **Who can create it.** **[V]** Any user can install Miniconda into their own home or scratch. **[V]** The docs say conda is not designed for multi-user installs, and there is no conda module, so IRIS would first have to install and own a conda distribution in the shared directory.
- **Pinning and updates.** **[I]** An `environment.yml` or explicit lock file; same immutable-directory-per-version pattern as the venv. The environment can be used by absolute path (`<env>/bin/python`) without `conda activate`.
- **GPU.** **[I]** Same as the venv when PyTorch is installed with pip inside the conda environment. PyTorch's install page now gives pip commands for Linux, so conda adds nothing for PyTorch itself.
- **Internet at run time.** **[I]** None.
- **When it is actually needed.** **[V]** The GH200 ARM node: the docs tell users to use "Conda for ARM (aarch64)" there. **[I]** Also when a tool needs a non-Python library that Katana has no module for.
- **[?]** Licensing. The Katana docs link to Anaconda and Miniconda, whose default channel has commercial-use terms for larger organisations. Whether UNSW has a position on this was not checked; Miniforge with conda-forge avoids the question.

For Cellpose and other pure-pip PyTorch tools on x86 nodes this is option A with an extra installer to maintain.

### C. Apptainer image in the shared IRIS directory

Example shape: `/srv/scratch/iris/images/cellpose-4.2.1-cu128.sif`, run as `apptainer exec --nv --bind /srv/scratch <image> python -m cellpose ...`.

- **Who can create it.** **[V]** Apptainer builds a SIF from a Docker image without root: `apptainer build alpine.sif docker://alpine`. Building from a definition file needs one of the "fakeroot" modes, which depend on unprivileged user namespaces (and for the least restricted mode, `/etc/subuid` mappings or a setuid install). ([build a container](https://apptainer.org/docs/user/main/build_a_container.html), [fakeroot](https://apptainer.org/docs/user/main/fakeroot.html)) **[?]** Which of these Katana allows. **[I]** The image does not have to be built on Katana at all: a SIF is one file, so it can be built on any Linux machine (or converted from a Docker image built in CI) and copied into the shared directory. That sidesteps the question.
- **Pinning and updates.** **[V]** "Apptainer produces immutable images in the Singularity Image Format (SIF)"; a SIF is "compressed read-only". ([quick start](https://apptainer.org/docs/user/main/quick_start.html), [build a container](https://apptainer.org/docs/user/main/build_a_container.html)) **[I]** Pinning is the strongest of all options: one file, identifiable by checksum, containing its own Python and system libraries. An update is a new file; the definition file or Dockerfile lives in the repo.
- **GPU.** **[V]** `--nv` binds the host's GPU devices and "basic CUDA libraries" into the container. It requires that "the host has a working installation of the NVIDIA GPU driver", and that "the application inside your container was compiled for a CUDA version, and device capability level, that is supported by the host card and driver." ([GPU support](https://apptainer.org/docs/user/main/gpu.html)) **[I]** So a container does not escape the driver and GPU-generation constraints below; it has exactly the same PyTorch-variant problem as a venv.
- **libc caveat.** **[V]** "the libc version present in the container and on the host must not be too far apart or there will be libc mismatch errors", chiefly when the container's libc is older than the host's. ([GPU support](https://apptainer.org/docs/user/main/gpu.html)) **[I]** Katana is Rocky 8, so a container based on a current Debian or Ubuntu image has a newer libc than the host, which is the less risky direction.
- **Internet at run time.** **[I]** None, provided the image is a local `.sif` file and not a `docker://` reference (which would pull on first run).
- **Storage.** **[V]** Apptainer mounts `$HOME` and the working directory by default; other paths need `--bind`. ([quick start](https://apptainer.org/docs/user/main/quick_start.html)) **[?]** Whether Katana's Apptainer configuration already binds `/srv/scratch`.
- **Costs.** **[I]** A second toolchain (image build) that the venv route does not need, a multi-GB image, and reliance on a tool that ResTech's public docs do not describe or promise. The benefit over a venv is independence from Katana's `python/*` modules and one file instead of tens of thousands.

### D. Custom modulefile

- **Who can create it.** **[V]** Any user, per the Katana docs (template at `/apps/modules/templates/module_file`; enable with `module use --append <dir>`). **[V]** `module use` prepends or appends a directory to `MODULEPATH`. ([Environment Modules, `module`](https://modules.readthedocs.io/en/latest/module.html))
- **What it is.** **[I]** A modulefile only sets environment variables (`PATH`, and so on). It cannot be the environment; it points at one, which must be option A, B or C. For IRIS the job script would run `module use /srv/scratch/iris/modulefiles && module load iris-cellpose/4.2.1` instead of calling an absolute path.
- **Pinning and updates.** **[I]** One modulefile per version; the version is in the module name, which matches how every other IRIS workflow names its software. **[V]** Environment Modules supports explicit default versions through `.version` files. ([Environment Modules, `module`](https://modules.readthedocs.io/en/latest/module.html))
- **GPU, internet.** Inherited from whatever it wraps.
- **Costs and benefit.** **[I]** One more file per version and one more failure point (the two `module` gotchas already recorded in `AGENTS.md`). The benefit is that researchers can load the same environment by name in their own interactive sessions and Jupyter kernels, not only through the form. If the form is the only consumer, an absolute path in the job script does the same job with less.

### E. ResTech-installed module

- **Who can create it.** **[V]** ResTech only; users request it by email to `restech.support@unsw.edu.au`. **[?]** The internal process, turnaround, and whether ResTech will package a fast-moving pip-only tool. The module tree is `/apps/Modules/linux-rocky8-ivybridge`, a Spack-style naming, **[I]** which suggests modules are built with Spack; Spack would have to carry a recipe for the tool at the wanted version.
- **Pinning and updates.** **[V]** By module version name, as with every installed module. **[I]** Each update is a request to ResTech. The installed `pytorch/1.13.1` module is the one PyTorch on Katana; **[V]** that release dates from December 2022 ([PyPI](https://pypi.org/project/torch/1.13.1/)). **[I]** That gap is a fair guide to how often a deep-learning module gets refreshed.
- **GPU.** **[I]** ResTech's responsibility, and built against Katana's own `cuda/*` modules. **[?]** Whether `pytorch/1.13.1` works on the newer GPU nodes; a 2022 build predates the H200 and RTX Pro 6000.
- **Internet at run time.** **[I]** None.
- **Precedent.** **[V]** `neurodesk/*` (container-backed) and `ollama/*` modules show ResTech does install imaging and AI tooling as modules on request.
- **Fit.** **[I]** The fewest moving parts for IRIS at run time (`module load cellpose/4.2.1`, identical to the MNIST reference workflow), and backed by `/apps` rather than unbacked scratch. The cost is that IRIS no longer controls the version or the update schedule.

## Side by side

| | A. Shared venv | B. Shared conda env | C. Apptainer image | D. Custom modulefile | E. ResTech module |
|---|---|---|---|---|---|
| Documented by Katana | Yes, the recommended route for pip software | Per-user only; "not designed for multi-user" | No public mention | Yes | Yes |
| Who creates it | Anyone with write access to the shared directory | Same, after installing a conda distribution | Same; build on Katana unconfirmed, can be built elsewhere | Any user | ResTech admins only |
| Stands alone | Yes | Yes | Yes | No, wraps A, B or C | Yes |
| Pinned by | Requirements file + versioned directory | Lock file + versioned directory | One immutable file + checksum | Module version name | Module version name |
| Updated by | Building a new directory | Building a new directory | Building a new image | Adding a modulefile | Request to ResTech |
| Depends on Katana's `python/*` module | Yes | No | No | As wrapped | No |
| CUDA libraries come from | pip wheels | pip wheels or conda | Inside the image | As wrapped | Katana `cuda/*` modules |
| Host needs | NVIDIA driver new enough | Same | Same, plus Apptainer and `--nv` | As wrapped | Nothing extra |
| Internet at run time | No | No | No (local `.sif`) | No | No |
| Internet at build time | Yes | Yes | Yes, but build can be off-cluster | No | ResTech's concern |
| Covers the ARM GH200 node | No | Yes (separate ARM env) | Only with a separate ARM image | As wrapped | No (docs: modules do not work there) |
| Moving parts added | Fewest | Conda distribution | Image build toolchain | One file per version | None for IRIS, but an external dependency |
| Backed up | No (scratch) | No (scratch) | No (scratch) | No (scratch) | `/apps`, ResTech-managed |

In every "No (scratch)" cell the thing that needs backing up is the recipe (requirements file, lock file, definition file, modulefile), which is small and belongs in the IRIS repo.

## GPU and CUDA compatibility

This section applies equally to options A, B and C, because all three ship PyTorch's own CUDA libraries and rely on the host driver.

### What the sources say

- **[V]** Current PyTorch is 2.14.1, needs Python >= 3.10, and ships `manylinux_2_28` wheels for x86_64 and aarch64. ([PyPI](https://pypi.org/pypi/torch/json)) **[V]** `manylinux_2_28` is "AlmaLinux 8 based" and dropped glibc 2.26 distros. ([PyTorch 2.7.0 notes](https://github.com/pytorch/pytorch/releases/tag/v2.7.0)) **[I]** Rocky 8.9 is the same glibc generation, so current wheels install on Katana.
- **[V]** A plain `pip install torch` today pulls CUDA 13.0 libraries (`cuda-toolkit[...]==13.0.3`, `nvidia-cudnn-cu13`). ([PyPI](https://pypi.org/pypi/torch/json))
- **[V]** CUDA 13.0 libraries "Removed support for Maxwell, Pascal, and Volta GPUs, corresponding to compute capabilities earlier than Turing" (stated for cuSOLVER and cuFFT 13.0). ([CUDA release notes](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html))
- **[V]** Minimum Linux driver per toolkit: CUDA 11.8 >= 520.61.05, 12.1 >= 530.30.02, 12.6 >= 560.28.03, 12.8 >= 570.26, 12.9 >= 575.51.03, 13.0 >= 580. "The CUDA driver is backward compatible: applications compiled against a particular CUDA Toolkit version continue to work on subsequent (later) driver releases." ([CUDA release notes](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html))
- **[V]** Blackwell GPU support arrived in PyTorch 2.7.0 together with CUDA 12.8 builds. ([PyTorch 2.7.0 notes](https://github.com/pytorch/pytorch/releases/tag/v2.7.0))
- **[V]** In PyTorch 2.8.0, "support for sm50 - sm60 architectures with CUDA 12.8 and 12.9 has been dropped"; Volta (sm70) is not in that list. ([PyTorch 2.8.0 notes](https://github.com/pytorch/pytorch/releases/tag/v2.8.0))
- **[V]** CUDA variants offered per PyTorch version: 2.7.1 has cu118, cu126, cu128; 2.8.0 has cu126, cu128, cu129; 2.9.1 and 2.10.0 have cu126, cu128, cu130; 2.11.0 onwards have cu126, cu130, cu132 and no cu128. ([previous versions](https://pytorch.org/get-started/previous-versions/))
- **[V]** Katana has `libbeagle/3.1.2-cuda-sm70`, `-sm80`, `-sm89`, `-sm90` and `-sm120` modules (`available-modules.md`). **[I]** That is ResTech building one binary per GPU generation on the cluster, which matches V100 = sm70, A100 = sm80, L40S = sm89, H100/H200 = sm90 and RTX Pro 6000 (96 GB, so the Blackwell model) = sm120.

### What follows

All **[I]**; none of this has been run on Katana.

| PyTorch build | V100 (32 cards) | A100, L40S, H100, H200 | RTX Pro 6000 (16 cards) | Driver needed |
|---|---|---|---|---|
| Default PyPI wheel, 2.14.1 (CUDA 13) | Likely unsupported | Yes | Yes | >= 580 |
| `cu126` (any version to date) | Yes | Yes | Likely unsupported (Blackwell needs CUDA 12.8) | >= 560.28.03 |
| `cu128` (2.7.x to 2.10.0 only) | Yes | Yes | Yes | >= 570.26 |
| Katana `pytorch/1.13.1` module | Unknown | Unknown | Very unlikely | n/a |

- An unpinned `pip install cellpose`, which is what the current form does, takes the first row. With no `gpu_model` in the select line the scheduler may hand the job a V100, where it is likely to fail or fall back to CPU.
- `torch==2.10.0` from the `cu128` index is the newest build stated to span every x86 GPU generation Katana has. It is a single environment for the whole fleet, at the price of pinning PyTorch to a version that will age.
- The alternative is the newest PyTorch plus a `gpu_model` restriction in the form's select line that excludes V100. That gives up 32 of 186 cards and makes the form depend on Katana's `gpu_model` names.
- The GH200 node is never selected unless a job asks for `cpu_arch=aarch64`, so it can be ignored for v1.
- Python: Cellpose recommends 3.12 and says "python 3.9 and 3.11 will also work"; Katana has 3.10.8, 3.11.3 and 3.13.2 but no 3.12. **[I]** `python/3.11.3` is the only installed module that both Cellpose names and current PyTorch supports. The existing form uses `python/3.10.8`.

## Model weights

Separate from the environment, but it decides whether a job touches the internet.

- **[V]** Cellpose 4 downloads its model from `https://huggingface.co/mouseland/cellpose-sam/resolve/main/` "when you first run a pretrained model", into `$HOME/.cellpose/models/`, unless `CELLPOSE_LOCAL_MODELS_PATH` is set. ([Cellpose README](https://github.com/MouseLand/cellpose/blob/main/README.md), [`cellpose/models.py`](https://github.com/MouseLand/cellpose/blob/main/cellpose/models.py), [installation docs](https://cellpose.readthedocs.io/en/latest/installation.html))
- **[I]** So a ready-made environment alone does not make the first run offline, and the default location lands in the researcher's 10 GB home. Stage the weights once in the shared directory and have the job export `CELLPOSE_LOCAL_MODELS_PATH`. In an Apptainer image they can be baked in.
- **[V]** Current Cellpose is 4.2.1.1 (June 2026), depends on `torch>=1.6`, `torchvision`, `segment_anything` and `opencv-python-headless`, and declares no `python_requires`. ([PyPI](https://pypi.org/pypi/cellpose/json)) The existing form pins `cellpose==3.*`, which is the previous major version.

## Open questions for Patrick

None of these is answerable from public sources.

1. **Driver version.** What does `nvidia-smi` report on each GPU node type (V100, A100, L40S, H200, RTX Pro 6000)? This decides which PyTorch CUDA variants can run at all.
2. **GPU names.** What does `pbsnodes -av | grep gpu_model` list, and is the "RTX Pro 6000 96GB" the Blackwell card?
3. **Apptainer.** Version, path, whether it is on every compute node, whether `/srv/scratch` is bound by default, and whether unprivileged `apptainer build` (from `docker://` and from a definition file) works on Katana.
4. **Egress.** Is outbound internet from compute nodes policy or accident, and is it expected to stay? What is `netsandbox` for?
5. **Shared directory.** Can the IRIS directory be world-readable rather than group-only, does scratch have a purge or file-count policy, and is there a backed-up home for shared software other than `/apps`?
6. **Module requests.** Would ResTech install and keep current a `cellpose` module (or a general "imaging PyTorch" module), and on what turnaround? Would it accept a container-backed module the way Neurodesk is done?
7. **Python modules.** Are `python/*` modules ever removed or rebuilt in place? A shared venv depends on the one it was built from.
8. **`pytorch/1.13.1`.** Which Python and CUDA is it built with, and does it run on the H200 and RTX Pro 6000 nodes?
9. **Conda licensing.** Does UNSW have a position on Anaconda's default channel? Only matters if option B is taken.

## Sources

Katana (UNSW ResTech):

- https://docs.restech.unsw.edu.au/software/python/
- https://docs.restech.unsw.edu.au/software/installing_software/
- https://docs.restech.unsw.edu.au/software/environment_modules/
- https://docs.restech.unsw.edu.au/software/operating_systems/
- https://docs.restech.unsw.edu.au/software/jupyter-notebooks/
- https://docs.restech.unsw.edu.au/using_katana/about_katana/
- https://docs.restech.unsw.edu.au/using_katana/running_jobs/
- https://docs.restech.unsw.edu.au/using_katana/tips_katana/
- https://docs.restech.unsw.edu.au/storage/storage_locations/
- https://docs.restech.unsw.edu.au/help_support/faq/
- https://docs.restech.unsw.edu.au/AI_in_Katana/Ollama/
- https://docs.restech.unsw.edu.au/AI_in_Katana/StableDiffusion/
- https://github.com/unsw-restech/unsw-restech.github.io (docs source, including `docs/imaging/neurodesk.md`)
- `available-modules.md` (the installed module list kept outside the repo)

Third-party description of Katana:

- https://github.com/nf-core/configs/blob/master/conf/unsw_katana.config
- https://github.com/nf-core/configs/blob/master/docs/unsw_katana.md

Apptainer:

- https://apptainer.org/docs/user/main/gpu.html
- https://apptainer.org/docs/user/main/build_a_container.html
- https://apptainer.org/docs/user/main/fakeroot.html
- https://apptainer.org/docs/user/main/quick_start.html

Environment Modules and Python:

- https://modules.readthedocs.io/en/latest/module.html
- https://docs.python.org/3/library/venv.html

PyTorch, NVIDIA and Cellpose:

- https://pypi.org/pypi/torch/json
- https://pytorch.org/get-started/previous-versions/
- https://github.com/pytorch/pytorch/releases/tag/v2.7.0
- https://github.com/pytorch/pytorch/releases/tag/v2.8.0
- https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html
- https://github.com/MouseLand/cellpose/blob/main/README.md
- https://github.com/MouseLand/cellpose/blob/main/cellpose/models.py
- https://cellpose.readthedocs.io/en/latest/installation.html
- https://pypi.org/pypi/cellpose/json

Not reachable or not usable: `https://pytorch.org/get-started/locally/` returned page-builder markup rather than the install matrix, so the current version and CUDA variants were taken from PyPI metadata and the previous-versions page instead.
