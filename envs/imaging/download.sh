#!/bin/bash
# Step 1 of a build: fetch every wheel into the version's wheelhouse.
#
# Run on the data mover, from this folder in a clone on Katana:
#   ssh katana-dm
#   cd <clone>/envs/imaging && ./download.sh <version>
#
# Uses imaging/1's lock, which is now microct/1's (../microct/1/), so a
# rebuild gets exactly the built versions. It downloads for the clone's
# lib/katana.sh's Python module; for another, run it as
# PYTHON_MODULE=<module> ./download.sh <version>.

set -euo pipefail

VERSION="${1:?usage: download.sh <version>}"
RECIPE="$(cd "$(dirname "$0")" && pwd)"
. "$RECIPE/../../lib/katana.sh"
WHEELHOUSE="/srv/scratch/katana_ai/iris/wheelhouse/imaging/$VERSION"

if [ "$(hostname -s)" != "kdm" ]; then
    echo "Run this on the data mover (ssh katana-dm), not on $(hostname -s)."
    exit 1
fi

REQS="$RECIPE/../microct/1/requirements.lock"

set +u
. /etc/profile.d/modules.sh
module load "${PYTHON_MODULE:-$IRIS_PYTHON_MODULE}"
set -u

# pip stages every download in TMPDIR, and the data mover's /tmp (4 GB) is
# smaller than the wheels. Keep its cache out of the 10 GB home too.
mkdir -p "$WHEELHOUSE" "$WHEELHOUSE.tmp"
trap 'rm -rf "$WHEELHOUSE.tmp"' EXIT
export TMPDIR="$WHEELHOUSE.tmp" PIP_NO_CACHE_DIR=1

echo "From       : $REQS"
echo "Wheelhouse : $WHEELHOUSE"
python3 -m pip download \
    --only-binary=:all: \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    --dest "$WHEELHOUSE" \
    -r "$REQS"
echo "$(ls "$WHEELHOUSE" | wc -l) wheels, $(du -sh "$WHEELHOUSE" | cut -f1)"
