#!/bin/bash
# bin/check's AI-attribution check against throwaway histories in a
# scratch repo, which IRIS_CHECK_REPO points it at, and .githooks/commit-msg
# against the same messages, so the two agree. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_attribution.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# A fresh repo in $scratch/<name> with one clean commit, then one commit
# whose message is $2, if given.
make_history() {
    local repo="$scratch/$1"
    git init -q "$repo"
    git -C "$repo" config user.name Test
    git -C "$repo" config user.email test@example.com
    git -C "$repo" commit -q --allow-empty -m "Add the first page"
    [ -z "$2" ] || git -C "$repo" commit -q --allow-empty -m "$2"
}

# report <pass|fail> <label> <exit status> <output>: prints <label> and
# <output> if the status disagrees with the verdict wanted.
report() {
    if [ "$1" = pass ] && [ "$3" != 0 ]; then
        echo "$2 failed on a clean message"
    elif [ "$1" = fail ] && [ "$3" != 1 ]; then
        echo "$2 passed (exit $3), expected a failure"
    else
        return 0
    fi
    echo "$4" | sed 's/^/  /'
}

# expect <pass|fail> <name> [<message>]: the check over a history built
# from <message>, and the hook over <message>.
expect() {
    local want="$1" name="$2" out rc
    make_history "$name" "$3"
    printf '%s\n' "$3" > "$scratch/$name.msg"
    out="$(.githooks/commit-msg "$scratch/$name.msg" 2>&1)"
    report "$want" "$name: hook" $? "$out"
    out="$(IRIS_CHECK_REPO="$scratch/$name" bin/check "AI attribution" 2>&1)"
    rc=$?
    [ "$want" = fail ] && [ "$rc" = 1 ] && ! grep -q '^FAIL: AI attribution' <<< "$out" && rc=0
    report "$want" "$name: check" "$rc" "$out"
}

expect pass clean
expect pass clean-body "Fix a typo

Reviewed by hand, with the session notes in the issue."
expect pass prose-mention "Check commit messages for attribution

The check fails on a co-author trailer, session link or \"Generated with\"
line in any commit."
expect pass quoted-at-line-start "Tidy the attribution check

The comment now says the phrase
\"Generated with\" passes mid-line."
expect pass backticked-at-line-start "Tidy the attribution check

The comment now says the phrase
\`Generated with\` passes mid-line."
expect fail co-author "Fix a typo

Co-authored-by: Some Agent <agent@example.com>"
expect fail co-author-human "Fix a typo

Co-authored-by: Jane Researcher <jane@example.com>"
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
expect fail generated-emoji "Fix a typo

🤖 Generated with [Some Tool](https://example.com)"

# git commit -v leaves its diff below the scissors line, which git cuts
# after the hook runs; a diff line must not count as the message.
printf '%s\n' "Tidy the attribution test" "" \
    "# ------------------------ >8 ------------------------" \
    "# Do not modify or remove the line above." \
    "+Generated with Some Tool" > "$scratch/verbose.msg"
out="$(.githooks/commit-msg "$scratch/verbose.msg" 2>&1)"
report pass "verbose: hook" $? "$out"
