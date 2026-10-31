#!/bin/bash
# bin/check's lab-section check against throwaway site trees. Each tree
# gets its own copy of bin/check, which checks the tree it sits in. Prints
# each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_lab_sections.sh
#
# bin/check name: lab-section test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# make_tree <name> [<flag>...]: a site in $scratch/<name> with two labs,
# ct-lab holding seg and mr-lab holding tumour, each page's breadcrumb
# linking its lab. Each flag breaks one part.
make_tree() {
    local tree="$scratch/$1" flag ct_open='<div class="lab" id="ct-lab">' tumour_lab=mr-lab outside="" after=""
    shift
    for flag in "$@"; do
        case "$flag" in
            no-id) ct_open='<div class="lab">' ;;
            wrong-crumb) tumour_lab=ct-lab ;;
            outside) outside='    <a href="workflows/seg/" class="workflow-card">Seg</a>' ;;
            after-last) after='    <a href="workflows/seg/" class="workflow-card">Seg</a>' ;;
        esac
    done
    mkdir -p "$tree/bin" "$tree/workflows/seg" "$tree/workflows/tumour"
    cp bin/check "$tree/bin/check"
    printf '%s\n' '<section id="workflows">' "$outside" "  $ct_open" \
        '    <a href="workflows/seg/" class="workflow-card">Seg</a>' '  </div>' \
        '  <div class="lab" id="mr-lab">' \
        '    <a href="workflows/tumour/" class="workflow-card planned">Tumour</a>' '  </div>' \
        "$after" '</section>' > "$tree/index.html"
    echo '<div class="breadcrumb"><a href="../../">IRIS</a> / <a href="../../#ct-lab">CT</a> / Seg</div>' \
        > "$tree/workflows/seg/index.html"
    echo "<div class=\"breadcrumb\"><a href=\"../../\">IRIS</a> / <a href=\"../../#$tumour_lab\">MR</a> / Tumour</div>" \
        > "$tree/workflows/tumour/index.html"
    [[ " $* " != *" no-page "* ]] || rm "$tree/workflows/tumour/index.html"
}

# labs <pass|fail> <name> [<flag>...]: the check over a tree built with
# those flags.
labs() {
    local want="$1" name="$2"
    shift 2
    make_tree "$name" "$@"
    expect "$want" "$scratch/$name" "cards sit in a lab section"
}

labs pass grouped
labs fail no-id no-id
labs fail wrong-crumb wrong-crumb
labs fail outside outside
labs fail after-last after-last
labs fail no-page no-page
