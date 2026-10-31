#!/bin/bash
# bin/check's unmaintained-workflow check against throwaway site trees,
# since no real workflow is unmaintained. Each tree gets its own copy of
# bin/check, which checks the tree it sits in. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_unmaintained.sh
#
# bin/check name: unmaintained-workflow test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

run_button() {
    echo "  <a href=\"https://kod.restech.unsw.edu.au/pun/dev/OpenComposer/$1\" class=\"run-btn\" target=\"_blank\">Run on Katana</a>"
}

# make_tree <name> [<flag>...]: a site in $scratch/<name> with two
# workflows: live-seg, in service, and old-seg, wholly demoted to
# Unmaintained. Each flag leaves one step of the demotion undone.
make_tree() {
    local tree="$scratch/$1" flag form=_archive
    shift
    site_tree "$tree" live-seg:ct-lab:active old-seg:ct-lab:unmaintained
    run_button live-seg >> "$tree/workflows/live-seg/index.html"
    echo 'title: Live seg' > "$tree/workflows/live-seg/form.yml.erb"
    mkdir -p "$tree/.github"
    echo '/workflows/live-seg/ @jdoe' > "$tree/.github/CODEOWNERS"
    for flag in "$@"; do
        case "$flag" in
            tier-row) sed -i '/^| \*\*Unmaintained\*\*/d' "$tree/CONTRIBUTING.md" ;;
            codeowners-line) echo '/workflows/old-seg/ @jdoe' >> "$tree/.github/CODEOWNERS" ;;
            banner) sed -i '/unmaintained-banner/d' "$tree/workflows/old-seg/index.html" ;;
            card) sed -i '/^  <\/div>/i\    <a href="workflows/old-seg/" class="workflow-card">Old seg</a>' "$tree/index.html" ;;
            run-button) run_button old-seg >> "$tree/workflows/old-seg/index.html" ;;
            form-in-place) form=workflows ;;
            page) rm "$tree/workflows/old-seg/index.html" ;;
        esac
    done
    mkdir -p "$tree/$form/old-seg"
    echo 'title: Old seg' > "$tree/$form/old-seg/form.yml.erb"
}

# demotion <pass|fail> <name> [<flag>...]: the check over a tree built
# with those flags.
demotion() {
    local want="$1" name="$2"
    shift 2
    make_tree "$name" "$@"
    expect "$want" "$scratch/$name" "unmaintained workflows have"
}

demotion pass demoted
demotion fail run-button run-button
demotion fail card card
demotion fail form-in-place form-in-place
demotion fail tier-row tier-row
demotion fail banner banner
demotion fail banner-and-run-button banner run-button
demotion fail page page
demotion fail codeowners-line codeowners-line
