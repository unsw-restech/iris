# Moving large files onto Katana, for researchers who don't use a terminal

Researched 2026-10-26 against primary sources: the ResTech Katana docs, Open OnDemand docs and source, Globus docs, and short read-only checks on Katana's login node (`katana2`) and data mover (`kdm`). **Verified** means a primary source or a command output shows it. **Unverified** means it comes from a search snippet, a dead page, or inference.

## Short answer

Recommendations for a researcher moving tens of GB to TB who won't open a terminal, best first:

1. **Globus, from the web browser plus Globus Connect Personal on the laptop.** Globus is the only option that resumes and checks transfers by itself, keeps going after the laptop sleeps, and needs no terminal. Katana's data mover runs **Globus Connect Server 5.4** (verified), and UNSW holds a Globus subscription (verified, from a UNSW facility's docs). What's missing: **ResTech doesn't document a Katana collection** (its docs mention Globus once, in passing), and we couldn't confirm the collection's name or which paths it exposes. Ask ResTech before telling researchers to use it.
2. **A GUI SFTP client (WinSCP on Windows, Cyberduck or FileZilla on Mac) pointed at `kdm.restech.unsw.edu.au`.** This is what ResTech documents and recommends today (verified). It's fine for tens of GB. At TB scale it is fragile: a dropped connection or a sleeping laptop stops the transfer, and the researcher has to restart or resume it by hand.
3. **Data already in the UNSW Data Archive or OneDrive.** Both need a terminal session on `kdm` (`unswdataarchive` scripts, or `rclone`). Neither suits non-technical researchers without help.

Not recommended: the **OnDemand Files app** for anything over about 10 GB. Its default upload cap is about 10.7 GB. Each upload is one browser request with no resume, and it is buffered on the OnDemand web node.

**Is there an OnDemand option?** Not today, as far as we can verify. Open OnDemand has two built-in hooks a site can switch on, both off by default:

- **A Globus button in the Files app** (OOD 3.1.0 and later). It opens the current directory in the Globus web app. Turning it on takes one `globus_endpoints` block in `ondemand.d` with the Katana collection's UUID. It's the cheapest and most useful change ResTech could make, because the collection already exists on `kdm`.
- **Remote file systems via rclone** (OOD 2.1 and later). This shows a user's rclone remotes, such as OneDrive, in the Files app. Every user still has to create their own remote with `rclone config` in a terminal, and rclone has to be installed on the OnDemand host. The data would also flow through the web node. It isn't a good fit.

We found no community OnDemand batch-connect app for file transfer that a site could adopt (unverified: a search turned up none).

## Does the IRIS rule match the docs?

AGENTS.md says that transfers over 10 GB go through the data mover, never a login node or the OnDemand Files app. That matches the docs, and they are stricter:

