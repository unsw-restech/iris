# IRIS

IRIS is the UNSW ResTech AI Imaging Gateway: a catalogue from which researchers launch imaging workflows on Katana.

## Language

**Workflow**:
One imaging analysis a researcher can launch from IRIS, made up of a catalogue page, a form and the code the job runs.
_Avoid_: Pipeline, app, job

**Catalogue**:
The set of workflows listed on the IRIS landing page. Onboarding pages such as `hello-world` are not part of it.
_Avoid_: Gallery, grid, registry

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
_Avoid_: Experiment, execution

**Environment**:
The shared, versioned set of software a workflow's runs use. It is built ahead of time and never changed, and nothing is installed into it when a run starts.
_Avoid_: Image, container, setup

**Volume**:
A 3D image dataset; for IRIS v1, microCT data arriving as netCDF.
_Avoid_: Stack, scan

**Label volume**:
An image or volume of the same shape as its source in which each pixel or voxel holds a class number. In training labels, 0 marks it as unlabelled. A label slice is a one-slice label volume.
_Avoid_: Mask, annotation, ground truth
