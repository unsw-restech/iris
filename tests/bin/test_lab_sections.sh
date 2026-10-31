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

card='    <a href="workflows/seg/" class="workflow-card">Seg</a>'

# labs <pass|fail> <name> [<sed script> <file>]: the check over a site with
# two labs, ct-lab holding seg and mr-lab holding tumour, with the sed
# script applied to <file>.
labs() {
    local want="$1" tree="$scratch/$2"
    site_tree "$tree" seg:ct-lab:active tumour:mr-lab:planned
    [ $# -lt 4 ] || sed -i "$3" "$tree/$4"
    expect "$want" "$tree" "cards sit in a lab section"
}

labs pass grouped
labs fail no-id 's/<div class="lab" id="ct-lab">/<div class="lab">/' index.html
labs fail wrong-crumb 's/#mr-lab/#ct-lab/' workflows/tumour/index.html
labs fail outside "/<section id=\"workflows\">/a\\$card" index.html
labs fail after-last "/<\\/section>/i\\$card" index.html

site_tree "$scratch/no-page" seg:ct-lab:active tumour:mr-lab:planned
rm "$scratch/no-page/workflows/tumour/index.html"
expect fail "$scratch/no-page" "cards sit in a lab section"
