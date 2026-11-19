#!/bin/bash
# bin/prune-merged on a throwaway main clone of a throwaway origin, with
# worktrees beside it and under .claude/worktrees/, as sessions leave them.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_prune_merged.sh
#
# bin/check name: prune-merged test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
sleeper='' mux='' ssh_client=''
trap 'kill $sleeper $mux $ssh_client 2>/dev/null; rm -rf "$fake"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# origin's main at A; the main clone, with bin/prune-merged committed.
clone="$fake/iris"
git init -q -b main "$fake/src"
mkdir -p "$fake/src/bin"
cp bin/prune-merged "$fake/src/bin/"
echo a > "$fake/src/a"
git -C "$fake/src" add -A && git -C "$fake/src" commit -qm "A"
git clone -q --bare "$fake/src" "$fake/origin.git"
git clone -q "$fake/origin.git" "$clone"

# branch <name> [<worktree>]: a branch with one commit of its own off
# origin/main, in <worktree> if given, else with no worktree.
branch() {
    if [ -n "$2" ]; then
        git -C "$clone" worktree add -q -b "$1" "$2" origin/main
        echo "$1" > "$2/$1" && git -C "$2" add "$1" && git -C "$2" commit -qm "$1"
    else
        git -C "$clone" branch -q --no-track "$1" origin/main
        git -C "$clone" commit-tree -m "$1" -p "$1" "$1^{tree}" | xargs git -C "$clone" update-ref -m "commit: $1" "refs/heads/$1"
    fi
}
# land <branch>...: pushes each branch's tip to origin's main, as a push
# <sha>:main does, so local main lags.
land() {
    local b
    for b in "$@"; do git -C "$clone" push -q origin "$b:main"; done
    git -C "$clone" fetch -q origin
}

wt_plain="$fake/iris-1"
wt_harness="$clone/.claude/worktrees/agent-1"
mkdir -p "$clone/.claude/worktrees"
branch merged-plain && land merged-plain
branch merged-wt "$wt_plain" && land merged-wt
branch merged-harness "$wt_harness" && land merged-harness
branch unmerged
branch merged-dirty "$fake/iris-2" && land merged-dirty
echo edited > "$fake/iris-2/merged-dirty"
branch merged-untracked "$fake/iris-3" && land merged-untracked
echo new > "$fake/iris-3/stray"
branch merged-busy "$fake/iris-4" && land merged-busy
mkdir "$fake/iris-4/sub dir"
(cd "$fake/iris-4/sub dir" && exec sleep 300) &
sleeper=$!
# An ssh ControlMaster (mux) keeps the folder its first ssh ran in as its
# working directory until ControlPersist ends it, but never reads it: no
# reason to keep the worktree (one held #150's retro worktree). An ssh
# command still running in a worktree, a mux's client included, keeps it.
branch merged-mux "$fake/iris-7" && land merged-mux
(cd "$fake/iris-7" && exec -a "ssh: $fake/cm-0123 [mux]" sleep 300) &
mux=$!
branch merged-ssh "$fake/iris-8" && land merged-ssh
(cd "$fake/iris-8" && exec -a "ssh katana" sleep 300) &
ssh_client=$!
# A worktree just made from origin/main, as a starting subagent's is: clean,
# no process in it, no commit of its own yet.
git -C "$clone" worktree add -q -b fresh "$clone/.claude/worktrees/agent-2" origin/main
branch merged-locked "$fake/iris-5" && land merged-locked
git -C "$clone" worktree lock "$fake/iris-5"
# The harness's lock alone doesn't keep a harness worktree; the other
# guards still do, and its reason on a worktree elsewhere is a plain lock.
wt_harness_locked="$clone/.claude/worktrees/agent-3"
branch merged-harness-locked "$wt_harness_locked" && land merged-harness-locked
git -C "$clone" worktree lock --reason "claude agent agent-3 (pid 999999 start 1)" "$wt_harness_locked"
wt_harness_dirty="$clone/.claude/worktrees/agent-4"
branch merged-harness-dirty "$wt_harness_dirty" && land merged-harness-dirty
git -C "$clone" worktree lock --reason "claude agent agent-4 (pid 999999 start 1)" "$wt_harness_dirty"
echo new > "$wt_harness_dirty/stray"
branch merged-claude-lock-outside "$fake/iris-9" && land merged-claude-lock-outside
git -C "$clone" worktree lock --reason "claude agent agent-9 (pid 999999 start 1)" "$fake/iris-9"
branch merged-missing "$fake/iris-6" && land merged-missing
rm -rf "$fake/iris-6"
tip=$(git -C "$clone" rev-parse --short origin/main)

