#!/bin/bash
# bin/check's stale-account rule against throwaway site trees. Each tree
# gets its own copy of bin/check, which checks the tree it sits in. The
# rule fails any mention of the stale patricktung-unsw account or the old
# ares-pages repo, except a digest map line in lib/katana.sh, or a
# workflow's library copy of it, naming that account's own container,
# which a workflow author's pull request pins until the review batch
# copies it (#201). Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_stale_account.sh
#
# bin/check name: stale account test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="stale account or old repo"
hex=$(printf 'c%.0s' {1..64})

# case <pass|fail> <name> <file> <line>: the rule over a site tree whose
# <file> holds <line>; a failure must name <file>.
case_() {
    local want="$1" tree="$scratch/$2" out
    site_tree "$tree" seg:ct-lab:active
    mkdir -p "$(dirname "$tree/$3")"
    printf '%s\n' "$4" >> "$tree/$3"
    out="$(expect "$want" "$tree" "$name")"
    [ -z "$out" ] || { echo "$out"; return; }
    [ "$want" = fail ] || return 0
    out="$("$tree/bin/check" "$name" 2>&1)"
    grep -qF -- "./$3:" <<< "$out" || { echo "$2: doesn't name $3"; echo "$out" | sed 's/^/  /'; }
}

case_ pass author-pin lib/katana.sh "    [ct/2]=ghcr.io/patricktung-unsw/iris-env@sha256:$hex"
# A workflow's library copy of lib/katana.sh carries the same line.
case_ pass author-pin-copy workflows/seg/lib/katana.sh "    [ct/2]=ghcr.io/patricktung-unsw/iris-env@sha256:$hex"
case_ fail page workflows/seg/index.html '<a href="https://github.com/patricktung-unsw/iris">'
case_ fail old-repo README.md 'https://github.com/unsw-restech/ares-pages'
# The exemption is the digest map line alone: in another file, with a
# short digest, another package or anything after it, the line still fails.
case_ fail pin-elsewhere bin/notes.sh "    [ct/2]=ghcr.io/patricktung-unsw/iris-env@sha256:$hex"
case_ fail pin-elsewhere-in-workflow workflows/seg/katana.sh "    [ct/2]=ghcr.io/patricktung-unsw/iris-env@sha256:$hex"
case_ fail short-digest lib/katana.sh "    [ct/2]=ghcr.io/patricktung-unsw/iris-env@sha256:abc"
case_ fail other-package lib/katana.sh "    [ct/2]=ghcr.io/patricktung-unsw/other@sha256:$hex"
case_ fail comment-after lib/katana.sh "    [ct/2]=ghcr.io/patricktung-unsw/iris-env@sha256:$hex  # see patricktung-unsw"
case_ fail comment lib/katana.sh "# patricktung-unsw's container"
