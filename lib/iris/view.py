"""iris-view: a run's label volume over its raw volume, in napari.

Run in a Virtual Desktop. The raw volume comes through the volume reader
(iris.volume), so it reads exactly as inference read it, and the label
volume is read one slice at a time from its BigTIFF, so scrolling never
loads either whole. With no run directory it lists recent runs, from the
run index, to pick from.

    python -m iris.view [RUN_DIR]        # or bin/iris-view
"""

import argparse
import json
import sys
import threading
from datetime import datetime
from pathlib import Path

import dask
import dask.array as da
import tifffile

from iris.record import iris_home, run_index
from iris.volume import open_volume


def load_run(run_dir):
    """The raw volume and the label volume of the run in `run_dir`, as lazy
    (z, y, x) dask arrays. The dataset is the folder holding runs/. The
    label BigTIFF stays open while the arrays are in use."""
    run_dir = Path(run_dir)
    raw = open_volume(run_dir.parents[1]).data
    tif = tifffile.TiffFile(run_dir / "labels.tif")
    pages = tif.pages
    lock = threading.Lock()  # one file handle, so one seek and read at a time

    def read_slice(z):
        with lock:
            return pages[z].asarray()

    first = pages[0]
    slices = [da.from_delayed(dask.delayed(read_slice)(z), shape=first.shape, dtype=first.dtype)
              for z in range(len(pages))]
    return raw, da.stack(slices)


def recent_runs(home, limit=10):
    """Up to `limit` finished runs in the run index under `home`, newest
    first, as (run directory, its run.json) pairs. A run whose run directory
    or run.json has since gone is left out."""
    runs = []
    index = run_index(home)
    for pointer in index.iterdir() if index.is_dir() else ():
        run_dir = Path(pointer.read_text().strip())
        try:
            runs.append((run_dir, json.loads((run_dir / "run.json").read_text())))
        except (OSError, ValueError):
            continue
    runs.sort(key=lambda r: r[1].get("end_time", 0), reverse=True)
    return runs[:limit]


def pick_run(home):
    """List recent runs and ask which to view. Returns its run directory,
    or exits if there is none or the researcher quits."""
    recent = recent_runs(home)
    if not recent:
        sys.exit(f"No finished runs in {run_index(home)}. Name a run directory instead:"
                 " iris-view <dataset>/runs/<job ID>")
    print("Recent runs, newest first:")
    for n, (run_dir, run) in enumerate(recent, 1):
        ended = datetime.fromtimestamp(run.get("end_time", 0)).strftime("%Y-%m-%d %H:%M")
        print(f"{n:3}  {ended}  {run.get('status', '?'):8}  {run.get('experiment', '?')}  {run_dir}")
    while True:
        try:
            answer = input(f"Run to view (1-{len(recent)}, Enter to quit): ").strip()
        except EOFError:
            answer = ""
        if not answer:
            sys.exit(0)
        if answer.isdigit() and 1 <= int(answer) <= len(recent):
            return recent[int(answer) - 1][0]


def intensity_range(run_dir):
    """The volume's (min, max) from the run's dataset record, so napari
    need not read the volume to set its contrast, or None."""
    try:
        intensity = json.loads((Path(run_dir) / "dataset.json").read_text())["intensity"]
        return intensity["min"], intensity["max"]
    except (OSError, ValueError, KeyError, TypeError):
        return None


def open_viewer(run_dir, show=True):
    """A napari viewer with the run's volume and its labels over it, on the
    middle slice. napari.run() then hands control to its window."""
    import napari  # slow to import, so only once there is a run to show

    raw, labels = load_run(run_dir)
    viewer = napari.Viewer(title=f"iris-view {run_dir}", show=show)
    viewer.add_image(raw, name="volume", contrast_limits=intensity_range(run_dir))
    viewer.add_labels(labels, name="labels", opacity=0.5)
    return viewer


def main():
    parser = argparse.ArgumentParser(prog="iris-view", description=__doc__.split("\n\n")[0])
    parser.add_argument("run_dir", nargs="?", type=Path, metavar="RUN_DIR",
                        help="a run directory, <dataset>/runs/<job ID>; without one, pick from recent runs")
    args = parser.parse_args()
    run_dir = (args.run_dir or pick_run(iris_home())).resolve()
    if not (run_dir / "labels.tif").is_file():
        sys.exit(f"No label volume at {run_dir / 'labels.tif'}: is the run still going, or did it fail?"
                 " Its log is next to it in runs/.")
    print(f"Opening {run_dir} in napari. Close its window to quit.")
    import napari

    open_viewer(run_dir)
    napari.run()


if __name__ == "__main__":
    main()