# The main clone on main at A, behind origin/main, where git branch -d
# would refuse every branch above.
run() { (cd "$clone" && bin/prune-merged "$@" 2>&1); }
out=$(run)
rc=$?
# has <case> <line pattern>: the bare run's output has a line matching it.
has() { grep -qE -- "$2" <<< "$out" || { echo "prune-merged $1: no line matching '$2'"; echo "$out" | sed 's/^/  /'; }; }
lacks() { ! grep -qE -- "$2" <<< "$out" || { echo "prune-merged $1: has a line matching '$2'"; echo "$out" | sed 's/^/  /'; }; }

[ "$rc" = 0 ] || echo "prune-merged: bare run exited $rc"
lacks same-copy "running origin/main's copy"
has plain '^  merged-plain$'
has worktree "^  merged-wt  \(worktree $wt_plain\)$"
has harness "^  merged-harness  \(worktree $wt_harness\)$"
lacks unmerged 'unmerged'
has main '^  main: main itself, checked out in the main clone$'
has fresh "^  fresh  \(worktree $clone/.claude/worktrees/agent-2\): no commits of its own in its reflog"
has locked "^  merged-locked  \(worktree $fake/iris-5\): its worktree is locked$"
has harness-locked "^  merged-harness-locked  \(worktree $wt_harness_locked\)$"
has claude-lock-outside "^  merged-claude-lock-outside  \(worktree $fake/iris-9\): its worktree is locked$"
has harness-dirty "^  merged-harness-dirty  \(worktree $wt_harness_dirty\): uncommitted or untracked files$"
has missing "^  merged-missing  \(worktree $fake/iris-6\): its worktree folder is missing"
has dirty "^  merged-dirty  \(worktree $fake/iris-2\): uncommitted or untracked files$"
has untracked "^  merged-untracked  \(worktree $fake/iris-3\): uncommitted or untracked files$"
has mux "^  merged-mux  \(worktree $fake/iris-7\)$"
has ssh "^  merged-ssh  \(worktree $fake/iris-8\): a running process has it as its working directory \(pid $ssh_client sleep\)$"
has busy "^  merged-busy  \(worktree $fake/iris-4\): a running process has it as its working directory \(pid $sleeper sleep\)$"
last=$(tail -n1 <<< "$out")
[ "$last" = "To remove them: bin/prune-merged --apply $tip" ] || echo "prune-merged: last line is '$last'"

# gone <case> <branch> [<worktree>]: the branch, and its worktree if given,
# are gone; kept <case> <branch> [<worktree>]: both are still there.
gone() {
    ! git -C "$clone" rev-parse -q --verify "refs/heads/$2" > /dev/null || echo "prune-merged $1: $2 is still there"
    [ -z "${3:-}" ] || [ ! -e "$3" ] || echo "prune-merged $1: worktree $3 is still there"
}
kept() {
    git -C "$clone" rev-parse -q --verify "refs/heads/$2" > /dev/null || echo "prune-merged $1: $2 was deleted"
    [ -z "${3:-}" ] || [ -d "$3" ] || echo "prune-merged $1: worktree $3 was removed"
}
remote_refs() { git -C "$fake/origin.git" for-each-ref --format='%(refname) %(objectname)'; }

# --apply refuses once origin/main has moved past the sha it was given,
# and removes nothing.
git -C "$fake/origin.git" branch -q later-work main
branch moved && land moved
out=$(run --apply "$tip")
rc=$?
[ "$rc" = 1 ] || echo "prune-merged --apply, origin/main moved: exit $rc, expected 1"
has refusal "not $tip: nothing removed"
kept refusal merged-plain
kept refusal merged-wt "$wt_plain"
kept refusal moved

