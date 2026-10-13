# What can an OpenComposer form do beyond submitting a script?

Research for [issue #5](https://github.com/PatrickTung/iris/issues/5). Researched 2026-10-13.

## Sources and how to read this

Everything below was read from the OpenComposer source and its bundled docs at
**v2.0.2, commit `7af3d94`** (2026-07-27), the head of the default branch on the research date.

- Source: <https://github.com/RIKEN-RCCS/OpenComposer/tree/7af3d94b36043d8019b1639cd8e463957eb7a37e>
- `run.rb` (the whole server): <https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/run.rb>
- Application creation manual: <https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/docs/application.html>
- Install manual: <https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/docs/install.html>
- User manual: <https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/docs/manual.html>
- Changelog: <https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/CHANGELOG.md>

Labels used:

- **Verified (source)**: read directly in the code or docs cited. `run.rb:NNN` are line numbers at the commit above.
- **Inference**: follows from the code plus ordinary Ruby/Sinatra behaviour, but nobody ran it.
- **Not confirmed**: could not be established from a primary source.

**Nothing here was executed.** No Ruby was available on the research machine, and no test was made against Katana.

**The biggest unknown: which OpenComposer version Katana runs.** That is not recorded anywhere in this repo. Several
features below arrived in specific releases (see "Version sensitivity" at the end), and two rules in `AGENTS.md`
disagree with v2.0.2 behaviour, which suggests Katana may be on an older release. Check the `VERSION` constant in
Katana's `run.rb` (or the version shown in the app footer/navbar) before relying on anything version-dependent.

---

## 1. How apps are discovered; is a restart needed?

**Verified (source).** Discovery is a directory listing done on every request. There is no registry and no cache.

- `create_all_manifests` (`run.rb:179-190`) does `Dir.children(apps_dir)`, skips any entry whose name starts with `.`,
  and keeps each entry that contains `form.yml` or `form.yml.erb`. `manifest.yml` is optional: without it the directory
  name is used as the app name (`run.rb:161-176`).
- That function is called from `show_website` (`run.rb:326`), which runs for every `GET /*` (`run.rb:554-556`).
- `conf.yml.erb` is also re-read on every request (`create_conf`, `run.rb:88`, called at `run.rb:307` and `run.rb:560`).
- The form itself is read fresh on each GET (`run.rb:379`) and again on each POST (`run.rb:623`).
- The URL segment is the directory name: the form route matches `m.dirname == @dir_name` (`run.rb:373`).

**So: no restart or reload is needed after adding, editing or removing an app.** A changed `form.yml.erb` or
`manifest.yml` takes effect on the next page load. This also covers `conf.yml.erb`.

What would need a restart: changes to OpenComposer's own Ruby (`run.rb`, `lib/*.rb`), since `sinatra/reloader` is only
registered when `RACK_ENV=development` (`run.rb:2`, `run.rb:19-22`). That is not something a form author touches.
One exception worth knowing: `lib/header.yml.erb` (the shared default header) is read with `read_yaml` per request
(`run.rb:383`), so edits to it are also live.

Side effects of the per-request scan:

- **Every `manifest.yml.erb` in `apps_dir` is evaluated on every page load of every form**, including the home and
  history pages, because the navbar lists all apps. Keep manifest ERB trivial. (Verified: `run.rb:326`, `run.rb:163`.)
- A manifest that fails to parse makes `create_manifest` return `nil` and the app silently disappears from the list
  (`run.rb:162-166`, `.compact` at `run.rb:189`). A broken manifest looks like "the URL is not found", not like a YAML error.
- The directory name must match `^[a-zA-Z][a-zA-Z0-9_]*$` according to the manual's Supplement section ("The same rule
  applies to the directory name"). **This conflicts with the project's slugs**, which use hyphens
  (`whisper-transcription`, `mnist-classification`). Those two are confirmed opening on Katana (AGENTS.md), so in
  practice hyphens work for opening a form. In the source, the regex is only enforced on widget names
  (`run.rb:407-413`), not on directory names. **Not confirmed**: whether a hyphenated directory name breaks anything
  downstream (history page, `#{OC_DIR_NAME}` substitution). Worth one test submission from a hyphenated form.

## 2. Can the apps directory be a git checkout or contain symlinks?

**Git checkout: yes. Verified (source).** `.git` and any other dot-entry are skipped (`run.rb:181`). Entries with no
`form.yml[.erb]` inside are ignored (`run.rb:184`), so a top-level `README.md`, a `LICENSE`, or a shared-fragments
directory do no harm. A `git pull` in that directory is the whole deployment, with no restart (section 1).

The install manual itself deploys OpenComposer by `git clone` and by Open OnDemand's "Clone Existing App" from a Git
remote (install manual, sections 1 and 4), but that is the OpenComposer app, not `apps_dir`. The manual says nothing
about `apps_dir` being a checkout; the answer above comes from the code.

**Symlinks: yes by inference.** Discovery uses `Dir.children`, `File.join` and `File.exist?` (`run.rb:180-184`), all of
which follow symlinks in Ruby. So `apps_dir` may itself be a symlink, and individual app directories may be symlinks
into a checkout elsewhere (for example a shared world-readable IRIS directory). The changelog for 1.4.0 has a related
fix: "A reference so that it works even if the destination of related_app in manuscript is a link." **Not run.**

Constraints on where `apps_dir` points:

- `apps_dir` comes from `conf.yml.erb` and can be relative (the sample uses `./sample_apps`) or absolute, and since the
  conf is ERB it can be computed (`conf.yml.erb.sample`). **Verified (source).**
- **Local icon files assume `apps_dir` is relative to the OpenComposer directory.** `get_icon_path`
  (`lib/index.rb`) builds `File.join(Dir.pwd, "/", @apps_dir, dirname, icon)`. With an absolute `apps_dir` that path
  does not exist and the icon falls back to the placeholder image. URL icons, Bootstrap icons (`bi-...`) and Font
  Awesome icons (`fa-...`) are unaffected. **Inference** from the code; the simple fix is a relative `apps_dir` that is
  a symlink, or non-file icons.
- The PUN process runs as the logged-in researcher, so every researcher needs read access to the directory the
  checkout lives in. **Inference** from how Open OnDemand per-user Nginx works.

This means the 1:1 rule in AGENTS.md (directory name = URL segment) can be satisfied by a checkout whose top-level
directories are the slugs. The `hello-world` -> `IRIS` rename is the one case a plain checkout cannot express; a
symlink `IRIS -> hello-world` inside the checkout would (it would also make `hello-world` appear as a second app
unless the real directory lives outside `apps_dir`).

## 3. Can a URL pre-fill form fields?

**Natively, only from a past job. Verified (source).**

- `GET <app>?jobId=<id>` loads that job's stored parameters from the history database and fills the header fields, the
  form fields and the script text (`run.rb:418-447`, `replace_with_cache` at `run.rb:201-223`). This is what the
  history page's "Load parameters" button links to (`lib/history.rb:123`, user manual section 4).
- With multiple clusters, `&cluster=<name>` selects which history database to read (`run.rb:419-421`).
- The id must exist in the visiting user's own history (`~/composer/*.sqlite3`), otherwise the page shows
  "Specified Job ID (...) is not found." So this cannot carry values from the IRIS page to a first-time visitor.
- There is **no** generic `?field=value` handling. Neither `show_website` nor `public/form.js` reads query parameters
  for field values (no `URLSearchParams` or `location.search` use in `form.js`).

**Via ERB, a form can read the query string itself. Inference, not run.** `read_yaml` renders the ERB with
`result(binding)` (`run.rb:78`) from inside a Sinatra request, so Sinatra's `params` and `request` are in scope. A form
could therefore write:

```yaml
form:
  input_path:
    widget: path
    label: Input volume
    value: <%= params["input_path"].to_s.to_json %>
```

and the IRIS page could link `.../OpenComposer/<slug>?input_path=/srv/scratch/...`. Things to know before using it:

- **Quote with `.to_json`.** A raw `<%= params[...] %>` pastes attacker-controllable text into YAML, so a crafted link
  could add or change keys in the form definition. `.to_json` yields a valid quoted YAML scalar.
- A pre-filled value flows into the generated job script. The researcher sees the script before submitting, but a
  link from anywhere could pre-fill a hostile value (a path containing `; rm -rf ...`). Validate in `check:` and quote
  the value in the script.
- The ERB is evaluated again on POST, where `params` holds the submitted fields, not the original query string
  (the form posts to `@current_path` with no query: `views/form.erb:34`). For a `value:` default this does not matter,
  because after submit the fields are refilled from the submitted values (`run.rb:448-452`).
- `jobId` and (multi-cluster) `cluster` are reserved query names.
- This relies on an implementation detail (the binding used for ERB), not a documented feature.

## 4. Can a form share fragments or includes with other forms?

**There is no include mechanism in OpenComposer.** The manual documents none and the code has none: each app is one
`form.yml[.erb]` read by `read_yaml` (`run.rb:75-84`). **Verified (source).**

Three ways sharing can still be done:

1. **The shared header (documented, verified).** If a form has no `header:` key, `lib/header.yml.erb` is used for
   every app (`run.rb:380-384`; manual sections 1.2 and 8). It is ERB and can branch per app with `@OC_DIR_NAME`
   (manual section 8 shows exactly this). It holds "Script location", "Script name" and "Job name". Limits: it lives
   inside the OpenComposer install, not in `apps_dir`, so editing it needs write access there and is overwritten by an
   OpenComposer upgrade; and it is shared by *every* OpenComposer app on the instance, not only IRIS ones.
2. **ERB reading another file (inference, not run).** Because `form.yml.erb` is arbitrary Ruby, it can splice in a
   file: `<%= File.read("/path/to/iris/_shared/resources.yml") %>`. Indentation of the spliced text must match the
   insertion point, since the result is parsed as one YAML document. A fragments directory can sit inside `apps_dir`
   as long as it has no `form.yml[.erb]` (section 2). For the path, note that `@apps_dir` is set on GET
   (`run.rb:308`) but **not** on POST (`run.rb:623` runs before `show_website`), so a fragment path built from
   `@apps_dir` would break at submit time. An absolute path is the safe choice. (`File.dirname(yml_path)` also works in
   both, since `yml_path` is a local of `read_yaml`, but that leans on an internal variable name.)
3. **YAML anchors within one file (not confirmed).** `read_yaml` uses `YAML.load` (`run.rb:78`). On Ruby 3.1+
   (Psych 4) `YAML.load` rejects aliases by default; on older Ruby it accepts them. The Ruby version of Katana's
   OnDemand host is unknown, so do not rely on anchors.

A general caution for options 1 and 2: the form ERB is evaluated in two different contexts. On GET `@OC_APP_NAME`,
`@OC_DIR_NAME`, `@conf`, `@apps_dir` are set; on POST (`run.rb:623`) they are not yet. Any ERB that changes the
*structure* of the form based on those will produce a different form at submit time than the one rendered.

Sharing by generation (the project's existing `gen_forms.py` approach, kept outside the repo) remains the
no-moving-parts alternative.

## 5. What can ERB run at render time?

**Arbitrary Ruby, as the logged-in user, on the OnDemand host. Verified (source).**

- `form.yml.erb`, `manifest.yml.erb` and `conf.yml.erb` are all rendered by
  `ERB.new(File.read(path), trim_mode: "-").result(binding)` (`run.rb:78`) with no sandbox.
- The shipped PBS sample runs a shell command at render time to build a dropdown:
  `` (`groups`.strip.split - [ENV['USER'], ENV['LOGNAME']]).each `` in
  [`sample_apps/PBS/form.yml.erb`](https://github.com/RIKEN-RCCS/OpenComposer/blob/7af3d94b36043d8019b1639cd8e463957eb7a37e/sample_apps/PBS/form.yml.erb).
  The default header uses `Dir.home` (`lib/header.yml.erb`).
- So ERB can: read environment variables and the user's identity, list directories (for example populate a `select`
  with the datasets found under a scratch path), read files, run commands (`qstat`, `module avail`, `groups`), and set
  defaults such as `value: /srv/scratch/<%= ENV["USER"] %>/iris`.
- Documented variables in ERB: `@OC_APP_NAME`, `@OC_DIR_NAME` (manual section 8), and the constant
  `OC_SCRIPT_CONTENT` (manual section 5.3).

Limits and costs:

- It runs on the **web host**, in the user's PUN process, not on a compute node. Whether Katana's OnDemand host mounts
  `/srv/scratch` and has `qstat`/`module` on its PATH is **not confirmed**.
- It runs synchronously on every page load and again on submit; a slow command makes the form slow.
- ERB output is then parsed as YAML, so command output must be YAML-safe.
- ERB cannot react to what the user types. In-page reactivity comes only from the Dynamic Form Widget options
  (`set-`, `disable-`, `enable-`, `hide-`, `show-` on select/radio/checkbox/multi_select: manual section 3) and the
  script functions `zeropadding`, `calc`, `dirname`, `basename` (manual section 2.9).

## 6. What can `check:` do before submit?

**Verified (source): `check:` is a Ruby string passed to `eval` on the server at submit time** (`run.rb:636-691`).

- When it runs: on POST, before the script is written to disk, before the `submit:` section and before `qsub`
  (`run.rb:683-695`; manual section 9 gives the same order).
- Inputs: each form value as an instance variable, `@field`, `@field_1`, `@field_2`; numbers are converted to
  Integer/Float; select/radio give the option's second element (`run.rb:639-681`). Also `@OC_APP_NAME`,
  `@OC_DIR_NAME`, `@OC_SCRIPT_LOCATION`, `@OC_SCRIPT_NAME`, `@OC_JOB_NAME`, `@OC_CLUSTER_NAME` (manual section 6).
- Capability: it is unrestricted Ruby running as the user, so beyond comparing numbers it can test that an input path
  exists and is readable, inspect a file header, check quota or free space, run a command, or write a file (for
  example append a line to a usage log). **Inference** for the specific uses; the mechanism is verified.
- Working directory: `Dir.chdir(script_dir)` wraps the eval (`run.rb:685`).

Three behaviours that matter for IRIS:

1. **`halt 500` versus `oc_assert`: the failure looks different. Inference from the code, not run.**
   `oc_assert(cond, msg)` raises `RuntimeError` (`run.rb:475-477`), which the `rescue` at `run.rb:688-690` turns into
   a re-rendered form with the banner "Job submission failed. (msg)" and **all entered values kept**
   (`views/form.erb:21-25`, `run.rb:448-452`). `halt 500, "msg"` is Sinatra's `throw :halt`, which a `rescue` does not
   catch, so the response is a bare HTTP 500 page carrying only the message and the researcher has to go back.
   The documented API is `oc_assert` (manual section 6); the shipped PBS sample still uses `halt 500`.
   AGENTS.md says the reference schema uses `halt 500, "..."`, not `oc_assert(...)`. `oc_assert` was added in
   **1.4.0** (changelog), so either Katana is older than 1.4.0 or the rule is a habit copied from the sample.
   A plain `raise "msg"` behaves like `oc_assert` and exists in every version.
2. **A form with `check:` fails if the script location does not exist yet. Inference from the code, not run.**
   The `Dir.chdir(script_dir)` at `run.rb:685` comes before `FileUtils.mkdir_p(script_location)` at `run.rb:694`.
   If the directory is missing, `chdir` raises and the user sees "Job submission failed. (No such file or
   directory ...)". Forms without `check:` create the directory. This matters if a form defaults the script location
   to a not-yet-created per-run directory.
3. **`#{}` inside `check:` is plain Ruby interpolation in v2.0.2. Verified (source).** Only `script` and `submit`
   content go through OpenComposer's `#{field}` substitution (`lib/form.rb`, `output_body`); `check` is read from the
   YAML and eval'd unchanged (`run.rb:637`, `run.rb:686`), and the PBS sample uses `"#{@time_1}:#{@time_2}"` inside
   `check:`. AGENTS.md trap 2 says `#{}` in `check:` collides with OpenComposer's substitution. The 1.7.0 changelog
   lists a fix for "variables could not be referenced in the submit and check sections", so the trap may be real on
   the version Katana runs. Keeping to string concatenation is harmless either way.

**Beyond `check:`, the `submit:` section** (manual section 7; `run.rb:697-721`) is a Bash script run after `check:` and
after the job script is saved, before `qsub`. It uses the same `#{field}` substitution as `script:`, can rewrite or
move the saved script, and can pass extra scheduler options by setting `OC_SUBMIT_OPTIONS`. A non-zero exit aborts the
submission and shows stderr in the form (`run.rb:715-717`). With `action: confirm` the user is shown the commands in a
modal first, which adds a click. `script: { action: save }` saves the file without submitting (manual section 5.2).
AGENTS.md lists the reference schema's top-level keys as `form`, `script`, `check` only; `submit:` and `header:` are
valid additional keys in v2.0.2 but have not been tried on Katana.

**There is no post-submission hook.** After `scheduler.submit` the server only writes the history record and a log
line (`run.rb:729-763`). Form code never sees the job ID. Anything that needs the job ID has to happen inside the job
script (`$PBS_JOBID`).

## 7. Does it keep a job history?

**Yes, per user, with no service. Verified (source and user manual section 4).**

- Stored in SQLite at `<data_dir>/<scheduler>.sqlite3`, `data_dir` defaulting to `~/composer`
  (`run.rb:117`, `run.rb:150`). Each user has their own file in their own home. Storage moved from PStore to SQLite in
  2.0.0 with automatic migration (changelog).
- Each record holds every submitted form value plus the full script text, job name, script location, submission time
  and status (`run.rb:735-758`).
- Status is refreshed by querying the scheduler when the history page is opened, only for unfinished jobs
  (`update_status`, `lib/history.rb:1053-1066`, called from `run.rb:340`). Nothing runs in the background, which fits
  the "no always-on services" constraint.
- The history page (`<OpenComposer>/history`) offers: filter and full-text search across all stored values including
  script contents, date range and AND/OR search (2.0.0), sort, cancel job, delete record, view the script, job details
  from the scheduler, a link to the script location in the OnDemand Files app, and "Load parameters" to reopen the form
  pre-filled (section 3).
- Extra columns can be added in `conf.yml.erb` under `history:`, but only scheduler-reported values, not form fields
  (install manual section 2.5).

What it is not: it is per-user and per-OnDemand-instance, there is no cross-user view, and it records what was
submitted, not results or metrics. It answers "what did I run and with which parameters" and "run that again with one
change"; it does not answer experiment comparison or ResTech usage logging on its own.

OpenComposer also prints one log line per submission to stdout (app directory, app name, category, job IDs:
`output_log`, `run.rb:508-515`, `run.rb:761`). Where that lands on Katana (the per-user PUN log, presumably) and
whether ResTech can read it across users is **not confirmed**.

## 8. Can a form link out to another OnDemand app, or show a link after submission?

**Link to another OnDemand app: yes, in three places.**

1. **`related_apps:` in `manifest.yml` (documented, verified).** Listed apps appear as icons next to each job of that
   form on the history page, linking to `<ood>/pun/sys/dashboard/apps/show/<name>` in a new tab
   (`lib/history.rb:5-26`, `views/history.erb:197-205`, manual section 1.1). Limits: the icons show **only on the
   history page**, not on the form or in the success banner; the link is hard-coded to `/pun/sys/`, so the target must
   be a system-installed OnDemand app (a `/pun/dev/` viewer would not resolve); and the link carries no context, so a
   volume viewer opened this way does not know which job or output directory it came from. The key was renamed from
   `related_app` to `related_apps` in 1.8.0 and the old spelling now halts with an error (`run.rb:169`).
2. **HTML in the manifest `description` (verified in source, not run).** `views/form.erb:45` emits
   `<%= @manifest['description'] %>` unescaped at the top of the form, so an `<a href="...">` works there. The manual's
   sample uses Markdown link syntax (`[Gaussian](https://gaussian.com)`), but no Markdown renderer was found anywhere
   in the v2.0.2 source, so Markdown probably shows as literal text. Use HTML.
3. **HTML in a widget's `help:` (verified in source, not run).** `output_help` (`lib/form.rb:72-84`) emits the help
   text unescaped inside a `<p>`, so a link can sit directly under a field. Labels are also unescaped but are copied
   into an HTML attribute as well, so keep markup out of labels.

These are static links, visible before and after submission. Using ERB they can include the user name or other
render-time values, but not values typed into the form.

**Link after submission: only the built-in one. Verified (source).** The success banner is fixed
(`views/form.erb:1-19`):

> Job was successfully submitted (Job ID is `N`). The script file is saved as *(link)*. Go to the History page.

- The script path links to the OnDemand Files app opened at the **script location** directory
  (`/pun/sys/dashboard/files/fs<dir>`).
- If `login_node` is set in `conf.yml.erb`, a terminal icon opens the OnDemand shell in that directory.
- "History page" links to the history.
- A form cannot add to or change this banner; there is no template hook or key for it.

The practical consequence: **if the job writes its outputs under the script location, the built-in banner already gives
one click from "submitted" to the results folder**, and the same link is on every history row. A link to a viewer app
has to be a static link in the description or help text, or a `related_apps` icon on the history page.

**Not confirmed:** the exact URL to deep-link an Open OnDemand interactive (batch connect) app's launch form, and
whether such a form accepts pre-filled values by URL. The Open OnDemand manifest documentation only says the `url` key
is "generated dynamically but can be overridden"
(<https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive/manifest.html>). That belongs to
the viewer ticket.

## Other things a form can do (all from the application manual, verified in docs)

- Widgets: `number`, `text`, `email`, `select`, `multi_select`, `radio`, `checkbox`, `path` (section 2). `path` is a
  server-side file/directory browser with `favorites:` shortcut paths and `show_files:` (section 2.8), which is the
  natural widget for picking an input volume on IDS, OneDrive or scratch mounts.
- Dynamic Form Widget: an option can set another widget's min/max/step/label/value/required/help, or disable, enable,
  hide or show widgets (section 3).
- Hide the script pane entirely, so the researcher sees only the form (section 5.3; uses `hide-<%= OC_SCRIPT_CONTENT %>`).
- The script text area is always user-editable before submit unless hidden (user manual section 3). What is submitted
  is the text area's content, not a server-side re-render (`run.rb:631`), so validation in `check:` sees the form
  fields, not hand edits to the script.
- A line of `script:` whose variable is empty is dropped; prefix with a colon (`#{:nodes}`) to keep it (section 9).
- Custom `header:` per form to change the defaults for script location, script name and job name (section 8). The
  default script location is the home directory and the default script name is `job.sh` (`lib/header.yml.erb`), so
  repeated runs from the default header overwrite the same `~/job.sh`.
- An OpenComposer form can be given its own tile on the OnDemand dashboard by creating a small OnDemand app directory
  whose `manifest.yml` has a `url:` pointing at the form (install manual section 3).

## Version sensitivity

Features above and the release that introduced them (changelog):

| Feature | Since |
| --- | --- |
| `related_apps` (as `related_app` before 1.8.0) | 1.1.0 |
| Failed submission re-renders with values kept | 1.1.0 |
| PBS support, `bin_overrides` | 1.2.0 |
| `submit:` section, per-form `header:`, script label | 1.3.0 |
| `oc_assert`, hide script | 1.4.0 |
| Multiple clusters; XSS sanitisation | 1.5.0 |
| `zeropadding`, submission log line | 1.6.0 |
| `action: save`, `action: confirm`; fix for variables in `submit`/`check` | 1.7.0 |
| `related_apps` rename, `@OC_DIR_NAME`, `OC_SCRIPT_CONTENT` rename | 1.8.0 |
| SQLite history, advanced history search | 2.0.0 |

## Open questions this raises

1. Which OpenComposer version is on Katana's dev instance, and which Ruby? This decides `oc_assert`, `submit:`,
   `action: save`, YAML anchors and the `#{}`-in-`check:` trap.
2. Is OpenComposer on Katana under `/pun/dev/` a per-user sandbox copy? The Open OnDemand docs say development apps
   live in each user's `~/ondemand/dev`
   (<https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html>). If so,
   other researchers cannot reach Patrick's dev copy at all, and each form's "Run on Katana" link only works for him
   until the move to `/pun/sys/`. **Not confirmed** for Katana; it bears on the "Going live" item on the map.
3. Does Katana's OnDemand web host mount `/srv/scratch` and the IDS/OneDrive mounts? Render-time ERB, `check:` and the
   `path` widget all run there, not on a compute node.
