# The IRIS instance replaces the shared OpenComposer

Supersedes in part ADR-0011: its two system apps beside the shared OpenComposer, `OpenComposer-iris` and `OpenComposer-iris-test`, its sysadmin's two symlinks, and its changeover that moves every Run button to `/pun/sys/OpenComposer-iris/<slug>`. The fork, its pinned commit, the instances' checkouts and their own `manifest.yml`, `conf.yml.erb` and `data_dir` all hold.

Asked for `OpenComposer-iris` beside the shared OpenComposer, the sysadmin saw no good way to run a stock OpenComposer with each user's own apps, so they pointed Katana OnDemand's `OpenComposer` system app at the IRIS instance's checkout instead, and made no `OpenComposer-iris`, whose URL answers `invalid app root` (#172, 2026-11-12). For the test instance, they proposed a dev app each workflow author links in, since a system app would sit in every user's menu, of no use to most (#139).

- **The IRIS instance is `OpenComposer`**, at `https://kod.restech.unsw.edu.au/pun/sys/OpenComposer/<slug>`, shown as "IRIS OpenComposer". Its `apps_dir` is the system clone's `workflows/`, as the shared OpenComposer's was, so every Run button already opens it, and `bin/syspull` still deploys its forms. Katana OnDemand has no shared OpenComposer now.
- **The test instance is a dev app.** A workflow author links its checkout into their own `~/ondemand/dev`, and if that folder is new, restarts their web server (**Help → Restart Web Server**), since Katana OnDemand turns on **Develop** for anyone who has the folder when their web server starts (the sysadmin, 2026-11-12). Linked under the checkout's name, it should open at `/pun/dev/OpenComposer-iris-test/<slug>`, under **Develop**, so its menu name never shows; #174's real run is the first to try it. Only authors who link it see it, and nobody asks the sysadmin for anything.
- **An app every user can open is deployed from where no user can write, before launch.** An app on Katana OnDemand runs as whoever opens it, so a user who can write to it can run code as everyone who clicks its link. The sysadmin accepts the IRIS instance's checkout in `katana_ai`'s scratch while only `katana_ai_ro` can read it, not once every Katana user can, and updates from wherever it moves to will not be instant (2026-11-12). So the checkout moves before launch. The forms it serves run as the user too, since OpenComposer evaluates each `form.yml.erb` when the form opens, so the system clone may have to move with it; the sysadmin has not said.

## Considered Options

- **`OpenComposer-iris` beside a stock shared OpenComposer** (ADR-0011): declined by the sysadmin, who saw no good way to give users their own apps on a stock install.
- **The test instance as a system app** (ADR-0011): every Katana user would see an app most never use.
- **Each author's own copy of the fork in `~/ondemand/dev`**: a copy stays on the commit it was cloned at, so an author could prove a workflow on code the IRIS instance doesn't run. Linking one checkout keeps every author on the commit `bin/ocpull` sets.

## Consequences

- #173's changeover moves no Run button and no URL. What is left of it is moving both checkouts to the fork commit carrying #165, #166, #168 and #171, the banner's hint in the same deploy, and a real `microct-2d-segmentation` job from the IRIS instance.
- The fork reached researchers as `88d45b1`, upstream 2.0.2 with the platform name and catalogue link (#160) and contrast-following text (#164), but without #165, #166, #168 or #171, when the sysadmin repointed the app, not through a planned changeover. Each job history starts afresh in `~/composer/iris`, since the IRIS instance keeps its own `data_dir`.
- The test instance's checkout keeps `katana_ai_ro` as its readers through the pilot. Who may read it after launch is open: a group of workflow authors, which would make an author ask to join before their first test, or every Katana user, which under the sysadmin's rule means moving it out of scratch like the IRIS instance's.
