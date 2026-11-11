# IRIS coding standards

Read at review, against a diff. These are the judgement calls; every mechanical rule is in `bin/check`, which CI runs on each push, so a review takes a green `bin/check` as given and spends nothing re-checking what it covers.

## Domain language

- **Glossary terms, exactly.** Page text, names, docstrings, comments, commit messages and issue text use the term `GLOSSARY.md` defines, never a word its _Avoid_ list names. Past drift: "scan" for Volume, `dataset_identity` for Dataset record, `environment()` for run tags (Environment means the versioned software set).
- **A new _Avoid_ word leaves no uses behind.** A diff that adds a word to an _Avoid_ list rewords every use of it across tracked files in the same change, or names each one it leaves and why. Grep for the new words only: older _Avoid_ words such as Image and User appear legitimately, so this is a review check, not a `bin/check` rule. #163 added "system OpenComposer" and left it in `AGENTS.md`, CONTRIBUTING and `bin/syspull`.
- **A new domain concept gets a glossary entry** in the same change, as `docs/agents/domain.md` describes.
- **ADRs hold.** A change that contradicts an ADR in `docs/adr/` either keeps to it or supersedes it with a new ADR.

## Forms

- **`hello-world` is the reference schema.** A form matches its structure, field order and comments. The one deliberate difference: imaging forms fail `check:` with `oc_assert` (AGENTS.md says why).
- **Defaults come from a real run.** Memory, walltime and epoch defaults cite the job that measured them, as `microct-2d-segmentation` does.

## Pages

- **The guide owns staging and viewing.** A workflow page links `../../guide/#stage` and `#view` and keeps only what is specific to its workflow (its checklist, its dataset rules). Restating the guide's steps, layout tree or Virtual Desktop size is a copy that drifts. `bin/check`'s `guide_copies` catches the markers it lists; the rest is judgement.
- **Name what the researcher clicks.** A page names Files as "**Files** in the top menu of Katana OnDemand" at first mention and "under **Files**" after (#90).
- **README's "Citing IRIS" owns the citing rule.** A workflow page's "Cite this workflow" block is the one other full statement, for its own workflow. Everything else summarises and points to one of those two: the catalogue's Cite step, `CITATION.cff`'s `message`, a WorkflowHub entry's description; restating the at-or-before rule or the IRIS fallback anywhere else is a copy that drifts. Past drift: #77's catalogue step dropped both, then got the fallback too narrow.

## Author docs

- **The contribute page owns the rules, CONTRIBUTING the procedure.** The fit criteria, when a proposal is needed, help while you build and the workflow owner's rules live on `contribute/index.html`; CONTRIBUTING, the PR template, the proposal form and `docs/agents/` link them and keep only their own mechanics. Past drift: #134's first draft restated the proposal list and the workflow owner's rules on both.
- **Every author step works for an outside author.** Read each step in CONTRIBUTING, the contribute page and the templates as a workflow author outside `unsw-restech` who isn't a pilot tester: anything that needs org membership (an org package, an org secret) or `katana_ai_ro` (`katana_ai` scratch: the environments folder, the system clone) says who can't do it and what they do instead. Past miss: #134 told authors to run the container tests themselves, which needs read access to the org's private package (#132).

## Job code

- **A record step warns, a run step fails.** Writing the run record or dataset record only warns on failure; anything the run's own result depends on stops the job.
- **Killed halfway leaves a whole file or none.** Anything that writes a file a later run reads (a record, a pointer, a store) writes it under a temporary name and renames it into place, as `rundir.write_atomic` and `tracking.rebuild` do, or leaves a state the next run recovers from (the importer's `incomplete` tag). Walltime and `qdel` will interrupt it.
- **Katana facts cite their source.** A limit, module name or path in code or docs names the job ID, file or Patrick's confirmation (with date) behind it.
