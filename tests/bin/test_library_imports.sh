#!/bin/bash
# bin/check's rule that lib/ imports nothing from workflows/ against
# throwaway trees. Prints each failed case and nothing on success, so
# bin/check can run it.
#
#   tests/bin/test_library_imports.sh
#
# bin/check name: library imports test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="lib/ imports nothing from workflows/"

# make_tree <name> <a library test's line>: a tree whose workflow has
# src/run.py and tests/test_synthetic.py.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active
    mkdir -p "$tree/lib/tests" "$tree/workflows/seg/src" "$tree/workflows/seg/tests"
    touch "$tree/workflows/seg/src/run.py" "$tree/workflows/seg/tests/test_synthetic.py"
    printf '%s\n' "$2" > "$tree/lib/tests/test_library.py"
    git -C "$tree" add -A
}

make_tree own-helper 'from datasets import make_volume'
expect pass "$scratch/own-helper" "$name"

make_tree prefix-of-a-module 'import test_synthetic_helpers'
expect pass "$scratch/prefix-of-a-module" "$name"

make_tree path-in-text 'WORKFLOW = "workflows/seg/src/run.py"'
expect pass "$scratch/path-in-text" "$name"

make_tree from-tests 'from test_synthetic import make_volume'
expect fail "$scratch/from-tests" "$name"

make_tree from-src '    import run'
expect fail "$scratch/from-src" "$name"
