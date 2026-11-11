<!--
Adding or changing a workflow? Fill in the checklist below; the PR is ready
for a review batch when every box that applies is ticked. CONTRIBUTING.md has
the steps, one section per step. The maintainer merges it or closes it naming
the criterion it failed, without back and forth: fix that and reopen it.
For any other change, replace this with a short description.
-->

Proposal: #<!-- only if the contribute page's #proposal list says you need one; otherwise "None" -->

- [ ] It needs no proposal, or the proposal above is labelled `approved`.
- [ ] It meets the contribute page's fit criteria: https://docs.restech.unsw.edu.au/iris/contribute/#criteria
- [ ] Actions is on for my fork, and `check` passes there on this branch, apart from the tests that run in a container until those are public (#132), which pass when I run `bin/check` myself.
- [ ] The workflow has a synthetic-dataset test under `workflows/<slug>/tests/`, like the reference workflow's `test_synthetic.py`; the shared library's tests are in `lib/tests/`, not copied.
- [ ] Its page documents the dataset layout its form's `check:` validates, and names me as its workflow owner.
- [ ] It ran on Katana from my own clone, after the folder's last change. Job ID: <!-- e.g. 9577519 -->
- [ ] Packages it needs beyond its lab's environment are in that environment's next version in this PR, or it needs none.
- [ ] I confirm my contribution is licensed under Apache-2.0, the licence IRIS uses (inbound = outbound; there is no separate agreement to sign).