# --apply at the new tip removes exactly what the listing shows, branches
# in origin/main but not in the main clone's HEAD included, and leaves
# every remote branch as it was.
tip=$(git -C "$clone" rev-parse --short origin/main)
before=$(remote_refs)
out=$(run --apply "$tip")
rc=$?
[ "$rc" = 0 ] || { echo "prune-merged --apply: exit $rc, expected 0"; echo "$out" | sed 's/^/  /'; }
gone apply merged-plain
gone apply merged-wt "$wt_plain"
gone apply merged-harness "$wt_harness"
gone apply moved
gone apply merged-mux "$fake/iris-7"
gone apply merged-harness-locked "$wt_harness_locked"
kept apply merged-claude-lock-outside "$fake/iris-9"
kept apply merged-harness-dirty "$wt_harness_dirty"
git -C "$clone" worktree list --porcelain | grep -qx "locked claude agent agent-4 (pid 999999 start 1)" || echo "prune-merged --apply: unlocked merged-harness-dirty's worktree"
kept apply unmerged
kept apply main
kept apply merged-dirty "$fake/iris-2"
kept apply merged-untracked "$fake/iris-3"
kept apply merged-busy "$fake/iris-4"
kept apply merged-ssh "$fake/iris-8"
kept apply fresh "$clone/.claude/worktrees/agent-2"
kept apply merged-locked "$fake/iris-5"
kept apply merged-missing
[ "$(remote_refs)" = "$before" ] || echo "prune-merged --apply: changed origin's branches"
git -C "$clone" fetch -q origin
[ -n "$(git -C "$clone" branch -r --list origin/later-work)" ] || echo "prune-merged --apply: origin/later-work is gone"

# A main clone with a spec's integration branch checked out, already in
# origin/main: skipped as checked out, not removed, and main is still
# skipped as main.
git -C "$clone" switch -q -c spec-branch origin/main
land spec-branch
tip=$(git -C "$clone" rev-parse --short origin/main)
out=$(run)
has checked-out '^  spec-branch: checked out in the main clone$'
has main-again '^  main: main itself$'
out=$(run --apply "$tip")
rc=$?
[ "$rc" = 0 ] || { echo "prune-merged --apply, spec branch checked out: exit $rc, expected 0"; echo "$out" | sed 's/^/  /'; }
has nothing-left '^Nothing to remove\.$'
kept checked-out spec-branch

