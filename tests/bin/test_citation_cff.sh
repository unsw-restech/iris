#!/bin/bash
# bin/check's "CITATION.cff and workflow pages list the same citable
# versions" check against throwaway trees, each with its own copy of
# bin/check. Prints each failed case and nothing on success, so bin/check
# can run it.
#
#   tests/bin/test_citation_cff.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# site <pass|fail> <name> <page DOIs> <CITATION.cff DOIs> [<in identifiers>
# [<in references>]]: the check over a tree in $scratch/<name> whose one
# workflow page lists the first set of DOIs (space-separated), and whose
# CITATION.cff identifies the second, with any extra lines at the end of
# its identifiers and references blocks.
site() {
    local dir="$scratch/$2" doi
    mkdir -p "$dir/bin" "$dir/workflows/some-workflow"
    cp bin/check "$dir/bin/check"
    {
        printf '%s\n' '<details id="cite">' '  <ul>'
        for doi in $3; do
            echo "    <li><a href=\"https://doi.org/$doi\">$doi</a> · 2026-11-02 · commit <code>d2c15b3</code></li>"
        done
        printf '%s\n' '  </ul>' '</details>'
    } > "$dir/workflows/some-workflow/index.html"
    {
        printf '%s\n' 'cff-version: 1.2.0' 'identifiers:' '  - type: url' '    value: "https://workflowhub.eu/projects/472"'
        for doi in $4; do
            printf '%s\n' '  - type: doi' "    value: $doi"
        done
        [ -z "$5" ] || printf '%s\n' "$5"
        printf '%s\n' 'references:' '  - type: generic' '    doi: 10.26190/669x-a286'
        [ -z "$6" ] || printf '%s\n' "$6"
    } > "$dir/CITATION.cff"
    expect "$1" "$dir" "CITATION.cff and workflow pages"
}

a=10.48546/workflowhub.workflow.1234.1
b=10.48546/workflowhub.workflow.1234.2

site pass none '' ''
site pass one "$a" "$a"
site pass two-any-order "$b $a" "$a $b"
site fail missing-from-cff "$b $a" "$a"
site fail missing-from-page "$a" "$b $a"
site fail cff-but-no-page '' "$a"
site fail only-in-a-comment "$a" '' "  # $a"
site fail only-in-references "$a" '' '' "  - type: generic
    doi: $a"
