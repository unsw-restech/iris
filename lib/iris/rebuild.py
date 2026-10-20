"""iris-rebuild: recreate a lost tracking store from run directories.

Scratch has no backup, but jobs never write the store (docs/adr/0001): each
run's record stays in its run directory, so the importer can replay them all
into a fresh store. By default it rebuilds /srv/scratch/$USER/iris/tracking.db
from the run index next to it; name dataset folders to rebuild from their
runs/ folders instead, if the run index is gone too. Each run lands under its
recorded experiment, named by its job ID. It never writes into a store that
already exists: --store points it at another folder, such as an empty one to
try a rebuild without touching your own. A rebuild that fails or is killed
leaves no store behind, so it can simply be run again.

    python -m iris.rebuild [--store FOLDER] [DATASET ...]    # or bin/iris-rebuild
"""

import argparse
import sys
from pathlib import Path

from iris.record import iris_home
from iris.tracking import STORE, StoreExists, rebuild


def main():
    parser = argparse.ArgumentParser(prog="iris-rebuild", description=__doc__.split("\n\n")[0])
    parser.add_argument("datasets", nargs="*", type=Path, metavar="DATASET",
                        help="dataset folders whose runs/ folders to rebuild from, instead of the run index")
    parser.add_argument("--store", type=lambda p: Path(p).resolve(), default=iris_home(), metavar="FOLDER",
                        help=f"the folder to create {STORE} in (default: %(default)s)")
    args = parser.parse_args()
    try:
        result = rebuild(args.store, datasets=args.datasets, index_home=iris_home())
    except StoreExists:
        sys.exit(f"{args.store / STORE} already exists, so there is nothing to rebuild."
                 " To try a rebuild, give --store an empty folder.")
    except FileNotFoundError as e:
        sys.exit(f"{e}." + ("" if args.datasets else
                            " With no run index, name the dataset folders to rebuild from."))
    print(f"Rebuilt {args.store / STORE} with {result['imported']} run(s)."
          + (f" Skipped {result['pending']} run directory(s) with no run.json." if result["pending"] else ""))


if __name__ == "__main__":
    main()
