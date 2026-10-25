#!/bin/bash
# bin/check's unmaintained-workflow check against throwaway site trees,
# since no real workflow is unmaintained. Each tree gets its own copy of
# bin/check, which checks the tree it sits in. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_unmaintained.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
. tests/bin/lib.sh

# make_tree <name> [<flag>...]: a site in $scratch/<name> with two
# workflows: live-seg, in service, and old-seg, wholly demoted to
# Unmaintained. Each flag leaves one step of the demotion undone.
make_tree() {
    local tree="$scratch/$1" flag card="" run="" form=archive
    shift
    for flag in "$@"; do
        case "$flag" in
            card) card='    <a href="workflows/old-seg/" class="workflow-card">Old seg</a>' ;;
            run-button) run='  <a href="https://kod.restech.unsw.edu.au/pun/dev/OpenComposer/old-seg" class="run-btn" target="_blank">Run on Katana</a>' ;;
            form-in-place) form=workflows ;;
        esac
    done
    mkdir -p "$tree/bin" "$tree/workflows/old-seg" "$tree/workflows/live-seg" "$tree/$form/old-seg"
    cp bin/check "$tree/bin/check"
    printf '%s\n' '| Tier | Workflows | What exists |' '|---|---|---|' \
        '| **Run and verified** | `live-seg` (microCT) | Page, form, job script |' \
        '| **Unmaintained** | `old-seg` (microCT) | Page only, with the banner |' > "$tree/CONTRIBUTING.md"
    printf '%s\n' '<div class="grid">' \
        '    <a href="workflows/live-seg/" class="workflow-card">Live seg</a>' \
        "$card" '</div>' > "$tree/index.html"
    printf '%s\n' '<div class="page">' \
        '  <div class="unmaintained-banner"><strong>Unmaintained.</strong> This workflow cannot be run.</div>' \
        "$run" '</div>' > "$tree/workflows/old-seg/index.html"
    printf '%s\n' '<div class="page">' \
        '  <a href="https://kod.restech.unsw.edu.au/pun/dev/OpenComposer/live-seg" class="run-btn">Run on Katana</a>' \
        '</div>' > "$tree/workflows/live-seg/index.html"
    echo 'title: Old seg' > "$tree/$form/old-seg/form.yml.erb"
    echo 'title: Live seg' > "$tree/workflows/live-seg/form.yml.erb"
}

# demotion <pass|fail> <name> [<flag>...]: the check over a tree built
# with those flags.
demotion() {
    local want="$1" name="$2"
    shift 2
    make_tree "$name" "$@"
    expect "$want" "$name" "unmaintained workflows have"
}

demotion pass demoted
demotion fail run-button run-button
demotion fail card card
demotion fail form-in-place form-in-place
