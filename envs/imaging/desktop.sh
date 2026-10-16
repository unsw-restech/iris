#!/bin/bash
# Build the desktop CPU venv for the synthetic-dataset test.
#
# Usage: envs/imaging/desktop.sh [requirements file] [venv dir]
#   defaults: requirements.lock, ~/.venvs/iris-imaging-<VERSION>
#
# Same packages as the Katana environment, from the same lock, with CPU
# PyTorch swapped in: the torch line becomes +cpu and the CUDA-only
# packages (nvidia-*, triton) are dropped. Needs Python 3.13.2, found
# through uv if PYTHON is not set (`uv python install 3.13.2`).

set -euo pipefail

VERSION=1
RECIPE="$(cd "$(dirname "$0")" && pwd)"
REQS="${1:-$RECIPE/requirements.lock}"
VENV="${2:-$HOME/.venvs/iris-imaging-$VERSION}"
PYTHON="${PYTHON:-$(uv python find 3.13.2)}"

[ -f "$REQS" ] || { echo "No $REQS. Build the Katana environment first, or pass requirements.in."; exit 1; }

CPU_REQS="$(mktemp)"
trap 'rm -f "$CPU_REQS"' EXIT
sed -E -e '/^(nvidia-|triton==)/d' -e 's/^(torch==[^+ ]+)\+cu[0-9]+/\1+cpu/' "$REQS" > "$CPU_REQS"

echo "Python : $("$PYTHON" --version) ($PYTHON)"
echo "From   : $REQS"
echo "Venv   : $VENV"

"$PYTHON" -m venv "$VENV"
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -r "$CPU_REQS"

"$VENV/bin/python" "$RECIPE/check_imports.py" "$CPU_REQS"
