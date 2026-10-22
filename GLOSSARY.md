# IRIS

IRIS is the UNSW ResTech AI Imaging Gateway: a catalogue from which researchers launch imaging workflows on Katana.

## Language

**Workflow**:
One imaging analysis a researcher can launch from IRIS, made up of a catalogue page, a form and the code the job runs.
_Avoid_: Pipeline, app, job

**Researcher**:
Someone who runs IRIS workflows on their own data from their own Katana account.
_Avoid_: User, end user

**Workflow author**:
A ResTech member who adds or changes a workflow, working on a branch and testing it on the dev clone before it reaches `main`. Distinct from the researcher, who runs workflows.
_Avoid_: Contributor, developer

**Catalogue**:
The set of workflows listed on the IRIS landing page. Onboarding pages such as `hello-world` are not part of it.
_Avoid_: Gallery, grid, registry

**Planned workflow**:
A catalogue entry with a page but no form and no Run button, listed to show what is coming.
_Avoid_: Coming soon, inactive

**Modality**:
The imaging technique a workflow serves, such as microCT, microscopy or pathology, shown as a tag on its catalogue card.
_Avoid_: Domain, category

**Reference workflow**:
The single microCT workflow every IRIS v1 design decision is tested against.
_Avoid_: Demo, example workflow

**Form**:
The OpenComposer definition of a workflow on Katana OnDemand, where the researcher sets parameters and submits.
_Avoid_: App, template

**Two-click launch**:
The path from catalogue to running job: one click on the workflow's IRIS page, one click to submit its form.
_Avoid_: One-click run

**Run**:
One submission of a form, producing one job on Katana and one set of outputs.
_Avoid_: Execution

**Experiment**:
A named group of one researcher's runs that are compared with each other, such as runs on the same dataset with different hyperparameters. The researcher names it on the form.
_Avoid_: Project, study

**Tracking store**:
The single file where a researcher's runs and experiments are recorded for comparison. Each researcher has their own.
_Avoid_: Database, log

**Usage count**:
ResTech's tally of runs per workflow per month, taken from Katana's own job records. It is separate from the tracking store, which belongs to the researcher.
_Avoid_: Usage log, telemetry

**Environment**:
The shared, versioned set of software a workflow's runs use. It is built ahead of time and never changed, and nothing is installed into it when a run starts.
_Avoid_: Image, container, setup

**Volume**:
A 3D image dataset; for IRIS v1, microCT data arriving as netCDF.
_Avoid_: Stack, scan

**Label volume**:
An image or volume of the same shape as its source in which each pixel or voxel holds a class number. In training labels, 0 marks it as unlabelled. A label slice is a one-slice label volume.
_Avoid_: Mask, annotation, ground truth

**Dataset**:
One volume together with its training pairs, kept in a single folder in the researcher's scratch with a fixed layout. A run reads one dataset.
_Avoid_: Project, input folder

**Dataset record**:
What a run notes about the dataset it read, so the researcher can find it again and spot if it changed: the folders' paths and file counts, the volume's size, modification time, shape, data type, voxel spacing if the volume records one, and intensity statistics. It holds no content hash; the digest MLflow shows hashes the record itself.
_Avoid_: Fingerprint, checksum, manifest

**Training pair**:
An image slice and its label slice, matched by filename, used to train a workflow's model.
_Avoid_: Sample, annotation

**Run directory**:
The folder inside a dataset where one run writes all its outputs: the label volume, the trained weights and the record of what the run did.
_Avoid_: Output folder, results

**Run index**:
The folder `/srv/scratch/$USER/iris/run-index/` in which every finished run leaves one file, named by its job ID, pointing at its run directory. It is how the importer finds runs.
_Avoid_: Registry, queue

**Importer**:
The single process that replays run directories from the run index into the tracking store. Jobs never write the store themselves (ADR-0001). Rebuilding a lost store is the same importer run into a fresh store, from the run index or, if that is gone too, from the `runs/` folders of named datasets.
_Avoid_: Sync, uploader
