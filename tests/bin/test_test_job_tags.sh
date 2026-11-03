#!/bin/bash
# bin/check's usage-tag rule for the library's test jobs against throwaway
# trees. Prints each failed case and nothing on success, so bin/check can
# run it.
#
#   tests/bin/test_test_job_tags.sh
#
# bin/check name: test-job tag test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="library test jobs use the iris-tests usage tag"

# make_tree <name> <job's tag line>
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree"
    mkdir -p "$tree/lib/tests/katana"
    printf '%s\n' '#!/bin/bash' "$2" 'echo ok' > "$tree/lib/tests/katana/job.pbs"
}

make_tree tagged '#PBS -A iris-tests'
expect pass "$scratch/tagged" "$name"

make_tree workflow-tag '#PBS -A iris-microct-2d-segmentation'
expect fail "$scratch/workflow-tag" "$name"

make_tree no-tag '#PBS -N job'
expect fail "$scratch/no-tag" "$name"
