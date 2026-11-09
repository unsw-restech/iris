# Each workflow carries its own copy of the library's job side

Supersedes ADR-0006's rule that `lib/iris` runs from the clone's `lib/`. Each workflow carries its own copy of the library's job side, the job library, the run record writer, the code recorder, the dataset record and the readers an entry script imports, in `workflows/<slug>/lib/`, and its form sources `$CODE/lib/iris-job.sh` from there. Under one shared `lib/`, a change the maintainer made could break a workflow nobody had looked at; with a copy, a library change reaches a workflow only when its owner updates the copy, by choice and with a new proof (Patrick, 2026-11-06, ADR-0008). `bin/libcopy` makes and updates the copy and records the commit it came from, and `bin/check` fails a copy that differs from `lib/` at that commit, so a copy is never edited by hand (#129, Patrick, 2026-11-07).

The shared side, the importer, `iris-view`, `iris-compare`, rebuild and tracking, stays one copy in the clone's `lib/`, since a researcher compares runs from different workflows in one place. It reads every run record format ever written, so a workflow on an old copy still imports. The rest of ADR-0006 holds: the entry script comes from the pane, and the copy is in the clone, in the workflow's folder, out of the pane.

## Consequences

- A fix to the job side reaches only the workflows it is copied into; a change says which.
- Each copy is about 50 KB in 12 files, kept in git with its workflow.
