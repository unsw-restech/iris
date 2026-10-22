#!/bin/bash
# IRIS Hello World: the code a hello-world job runs from its clone.
#
# Usage: hello_world.sh OUTDIR NCPUS MEM NGPUS

set -euo pipefail

OUTDIR="$1"
NCPUS="$2"
MEM="$3"
NGPUS="$4"
CODE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# One command, not a { } group: Katana's bash 4.4 ignores set -e when a
# group's redirection fails, so an unwritable OUTDIR would still say Done
# (job 9584925, checked on a login node 2026-10-22, #53).
printf '%s\n' \
  "IRIS Hello World" \
  "User: $USER" \
  "Date: $(date)" \
  "Host: $(hostname)" \
  "CPUs: $NCPUS" \
  "Mem:  $MEM" \
  "GPUs: $NGPUS" \
  "Code: $CODE" > "$OUTDIR/result.txt"

echo "Done. Result at $OUTDIR/result.txt"
