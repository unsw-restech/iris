# IRIS coding standards

Read at review, against a diff. These are the judgement calls; every mechanical rule is in `bin/check`, which CI runs on each push, so a review takes a green `bin/check` as given and spends nothing re-checking what it covers.

## Domain language

- **Glossary terms, exactly.** Names, docstrings, comments, commit messages and issue text use the term `GLOSSARY.md` defines, never a word its _Avoid_ list names. Past drift: "scan" for Volume, `dataset_identity` for Dataset record, `environment()` for run tags (Environment means the versioned software set).
- **A new domain concept gets a glossary entry** in the same change, as `docs/agents/domain.md` describes.
- **ADRs hold.** A change that contradicts an ADR in `docs/adr/` either keeps to it or supersedes it with a new ADR.

## Forms

- **`hello-world` is the reference schema.** A form matches its structure, field order and comments. The one deliberate difference: imaging forms fail `check:` with `oc_assert` (AGENTS.md says why).
- **Defaults come from a real run.** Memory, walltime and epoch defaults cite the job that measured them, as `microct-2d-segmentation` does.

## Job code

- **A record step warns, a run step fails.** Writing the run record or dataset record only warns on failure; anything the run's own result depends on stops the job.
- **Killed halfway leaves a whole file or none.** Anything that writes a file a later run reads (a record, a pointer, a store) writes it under a temporary name and renames it into place, as `record.write_atomic` and `tracking.rebuild` do, or leaves a state the next run recovers from (the importer's `incomplete` tag). Walltime and `qdel` will interrupt it.
- **Katana facts cite their source.** A limit, module name or path in code or docs names the job ID, file or Patrick's confirmation (with date) behind it.