# --repo <path> works on another repo's main clone, as the fork's beside
# this one (#179's retro): that clone's own origin/main, its checked-out
# branch skipped even when it isn't main, and an --apply line that names
# the clone, quoted so a path with a space stays one argument, and which
# runs as printed. Nothing in the clone it runs from is touched.
fork="$fake/fork clone/OpenComposer"
git init -q -b main "$fake/fork-src"
echo f > "$fake/fork-src/f"
git -C "$fake/fork-src" add -A && git -C "$fake/fork-src" commit -qm "F"
git clone -q --bare "$fake/fork-src" "$fake/fork-origin.git"
git clone -q "$fake/fork-origin.git" "$fork"
git -C "$fork" switch -q -c iris-fork
git -C "$fork" commit -q --allow-empty -m "iris-fork"
git -C "$fork" push -q origin iris-fork:main
git -C "$fork" worktree add -q -b fork-merged "$fake/OpenComposer-1" origin/main
git -C "$fake/OpenComposer-1" commit -q --allow-empty -m "fork-merged"
git -C "$fork" push -q origin fork-merged:main fork-merged
git -C "$fork" worktree add -q -b fork-unmerged "$fake/OpenComposer-2" origin/main
git -C "$fake/OpenComposer-2" commit -q --allow-empty -m "fork-unmerged"
git -C "$fork" fetch -q origin
fork_tip=$(git -C "$fork" rev-parse --short origin/main)
iris_branches=$(git -C "$clone" for-each-ref refs/heads)
out=$(run --repo "$fork")
rc=$?
[ "$rc" = 0 ] || echo "prune-merged --repo: bare run exited $rc"
has repo-tip "^origin/main is at $fork_tip fork-merged$"
has repo-worktree "^  fork-merged  \(worktree $fake/OpenComposer-1\)$"
has repo-checked-out '^  iris-fork: checked out in the main clone$'
has repo-main '^  main: main itself$'
lacks repo-unmerged 'fork-unmerged'
lacks repo-other-clone 'spec-branch'
last=$(tail -n1 <<< "$out")
[ "$last" = "To remove them: bin/prune-merged --repo $(printf %q "$fork") --apply $fork_tip" ] || echo "prune-merged --repo: last line is '$last'"
# The other clone's origin/main doesn't pass for this one's.
out=$(run --repo "$fork" --apply "$tip")
[ $? = 1 ] || echo "prune-merged --repo --apply, iris's sha: expected exit 1"
grep -qF "Run bin/prune-merged --repo $(printf %q "$fork") again" <<< "$out" || { echo "prune-merged --repo --apply, iris's sha: no quoted line to list again"; echo "$out" | sed 's/^/  /'; }
fork_remote=$(git -C "$fake/fork-origin.git" for-each-ref --format='%(refname) %(objectname)')
out=$(cd "$clone" && eval "${last#To remove them: }" 2>&1)
rc=$?
[ "$rc" = 0 ] || { echo "prune-merged --repo --apply: exit $rc, expected 0"; echo "$out" | sed 's/^/  /'; }
git -C "$fork" rev-parse -q --verify refs/heads/fork-merged > /dev/null && echo "prune-merged --repo --apply: fork-merged is still there"
[ ! -e "$fake/OpenComposer-1" ] || echo "prune-merged --repo --apply: worktree $fake/OpenComposer-1 is still there"
for b in iris-fork main fork-unmerged; do
    git -C "$fork" rev-parse -q --verify "refs/heads/$b" > /dev/null || echo "prune-merged --repo --apply: $b was deleted"
done
[ "$(git -C "$fake/fork-origin.git" for-each-ref --format='%(refname) %(objectname)')" = "$fork_remote" ] || echo "prune-merged --repo --apply: changed the fork origin's branches"
[ "$(git -C "$clone" for-each-ref refs/heads)" = "$iris_branches" ] || echo "prune-merged --repo --apply: changed the clone it ran from"

# A main clone whose checked-out copy is behind origin/main's, as after a
# push <sha>:main that changes this script, runs origin/main's copy on the
# clone, whatever branch it has checked out (spec-branch here), and leaves
# no copy behind (#223's retro). A copy ahead of origin/main's, committed
# on a branch or edited in place, runs as it is.
newer="$fake/iris-newer"
git -C "$clone" worktree add -q -b newer-copy "$newer" origin/main
sed -i '1a echo "newer copy ran"' "$newer/bin/prune-merged"
git -C "$newer" commit -qam "newer copy" && land newer-copy
mkdir "$fake/tmp"
out=$(TMPDIR="$fake/tmp" run)
has newer-copy '^newer copy ran$'
has newer-notice "running origin/main's copy"
has newer-listing '^origin/main is at [0-9a-f]+ newer copy$'
has newer-checked-out '^  spec-branch: checked out in the main clone$'
[ -z "$(ls -A "$fake/tmp")" ] || echo "prune-merged, newer copy: left $(ls -A "$fake/tmp") in TMPDIR"
sed -i '1a echo "ahead copy ran"' "$newer/bin/prune-merged"
git -C "$newer" commit -qam "ahead copy"
out=$(cd "$newer" && bin/prune-merged 2>&1)
has ahead-copy '^ahead copy ran$'
lacks ahead-notice "running origin/main's copy"
sed -i '1a echo "edited copy ran"' "$clone/bin/prune-merged"
out=$(run)
has edited-copy '^edited copy ran$'
lacks edited-notice "running origin/main's copy"
git -C "$clone" checkout -q -- bin/prune-merged
