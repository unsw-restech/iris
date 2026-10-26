# IRIS coding standards

Read at review, against a diff. These are the judgement calls; every mechanical rule is in `bin/check`, which CI runs on each push, so a review takes a green `bin/check` as given and spends nothing re-checking what it covers.

## Domain language

- **Glossary terms, exactly.** Names, docstrings, comments, commit messages and issue text use the term `GLOSSARY.md` defines, never a word its _Avoid_ list names. Past drift: "scan" for Volume, `dataset_identity` for Dataset record, `environment()` for run tags (Environment means the versioned software set).
- **A new domain concept gets a glossary entry** in the same change, as `docs/agents/domain.md` describes.
- **ADRs hold.** A change that contradicts an ADR in `docs/adr/` either keeps to it or supersedes it with a new ADR.

## Forms

- **`hello-world` is the reference schema.** A form matches its structure, field order and comments. The one deliberate difference: imaging forms fail `check:` with `oc_assert` (AGENTS.md says why).
- **Defaults come from a real run.** Memory, walltime and epoch defaults cite the job that measured them, as `microct-2d-segmentation` does.

## Pages

- **The guide owns staging and viewing.** A workflow page links `../../guide/#stage` and `#view` and keeps only what is specific to its workflow (its checklist, its dataset rules). Restating the guide's steps, layout tree or Virtual Desktop size is a copy that drifts. `bin/check` catches the host, quota, WinSCP, Globus link and Katana scratch collection ID markers; the rest is judgement.
- **README's "Citing IRIS" owns the citing rule.** A workflow page's "Cite this workflow" block is the one other full statement, for its own workflow. Everything else summarises and points to one of those two: the catalogue's Cite step, `CITATION.cff`'s `message`, a WorkflowHub entry's description; restating the at-or-before rule or the IRIS fallback anywhere else is a copy that drifts. Past drift: #77's catalogue step dropped both, then got the fallback too narrow.

## Job code

- **A record step warns, a run step fails.** Writing the run record or dataset record only warns on failure; anything the run's own result depends on stops the job.
- **Killed halfway leaves a whole file or none.** Anything that writes a file a later run reads (a record, a pointer, a store) writes it under a temporary name and renames it into place, as `record.write_atomic` and `tracking.rebuild` do, or leaves a state the next run recovers from (the importer's `incomplete` tag). Walltime and `qdel` will interrupt it.
- **Katana facts cite their source.** A limit, module name or path in code or docs names the job ID, file or Patrick's confirmation (with date) behind it.
