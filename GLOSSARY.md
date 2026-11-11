# IRIS

IRIS (Intelligent Research Imaging Suite) is the UNSW ResTech AI Imaging Gateway: a catalogue from which researchers launch imaging workflows on Katana.

## Language

**Pilot**:
The period in which IRIS runs on Katana's system instance but only pilot testers, members of a group ResTech chooses, can run workflows.
_Avoid_: Beta, test instance

**Launch**:
The day IRIS opens to every researcher with a Katana account, ending the pilot. Starting a single run is launching a workflow, never "a launch".
_Avoid_: Go-live, release

**Workflow**:
One imaging analysis a researcher can launch from IRIS, made up of a catalogue page, a form and the code the job runs. It may also read data that complements the images, such as tables or audio, but IRIS takes no workflow without imaging.
_Avoid_: Pipeline, app, job

**Researcher**:
Someone who runs IRIS workflows on their own data from their own Katana account.
_Avoid_: User, end user

**Workflow author**:
Anyone with a Katana account who adds or changes a workflow, whether a ResTech member or a researcher. Distinct from the researcher who only runs workflows.
_Avoid_: Contributor, developer

**Maintainer**:
The ResTech member who approves proposals, reviews and merges workflows, and builds environments.
_Avoid_: Admin, owner, reviewer

**Workflow owner**:
The workflow author answerable for keeping one workflow working, named on its page. A workflow whose owner stops answering is taken out of service.
_Avoid_: Maintainer, contributor

**Proposal**:
A workflow author's request for something only the maintainer can give, made before building the workflow that needs it: new packages, a new modality or lab, or adopting an unmaintained workflow. The maintainer approves or declines it. A workflow that needs none of these needs no proposal.
_Avoid_: Request, submission, application

**Test instance**:
The OpenComposer on Katana that shows each workflow author the forms in their own clone and runs them as that author, so they can prove a workflow before it joins IRIS.
_Avoid_: Sandbox, staging

**Run proof**:
The generated record of a real run from the test instance, kept with the workflow, that shows the workflow's current code ran and finished. It shows the testing was done; it does not replace review.
_Avoid_: Certificate, test report

**Review batch**:
The maintainer's pass over every pull request that has passed all its checks, approved together and then deployed. IRIS tells authors to expect one about every fortnight, but the maintainer decides when each happens, and a request waits until then.
_Avoid_: Release, train

**Catalogue**:
The set of workflows listed on the IRIS landing page. Onboarding pages such as `hello-world` are not part of it.
_Avoid_: Gallery, grid, registry

**Planned workflow**:
A catalogue entry with a page but no form and no Run button, listed to show what is coming.
_Avoid_: Coming soon, inactive

**Unmaintained workflow**:
A workflow taken out of service because its owner stopped answering. It leaves the catalogue and can no longer be run, but its page stays so its citable versions and cited commits still lead somewhere.
_Avoid_: Retired, deprecated, archived

**Adoption**:
A workflow author's taking on an unmaintained workflow: their proposal to adopt it is approved, their PR fixes it and cites a `qsub` run, and they become its workflow owner. It returns as the same folder and WorkflowHub entry. Handing a working workflow from one owner to another is not adoption.
_Avoid_: Revival, rescue, takeover

**Modality**:
The imaging technique a workflow serves, such as microCT, microscopy or pathology, shown as a tag on its catalogue card.
_Avoid_: Domain, category

**Lab**:
The imaging facility or research group a workflow serves, such as the X-ray MicroCT Lab or BRIL. The catalogue groups its workflows by lab. A lab can span several modalities, so a workflow's lab and its modality are separate.
_Avoid_: Group, team, facility

**Reference workflow**:
The single microCT workflow every IRIS v1 design decision is tested against.
_Avoid_: Demo, example workflow

**Form**:
The OpenComposer definition of a workflow on Katana OnDemand, where the researcher sets parameters and submits.
_Avoid_: App, template

**Imaging form**:
A form whose script carries its workflow's entry script, so a researcher can edit it for one run, and runs it in an environment. The `hello-world` form is not one.
_Avoid_: Python form, real form

**Two-click launch**:
The path from catalogue to running job: one click on the workflow's IRIS page, one click to submit its form.
_Avoid_: One-click run

**Citable version**:
A frozen WorkflowHub snapshot of one workflow at one commit of `main`, with its own DOI. Researchers cite it alongside the commit their run recorded. It is not a version number: nothing versions a workflow.
_Avoid_: Release, workflow version

**Run**:
One submission of a form, producing one job on Katana and one set of outputs.
_Avoid_: Execution

**Edited run**:
A run whose code the researcher changed on the form before submitting, so it differs from the code at the commit the run recorded. The change belongs to that run alone; the workflow itself is unchanged.
_Avoid_: Custom run, modified workflow

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
A versioned set of software a lab's workflows, or the researcher tools, run in, packaged as a container; several labs may share one. It is built ahead of time and never changed, and nothing is installed into it when a run starts. `imaging/1`, from before the move to containers, is a venv.
_Avoid_: Image, venv, setup

