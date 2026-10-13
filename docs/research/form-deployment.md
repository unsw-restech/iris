# How can files in a GitHub repo reach the OpenComposer apps directory?

Research for [issue #10](https://github.com/PatrickTung/iris/issues/10), on the wayfinder map [issue #1](https://github.com/PatrickTung/iris/issues/1). Researched 2026-10-13.

This file lives on the throwaway branch `research/form-deployment` and is never merged.

## Short answer

OpenComposer re-reads its config, the apps directory listing and each form from disk on every request, so "deploying" a form means nothing more than making the two files appear in a directory. No restart, no registration step.

That directory can be a git checkout or a subdirectory of one. So the mechanism with the fewest moving parts is: keep the forms in a GitHub repo, keep one clone of it on Katana, point OpenComposer's `apps_dir` at the forms directory inside the clone, and run `git pull` by hand when forms change. It needs no credential (the repo is public), no CI and no running process.

Dev and sys differ in who owns the directory and who can reach the URL, not in the mechanism. One finding matters beyond this ticket: under Open OnDemand's default configuration a `/pun/dev/` URL resolves to the *visiting* user's own sandbox, so the current "Run on Katana" links probably work only for Patrick.

## How to read this document

Each claim is tagged:

- **[Verified]** read directly in a primary source, cited with a URL.
- **[Inference]** follows from verified facts but was not itself stated or tested.
- **[Unconfirmed]** could not be established from public sources. UNSW-internal ones are repeated under "Open questions for Patrick".

Nothing here was tested on Katana. Source versions read:

| Source | Version read |
|---|---|
| OpenComposer source | commit `7af3d94` (2026-07-27), `VERSION` 2.0.2 |
| Open OnDemand docs | `OSC/ood-documentation` branch `latest`, commit `8e87b05` (2026-10-12), documents OnDemand 4.2 |
| UNSW ResTech docs | `unsw-restech/unsw-restech.github.io` commit `70311da` (2026-09-14), published at docs.restech.unsw.edu.au |
| GitHub docs, git docs | live pages on 2026-10-13 |

The version of OpenComposer installed on Katana is not known, so every OpenComposer source claim is "true of 2.0.2".

## 1. What OpenComposer does with the apps directory

### 1.1 `apps_dir` is one required path in `conf.yml.erb`

**[Verified]** `apps_dir` is a required setting, documented only as "Application directory", with no default. The sample sets `apps_dir: "./sample_apps"`.
[install.html section 2](https://riken-rccs.github.io/OpenComposer/docs/install.html#setting), [conf.yml.erb.sample](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/conf.yml.erb.sample)

**[Verified]** The code only ever uses it as a path prefix: `File.join(apps_dir, dir)`, `File.join(@apps_dir, @dir_name, "form.yml")`. There is no check that it sits inside the OpenComposer directory.
[run.rb L179-L190, L379](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb#L179-L190)

**[Inference]** An absolute path outside the OpenComposer directory therefore works for forms. The docs neither promise nor forbid it.

**[Verified]** `conf.yml.erb` is listed in OpenComposer's own `.gitignore`, so it is per-install state and is not overwritten by updating OpenComposer.
[.gitignore](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/.gitignore)

### 1.2 An app is any non-hidden subdirectory holding a form file

**[Verified]** `create_all_manifests` lists the children of `apps_dir`, skips any name starting with `.`, and keeps a child only if it contains `form.yml` or `form.yml.erb`. `manifest.yml` is optional; without it the directory name is the app name.
[run.rb L159-L190](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb#L159-L190)

Consequences:

- **[Inference]** `apps_dir` may be the root of a git checkout: `.git` is skipped by the dot rule, and loose files or directories without a form file (`README.md`, `assets/`) are ignored.
- **[Inference]** `apps_dir` may be a subdirectory of a checkout (for example `<clone>/forms`). Nothing in the code looks upward.
- **[Inference]** A directory that holds other files beside the form is still an app. So `apps_dir` could point at this repo's existing `workflows/` directory if each `workflows/<slug>/` gained a `form.yml.erb` and `manifest.yml`; the 1:1 slug match recorded in `AGENTS.md` would then be structural. Whether that layout is wanted is a design decision, not a finding.
- **[Inference, untested]** Symlinks work, both `apps_dir` itself being a symlink and individual app directories being symlinks, because the code uses `Dir.children`, `File.exist?` and `File.read`, which follow symlinks. No code path calls `realpath` or rejects links.

### 1.3 Changes are live on the next request: no restart

**[Verified]** Every GET goes through `show_website`, which calls `create_conf` (re-reads and re-evaluates `conf.yml.erb`), then `create_all_manifests(@apps_dir)` (re-lists the directory and re-reads every `manifest.yml`), then `read_yaml(.../form.yml)` (re-reads and re-evaluates the form's ERB). Every POST calls `create_conf` and `create_manifest` again. Nothing is cached in memory between requests.
[run.rb L305-L326, L371-L388](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb#L305-L388), [run.rb L554-L605](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb#L554-L605)

**[Inference]** Adding, changing or removing a form needs no Passenger restart, no "Restart Web Server" and no per-user Nginx restart. Even changing `apps_dir` takes effect on the next request. A restart is needed only when OpenComposer's own Ruby code changes.

**[Inference]** Because the read is per request, a visitor who loads a form mid-update could see a half-written file. `git pull` updates files one at a time; for two small files per form this window is negligible but not zero.

### 1.4 Caveat: local icon files assume a one-segment relative `apps_dir`

**[Verified]** For a local icon file, `get_icon_path` checks `File.join(Dir.pwd, "/", @apps_dir, dirname, icon)` and the icon is served by the route `GET /:apps_dir/:folder/:icon`, which matches exactly three path segments.
[lib/index.rb L14-L35](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/lib/index.rb#L14-L35), [run.rb L517-L521](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb#L517-L521)

**[Inference]** With an absolute or multi-segment `apps_dir`, local icon images fall back to the placeholder. URL icons and Bootstrap or Font Awesome icon names (`bi-...`, `fa-...`) are unaffected. A workaround that keeps image icons is a symlink inside the OpenComposer directory (`apps -> /path/to/clone/forms`) with `apps_dir: ./apps`.

### 1.5 Forms are code that runs as the visitor

**[Verified]** `read_yaml` evaluates `form.yml.erb` with `ERB.new(...).result(binding)` inside the OpenComposer process.
[run.rb L73-L84](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb#L73-L84)

**[Verified]** Open OnDemand apps run inside the per-user Nginx, as the logged-in user. The OnDemand docs make the same point about sandbox apps: users run "arbitrary code on the OnDemand node (of course the UID of the processes are still their regular unprivileged user UID)".
[Enabling App Development](https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html)

**[Inference]** Whoever can write to `apps_dir` can run Ruby as every user who opens a form. On the dev instance that is only Patrick affecting himself. On a sys instance it is the reason administrators may insist on a root-owned directory or a review step, and it makes "what gets pulled, and by whom" a security question rather than a convenience one.

## 2. What Open OnDemand provides

### 2.1 Dev (sandbox) apps

**[Verified]** A user is made a developer by an administrator creating `/var/www/ood/apps/dev/<user>/gateway` as a symlink to `~<user>/ondemand/dev`. Apps are directories under `~/ondemand/dev/` and are served at `/pun/dev/<app>`. Sys apps are at `/pun/sys/<app>`.
[Enabling App Development](https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html), [nginx_stage.yml reference: `app_root`, `app_request_uri`](https://osc.github.io/ood-documentation/latest/reference/files/nginx-stage-yml.html)

**[Verified]** In the default configuration each user's Nginx serves only *that user's* dev apps: `pun_app_configs` has `env: dev, owner: "%{user}"`, and the dev URL pattern `/dev/<name>` carries no owner, unlike the shared pattern `/usr/<owner>/<name>`.
[nginx_stage.yml reference: `pun_app_configs`, `app_request_regex`](https://osc.github.io/ood-documentation/latest/reference/files/nginx-stage-yml.html)

**[Inference]** `https://<kod>/pun/dev/OpenComposer/<slug>` therefore opens Patrick's OpenComposer only when Patrick is the one logged in. Another researcher following the same link gets their own sandbox, which has no OpenComposer unless they are developer-enabled and have their own copy or symlink. **[Unconfirmed]** whether Katana uses the default `nginx_stage.yml`.

**[Verified]** OpenComposer documents a non-admin install for exactly this case: Develop menu, "My Sandbox Apps (Development)", "New App", "Clone Existing App", enter a directory name and the Git remote. It requires an administrator to have enabled app development first.
[install.html section 4](https://riken-rccs.github.io/OpenComposer/docs/install.html#general)

**[Verified]** OnDemand's documented ways to share a sandbox app's code are "a web-based file repository such as Github, emailing zipped app directories, or a group readable directory symlinked to each user's `~/ondemand/dev/` directory". The docs note the symlinked variant gives non-owners "a slightly broken experience".
[App Sharing: Code Sharing](https://osc.github.io/ood-documentation/latest/how-tos/app-development/app-sharing.html)

### 2.2 Sys apps

**[Verified]** "Admins may install apps to the system by copying the application directory to `/var/www/ood/apps/sys`." Default `755` permissions make the app visible to everyone; access is narrowed with ordinary file permissions, and "these changes take effect immediately". The documented commands all use `sudo`.
[App Sharing: System Installed Apps](https://osc.github.io/ood-documentation/latest/how-tos/app-development/app-sharing.html)

**[Verified]** The documented publish step is "Having an administrator checkout a copy of the production version to a directory under `/var/www/ood/apps/sys`", by `sudo` copy or `git clone`. So a git checkout as the installed form of an app is the documented norm. First access to a newly installed sys app restarts the user's Nginx.
[Passenger app tutorial: Publish App](https://github.com/OSC/ood-documentation/blob/8e87b05a7975aa54e44c410c5dd2956c447287b0/source/tutorials/tutorials-passenger-apps/deploy-to-production.inc)

**[Verified]** OpenComposer's own primary install path is the same: `cd /var/www/ood/apps/sys/` then `sudo git clone https://github.com/RIKEN-RCCS/OpenComposer.git`.
[install.html section 1](https://riken-rccs.github.io/OpenComposer/docs/install.html#install)

**[Inference]** That restart warning concerns a new *OnDemand* app. A new OpenComposer form is a subdirectory read by an already-running app (section 1.3), so it should not trigger one.

### 2.3 Restarting the per-user Nginx

**[Verified]** A user restarts their own Nginx from the dashboard ("Help" then "Restart Web Server", also in the Develop menu). An administrator restarts everyone's with `sudo /opt/ood/nginx_stage/sbin/nginx_stage nginx_clean -f`; without `-f` it stops only those with no active connections.
[Customizations](https://osc.github.io/ood-documentation/latest/customizations.html), [nginx_stage nginx_clean](https://osc.github.io/ood-documentation/latest/reference/commands/nginx-stage/commands/nginx-clean.html)

Per section 1.3, neither is needed for a form change.

### 2.4 Does OnDemand itself move files from GitHub?

**[Verified]** The only GitHub-facing feature found is the dashboard's "Clone Existing App" (a one-off `git clone` of a whole OnDemand app into the sandbox). The Files app uploads from a browser, and the Shell app gives a terminal where `git` can be run.
[install.html section 4](https://riken-rccs.github.io/OpenComposer/docs/install.html#general), [Katana OnDemand](https://docs.restech.unsw.edu.au/using_katana/ondemand/)

**[Unconfirmed, negative]** No scheduled or webhook-driven sync from a Git remote was found in the OnDemand docs. Absence in the docs is not proof, but nothing suggests one exists.

## 3. What GitHub provides

**[Verified]** `PatrickTung/iris` is a public repository (checked with `gh repo view`, 2026-10-13). **[Inference]** A public repo clones and pulls over HTTPS with no credential, so no deploy key or token is needed on Katana while the forms live in a public repo.

**[Verified]** If the forms ever move to a private repo, a deploy key is the narrowest credential: "an SSH key that grants access to a single repository", "read-only by default". Its documented downsides are that it is "usually not protected by a passphrase" and has no expiry.
[Managing deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)

**[Verified]** Sparse checkout narrows a working tree to listed directories (cone mode is the default). The git manual still marks the command experimental.
[git-sparse-checkout](https://git-scm.com/docs/git-sparse-checkout)

**[Inference]** Sparse checkout is not needed here. `apps_dir` can point at a subdirectory of a full clone (section 1.2), and the repo is small.

**[Verified]** Single files and tarballs can be fetched without git: `GET /repos/{owner}/{repo}/contents/{path}` with media type `application/vnd.github.raw+json`, and `GET /repos/{owner}/{repo}/tarball/{ref}`.
[REST API: repository contents](https://docs.github.com/en/rest/repos/contents)

**[Inference]** Raw or tarball fetch is a fallback if only HTTPS downloads work and `git` does not; it loses `git pull`'s incremental update and its record of which commit is deployed.

**[Verified]** A self-hosted runner:

- "must be running on the host machine to accept and run GitHub Actions jobs", and makes "outbound HTTPS connections over port 443" to several GitHub domains (`github.com`, `api.github.com`, `*.actions.githubusercontent.com` and others). [Self-hosted runners reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- "is automatically removed from GitHub if it has not connected to GitHub Actions for more than 14 days". [Removing self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/remove-runners)
- "should almost never be used for public repositories on GitHub, because any user can open pull requests against the repository and compromise the environment". [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)

**[Inference]** A self-hosted runner on Katana fails three standing constraints at once: it is an always-on process, it is discouraged for a public repo, and it adds CI to a repo whose `AGENTS.md` says "no CI".

## 4. What UNSW ResTech documents about Katana

**[Verified]** Git is installed and cloning from GitHub is a documented activity: "Git is available by default on katana", with `git clone https://github.com/project/project.git` and `wget https://github.com/...` given as examples. The same page says to install software "using an interactive session, qsub -I, not directly on the login node".
[Installing software](https://docs.restech.unsw.edu.au/software/installing_software/)

**[Inference]** Outbound HTTPS to `github.com` works from Katana in general, and the "use an interactive session" note implies it works from compute nodes too. **[Unconfirmed]** which specific nodes, and whether the OnDemand host itself has outbound access. `AGENTS.md` already advises doing downloads on a login node in case a compute node has none.

**[Verified]** Katana OnDemand (`kod.restech.unsw.edu.au`) is reachable only on campus or through the UNSW VPN. SSH to Katana works from "both inside and outside UNSW" for account holders.
[FAQ](https://docs.restech.unsw.edu.au/help_support/faq/), [Web access to Katana](https://docs.restech.unsw.edu.au/using_katana/ondemand/)

**[Verified]** There are three login nodes (`katana1`, `katana2`, `katana3`); a `tmux` session lives on whichever one was used.
[Other software: tmux](https://docs.restech.unsw.edu.au/software/others/)

**[Unconfirmed]** Whether user cron is permitted. The word "cron" does not appear anywhere in the ResTech docs repository at the commit read. **[Inference]** If it is permitted, a crontab is per login node, so a scheduled pull would live on one of three nodes.

**[Unconfirmed]** Whether SSH key authentication is allowed, which a laptop script or a hosted CI job pushing into Katana would rely on for unattended use.

## 5. The mechanisms side by side

"Process" means something that keeps running or fires on a schedule on Katana or elsewhere, beyond a person typing a command.

| Mechanism | Access it needs | Adds a process? | Dev instance | Sys instance | Fit with the map's constraints |
|---|---|---|---|---|---|
| **A. Manual `git pull`** in a clone that `apps_dir` points at | A shell on a node that mounts the directory (SSH, or the OnDemand Shell app); outbound HTTPS to `github.com`; write access to the clone. No credential while the repo is public | No | Patrick clones under his own space and edits `apps_dir` in his own `conf.yml.erb`; pulls himself | Whoever owns the directory pulls. If it is under `/var/www/ood/apps/sys`, that is an admin with `sudo`. If `apps_dir` points at the shared IRIS directory, its owner pulls with no `sudo` | Fewest parts. Deployed version is a commit hash |
| **B. Scheduled `git pull`** (user cron) | As A, plus permission to run cron | Yes: a scheduled job on one login node | As A, unattended | As A; an unattended pull into a directory every user executes code from is the case admins are most likely to refuse | Extra moving part; cron permission unconfirmed |
| **C. Sync script from the maintainer's computer** (`scp`/`rsync` over SSH) | SSH to Katana (works off campus); write access to the apps directory. Katana needs no outbound access | No | Today's hand copy, scripted | Needs write access to the sys directory, or an admin to run it | Works even if Katana cannot reach GitHub. Deployed version is "whatever was on the laptop", unless the script records the commit |
| **D. Self-hosted Actions runner on Katana** | Outbound 443 to several GitHub domains; a long-lived process on a node; a place to run it | Yes: always-on | Would run as Patrick | Would need a service account | Violates "no always-on services"; GitHub advises against it for public repos; adds CI |
| **E. GitHub-hosted Actions job that SSHes into Katana** | A Katana SSH credential stored as a GitHub secret; Katana SSH reachable from GitHub's runners | No process on Katana; adds a CI workflow | Patrick's own credential in a repo secret | A service credential | Adds CI, which `AGENTS.md` rules out, and puts a UNSW credential in GitHub. Reachability and key auth unconfirmed |
| **F. Open OnDemand's own features** | Dashboard access | No | "Clone Existing App" clones once into the sandbox; Files app uploads by hand; Shell app is mechanism A in a browser | Admin copies or clones into `/var/www/ood/apps/sys` | Nothing here syncs on its own. Useful as the *way to run* A without a separate SSH client |

Reading the table against the standing preference for fewer moving parts: A is the lightest when Katana can reach GitHub, C is the fallback when it cannot, and the two can share one layout (a directory of `<slug>/form.yml.erb` + `manifest.yml`). B, D and E each add a process or a CI system for a job that is otherwise one command.

## 6. How dev and sys differ

| | Dev (`/pun/dev/`) | Sys (`/pun/sys/`) |
|---|---|---|
| Where OpenComposer lives | `~/ondemand/dev/OpenComposer` of one developer **[Verified, OOD default]** | `/var/www/ood/apps/sys/OpenComposer` **[Verified, OpenComposer docs]** |
| Who edits `conf.yml.erb` | That developer | An administrator |
| Who can open a form | By default only the developer themselves **[Inference from verified default config]** | Every OnDemand user, subject to file permissions **[Verified]** |
| Who can write the apps directory | The developer (Patrick has this today, per the map) | Root, unless `apps_dir` is pointed elsewhere **[Inference]** |
| Deploy step for a form change | Pull or copy; live on next request | Same, done by whoever owns the directory |
| Restart needed | None for forms **[Verified in source, 2.0.2]** | None for forms |
| Whose code runs | The developer's forms, as the developer | The directory owner's forms, as every visitor |

**[Inference]** The move to sys therefore turns on one decision that is ResTech's to make: whether sys OpenComposer's `apps_dir` may point at a directory the IRIS maintainer can write (the shared IRIS directory), or must stay root-owned with an admin performing each update. The first keeps deployment a one-command step for the maintainer; the second adds a person to every form change.

## Open questions for Patrick

These are UNSW-internal or installation-specific facts that public sources do not settle.

1. **What is installed.** Which OpenComposer version runs on the dev instance, where it lives (`~/ondemand/dev/OpenComposer`?), and what `apps_dir` is set to now. Section 1 is true of 2.0.2.
2. **Can the node where you would pull reach `github.com`?** One `git ls-remote https://github.com/PatrickTung/iris` from a Katana login node and from the OnDemand Shell app settles it. If not, mechanism C is the route.
3. **Do `/pun/dev/OpenComposer/...` links open for anyone but you?** Under the OnDemand default they should not. If a colleague has opened one successfully, Katana's configuration differs from the default and section 2.1 needs correcting.
4. **Is user cron permitted on Katana?** Only matters if a scheduled pull is wanted.
5. **For sys: may `apps_dir` point outside `/var/www/ood/apps/sys`, at a directory the IRIS maintainer writes?** This is the question to put to the OnDemand administrators.
6. **Is SSH key authentication to Katana allowed?** Only matters for an unattended sync from a laptop or CI.

## Questions the findings raise for the map

- **Are the forms allowed to be public?** They are deliberately outside the repo today. Any Git-based mechanism from `PatrickTung/iris` publishes them. The PBS scripts they generate are already public in `workflows/`, but this is Patrick's call.
- **Which repo and which directory hold the forms?** This repo (a `forms/` directory, or beside each page under `workflows/<slug>/`), or a separate one. Pointing `apps_dir` at `workflows/` would make the page slug and the form URL the same thing by construction.
- **`hello-world` is deployed as `IRIS`.** A checkout cannot serve one directory under two names without a symlink or a rename, so the exception recorded in `AGENTS.md` has to be resolved one way or the other before `apps_dir` points at a clone.
- **Does a clone of the whole repo on Katana pin a version?** A clone gives "deployed = commit X" for free; whether deployment should track `main` or a tag belongs to the form-versioning decision.
