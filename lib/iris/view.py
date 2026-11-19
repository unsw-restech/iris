"""iris-view: a run's label volume over its image set or raw volume, in napari.

Run in a Virtual Desktop. The images come through the readers in
iris.volume, so they read exactly as inference read them, and the label
volume is read one slice at a time from its BigTIFF, so scrolling never
loads either whole. With no run directory it lists recent runs, from the
run index, to pick from.

    python -m iris.view [RUN_DIR]        # or bin/iris-view
"""

import argparse
import sys
import threading
from datetime import datetime
from pathlib import Path

import dask
import dask.array as da
import tifffile

from iris import rundir, runs
from iris.record import indexed_runs, iris_home, run_index
from iris.volume import IMAGE_SET, open_image_set, open_volume


def recorded_files(run_dir):
    """The image set's file names, in page order, that the run's dataset
    record holds, or None for a run that read a volume or recorded none."""
    try:
        return runs.read_run(run_dir).dataset_extras()["image_set"]["files"]
    except (OSError, ValueError, KeyError, TypeError):
        return None


def open_images(run_dir):
    """The layer name and lazy (page, y, x) images under the run's labels:
    the image set its dataset record names, or its dataset's volume when
    the record names none. An image set that no longer holds the files the
    run recorded, in that order, raises ValueError naming one, so no label
    page is shown over another image."""
    dataset = rundir.dataset_of(run_dir)
    files = recorded_files(run_dir)
    if files is None:
        return "volume", open_volume(dataset).data
    images = open_image_set(dataset)
    now = images["image"].values.tolist()
    if now != files:
        added = sorted(set(now) - set(files))
        removed = sorted(set(files) - set(now))
        change = (f"{added[0]} has been added" if added else f"{removed[0]} has gone" if removed
                  else "its files have been renamed")
        raise ValueError(f"{Path(dataset, IMAGE_SET)} no longer holds the {len(files)} images this run labelled: "
                         f"{change}. Put the image set back as the run read it to view its labels.")
    return "images", images.data


def load_run(run_dir):
    """The images and the label volume of the run in `run_dir`, as lazy
    dask arrays with one image or z-slice per page of the labels, as
    open_images gives them. The dataset is the folder holding runs/. The
    label BigTIFF stays open while the arrays are in use."""
    _, raw, labels = open_run(run_dir)
    return raw, labels


def open_run(run_dir):
    """load_run's arrays, after open_images's layer name."""
    run_dir = Path(run_dir)
    name, raw = open_images(run_dir)
    tif = tifffile.TiffFile(run_dir / rundir.LABELS)
    pages = tif.pages
    lock = threading.Lock()  # one file handle, so one seek and read at a time

    def read_slice(z):
        with lock:
            return pages[z].asarray()

    first = pages[0]
    slices = [da.from_delayed(dask.delayed(read_slice)(z), shape=first.shape, dtype=first.dtype)
              for z in range(len(pages))]
    return name, raw, da.stack(slices)


def recent_runs(home, limit=10):
    """Up to `limit` runs in the run index under `home` that finished with
    a label volume, so have a whole one, newest first, as (run directory,
    its record, iris.runs.Run) pairs, whatever format recorded them. A
    run whose workflow writes no label volume is left out, as is one whose
    run directory or run.json has since gone or can't be read."""
    found = []
    for _, run_dir in indexed_runs(run_index(home)):
        try:
            run = runs.read_run(run_dir)
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if run.status == "FINISHED" and (run_dir / rundir.LABELS).is_file():
            found.append((run_dir, run))
    found.sort(key=lambda r: r[1].end_time, reverse=True)
    return found[:limit]


def pick_run(home):
    """List recent runs and ask which to view. Returns its run directory,
    or exits if there is none or the researcher quits."""
    recent = recent_runs(home)
    if not recent:
        sys.exit(f"No finished runs in {run_index(home)}. Name a run directory instead:"
                 " iris-view <dataset>/runs/<job ID>")
    print("Recent runs, newest first:")
    for n, (run_dir, run) in enumerate(recent, 1):
        ended = datetime.fromtimestamp(run.end_time).strftime("%Y-%m-%d %H:%M")
        print(f"{n:3}  {ended}  {run.experiment}  {run_dir}")
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
    """The images' (min, max) from the run's dataset record, so napari
    need not read them all to set its contrast, or None."""
    try:
        intensity = runs.read_run(run_dir).dataset_extras()["intensity"]
        return intensity["min"], intensity["max"]
    except (OSError, ValueError, KeyError, TypeError):
        return None


def show(run_dir, name, raw, labels):
    """Open napari on open_run's arrays for the run in `run_dir`, the
    images layer called `name` and the label volume over it, until its
    window is closed. Its slider steps through the images or z-slices."""
    import napari  # slow to import, so only once there is a run to show

    viewer = napari.Viewer(title=f"iris-view {run_dir}")
    viewer.add_image(raw, name=name, contrast_limits=intensity_range(run_dir))
    viewer.add_labels(labels, name="labels", opacity=0.5)
    napari.run()


def main():
    parser = argparse.ArgumentParser(prog="iris-view", description=__doc__.split("\n\n")[0])
    parser.add_argument("run_dir", nargs="?", type=Path, metavar="RUN_DIR",
                        help="a run directory, <dataset>/runs/<job ID>; without one, pick from recent runs")
    args = parser.parse_args()
    run_dir = (args.run_dir or pick_run(iris_home())).resolve()
    if not (run_dir / rundir.LABELS).is_file():
        sys.exit(f"No label volume at {run_dir / rundir.LABELS}: is the run still going, or did it fail?"
                 " Its log is next to it in runs/. Some workflows write no label volume, so have nothing to view.")
    try:
        opened = open_run(run_dir)
    except (FileNotFoundError, ValueError) as e:
        sys.exit(f"ERROR: {e}")
    print(f"Opening {run_dir} in napari. Close its window to quit.")
    show(run_dir, *opened)


if __name__ == "__main__":
    main()