- ResTech: "We require large or frequent data transfers to go through the KDM server." Only small files ("a few job scripts <2–3 MB") should go straight to Katana. KDM is "designed to handle many and/or very large transfers without impacting the login/head nodes." ([kdm page](https://docs.restech.unsw.edu.au/storage/kdm/))
- The Files app goes through the OnDemand web host (`kod.restech.unsw.edu.au` = 149.171.180.131), which is a different machine from the login nodes (`katana.restech.unsw.edu.au` = 129.94.146.60/61/67) and from `kdm` (129.94.146.56). These are `getent hosts` results from `katana2`. Upload bodies are buffered on that host (see the OnDemand section below), so large uploads load a shared web node. ResTech's docs give no size guidance for OnDemand ([ondemand page](https://docs.restech.unsw.edu.au/using_katana/ondemand/)).
- OnDemand's default upload cap (10,737,420,000 bytes) is almost exactly IRIS's 10 GB line. Above it, uploads fail outright unless ResTech has raised the cap (unverified, see the open questions).

## Options

### 1. Globus (web app + Globus Connect Personal)

**How it works.** The researcher installs Globus Connect Personal (GCP) on their laptop, which turns the laptop into a Globus collection. They then log in to app.globus.org with their UNSW identity and pick the laptop on one side and Katana on the other. Globus's cloud service runs the transfer between the two endpoints, retries failures, checks integrity and emails when the transfer is done. The browser can be closed. The laptop has to stay on and online, but a transfer that is interrupted carries on when the laptop comes back.

**Size suitability.** Tens of GB to many TB. This is what it's built for.

**What the researcher installs or does.** Install GCP. Admin rights aren't needed: "If you do not have local administrator permissions…" pick a folder you can write to ([GCP Windows install](https://docs.globus.org/globus-connect-personal/install/windows/)). Log in, then drag and drop in the web app.

**Available at UNSW today?**

- **Verified:** `kdm` runs Globus Connect Server. `rpm -q globus-connect-server54` gives `globus-connect-server54-5.4.97-1.el8+gcs5`, and `systemctl is-active globus-gridftp-server gcs_manager` reports `active active` (run on `kdm`, 2026-10-26).
- **Verified:** UNSW is a Globus subscriber. The Structural Biology Facility's Discworld docs list collections with "Subscription: University of New South Wales" on a "Subscribed Mapped Collection (GCS) on ResTech (gd1)" ([Discworld Globus page](https://docs.discworld.unsw.edu.au/how-to/globus-data-transfer)). That page covers Discworld storage, not Katana.
- **Unverified:** the Katana collection's name and scope. A search snippet of a now-404 UNSW research page (`research.unsw.edu.au/node/135141`) said Katana "is set up as a Globus Endpoint" giving access to Katana scratch and home, with collections found by searching "UNSW Katana" and choosing Scratch, Home or CCRC. A snippet of AARNet's [Globus data transfer nodes in Australia](https://support.aarnet.edu.au/hc/en-us/articles/14944937395471-Globus-data-transfer-nodes-in-Australia) said UNSW's Globus is connected to Katana and needs a Katana account. That page refused automated fetches (HTTP 403), so it wasn't read directly.
- **Gap:** ResTech's Katana docs mention Globus only once, as an aside on the Stable Diffusion page ("you can use either `rsync` command or `WinSCP` software or `Globus`"). The search index at `docs.restech.unsw.edu.au/search/search_index.json` has no Globus how-to.
- **Katana module:** `globus/3.28.3` provides only a `globus` binary. Its version matches the Globus CLI, so it's a command-line client, not an endpoint (from `ls` of the module's `bin`). Non-technical users won't need it.

**Licensing.** Laptop (GCP) to server (GCS) transfers are free for non-profit research ([globus.org/subscriptions](https://www.globus.org/subscriptions)). Transfers between two GCP endpoints and sharing from GCP need a subscription ([subscriptions FAQ](https://docs.globus.org/faq/subscriptions/)), and so does HTTPS upload/download in the browser ([globus.org/subscriptions](https://www.globus.org/subscriptions)). UNSW's subscription would cover those if ResTech has enabled them (unverified for Katana's collection).

### 2. GUI SFTP client to the data mover

**How it works.** WinSCP, FileZilla or Cyberduck connect over SFTP to `kdm.restech.unsw.edu.au` with the user's zID and zPass, and the researcher drags files across. ResTech's documented FileZilla settings: Host `kdm.restech.unsw.edu.au`, Protocol SFTP, zID and password ([kdm page](https://docs.restech.unsw.edu.au/storage/kdm/)). Destination is `/srv/scratch/<zID>`.

**Size suitability.** Good for tens of GB. TB transfers work, but the client and laptop have to stay connected for hours. WinSCP and FileZilla can resume partial files, but the user has to notice the failure and restart.

**What the researcher installs or does.** Install a client and fill in four fields. ResTech warns that "Some antivirus vendors flag FileZilla as a potential risk" and suggests WinSCP instead ([kdm page](https://docs.restech.unsw.edu.au/storage/kdm/)).

**Available today?** Verified. The documented route, and `kdm` resolves to 129.94.146.56.

**Off-campus access, VPN and MFA.**

- The ResTech FAQ says you "can connect to Katana from both inside and outside UNSW", and that services "like Katana OnDemand are only available on campus so you will need to connect to the UNSW VPN" ([FAQ](https://docs.restech.unsw.edu.au/help_support/faq/#can-i-access-katana-from-outside-unsw)). So SSH and SFTP to `kdm` should work without the VPN. That reading is unverified: the kdm page doesn't say either way.
- Docs show password (zPass) login for SSH and SFTP, with no mention of MFA ([accessing Katana](https://docs.restech.unsw.edu.au/using_katana/accessing_katana/)).
- Space: user scratch is 128 GB. Anything bigger needs a shared-scratch allocation, requested by email ([storage locations](https://docs.restech.unsw.edu.au/storage/storage_locations/)).

### 3. OnDemand Files app (browser upload)

**How it works.** The Files app uploads with Uppy's `XHRUpload` plugin, one file per request (`limit: 1`). There is no chunking or resume ([uppy_ops.js](https://github.com/OSC/ondemand/blob/master/apps/dashboard/app/javascript/files/uppy_ops.js)). The per-user nginx buffers the request body under the PUN tmp root, `client_body_temp_path <%= tmp_root %>/client_body` with `client_max_body_size <%= nginx_file_upload_max %>` ([pun.conf.erb](https://github.com/OSC/ondemand/blob/master/nginx_stage/templates/pun.conf.erb)). The default root is `/var/tmp/ondemand-nginx/%{user}` ([nginx_stage_example.yml](https://github.com/OSC/ondemand/blob/master/nginx_stage/share/nginx_stage_example.yml)). Rails then moves the tempfile into place (`@path.handle_upload(file.tempfile)` in [files_controller.rb](https://github.com/OSC/ondemand/blob/master/apps/dashboard/app/controllers/files_controller.rb)). So the whole file lands on the web node's local disk before it reaches Katana storage.

**Size suitability.** Small files only. "By default, the file size upload limit is 10737420000 bytes (~10.7 GB)." Sites can lower it with `FILE_UPLOAD_MAX` in `/etc/ood/config/apps/dashboard/env`, or raise it with `nginx_file_upload_max` in `nginx_stage.yml` ([customizations: Set Upload Limits](https://osc.github.io/ood-documentation/latest/customizations.html#set-upload-limits)). On the OnDemand forum, maintainers report uploads becoming unreliable above about 20 GB and point to Globus instead ([discourse thread](https://discourse.openondemand.org/t/exceeds-maximum-allowed-size-of-10gb/3846)). That's a community forum, so treat it as secondary.

**Available today?** Verified that it exists: ResTech says "you can easily upload, download, delete and modify files" ([ondemand page](https://docs.restech.unsw.edu.au/using_katana/ondemand/)). Off campus it needs the UNSW VPN ([FAQ](https://docs.restech.unsw.edu.au/help_support/faq/#can-i-access-katana-from-outside-unsw)). Login goes through UNSW's Microsoft Entra ID: `/pun/sys/dashboard` redirects to `login.microsoftonline.com/3ff6cfa4-…/oauth2/v2.0/authorize` (verified with curl). Unverified: Katana's OnDemand version, and whether its upload cap differs from the default. The OnDemand config is on the web node, not on `katana2`, so we couldn't read it.

### 4. OnDemand Globus button (needs ResTech)

**How it works.** `globus_endpoints` in `ondemand.d` "Add[s] a Globus button to the file browser. The button opens the current directory in the Globus transfer web app." It maps local paths to collection UUIDs, for example `path: "/srv/scratch"`, `endpoint: <uuid>`, `endpoint_path: …`. The default is off ([ondemand.d reference](https://osc.github.io/ood-documentation/latest/reference/files/ondemand-d-ymls.html), [source rst](https://github.com/OSC/ood-documentation/blob/latest/source/reference/files/ondemand-d-ymls.rst)). It was added in 3.1.0: "The File browser now has a Globus button to link to Globus endpoints" ([CHANGELOG](https://github.com/OSC/ondemand/blob/master/CHANGELOG.md), PR 2858). The latest release is v4.2.5 (2026-09-24, GitHub releases API).

**What it would take.** Katana's OnDemand has to be at 3.1 or later (unverified). ResTech adds one YAML block with the Katana collection UUID(s). The researcher still installs GCP for the laptop side. The button only saves them finding the collection and path in Globus. Per-user personal endpoints can't be wired in ([OOD discourse feature request](https://discourse.openondemand.org/t/support-of-per-user-globus-configurations/3384), secondary).

### 5. OneDrive / SharePoint / Teams via rclone on the data mover

**How it works.** ResTech documents running `rclone config` on `kdm`, with a token authorised by `rclone authorize "onedrive"` on a local machine, then `rclone mount OneDrive: ~/OneDrive --daemon --vfs-cache-mode writes`. It says to mount "only on Katana Data Mover", calls the setup "not ideal", and says rclone's OneDrive limits are outside what it supports ([onedrive page](https://docs.restech.unsw.edu.au/storage/onedrive/)).

**Size suitability.** Fine for big copies if run as `rclone copy` in `tmux` on `kdm`. A mount with write caching is not a good bulk path. That's our judgement; ResTech documents only the mount.

**What the researcher installs or does.** Two terminals, a token paste, and a re-mount at every login. Not suitable for non-technical users unaided.

**Available today?** Verified. `rclone` v1.55.1-DEV is at `/usr/local/bin` on `kdm`, and modules `rclone/1.51.0` to `rclone/1.70.2` are available. Neither is on `katana2` (`which rclone`). `available-modules.md` doesn't list rclone, because that list is from the login node.

**OnDemand angle.** OnDemand's remote-files feature (2.1 and later; `remote_files_enabled`, default false) would show these remotes in the Files app. It requires "`rclone` installed on the same machine that Open OnDemand is installed", and users set up their own remotes ([customizations: Accessing Remote File Systems](https://osc.github.io/ood-documentation/latest/customizations.html#accessing-remote-file-systems)). Transfers would then run through the web node.

### 6. UNSW Data Archive to Katana

**How it works.** On `kdm`, run `module add unswdataarchive/<version>`, then `get-config-file`, add a token (from the IT Service Centre) or `user=<zID>`, then `download.sh /UNSW_RDS/Dxxxxxxx/... <dir>`. Needs an RDMP ([data archive page](https://docs.restech.unsw.edu.au/storage/data_archive/)). Versions on `kdm`: 2017-02-06 to 2025-10-29 (`module avail unswdataarchive`).

**From a laptop to the Archive** (not to Katana): the web app for under 50 GB or 1000 files, SFTP to `rds.unsw.edu.au:8022` above that ([Data Archive SFTP guide](https://www.unsw.edu.au/research/data-archive/help-topics/sftp-client-guide)). Researchers could stage data there with a GUI client, but that's two hops instead of one.

**Suitability.** Good when the data already lives in the Archive. It needs a terminal on `kdm`, so a non-technical researcher needs help.

### 7. FileSender (AARNet)

FileSender is a send-a-link service between people. Nothing in the sources above ties it to Katana, and fetching a link onto Katana would need a terminal (`wget` on `kdm`). Not a fit. We didn't verify it further.

## Open questions for ResTech

1. What is the Katana Globus collection called, and which paths does it map: `/home`, `/srv/scratch/<zID>`, shared scratch? Is it open to all Katana users or only `katana_ai_ro` during the IRIS pilot? Can it be documented on docs.restech?
2. Is the collection linked to UNSW's subscription, so that HTTPS browser upload/download and guest-collection sharing with external collaborators work?
3. Which Open OnDemand version is KOD running? If it's 3.1 or later, would ResTech add a `globus_endpoints` block so the Files app gets a Globus button?
4. Has KOD's upload cap (`FILE_UPLOAD_MAX` / `nginx_file_upload_max`) been changed from the 10.7 GB default? Is ResTech happy for researchers to upload multi-GB files through the web node at all?
5. Is SFTP to `kdm` reachable off campus without the VPN, and is MFA required anywhere on the SSH/SFTP path?
6. Is there a supported route from OneDrive/SharePoint for large datasets beyond the documented `rclone mount`, such as `rclone copy` guidance or a newer default rclone than v1.55.1 on `kdm`?
