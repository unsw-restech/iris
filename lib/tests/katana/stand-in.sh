#!/bin/bash
# The stand-in container the job library's Katana test (job_lib.pbs) runs
# jobs in, so the test needs no published environment version: Docker
# Hub's python:3.13.2-bookworm, by digest alone, which has the git the
# code recorder runs. It is a test fixture only, never an IRIS environment,
# so it lives in the tester's own container cache, /srv/scratch/$USER/.envs
# (AGENTS.md), never in katana_ai.
#
# Sourced, it only sets IRIS_STAND_IN, the container file. Sent to the data
# mover with --pull, it pulls the file there unless it is already there,
# as bin/katana-test does before submitting the test:
#
#   ssh katana-dm 'bash -s -- --pull' < lib/tests/katana/stand-in.sh
#
# About 380 MB. Removing the file only means the next bin/katana-test
# pulls it again.
# shellcheck disable=SC2034  # IRIS_STAND_IN is for the scripts that source it

IRIS_STAND_IN_REF=docker://python@sha256:4165118ed569aff9dbd11d5518199e5379d93bf5bf1cdda62eb13593cf66fb68
IRIS_STAND_IN="/srv/scratch/$USER/.envs/iris-stand-in-python-3.13.2-bookworm.sif"

if [ "${1-}" = --pull ]; then
    [ -e "$IRIS_STAND_IN" ] && { echo "stand-in container: present, $IRIS_STAND_IN"; exit 0; }
    dir="${IRIS_STAND_IN%/*}" part="${IRIS_STAND_IN%/*}/.stand-in.sif.part" tmp="${IRIS_STAND_IN%/*}/.stand-in.tmp"
    mkdir -p "$tmp" || exit 1
    echo "stand-in container: pulling $IRIS_STAND_IN_REF into $dir"
    if ! APPTAINER_TMPDIR="$tmp" apptainer pull --disable-cache --force "$part" "$IRIS_STAND_IN_REF"; then
        rm -rf -- "$tmp" "$part"
        echo "stand-in container: the pull failed; nothing written." >&2
        exit 1
    fi
    rm -rf -- "$tmp"
    mv -- "$part" "$IRIS_STAND_IN" && echo "stand-in container: pulled, $IRIS_STAND_IN"
fi
