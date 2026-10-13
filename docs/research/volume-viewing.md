# Viewing microCT volumes through Katana OnDemand

Research for [issue #8](https://github.com/PatrickTung/iris/issues/8), map [issue #1](https://github.com/PatrickTung/iris/issues/1). Researched 2026-10-13.

Every claim is tagged:

- **[V]** verified against the cited primary source on 2026-10-13.
- **[I]** inference drawn from verified facts; not stated by any source.
- **[?]** could not be confirmed from a public source. Collected under [Open questions for Patrick](#open-questions-for-patrick).

Nothing here was run on Katana. Katana module names come from the local `available-modules.md` list, not from a live `module avail`.

## Short answer

1. Katana OnDemand already offers a **Virtual Desktop**, **JupyterLab**, **RStudio** and a **terminal**. Whether a desktop session can get a GPU or hardware OpenGL is **not documented publicly**.
2. **napari** runs in an Open OnDemand VNC desktop only if OpenGL 2.1 or later is available inside the VNC session. A VNC X proxy has no GPU access by itself; hardware rendering needs VirtualGL (`vglrun`) plus a job that holds a GPU. napari is lazy for dask, zarr and xarray arrays, but **its built-in reader does not read `.nc` and reads a single TIFF file eagerly**, so lazy loading needs a short launcher script.
3. **Fiji** and **ParaView** are already Katana modules and need no install. Fiji handles TIFF stacks larger than RAM as virtual stacks with no OpenGL. ParaView reads netCDF directly.
4. Open OnDemand has **no way to pre-fill an interactive app form from a URL**, and its maintainers have ruled out launching a session from a link. "One click on a given path" is not achievable with stock Open OnDemand. The closest stock route is a custom app whose form computes its default path with ERB, reached from an icon OpenComposer already puts on its history page.

## 1. What Katana OnDemand offers today

- **[V]** "Katana OnDemand allows you to run Virtual Desktop giving you access to multiple graphical applications, JupyterLab, RStudio, and a Terminal Session of Katana on your web browser." It is at `https://kod.restech.unsw.edu.au` and needs campus network or the UNSW VPN. Files in `/home`, `/srv/scratch` and project storage are reachable from its Files menu. Source: https://docs.restech.unsw.edu.au/using_katana/ondemand/
- **[V]** ResTech's own docs point GUI software at OnDemand: Ansys, COMSOL and MATLAB are each described as best run interactively through Katana OnDemand. Source: https://docs.restech.unsw.edu.au/software/others/
- **[V]** JupyterLab "is best run via Katana OnDemand"; users add their own kernels from a venv or conda environment (`install_jupyter_kernels`, or `python3 -m ipykernel install --prefix=$HOME/.local --name=...`). Source: https://docs.restech.unsw.edu.au/software/jupyter-notebooks/
- **[V]** There is precedent for imaging inside the JupyterLab app: the Neurodesk page has users build a venv with `ipyniivue` (a browser-rendered viewer), register it as a kernel, and launch JupyterLab from OnDemand after choosing a compute node and walltime. Source: https://docs.restech.unsw.edu.au/imaging/neurodesk/
- **[V]** Katana has GPU nodes, requested in PBS with `ngpus` and optionally `gpu_model`, e.g. `qsub -I -l select=1:ncpus=2:mem=8gb:ngpus=1:gpu_model=A100`. Source: https://docs.restech.unsw.edu.au/using_katana/running_jobs/
- **[V]** Relevant modules present in `available-modules.md`: `fiji/20240614-2117`, `paraview/5.10.1`, `5.11.1`, `6.0.0`, `slicer/5.2.2` and `5.6.2`, `neurodesk/itksnap/4.0.2`, `mesa/22.1.2`, `vtk/9.0.3`, `python/3.11.3` and `3.13.2`, `ood-jupyterlab/3.4.8` to `4.6.1`. There is **no** `napari`, `virtualgl` or `turbovnc` module.
- **[?]** The public docs do not list the Virtual Desktop form fields. Whether it offers a GPU option, which desktop environment it runs, and whether VirtualGL is installed on the nodes are all undocumented. The absence of a `virtualgl` module does not prove VirtualGL is absent; it may be installed system-wide.
- **[?]** Which Open OnDemand version Katana runs. It matters for form widgets (`path_selector`) and for anything added in 4.x.

## 2. Open OnDemand: desktops, GPUs and adding an app

### How interactive apps work

- **[V]** An interactive ("batch connect") app is a directory holding `manifest.yml`, `form.yml` (or `form.yml.erb`), `submit.yml.erb`, a `template/` directory (`before.sh.erb`, `script.sh.erb`, optional `after.sh`, `clean.sh`) and, for non-VNC apps, `view.html.erb`. Source: https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive.html
- **[V]** Two kinds exist. A **VNC app** sets `batch_connect: template: vnc` in `submit.yml.erb`; Open OnDemand starts the VNC server and websockify itself ("you DO NOT need to start the VNC server process") and the app must not ship `view.html.erb`. A **basic app** starts a web server on the compute node and the browser reaches it through the reverse proxy at `/node/<host>/<port>` or `/rnode/<host>/<port>`. Sources: https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/template.html , https://osc.github.io/ood-documentation/latest/reference/files/submit-yml/vnc-bc-options.html , https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/view.html , https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/setup/enable-reverse-proxy.html
- **[V]** Desktop environments supported for VNC sessions on compute nodes: Xfce 4+, MATE 1+ (default), GNOME 2. Source: https://osc.github.io/ood-documentation/latest/enable-desktops/software-requirements.html
- **[V]** A working example of a single-application VNC viewer is OSC's ParaView app: `submit.yml.erb` uses `template: vnc` and requests a GPU; `template/script.sh.erb` starts the Xfce window manager, loads the `virtualgl` and ParaView modules, then runs `vglrun paraview`. The repo was pushed to as recently as 2026-10-07. Source: https://github.com/OSC/bc_osc_paraview (`template/script.sh.erb`, `submit.yml.erb`). It targets Slurm; the PBS Pro resource request for Katana would differ **[I]**.

### GPU and OpenGL inside a VNC session

- **[V]** A VNC session does not get GPU-accelerated OpenGL by itself. X proxies such as VNC "render X Window System drawing commands to a virtual framebuffer in main memory rather than to a real framebuffer in GPU memory". VirtualGL fixes this by redirecting an application's OpenGL to a GPU on the server and handing only rendered frames to the X proxy. Source: VirtualGL User's Guide, https://rawcdn.githack.com/VirtualGL/virtualgl/main/doc/index.html
- **[V]** VirtualGL has two back ends. The GLX back end needs a 3D X server attached to the GPU. The EGL back end "accesses a GPU through an associated EGL device without the need for a 3D X server", selected with `vglrun -d egl0` (or a DRI device path). The EGL back end does not support every GLX extension. Same source.
- **[I]** So hardware rendering in a Katana desktop needs three things at once: the PBS job holds a GPU (`ngpus=1`), VirtualGL is installed on that node, and the viewer is started under `vglrun`. Without them, OpenGL falls back to whatever software renderer the VNC server or a Mesa build provides, if any.
- **[?]** Whether Katana's desktop sessions currently provide any OpenGL at all (software or hardware). Running `glxinfo | grep -E "OpenGL (renderer|version)"` in a Virtual Desktop session answers it in one line.

### Opening the viewer on a given path

- **[V]** Open OnDemand cannot pre-fill an interactive app form from URL parameters. An OOD developer answered this exact question on 2026-01-16: it "is not currently supported". Source: https://discourse.openondemand.org/t/pre-filling-application-form-submitting-job-via-url/4714
- **[V]** The feature request is open in the Backlog milestone: https://github.com/OSC/ondemand/issues/4849 . In it a maintainer rules out launching from a link: auto-submission "can't happen because these are GET requests and we cannot be modifying the system through GET requests (launching/submitting ... happens through POST requests which need an authenticity token to protect against CSRF attacks)".
- **[V]** The source agrees. On the default branch (latest release v4.2.5), `SessionContextsController#new` reads only `params[:session_id]` (to reload a previous session's values) and otherwise fills the form from the per-user cache file; no other query parameter is read. Source: https://github.com/OSC/ondemand/blob/master/apps/dashboard/app/controllers/batch_connect/session_contexts_controller.rb
- **[V]** What stock Open OnDemand does provide:
  - `form.yml.erb`: the form can contain ERB, so defaults can be computed in Ruby when the form renders. Source: https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/form.html
  - Form values are cached per user by default and reappear next time; caching can be turned off per attribute with `cacheable`. Same source.
  - A `path_selector` widget: a text field plus a button opening a file-browser modal, with options `directory` (start directory), `show_files`, `show_hidden`, `favorites`. Source: https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/form-widgets.html
  - Hard-coded attributes and sub-apps: a variant of an app with every attribute fixed, so the user is "not presented with any choice" and only presses Launch. Sub-app files live in the app's `local/` directory or `/etc/ood/config/apps/<app>/`. Source: https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/sub-apps.html
  - Saved settings (`bc_saved_settings`, off by default): users save named form configurations and relaunch them from a play icon. Source: https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/saved-settings.html
- **[V]** OpenComposer can link to an Open OnDemand app. `manifest.yml` accepts `related_apps:` naming "an application registered in Open OnDemand. The specified application is displayed on the history page"; on the history page, "If an icon is shown next to the application name, clicking it will open the Open OnDemand application page directly." The docs do not describe passing the job's directory to that app. Sources: https://github.com/RIKEN-RCCS/OpenComposer/blob/main/docs/application.html , https://github.com/RIKEN-RCCS/OpenComposer/blob/main/docs/manual.html
- **[I]** The closest stock route to "one click on a path": the IRIS workflow job writes its output path to a small per-user pointer file (for example `~/.iris/last-output`); the viewer app's `form.yml.erb` reads that file and uses it as the default of its path field. The researcher then clicks the viewer icon on the OpenComposer history page, presses Launch, waits for the PBS job to start, and presses the connect button. That is three clicks and a queue wait, with no typing. The path field would need `cacheable: false`, otherwise the cached previous value is likely to win over the ERB default. This has not been tested.
- **[I]** A session always costs at least two interactions after arriving at the form (Launch, then connect once the job is running), because launch is a POST and the session is a queued PBS job. The two-click bar in the map covers launching a workflow; viewing cannot be folded into it.

### Installing the app

- **[V]** Development apps live in the developer's `~/ondemand/dev/<app>` once an admin has enabled development mode for that user (a symlink under `/var/www/ood/apps/dev/<user>/gateway`). Only enabled users see the Develop menu. System apps, visible to everyone, live in `/var/www/ood/apps/sys/<app>`. Source: https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html
- **[I]** A viewer app in Patrick's dev sandbox is visible only to Patrick. For researchers to use it, ResTech must install it as a system app. The map already records that new interactive apps can be installed.
- **[?]** Whether OpenComposer's `related_apps` resolves a dev-sandbox app or only system apps. The doc says "registered in Open OnDemand" and no more.

## 3. napari

### What it needs

- **[V]** Python 3.11 or later (`requires-python = ">=3.11"` on the default branch), a Qt binding (PyQt6 is the default of `napari[all]`; PySide6 and PyQt5 also supported) and vispy `>=0.17,<0.18`. Sources: https://github.com/napari/napari/blob/main/pyproject.toml , https://napari.org/stable/getting_started/installation.html
- **[V]** vispy: "The OpenGL version must be at least 2.1", and it expects an up-to-date GPU driver. Source: https://vispy.org/installation.html
- **[V]** napari's docs treat remote display as fragile. Listing ways to see a remote X server, they say "VNC (might have issues with OpenGL)" and note "napari relies on OpenGL for its (hardware) accelerated parts, we need to ensure that the piece we choose are OpenGL compatible". Without a GPU "everything will be rendered in the CPU. Expect some performance overhead!" Source: https://napari.org/stable/howtos/docker.html
- **[V]** Headless use (`QT_QPA_PLATFORM=offscreen`, `Viewer(show=False)`) is for scripting and screenshots, not for interactive viewing. Source: https://napari.org/stable/howtos/headless.html
- **[V]** There is no napari module on Katana (`available-modules.md`). Katana does carry `python/3.11.3` and `python/3.13.2`, either of which satisfies the Python requirement.
- **[I]** napari would be the one piece of software IRIS has to install and maintain itself (a venv or conda environment in the shared IRIS directory, built on a login node because compute nodes may lack internet). Fiji and ParaView need none of that.

### Lazy loading

- **[V]** napari accepts numpy, dask, xarray and zarr arrays and "will also wait until just before it displays data onto the screen to actually generate a NumPy array from your data, and so if you're using a library like dask or zarr that supports lazy loading and lazy evaluation, we won't force you to load or compute data that you're not examining." Source: https://napari.org/stable/howtos/layers/image.html
- **[V]** With big lazy arrays, pass `contrast_limits` and `multiscale=False` explicitly, which "prevents napari from trying to calculate the data min/max, which can take an extremely long time with big data". Source: https://napari.org/stable/tutorials/processing/dask.html
- **[V]** 3D rendering is not out-of-core. The pipeline is: slicing "loads the corresponding 2D or 3D region of the layer's ND data into RAM", then drawing "pushes the 2D or 3D sliced data from RAM to VRAM"; and "Sliced layer data may exceed the maximum texture size supported by the GPU." For multiscale data, "in 3D the coarsest level is used for performance." Sources: https://napari.org/stable/guides/rendering.html , https://napari.org/stable/howtos/layers/image.html
- **[I]** So lazy loading buys cheap 2D slice browsing of a volume far larger than RAM. A 3D rendering of a full-resolution microCT volume needs the whole volume in RAM and in GPU memory, or a downsampled copy. For a 2000 x 2000 x 2000 16-bit volume that is 16 GB before any pyramid.

### Readers for netCDF and TIFF

- **[V]** napari's built-in reader does not claim `.nc`: its filename patterns include `*.tif`, `*.tiff`, `*.ome.tif`, `*.zarr`, `*.npy`, `*.h5` and many camera formats, but no netCDF extension. Source: https://github.com/napari/napari/blob/main/src/napari_builtins/builtins.yaml
- **[V]** The built-in reader is lazy only for zarr and for multiple files. `magic_imread` sets `use_dask = len(filenames) > 1`; a single file goes through `imageio.v3.imread` into a numpy array, i.e. fully into RAM. A directory of TIFFs, or several files, becomes a dask stack with one delayed read per file. Source: https://github.com/napari/napari/blob/main/src/napari_builtins/io/_read.py
- **[V]** `napari my_image.tif` opens a file from the command line. Source: https://napari.org/stable/getting_started/launch_napari.html
- **[V]** netCDF can be opened lazily in Python with xarray: `xr.open_dataset("file.nc", chunks={...})` returns dask-backed arrays that are not read until computed; `xr.open_mfdataset('files/*.nc')` does the same across many files; engines are `netcdf4` (default), `h5netcdf` and `scipy`. Source: https://docs.xarray.dev/en/stable/user-guide/dask.html
- **[V]** A large single TIFF can be read lazily with tifffile, which can return image data "as NumPy arrays or Zarr arrays/groups" and can memory-map contiguous uncompressed data (`tifffile.memmap`). Source: https://github.com/cgohlke/tifffile/blob/master/README.rst
- **[I]** napari can therefore view both `.nc` input and large TIFF output lazily, but only through a launcher script of a few lines (open with xarray or tifffile, hand the array to `napari.imshow` with fixed contrast limits) or a reader plugin. A bare `napari file.nc` will not work, and a bare `napari big.tif` loads the whole file.
- **[?]** A maintained napari reader plugin for netCDF was not searched for on napari hub. A launcher script avoids the dependency either way.

## 4. Lighter alternatives

### Fiji / ImageJ (module `fiji/20240614-2117`)

- **[V]** Virtual stacks are "disk resident (as opposed to RAM resident)" and "the only way to load image sequences that do not fit in RAM". Opened through File > Import > TIFF Virtual Stack or Image Sequence, or by dropping a `.tif` on the toolbar. They are read-only, and commands that create a new stack (for example Crop) produce a RAM-resident one. Source: https://imagej.net/ij/docs/guide/146-8.html
- **[V]** ImageJ opens files passed on the command line and can run a macro at start (`-macro`, `-eval`, `-run`), so a wrapper can open a chosen path. Source: https://imagej.net/ij/docs/install/linux.html . Fiji's launcher takes `-macro file.ijm 'arguments'`: https://imagej.net/learn/headless
- **[V]** The 3D Viewer plugin renders stacks as "texture-based volume renderings, surfaces or orthoslices" using "hardware-accelerated visualization ... using the Java 3D library". Source: https://imagej.net/plugins/3d-viewer/
- **[I]** 2D slice browsing in Fiji uses ordinary Java drawing, not OpenGL, so it should work in a plain VNC desktop with no GPU. Only the 3D Viewer has the same OpenGL dependency as napari.
- **[?]** Whether Fiji as installed on Katana can open the microCT `.nc` files. The part of the Bio-Formats supported-formats table that could be read lists TIFF and OME-TIFF and showed no netCDF row, but the page could not be read reliably end to end, so absence is not established. Source consulted: https://bio-formats.readthedocs.io/en/latest/supported-formats.html . Test with a sample file. If results are TIFF anyway, Fiji covers results without it.

### ParaView (modules `paraview/5.10.1`, `5.11.1`, `6.0.0`)

- **[V]** ParaView reads netCDF directly. The NetCDF Reader "Reads arrays from NetCDF files into structured VTK data sets. In the absence of any other information, the files will be read as image data", and it also understands CF/COARDS metadata. Source: https://www.paraview.org/paraview-docs/v5.13.3/python/paraview.simple.NetCDFReader.html
- **[V]** A file can be opened at start with `paraview --data=<file>`, and numbered file series are detected and grouped automatically. Source: https://docs.paraview.org/en/latest/UsersGuide/dataIngestion.html
- **[V]** "The desktop Qt client can only operate in on-screen mode and hence needs an accessible X server." Headless rendering uses EGL (hardware) or OSMesa (software), and "VTK is capable of detecting a suitable OpenGL context backend at runtime and fallback to pure software based rendering through OSMesa." Source: https://www.paraview.org/paraview-docs/latest/cxx/Offscreen.html
- **[V]** OSC's Open OnDemand ParaView app is a ready pattern: VNC template plus `vglrun paraview`. Source: https://github.com/OSC/bc_osc_paraview
- **[I]** ParaView is the only already-installed tool that covers both `.nc` input and 3D volume rendering with no new software. Its costs are a heavier interface for a researcher who only wants to scroll slices, and no lazy slice-on-demand: it reads the selected arrays into memory.
- **[?]** Whether the Katana ParaView modules were built with a software OpenGL fallback (the `mesa/22.1.2` module suggests one exists) and how ParaView's TIFF stack reading behaves on large volumes. Neither was checked against a primary source.

### Browser-based viewers

- **[V]** Neuroglancer "is purely a client-side program, but it depends on data being accessible via HTTP in a suitable format": precomputed, N5, Zarr and OME-Zarr, single NIfTI files, Deep Zoom, or in-memory volumes served by its Python package. It needs WebGL 2 in the researcher's browser. netCDF and TIFF are not among its sources. Source: https://github.com/google/neuroglancer/blob/master/README.md
- **[I]** Neuroglancer on Katana would mean converting every volume to a chunked format and running an HTTP data server inside a PBS job behind the Open OnDemand reverse proxy (a "basic" interactive app). It renders on the researcher's own GPU, which removes the cluster-GPU question, but it adds a conversion step and a server process. That is the opposite of fewer moving parts.
- **[V]** itkwidgets is a Jupyter 3D image viewer that accepts numpy, dask, xarray and zarr data and renders in the browser through WebGL. Source: https://itkwidgets.readthedocs.io/en/latest/
- **[I]** A notebook in the existing JupyterLab app is the route with the least new infrastructure: no new Open OnDemand app, no VNC, no cluster GPU, and it reads `.nc` lazily through xarray. Its costs: each researcher needs a kernel with the viewer packages (or IRIS provides a shared one), opening a notebook is more than one click, and a notebook is a weaker instrument than Fiji or napari for inspecting a volume. itkwidgets' behaviour on multi-gigabyte volumes was not verified.

### Other modules already on Katana, not researched

`slicer/5.2.2` and `5.6.2` (3D Slicer) and `neurodesk/itksnap/4.0.2` are installed and are volume viewers. They were out of the ticket's list and were not investigated.

## 5. Side by side

| | Fiji | ParaView | napari | JupyterLab notebook viewer | Neuroglancer |
|---|---|---|---|---|---|
| On Katana today | Module **[V]** | Module **[V]** | No module **[V]**; IRIS installs it | JupyterLab app exists **[V]**; viewer packages per kernel | Not installed |
| Reads `.nc` | Unconfirmed **[?]** | Yes, built-in reader **[V]** | Not built in **[V]**; via xarray in a launcher script | Yes, via xarray **[V]** | No; convert first **[V]** |
| Reads TIFF | Yes **[V]** | Not verified from a source **[?]** | Yes **[V]** | Yes, via tifffile **[V]** | No; convert first **[V]** |
| Larger than RAM | Yes for TIFF, as a read-only virtual stack **[V]** | Loads arrays into memory **[I]** | Yes for 2D slicing with dask or zarr **[V]**; single TIFF and `.nc` only via script **[V]** | Yes for slicing, via dask **[V]** | Yes, by design, after conversion **[V]** |
| 3D volume rendering | 3D Viewer plugin, needs OpenGL **[V]** | Yes, its main purpose | Yes, whole volume in RAM and VRAM **[V]** | itkwidgets, in the browser **[V]** | Cross-sections and meshes **[V]** |
| Needs OpenGL on the node | No for slices **[I]**; yes for 3D | Yes; software fallback possible **[V]** | Yes, OpenGL 2.1+ **[V]** | No; renders in the browser | No; renders in the browser |
| Needs a cluster GPU | No | Only for smooth 3D | For acceptable 3D **[I]** | No | No |
| Open OnDemand route | Existing Virtual Desktop, or a small VNC app | Existing Virtual Desktop, or a VNC app (OSC pattern) **[V]** | New VNC app | Existing JupyterLab app | New basic app with a data server |
| New things IRIS maintains | None, or one small app | None, or one small app | Python environment, launcher script, app | Kernel environment, notebook | Converter, server, app |

## 6. What this suggests

This is inference, offered as input to the decision ticket, not a decision.

- The lightest thing that could work is **no new software at all**: the existing Virtual Desktop with `module load fiji` for TIFF results and `module load paraview` for `.nc` input. It costs the researcher a terminal command inside the desktop, which breaks the "no terminal step" preference.
- One small custom VNC app removes that terminal step. It would take a path (ERB default from a pointer file, `path_selector` to change it), load a module and start the viewer on that path. Built around Fiji or ParaView it needs no environment; built around napari it also needs a maintained Python environment and a launcher script.
- napari earns its extra weight only if researchers need what the other two lack: lazy slice browsing of `.nc` without conversion, or Python-side overlays such as segmentation labels on top of the raw volume. If viewing means "scroll through the TIFF result", Fiji already does that with nothing to install and no GPU.
- Whatever is chosen, the GPU question decides how good 3D looks, not whether slices can be viewed.

## Open questions for Patrick

These are UNSW-internal or need a test on Katana; none could be answered from public sources.

1. Does the Katana OnDemand Virtual Desktop form offer a GPU, and is VirtualGL (`vglrun`) installed on the nodes it runs on? What does `glxinfo | grep -E "OpenGL (renderer|version)"` print in a desktop session today?
2. Which desktop environment and VNC server do Katana's desktop sessions use, and which Open OnDemand version is Katana on?
3. What does a real microCT `.nc` look like: one file or a directory of block files, which variable holds the volume, netCDF-3 or netCDF-4, dimensions and dtype, total size? This decides whether ParaView's generic reader and Fiji can open it unconverted, and whether 3D rendering at full resolution is realistic.
4. What do researchers need from viewing: scroll slices of the result, 3D rendering, or overlaying a segmentation on the raw volume? This is the question that chooses between Fiji, ParaView and napari.
5. Does OpenComposer's `related_apps` accept an app in the dev sandbox, or only a system app? And who installs the viewer as a system app when IRIS goes live?
6. Is a three-click, queue-wait launch of the viewer (history-page icon, Launch, connect) acceptable, given that Open OnDemand cannot open a session from a link?

## Sources not reachable or not conclusive

- `https://docs.restech.unsw.edu.au/restech-docs-2/using_katana/ondemand.html` returned 404; the current page at `/using_katana/ondemand/` was used instead.
- `https://www.paraview.org/Wiki/ParaView/ParaView_And_Mesa_3D` redirects to `docs.paraview.org`; the Offscreen rendering page was used instead.
- The Bio-Formats supported-formats page was too long to read reliably in one pass; the Fiji netCDF question is left open rather than answered from it.
- The napari "rendering" and "image layer" pages were read from their Markdown sources in `github.com/napari/docs` (the rendered pages are very large); the URLs cited are the rendered pages for the same content.
