#!/bin/bash
# bin/check's AI-attribution check against throwaway histories in a
# scratch repo, which IRIS_CHECK_REPO points it at. Prints each failed
# case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_attribution.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# A fresh repo in $scratch/<name> with one clean commit, then one commit
# whose message is $2, if given.
history() {
    local repo="$scratch/$1"
    git init -q "$repo"
    git -C "$repo" -c user.name=Test -c user.email=test@example.com \
        commit -q --allow-empty -m "Add the first page"
    [ -z "$2" ] || git -C "$repo" -c user.name=Test -c user.email=test@example.com \
        commit -q --allow-empty -m "$2"
}

# expect <pass|fail> <name> [<message>]: the check over a history built
# from <message>.
expect() {
    local want="$1" name="$2" out rc
    history "$name" "$3"
    out="$(IRIS_CHECK_REPO="$scratch/$name" bin/check "AI attribution" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "$name: check failed on clean history"
        echo "$out" | sed 's/^/  /'
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep -q '^FAIL: AI attribution' <<< "$out"; }; then
        echo "$name: check passed (exit $rc), expected FAIL"
        echo "$out" | sed 's/^/  /'
    fi
}

expect pass clean
expect pass clean-body "Fix a typo

Reviewed by hand, with the session notes in the issue."
expect pass prose-mention "Check commit messages for attribution

The check fails on a co-author trailer, session link or \"Generated with\"
line in any commit."
expect fail co-author "Fix a typo

Co-authored-by: Some Agent <agent@example.com>"
expect fail co-author-lowercase "Fix a typo

co-authored-by: Another Bot <bot@example.com>"
expect fail session "Fix a typo

Agent-Session: https://example.com/s/123"
expect fail session-uppercase "Fix a typo

TOOL-SESSION: abc"
expect fail generated "Fix a typo

Generated with Some Tool"
expect fail generated-prefixed "Fix a typo

* generated with [Another Tool](https://example.com)"
