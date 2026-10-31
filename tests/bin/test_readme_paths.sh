#!/bin/bash
# bin/check's "README repo map names real paths" check against throwaway
# site trees. Prints each failed case and nothing on success, so bin/check
# can run it.
#
#   tests/bin/test_readme_paths.sh
#
# bin/check name: README paths test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="README repo map names real paths"

site_tree "$scratch/clean" seg:ct-lab:active
expect pass "$scratch/clean" "$name"

site_tree "$scratch/missing-path" seg:ct-lab:active
echo '| `envs/imaging/` | The software |' >> "$scratch/missing-path/README.md"
expect fail "$scratch/missing-path" "$name"

# <workflow> stands for any workflow folder, so it names nothing in a tree
# with none.
site_tree "$scratch/no-workflow-folder" seg:ct-lab:active
rm -r "$scratch/no-workflow-folder/workflows"
expect fail "$scratch/no-workflow-folder" "$name"
