# A form's script carries its workflow code

Researchers want to change a workflow's code for one run, such as the model's architecture, without cloning the repo. OpenComposer's script pane is the one place on the form they can edit, and the text in it is exactly what is submitted. So each imaging form embeds its entry script (`src/run.py` for microCT) in its `script:` as a quoted heredoc, the job writes it into the run directory and runs it from there. `src/run.py` stays the single source: the form reads it at render time and never holds a copy. `lib/iris`, which keeps the run record the importer and `iris-compare` rely on, stays in the clone and out of the pane. This reverses part of the rule that a job runs `$CODE/src/...`: the entry script now comes from the pane, the rest still from the clone.

## Considered Options

- **Only a marked model section in the pane**: safer, but covers the architecture and nothing else; researchers also want to change the loss, augmentation or training loop.
- **The entry script and `lib/iris` both in the pane**: rejected, since an edit could then break the run record and leave the run invisible to the importer.
- **A copy of the workflow in the researcher's scratch, named by a form field**: rejected for now. It suits large changes but adds staging, and the code that ran is no longer visible on the form.
- **A second editable pane for the code**: not possible. OpenComposer 1.9.0 has one editable script pane and no multi-line text widget.

## Consequences

- OpenComposer regenerates the whole pane when a field the script uses changes, warning first but never merging. Researchers set the fields first and edit the code last; the pane's banner, the workflow page and an edited run's job output say so. After a failed `check:` the edits are kept but the warning is reset, so the next field change discards them silently.
- The form records the clone's commit when it renders, and the job writes that to `commit.txt`, since the embedded code dates from render time while `lib/` is read at job start. If the clone has moved in between, such as a `bin/syspull`, the job records the newer commit as `lib_commit` and warns.
- Every run keeps the `run.py` it ran and its diff against that commit, written before Python starts. A run whose code differs is an edited run: `run.json` says so, and the importer tags it and attaches both files. OpenComposer keeps no lasting copy of the submitted script, so the run directory is the only record.
- An edited run cites its citable version and commit, and publishes its `run.py` or diff alongside.
- Embedded code can contain neither `#{` (OpenComposer substitutes a field name, or drops the line if the field is empty) nor `<%` (ERB); `bin/check` enforces it.
- `hello-world` keeps its plain script: it is onboarding and has no code worth editing.
