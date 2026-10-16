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

{
  echo "IRIS Hello World"
  echo "User: $USER"
  echo "Date: $(date)"
  echo "Host: $(hostname)"
  echo "CPUs: $NCPUS"
  echo "Mem:  $MEM"
  echo "GPUs: $NGPUS"
  echo "Code: $CODE"
} > "$OUTDIR/result.txt"

echo "Done. Result at $OUTDIR/result.txt"
