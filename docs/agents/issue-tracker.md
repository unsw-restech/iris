# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations. `jq` isn't installed on the desktop: filter with `gh ... --jq`, since a pipe into `jq` fails and leaves an empty result that reads as zero matches.

## Conventions

- **Write a body first**: every issue body and comment goes in a file written with the Write tool, then `--body-file <file>` in a `gh` call of its own, which the lone-write hook lets through.
- **Create an issue**: `gh issue create --title "..." --body-file <file>`.
- **Read an issue**: `gh issue view <number> --json title,state,labels,body,comments`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Make an issue a sub-issue of a parent**: `gh issue edit <child> --parent <parent>`, or `gh issue create --parent <parent>` for a new one.
- **Comment on an issue**: `gh issue comment <number> --body-file <file>`.
- **Tick a box**: `bin/issue-tick <number> "<box text prefix>"...`, one prefix per box. It ticks in the body, or else in the latest `## Agent Brief` comment, where triage puts a brief's acceptance criteria, and changes nothing unless one of them has exactly one box for each prefix. A ticket with boxes in both needs a call for each.
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Settle part of another ticket**: comment on it, naming the commit and what it settles, whenever a commit cites an open issue other than its own or meets one of its acceptance criteria, so whoever builds it starts from what's left. adc5e01 cited #147 in a doc and said nothing on #147, so its triage re-derived the fix (2026-11-10).
- **Split a ticket across pushes**: a ticket that lands in more than one push to `main` gets one PR per push, the last saying `Closes #N` and each earlier one `Part of #N`. Pushing a branch's commit to `main` marks its PR merged, deletes the branch (the repo deletes branches on merge) and closes every issue the body names after `Closes` or `Fixes`, whatever words follow. #155's "Closes #149 once its second commit lands" closed #149 before its digest pin (2026-11-11).
- **Close with a comment**: comment as in **Comment on an issue**, then `gh issue close <number>` as its own call (adding `--reason "not planned"` or `--reason duplicate` when it wasn't completed), since `close` has no file form.
- **Close a spec**: first list every open issue (`gh issue list --state open --json number,title --jq '.[] | "\(.number) \(.title)"'`), not just its sub-issues, and settle or comment on any whose question the spec's work answers. An issue raised beside a spec often isn't linked to it: #97 asked what #83's real run had just shown, and #83 closed without it (2026-10-27).

The repo is `unsw-restech/iris`. `gh` infers it when run inside the clone (`iris\`); from the parent `IRIS_github_pages\` directory, which is not a git repo, pass `-R unsw-restech/iris`.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; the triage skill reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --json title,state,labels,body,comments,reviews` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by the wayfinder skill. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (see **Make an issue a sub-issue of a parent**). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh issue edit <child> --add-blocked-by <blocker>`, or `gh issue create --blocked-by <blocker>` for a new one. GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: close with the answer as in **Close with a comment**, then append a context pointer (gist + link) to the map's Decisions-so-far.
