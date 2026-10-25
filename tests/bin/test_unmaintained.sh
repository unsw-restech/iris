#!/bin/bash
# bin/check's unmaintained-workflow check against throwaway site trees,
# since no real workflow is unmaintained. Each tree gets its own copy of
# bin/check, which checks the tree it sits in. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_unmaintained.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# make_tree <name> [card] [run-button] [form-in-place]: a site in
# $scratch/<name> with one workflow, old-scan, demoted to Unmaintained.
# Each flag leaves that step of the demotion undone.
make_tree() {
    local tree="$scratch/$1" flag card="" run="" form=archive
    shift
    for flag in "$@"; do
        case "$flag" in
            card) card='    <a href="workflows/old-scan/" class="workflow-card">Old scan</a>' ;;
            run-button) run='  <a href="https://kod.restech.unsw.edu.au/pun/dev/OpenComposer/old-scan" class="run-btn" target="_blank">Run on Katana</a>' ;;
            form-in-place) form=workflows ;;
        esac
    done
    mkdir -p "$tree/bin" "$tree/workflows/old-scan" "$tree/workflows/live-scan" "$tree/$form/old-scan"
    cp bin/check "$tree/bin/check"
    printf '%s\n' '<div class="grid">' \
        '    <a href="workflows/live-scan/" class="workflow-card">Live scan</a>' \
        "$card" '</div>' > "$tree/index.html"
    printf '%s\n' '<div class="page">' \
        '  <div class="unmaintained-banner"><strong>Unmaintained.</strong> This workflow cannot be run.</div>' \
        "$run" '</div>' > "$tree/workflows/old-scan/index.html"
    printf '%s\n' '<div class="page">' \
        '  <a href="https://kod.restech.unsw.edu.au/pun/dev/OpenComposer/live-scan" class="run-btn">Run on Katana</a>' \
        '</div>' > "$tree/workflows/live-scan/index.html"
    echo 'title: Old scan' > "$tree/$form/old-scan/form.yml.erb"
    echo 'title: Live scan' > "$tree/workflows/live-scan/form.yml.erb"
}

# expect <pass|fail> <name> [<flag>...]: the check over a tree built with
# those flags; a failure must name the unmaintained check.
expect() {
    local want="$1" name="$2" out rc
    shift 2
    make_tree "$name" "$@"
    out="$("$scratch/$name/bin/check" "unmaintained workflows have" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "$name: failed on a whole demotion"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep -q "^FAIL: unmaintained workflows have" <<< "$out"; }; then
        echo "$name: passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

expect pass demoted
expect fail run-button run-button
expect fail card card
expect fail form-in-place form-in-place
