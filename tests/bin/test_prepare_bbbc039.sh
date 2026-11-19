#!/bin/bash
# The BBBC039 preparation script,
# workflows/microscopy-cell-segmentation/dataset/prepare_bbbc039.py, through
# its test,
# workflows/microscopy-cell-segmentation/dataset/test_prepare_bbbc039.py, in
# the microct/1 environment the script runs in, on CPU with no network. It
# runs from here rather than the workflow's tests/ folder, whose tests
# bin/check runs in the version the workflow's form pins.
# Prints the test's output if it fails and nothing on success, so bin/check
# can run it.
#
#   tests/bin/test_prepare_bbbc039.sh
#
# bin/check name: BBBC039 preparation test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
folder=workflows/microscopy-cell-segmentation/dataset
out="$(cd "$folder" && ../../../bin/envrun --no-network --time-limit 120 microct/1 python -B -m unittest test_prepare_bbbc039 2>&1)" ||
    printf '%s\n' "$out"
