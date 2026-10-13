# How the four data paths to Katana work

Research for [issue #6](https://github.com/PatrickTung/iris/issues/6). Researched 2026-10-13 from public primary sources only. Nothing here was tested on Katana.

Each claim is tagged:

- **[V]** verified: stated by the cited source.
- **[I]** inference: follows from verified facts but no source says it outright.
- **[?]** not confirmed: no public source found. Collected under "Open questions for Patrick".

## Short answer

Only one place on Katana is both a transfer destination and readable by a PBS job: scratch (`/srv/scratch/...`) or home. Two of the four paths (OneDrive, IDS) do not deliver data there. They are mounts that exist on the Katana Data Mover (KDM) only, so they are staging areas: the researcher must SSH to KDM and copy into scratch. rsync lands data in scratch directly but needs a terminal (or a desktop GUI client) on the researcher's computer. Globus is the only one of the four that can be started from a web link with no terminal, and Globus documents a pre-filled File Manager URL, but whether a Katana collection exposing scratch exists is not public.

| Path | Appears on Katana at | Readable from compute nodes | Terminal step | Documented limits |
|---|---|---|---|---|
| OneDrive (rclone mount) | `/home/<zID>/OneDrive` on KDM | No, KDM only | Yes, several | 250 GiB per file, 400-character paths (rclone/OneDrive) |
| IDS mount | `/home/<zID>/ids` on KDM | No, KDM only | Yes, to copy off it [I] | "Depends on storage location" |
| rsync to KDM | wherever it is sent: home or `/srv/scratch/<zID>` | Yes | Yes (or a GUI client) | Scratch quota 128 GB, home 10 GB |
| Globus | whatever the collection maps [?] | Yes if it maps scratch [?] | No | 3 active tasks per user; no per-file size limit stated |

## Katana storage, as the baseline

Source: <https://docs.restech.unsw.edu.au/storage/storage_locations/>

- **[V]** Home `/home/z1234567`: 10 GB, backed up, usable "Anywhere".
- **[V]** User scratch `/srv/scratch/z1234567`: 128 GB, not backed up, usable "Anywhere".
- **[V]** Shared scratch `/srv/scratch/group_name`: size "Upon group requirements", not backed up, usable "Anywhere".
- **[V]** Local scratch `$TMPDIR`: 200 GB shared between users of a node, "Only on compute nodes", temporary per job.
- **[V]** UNSW Research Storage `/home/z1234567/sharename`: "Only available on KDM (and login nodes for small files)".
- **[V]** Instrument Data Store `/home/z1234567/ids`: "Storage of instrument data generated within MWAC", backed up, size "Depends on storage location", "Only available on KDM".
- **[V]** Storage increases are by request to `restech.support@unsw.edu.au` and "are not automatic".
- **[I]** "Anywhere" includes compute nodes, since the same column says "Only on compute nodes" for local scratch and "Only available on KDM" for the mounts.
- **[V]** No purge policy for scratch is stated on this page or in the FAQ (<https://docs.restech.unsw.edu.au/help_support/faq/>). The FAQ says only that global scratch is not backed up.

The Katana Data Mover: <https://docs.restech.unsw.edu.au/storage/kdm/>

- **[V]** Host `kdm.restech.unsw.edu.au`, reached by `ssh z1234567@kdm.restech.unsw.edu.au`. "KDM is designed to handle many and/or very large transfers without impacting the login/head nodes."
- **[V]** "For small files (e.g. a few job scripts <2–3 MB) you can copy directly to Katana, but please keep such direct copies minimal." Anything larger goes through KDM.
- **[V]** Transfer methods the page names: rsync, scp, FileZilla, WinSCP. It does not mention Globus.
- **[V]** KDM sees the same home and scratch as the cluster: the documented destinations are `z1234567@kdm.restech.unsw.edu.au:` (home) and `...:/srv/scratch/z1234567`.

## 1. OneDrive mount

Source: <https://docs.restech.unsw.edu.au/storage/onedrive/>

- **[V]** Mechanism is an rclone FUSE mount: `rclone mount OneDrive: /home/z1234567/OneDrive --daemon --vfs-cache-mode writes`. Files "appear under `/home/z1234567/OneDrive` (or your chosen mount point)".
- **[V]** "Please mount OneDrive only on **Katana Data Mover** ... not on the login nodes." And: "Mounting OneDrive locally will only work on the machine where the `mount` command is executed."
- **[I]** So a PBS job on a compute node cannot read the OneDrive path, even though it sits under `$HOME`. Data must be copied from the mount into scratch on KDM first. The quick-start guide shows exactly that pattern, rsync from the mounted directory to scratch (<https://docs.restech.unsw.edu.au/using_katana/troubleshooting_navigation/>).
- **[V]** What the researcher does, all in a terminal:
  1. Grant consent once in a browser at the UNSW consent helper link given on the page.
  2. SSH to KDM and run `rclone config` through an interactive wizard.
  3. During the wizard, run `rclone authorize "onedrive"` on their own computer (so rclone must be installed there too) and paste the token back into KDM.
  4. Run the mount command. "You will need to re-run the mount command each session (mounts are temporary)."
  5. Unmount with `fusermount -u`.
- **[V]** ResTech's own position: "We don't generally recommend researchers mount their OneDrive because the configuration process is not ideal, and RClone integration with OneDrive has **limitations** that UNSW support cannot assist with." No guarantee for users in Germany or China.
- **[V]** Limits, from the rclone page ResTech links (<https://rclone.org/onedrive/>): largest file 250 GiB; whole path under 400 characters; about 50,000 files per folder is reliable and listing errors appear around 100,000; names are case-insensitive with some characters remapped.
- **[?]** Speed: no figure published by ResTech or rclone.
- **[V]** `available-modules.md` has no rclone module. **[I]** rclone is installed system-wide on KDM, since the docs call it without a `module load`.

Verdict against the two-click bar: fails. Every step is a terminal step, one of them on the researcher's own machine, and the result is still not visible to a job.

## 2. Instrument Data Store (IDS) mount

- **[V]** On Katana it is `/home/z1234567/ids`, "Only available on KDM", holding "instrument data generated within MWAC" (the Mark Wainwright Analytical Centre). Source: <https://docs.restech.unsw.edu.au/storage/storage_locations/>. That one table row is everything the Katana docs say about IDS.
- **[I]** As with OneDrive, a compute node cannot read it. A researcher must SSH to KDM and `cp` or `rsync` from `$HOME/ids` to scratch, which is a terminal step.
- **[?]** Whether `$HOME/ids` is mounted automatically for every user, appears only for users with an IDS directory, or needs a request or a command. Not documented publicly.
- **[?]** Whether the mount is read-only on KDM, and its size and speed limits ("Depends on storage location" is all that is published).
- **Unreachable source.** The MWAC pages that describe IDS itself (`analytical.unsw.edu.au/node/1140`, the "IDS The Essential 5 FAQs" PDF and the "Manual mount IDS" PDF) could not be fetched: the site's TLS certificate has expired. Search-engine snippets of those pages say IDS is an SMB share mapped as `\\ids.mwac.unsw.edu.au\ids` with `zID@ad.unsw.edu.au` credentials, needs the UNSW VPN off the MWAC network, gives each user a zID directory when their ACLS account is created, and copies raw instrument data to the UNSW Data Archive. Treat all of that as unverified second-hand until someone reads the pages.

Verdict: same shape as OneDrive without the setup pain. Good as a source, not as a job input path.

## 3. rsync from the researcher's computer

Source: <https://docs.restech.unsw.edu.au/storage/kdm/>

- **[V]** Recommended form: `rsync -avh /local/path z1234567@kdm.restech.unsw.edu.au:/srv/scratch/z1234567/`. Resumable form: `rsync -avhP --partial`. The FAQ agrees: "Use `rsync` to copy data to the KDM server."
- **[V]** Data lands wherever it is pointed. Scratch and home are usable "Anywhere", so this is the one documented path whose destination a job can read directly.
- **[V]** Needs a terminal on the researcher's computer. The documented non-terminal alternatives are desktop GUI clients, FileZilla and WinSCP, pointed at the same host. rsync is recommended for Linux and macOS; Windows users are pointed at the GUI clients.
- **[V]** For long transfers run on KDM itself, the page recommends `tmux` or `screen`.
- **[V]** Limits: the destination quota (128 GB user scratch, 10 GB home). No transfer size cap or speed figure is published.
- **[?]** Whether SSH to KDM needs the UNSW VPN from off campus. The OnDemand page says remote access needs the VPN (<https://docs.restech.unsw.edu.au/using_katana/ondemand/>); the KDM and "Accessing Katana" pages do not say either way.

Verdict: works and is the documented default, but it is a terminal (or third-party app) step outside the two clicks. Acceptable only as a "do this once before you launch" instruction.

## 4. Globus

### Does UNSW have a subscription and a Katana collection?

- **[V]** UNSW runs Globus on its HPC side. The ResTech facility page says: "UNSW has a Globus data transfer node attached to our High Performance Computing environment." It points staff to a SharePoint page (`unsw.sharepoint.com/sites/Restech/SitePages/Globus.aspx`, zID required) and outsiders to `RDM@UNSW.edu.au`. Source: <https://www.unsw.edu.au/research/facilities-and-infrastructure/find-a-facility/restech>
- **[V]** UNSW has a Globus subscription. The UNSW Structural Biology Facility's public docs show two collections, "UNSW-EMU" and "Discworld StructBio /User Data", each described as a "Subscribed Mapped Collection (GCS) on ResTech (gd1)" with "Subscription: University of New South Wales", and sign-in by UNSW single sign-on at app.globus.org. Source: <https://docs.discworld.unsw.edu.au/how-to/globus-data-transfer>. This is a UNSW facility's documentation, not ResTech's own.
- **[V]** The same source shows ResTech already operates a Globus Connect Server endpoint ("gd1") and that an instrument-side collection exists for the electron microscope unit. Guest collections (sharing) are in use there, which needs a subscription.
- **[?]** Whether any collection maps Katana's `/srv/scratch` or `/home`, and its UUID. The public Katana docs never mention Globus, and the page that would say is behind zID login. This is the single fact the Globus option hangs on.
- **[V]** Katana has a `globus/3.28.3` module (`available-modules.md`). **[I]** It is the Globus CLI: the CLI has a release tagged 3.28.3 (2024-06-14, <https://github.com/globus/globus-cli/releases/tag/3.28.3>), and no other Globus product uses that version line. The CLI can submit transfers (`globus transfer`) but needs an interactive `globus login` first (<https://docs.globus.org/cli/>), so it is a terminal tool and not a route to two clicks.

### Can a transfer be started from a pre-filled web link?

- **[V]** Yes, the File Manager can be pre-filled. Globus documents four query parameters on `https://app.globus.org/file-manager`: `origin_id` and `origin_path` for the left pane, `destination_id` and `destination_path` for the right pane. Documented example: `https://app.globus.org/file-manager?destination_id=<uuid>&origin_id=<uuid>&origin_path=%2Fshare%2F`. Source: <https://docs.globus.org/faq/transfer-sharing/> (the FAQ's text for `destination_id` says "left hand side", an evident typo; its examples put it on the right).
- **[V]** The link pre-selects; it does not submit. The researcher still selects files and presses Start. "Once submitted" Globus runs the transfer unattended and the browser can be closed. Source: <https://docs.globus.org/guides/tutorials/manage-files/transfer-files/>
- **[I]** A static IRIS page can carry such a link, since it is a plain URL with no server side. It would be clicks, not terminal steps, but they are extra clicks beyond the two, plus a Globus sign-in and a first-use consent for the collection.
- **[I]** The link can only pre-fill what the page knows. A static page does not know the researcher's zID, so `destination_path=/srv/scratch/<zID>/...` cannot be filled in unless the collection's root already maps to the user's own directory. That depends on how the Katana collection is laid out [?].
- **[I]** The origin is the open end. If the data is on the researcher's own computer they need Globus Connect Personal installed and running there, which is an install step. If the data is already on a UNSW collection (as the microscope unit's is), both ends are server collections and nothing is installed.

### Does Open OnDemand's Globus integration apply?

- **[V]** It exists from Open OnDemand 3.1: "The files application will now provide a link to Globus endpoints when users navigate to a directory that is within that endpoint." Source: <https://osc.github.io/ood-documentation/latest/release-notes/v3.1-release-notes.html>
- **[V]** It is an admin setting, `globus_endpoints` in an `ondemand.d` YAML file, mapping a local `path` to an `endpoint` UUID and `endpoint_path`. Default is null, meaning no button. Source: `source/reference/files/ondemand-d-ymls.rst` in <https://github.com/OSC/ood-documentation>
- **[V]** All it does is build a link: `https://app.globus.org/file-manager?origin_id=<endpoint>&origin_path=<current dir>`, opened in a new tab. It sets the origin only, never a destination, and starts nothing. Source: `apps/dashboard/app/javascript/files/globus.js` in <https://github.com/OSC/ondemand>
- **[I]** So it applies only if (a) Katana OnDemand is 3.1 or later, (b) a Katana collection exists, and (c) a ResTech admin adds the mapping. It is a convenience for "send this Katana folder somewhere", pointing the wrong way for getting data in. IRIS can build the same kind of link itself, with a destination, without touching OnDemand config.
- **[?]** Katana OnDemand's version, and whether `globus_endpoints` is set. The public OnDemand page lists Files, JupyterLab, RStudio, Virtual Desktop and Terminal, and does not mention Globus (<https://docs.restech.unsw.edu.au/using_katana/ondemand/>).

### Limits

- **[V]** Globus service limits: 3 active and 100 pending transfer tasks per user; 100,000,000 files per task; 7,500,000 files per directory. No per-file size limit is listed. Source: <https://docs.globus.org/faq/transfer-sharing/>
- **[V]** Speed depends on the network between the collections and on each end's storage and resources; Globus sets concurrency and parallelism automatically. Same source. No UNSW figure is published.
- **[I]** The destination quota still applies: 128 GB user scratch unless raised.

## Not one of the four, but relevant: the OnDemand Files app

- **[V]** Katana OnDemand has a Files app "for uploading, downloading, deleting and modifying files" in the browser (<https://docs.restech.unsw.edu.au/using_katana/ondemand/>).
- **[V]** Open OnDemand's default upload cap is 10737420000 bytes (about 10.7 GB), set by `FILE_UPLOAD_MAX` and `nginx_file_upload_max`, the smaller winning (<https://osc.github.io/ood-documentation/latest/customizations.html>).
- **[V]** Open OnDemand 2.1 and later can show rclone remotes in the Files app if an admin sets `remote_files_enabled`; users still configure their own rclone remotes (same source).
- **[?]** Katana's actual upload cap, and whether ResTech treats browser uploads like the "2–3 MB" rule for login nodes.
- **[I]** For small inputs this is the only path that is already inside OnDemand and needs neither a terminal nor an install.

## What this means for IRIS

All inference, for the decision tickets to weigh.

1. A workflow form should take a scratch path as its input. No job can read `$HOME/OneDrive` or `$HOME/ids`.
2. OneDrive and IDS are sources that feed scratch through KDM, not inputs. Neither can meet the no-terminal bar as documented.
3. The realistic candidates for "no terminal" are a pre-filled Globus link (large data, if a Katana collection exists) and the OnDemand Files upload (small data). Both are plain links from a static page and add no service.
4. rsync remains the documented fallback and the only fully verified route into scratch.
5. Because a microCT instrument at MWAC writes to IDS, and UNSW already runs an instrument-side Globus collection for another facility, a collection-to-collection transfer from IDS to Katana scratch would need nothing installed on the researcher's computer. Whether IDS has a Globus collection is not public.

## Open questions for Patrick

UNSW-internal facts that no public source settles.

1. Is there a Globus collection that maps Katana `/srv/scratch` (and `/home`)? What are its name and UUID, and what does its root map to (so what would `destination_path` look like for a given zID)?
2. What does the ResTech SharePoint Globus page say (`unsw.sharepoint.com/sites/Restech/SitePages/Globus.aspx`)? It is the owning source for question 1.
3. Does IDS have a Globus collection, or is the KDM mount the only route from IDS to Katana?
4. Is `$HOME/ids` on KDM automatic for every user with an IDS directory, or does it need a request or a mount command? Is it read-only there?
5. Which Open OnDemand version does Katana run on `/pun/dev/` and `/pun/sys/`, and is `globus_endpoints` configured?
6. What is the Files app upload cap on Katana OnDemand, and is uploading gigabytes through it acceptable to ResTech?
7. Does SSH to `kdm.restech.unsw.edu.au` need the VPN from off campus?
8. Is there a scratch purge policy? None is published.
9. Can a compute node or an OnDemand interactive app reach KDM-only mounts in any supported way (for example a job on KDM)? The docs imply no.
10. Typical microCT dataset size against the 128 GB default scratch quota: is a quota increase or shared scratch part of onboarding?

## Sources

UNSW:

- <https://docs.restech.unsw.edu.au/storage/storage_locations/>
- <https://docs.restech.unsw.edu.au/storage/kdm/>
- <https://docs.restech.unsw.edu.au/storage/onedrive/>
- <https://docs.restech.unsw.edu.au/storage/data_archive/> (Data Archive is reached from KDM with the `unswdataarchive` module's `upload.sh` and `download.sh`; needs an RDMP and a token; terminal only)
- <https://docs.restech.unsw.edu.au/using_katana/ondemand/>
- <https://docs.restech.unsw.edu.au/using_katana/troubleshooting_navigation/>
- <https://docs.restech.unsw.edu.au/help_support/faq/>
- <https://www.unsw.edu.au/research/facilities-and-infrastructure/find-a-facility/restech>
- <https://docs.discworld.unsw.edu.au/how-to/globus-data-transfer>

Globus:

- <https://docs.globus.org/faq/transfer-sharing/>
- <https://docs.globus.org/guides/tutorials/manage-files/transfer-files/>
- <https://docs.globus.org/cli/>
- <https://github.com/globus/globus-cli/releases/tag/3.28.3>

Open OnDemand:

- <https://osc.github.io/ood-documentation/latest/release-notes/v3.1-release-notes.html>
- <https://osc.github.io/ood-documentation/latest/customizations.html>
- <https://github.com/OSC/ood-documentation> (`source/reference/files/ondemand-d-ymls.rst`)
- <https://github.com/OSC/ondemand> (`apps/dashboard/app/javascript/files/globus.js`)

Other:

- <https://rclone.org/onedrive/>

Could not be read:

- `analytical.unsw.edu.au` and `www.analytical.unsw.edu.au` (IDS pages and PDFs): TLS certificate expired.
- `support.aarnet.edu.au` article "Globus data transfer nodes in Australia": HTTP 403.
- `unsw.sharepoint.com/sites/Restech/SitePages/Globus.aspx`: needs a zID login; not attempted.
