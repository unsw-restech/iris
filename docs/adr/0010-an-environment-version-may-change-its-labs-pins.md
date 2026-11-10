# An environment version may change its lab's pins

Supersedes in part ADR-0007 (a new version only adds packages, and a package that conflicts with its lab's pins is declined) and ADR-0008 (a new version can only add packages, never remove them). A later version of a lab's environment may add, change or remove packages (Patrick, 2026-11-10).

The add-only rule did not keep cited runs reproducible: digest pinning does that. Every form pins the exact version it was proved in, and each version is one container by digest (ADR-0008), so a new version can change neither a cited run nor another workflow's results. Those workflows stay on their version until their owners move. What the add-only rule bought was sharing: every version of a lab could be one layer on the version before it. That came at a cost. An author who needed, for example, PyTorch 2.11 where `microct/1` pins 2.10 had nowhere to go, and a lab-wide move such as napari to PyQt6 had no route but a second environment for the lab (#146).

- **A later version may add, change or remove packages.** A version whose lock changes or removes a line of the lock before it needs the maintainer's review of its pull request. Nothing is declined for conflicting with its lab's pins, and no lab gets a second environment for it: the change is the lab's next version, `microct/2`, not a `microct-qt6/1`. One environment per lab, and labs sharing one, both still hold (ADR-0007).
- **How a version is built follows from its lock.** A version whose lock keeps every line of the lock before it is built as one layer on that version. Any other version is built fresh, like a first version, which also ends the layer chain: the version after it layers on it, not on the ones before (#148).
- **A new version moves its lab in the lab table.** The pull request that adds a version also points its lab's entry at it, so new workflows start on the newest version, and the maintainer's review of that pull request is the maintainer moving the lab. A lab that shares another lab's environment keeps its entry until the maintainer moves that lab.
- **Existing workflows keep the version their form pins**, and move when their owners prove them in a newer one. Versions are kept as long as a live form or a citable version pins them, as before (ADR-0008).
- **The researcher tools get their own environment** (#149), so a change to the viewer's stack, such as napari's move off PyQt5, is never a change to a lab's environment, and a lab's new version never moves the viewer.
- **A new version reports which other workflows pass in it** (#150): CI runs the tests of every workflow that pins an earlier version of the same environment in the new container and lists each with pass or fail, without blocking the version, so their owners know before they move.

## Considered Options

- **Decline (ADR-0007 as written)**: the simplest. A lab whose workflows can't share pins loses a workflow, and a lab-wide move has no route except a new environment every workflow in the lab moves to, which is a second environment anyway.
- **A second environment per lab**, named for what it was built for, such as `microct-qt6/1`, with the lab table still naming one version for new workflows: no change to the add-only rule, but every conflicting request becomes another environment beside the lab's, each a fresh build of about 4.7 GB, and ADR-0007's one environment per lab no longer holds.
- **Decline by default, and a second environment only when the maintainer opens one for a lab-wide move**, such as PyQt6 or a new PyTorch major version: agreed first, then dropped for this decision. It still declines an author's legitimate need, and a lab-wide move is just as well served by the lab's next version.
- **Read-only overlays per workflow** on the lab's container: workflows would share the base, but what ran would no longer be the one container a form pins by digest, so every job would have to mount, and every proof name, a second thing.
- **Several venvs in one container**: one container per lab, but every version of it would carry every venv, so any change rebuilds and republishes all of them, and a form would have to name a venv as well as a version.
- **One environment per workflow**: more viable since each workflow carries its own library copy (ADR-0009), so the shared `lib/` no longer has to work across all of them. It costs a container per workflow, and workflows in a lab would never converge on shared pins.

## Consequences

- `envs/README.md`, `bin/check`'s rule that fails a later version's lock for removing or changing a line, its test and the `containers` workflow still say versions only add packages, and change in #148.
- A fresh build shares only its base layer with the versions before it, so each costs about 4.7 GB of registry space. GHCR storage counts against the org's plan while the `iris-env` package is private (#132), so fresh builds cost the org until an org owner makes the package public. Katana's `katana_ai` quota is not a constraint: the sysadmins raise it on request (Patrick, 2026-11-10).
- A workflow author whose package conflicts with their lab's pins proposes the lab's next version, and their pull request waits on the maintainer's review. The contribution docs (#134) and the author's fork build (#138) say so in their own tickets.