**Container**:
The single file one version of an environment is packaged as, which a run starts inside. Registries and container tools call it an image; IRIS never does, since an image in IRIS is imaging data.
_Avoid_: Image, container image, SIF

**Environment version**:
One fixed build of an environment, named `<env>/<n>` after the lab it was first built for and counting from 1, such as `microct/1`. The researcher tools' environment, `tools`, is the one not named after a lab, since it is no lab's. A later version may add, change or remove packages, and a form pins the version its workflow was proved in.
_Avoid_: Tag, release, image version

**Digest map**:
The one list that ties each environment version to the exact container it means, by digest, or marks it unpublished until it is published.
_Avoid_: Lock, pin file

**Lab table**:
The one list of labs and the environment version each lab's new workflows start on. Labs may share a version, and each lab's entry moves only when the maintainer moves that lab.
_Avoid_: Lab map, lab config

**Container file**:
Katana's copy of one environment version's container, the file a job runs.
_Avoid_: SIF, image file

**Environments folder**:
The folder in `katana_ai` scratch holding a container file for each environment version a live form pins, plus the researcher tools' version, and nothing else.
_Avoid_: Env cache, envs directory

**Researcher tools**:
`iris-view`, `iris-compare`, the importer and rebuild: what a researcher views and compares runs with. They run in one environment version whatever the run's lab.
_Avoid_: IRIS tools, utilities

**`iris` module**:
The Katana module that `module load iris` loads. It puts `iris-view` and `iris-compare`, from the system clone, on the researcher's PATH and does nothing else. It is not an environment: it installs no software and has no version.
_Avoid_: IRIS environment, iris package

**Volume**:
A 3D image dataset; for IRIS v1, microCT data arriving as netCDF.
_Avoid_: Stack, scan

**Label volume**:
An image or volume of the same shape as its source in which each pixel or voxel holds a class number. In training labels, 0 marks it as unlabelled. A label slice is a one-slice label volume.
_Avoid_: Mask, annotation, ground truth

**Dataset**:
The folder in the researcher's scratch that a run reads, laid out as its workflow requires: for `microct-2d-segmentation`, one volume and its training pairs. A run reads one dataset.
_Avoid_: Project, input folder

**Dataset record**:
What a run notes about the dataset it read, so the researcher can find it again and spot if it changed: what is true of any folder, its path, file count, total size and newest change, plus whatever details its workflow adds, such as a volume's shape and voxel spacing. It holds no content hash; the digest MLflow shows hashes the record itself.
_Avoid_: Fingerprint, checksum, manifest

**Staging**:
Copying a dataset from where it was made, such as the researcher's own computer or an instrument PC, into their Katana scratch before its first run, and bringing run directories back. It sits outside the two-click launch.
_Avoid_: Upload, ingest, data movement

**Files**:
The **Files** item in the top menu of Katana OnDemand, where a researcher browses their scratch, copies in a few training pairs and opens a folder in Globus.
_Avoid_: Files app, OnDemand Files app

**Endpoint**:
A computer or storage system Globus can transfer to or from: a researcher's computer running Globus Connect Personal, or Katana. Globus's own web app now says "collection"; IRIS keeps endpoint.
_Avoid_: Collection, except when quoting Globus

**Training pair**:
An image slice and its label slice, matched by filename, used to train a workflow's model.
_Avoid_: Sample, annotation

**Run directory**:
The folder inside a dataset where one run writes all its outputs: the record of what the run did, plus whatever its workflow writes, such as a label volume or trained weights.
_Avoid_: Output folder, results

**Run record format**:
The numbered layout of a run's record of what it did; a record that names none is format 1. The shared side reads every format ever written.
_Avoid_: Schema version, record version

**Run index**:
The folder `/srv/scratch/$USER/iris/run-index/` in which every finished run leaves one file, named by its job ID, pointing at its run directory. It is how the importer finds runs.
_Avoid_: Registry, queue

**Importer**:
The single process that replays run directories from the run index into the tracking store. Jobs never write the store themselves (ADR-0001). Rebuilding a lost store is the same importer run into a fresh store, from the run index or, if that is gone too, from the `runs/` folders of named datasets.
_Avoid_: Sync, uploader

**Job side**:
The part of IRIS's library a job runs: starting the run in its container, writing the run record, recording the code, the dataset record and the readers an entry script imports. Each workflow runs its own library copy of it.
_Avoid_: Runtime, core

**Shared side**:
The part of IRIS's library that reads the runs of every workflow: the importer, the researcher tools and the tracking store. One copy in the system clone serves every workflow.
_Avoid_: Common library, core

**Library copy**:
A workflow's own copy of the job side, kept in its folder and taken from one recorded commit. Its owner updates it only by choice, with a new proof.
_Avoid_: Vendored library, fork
