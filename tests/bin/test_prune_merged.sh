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
sleeper=
trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; rm -rf "$fake"' EXIT
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
        git -C "$clone" commit-tree -m "$1" -p "$1" "$1^{tree}" | xargs git -C "$clone" update-ref "refs/heads/$1"
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
(cd "$fake/iris-4" && exec sleep 300) &
sleeper=$!
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
has plain '^  merged-plain$'
has worktree "^  merged-wt  \(worktree $wt_plain\)$"
has harness "^  merged-harness  \(worktree $wt_harness\)$"
lacks unmerged 'unmerged'
has main '^  main: main itself, checked out in the main clone$'
has dirty "^  merged-dirty  \(worktree $fake/iris-2\): uncommitted or untracked files$"
has untracked "^  merged-untracked  \(worktree $fake/iris-3\): uncommitted or untracked files$"
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
kept apply unmerged
kept apply main
kept apply merged-dirty "$fake/iris-2"
kept apply merged-untracked "$fake/iris-3"
kept apply merged-busy "$fake/iris-4"
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
run --apply "$tip" > /dev/null
kept checked-out spec-branch
