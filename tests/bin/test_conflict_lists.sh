#!/bin/bash
# bin/check's conflict-list check against throwaway histories in a scratch
# repo, which IRIS_CHECK_REPO points it at. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_conflict_lists.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# expect <pass|fail> <name> <message>: the check over a fresh repo whose
# second commit has <message>, kept verbatim as git commit --no-edit does.
expect() {
    local repo="$scratch/$2" out rc
    git init -q "$repo"
    git -C "$repo" config user.name Test
    git -C "$repo" config user.email test@example.com
    git -C "$repo" commit -q --allow-empty -m "Add the first page"
    git -C "$repo" commit -q --allow-empty --cleanup=verbatim -m "$3"
    out="$(IRIS_CHECK_REPO="$repo" bin/check "conflict list" 2>&1)"
    rc=$?
    if [ "$1" = pass ] && [ "$rc" != 0 ]; then
        echo "$2: failed, expected a pass"
    elif [ "$1" = fail ] && { [ "$rc" != 1 ] || ! grep -q "^FAIL: git's conflict list" <<< "$out"; }; then
        echo "$2: passed (exit $rc), expected a failure"
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
