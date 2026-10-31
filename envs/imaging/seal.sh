#!/bin/bash
# Step 4 of a build: make the environment read-only for everyone.
#
# Run on the data mover once both smoke tests have passed:
#   ssh katana-dm
#   cd <clone>/envs/imaging && ./seal.sh <version>

set -euo pipefail

VERSION="${1:?usage: seal.sh <version>}"
. "$(cd "$(dirname "$0")" && pwd)/../../lib/katana.sh"
ENV_DIR="${IRIS_ENV_DIR%/*}/$VERSION"

if [ "$(hostname -s)" != "kdm" ]; then
    echo "Run this on the data mover (ssh katana-dm), not on $(hostname -s)."
    exit 1
fi
[ -f "$ENV_DIR/build-info.txt" ] || { echo "$ENV_DIR has no build-info.txt; build.pbs did not finish."; exit 1; }

chmod -R a+rX,a-w "$ENV_DIR"
echo "Sealed $ENV_DIR"
