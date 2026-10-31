#!/bin/bash
# bin/check's "card status matches the CONTRIBUTING tier table" check
# against throwaway site trees. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_card_status.sh
#
# bin/check name: card status test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="card status matches the CONTRIBUTING tier table"
workflows=(seg:ct-lab:active denoise:ct-lab:testing tumour:mr-lab:planned old:mr-lab:unmaintained)

site_tree "$scratch/clean" "${workflows[@]}"
expect pass "$scratch/clean" "$name"

# The card reads Active, but the tier table puts seg in Planned.
site_tree "$scratch/disagrees" "${workflows[@]}"
sed -i '/^| \*\*Run and verified\*\*/d; s/`tumour`/`seg`, `tumour`/' "$scratch/disagrees/CONTRIBUTING.md"
expect fail "$scratch/disagrees" "$name"

site_tree "$scratch/wrong-label" "${workflows[@]}"
sed -i 's|</span> Testing</span>|</span> Active</span>|' "$scratch/wrong-label/index.html"
expect fail "$scratch/wrong-label" "$name"

site_tree "$scratch/no-row" "${workflows[@]}"
sed -i '/^| \*\*Run, browser run pending\*\*/d' "$scratch/no-row/CONTRIBUTING.md"
expect fail "$scratch/no-row" "$name"

site_tree "$scratch/unknown-tier" "${workflows[@]}"
sed -i 's/^| \*\*Planned\*\*/| **Someday**/' "$scratch/unknown-tier/CONTRIBUTING.md"
expect fail "$scratch/unknown-tier" "$name"

site_tree "$scratch/crlf" "${workflows[@]}"
sed -i 's/$/\r/' "$scratch/crlf/index.html" "$scratch/crlf/CONTRIBUTING.md"
expect pass "$scratch/crlf" "$name"
