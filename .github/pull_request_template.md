<!--
Adding or changing a workflow? Fill in the checklist below; the PR is ready
for review when every box that applies is ticked. CONTRIBUTING.md has the
steps. For any other change, replace this with a short description.
-->

Proposal: #<!-- the approved proposal's issue number -->

- [ ] The proposal above is labelled `approved`.
- [ ] `bin/check` passes in CI on this PR.
- [ ] The workflow has a synthetic-dataset test under `workflows/<slug>/tests/`, like the reference workflow's `test_synthetic.py`; the shared library's tests are in `lib/tests/`, not copied.
- [ ] A `qsub` run from my own clone finished. Job ID: <!-- e.g. 9577519 -->
- [ ] Packages the workflow needs beyond the shared imaging environment are added to `envs/imaging/requirements.in` in this PR, or it needs none.
- [ ] I confirm my contribution is licensed under Apache-2.0, the licence IRIS uses (inbound = outbound; there is no separate agreement to sign).
