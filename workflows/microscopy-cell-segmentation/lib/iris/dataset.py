"""The dataset record: which data a run used, so a researcher can
find their dataset again and spot if it changed.

The job writes it to dataset.json in the run directory, and the importer
logs it on the MLflow run as the run's dataset input. It holds what is
true of any folder a workflow reads, whatever its data:

  path        the dataset folder
  files       how many files it holds, in every subfolder but runs/
  size_bytes  their total size
  mtime       the newest file's change, in UTC; null for a folder with none
  extras      the workflow's own details, such as a volume's shape: {} if
              it adds none

runs/ is left out, so the record holds still while runs write into it.
There is no content hash: it would mean reading the whole dataset again
just for the record.

This is run record format 2's dataset record (iris.runs). Format 1's held
the microCT workflow's details at its top level instead: "train",
"volume" and "intensity" beside "path".
"""

import os
from datetime import datetime, timezone
from pathlib import Path

from iris import rundir


def dataset_record(dataset, extras=None):
    """The record for the folder `dataset`, with the workflow's `extras`."""
    root = Path(dataset).resolve()
    stats = []
    for folder, subfolders, names in os.walk(root):
        if Path(folder) == root and rundir.RUNS in subfolders:
            subfolders.remove(rundir.RUNS)
        stats.extend(os.stat(Path(folder, name)) for name in names)
    newest = max((s.st_mtime for s in stats), default=None)
    return {
        "path": str(root),
        "files": len(stats),
        "size_bytes": sum(s.st_size for s in stats),
        "mtime": None if newest is None else datetime.fromtimestamp(newest, timezone.utc).isoformat(),
        "extras": dict(extras or {}),
    }
