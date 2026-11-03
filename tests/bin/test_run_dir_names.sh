#!/bin/bash
# bin/check's rule that run directory file names come from iris.rundir
# against throwaway trees. Prints each failed case and nothing on success,
# so bin/check can run it.
#
#   tests/bin/test_run_dir_names.sh
#
# bin/check name: run directory names test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="run directory file names come from iris.rundir"

# make_tree <name> <file> <a line of it>: a tree whose iris.rundir names
# labels.tif and a folder, with <line> in <file>.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree"
    mkdir -p "$tree/lib/iris" "$tree/workflows/seg/src" "$tree/workflows/seg/tests"
    printf '%s\n' 'RUNS = "runs"' 'LABELS = "labels.tif"  # the label volume' > "$tree/lib/iris/rundir.py"
    printf '%s\n' "$3" > "$tree/$2"
    git -C "$tree" add -A
}

make_tree constant workflows/seg/src/run.py 'print(run_dir / rundir.LABELS)'
expect pass "$scratch/constant" "$name"

make_tree in-prose lib/iris/record.py '"""labels.tif is the label volume."""'
expect pass "$scratch/in-prose" "$name"

make_tree in-a-test workflows/seg/tests/test_run.py 'print("labels.tif")'
expect pass "$scratch/in-a-test" "$name"

make_tree quoted workflows/seg/src/run.py "print(run_dir / 'labels.tif')"
expect fail "$scratch/quoted" "$name"

make_tree path-end lib/iris/view.py 'print(run + "/labels.tif")'
expect fail "$scratch/path-end" "$name"
