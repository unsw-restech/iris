#!/bin/bash
# bin/check's conflict-list check against throwaway histories in a scratch
# repo, which IRIS_CHECK_REPO points it at, and .githooks/commit-msg on real
# conflicted merges. Prints each failed case and nothing on success, so
# bin/check can run it.
#
#   tests/bin/test_conflict_lists.sh
#
# bin/check name: conflict-list test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# expect <pass|fail> <name> <message>: the check over a fresh repo whose
# second commit has <message>, kept verbatim as git commit --no-edit does.
expect() {
    local want="$1" name="$2" repo="$scratch/$2" out rc
    git init -q "$repo"
    git -C "$repo" config user.name Test
    git -C "$repo" config user.email test@example.com
    git -C "$repo" commit -q --allow-empty -m "Add the first page"
    git -C "$repo" commit -q --allow-empty --cleanup=verbatim -m "$3"
    out="$(IRIS_CHECK_REPO="$repo" bin/check "conflict list" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "$name: failed, expected a pass"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep -q "^FAIL: git's conflict list" <<< "$out"; }; then
        echo "$name: passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

expect pass clean-merge "Merge #73: CONTRIBUTING works for outside workflow authors"
expect pass prose-mention "Check merge messages

A message keeping git's # Conflicts: list fails bin/check."
expect fail no-edit-merge "Merge branch '58-t72' into 58-citable-workflows

# Conflicts:
#	CONTRIBUTING.md"

# conflicted_repo <name>: a repo in $scratch/<name> using the hook, stopped in a
# conflicted merge of its branch other.
conflicted_repo() {
    local repo="$scratch/$1"
    git init -q -b main "$repo"
    git -C "$repo" config user.name Test
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config core.hooksPath "$PWD/.githooks"
    echo one > "$repo/page"
    git -C "$repo" add page
    git -C "$repo" commit -q -m "Add the page"
    git -C "$repo" checkout -q -b other
    echo two > "$repo/page"
    git -C "$repo" commit -q -am "Change the page"
    git -C "$repo" checkout -q main
    echo three > "$repo/page"
    git -C "$repo" commit -q -am "Change the page differently"
    git -C "$repo" merge -q other > /dev/null 2>&1
    echo merged > "$repo/page"
    git -C "$repo" add page
}

# A --no-edit commit keeps the list, so the hook refuses it; the merge is
# still open for a commit -m, which passes.
conflicted_repo no-edit-hook
git -C "$scratch/no-edit-hook" commit -q --no-edit > /dev/null 2>&1 &&
    echo "hook: passed a --no-edit commit of a conflicted merge"
git -C "$scratch/no-edit-hook" commit -q -m "Merge other" > /dev/null 2>&1 ||
    echo "hook: refused a conflicted merge's commit -m"

# An editor session passes, since git's cleanup removes the list.
conflicted_repo editor-hook
GIT_EDITOR=true git -C "$scratch/editor-hook" commit -q > /dev/null 2>&1 ||
    echo "hook: refused a conflicted merge finished in an editor"
! git -C "$scratch/editor-hook" log -1 --format=%B | grep -q '^# Conflicts:' ||
    echo "hook: an editor session kept the conflict list"

# With no terminal, a cherry-pick's --continue strips the list with no
# editor, so it passes.
conflicted_repo cherry-pick-hook
git -C "$scratch/cherry-pick-hook" merge --abort
git -C "$scratch/cherry-pick-hook" cherry-pick other > /dev/null 2>&1
echo picked > "$scratch/cherry-pick-hook/page"
git -C "$scratch/cherry-pick-hook" add page
git -C "$scratch/cherry-pick-hook" cherry-pick --continue < /dev/null > /dev/null 2>&1 ||
    echo "hook: refused a cherry-pick's --continue"
