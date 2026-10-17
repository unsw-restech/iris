#!/bin/bash
# Step 1 of a build: fetch every wheel into the version's wheelhouse.
#
# Run on the data mover, from this folder in a clone on Katana:
#   ssh katana-dm
#   cd <clone>/envs/imaging && ./download.sh <version>
#
# Uses requirements.lock if it exists, so a rebuild gets exactly the built
# versions. The first build of a version has no lock yet and resolves
# requirements.in; build.pbs then freezes the result into the lock.

set -euo pipefail

VERSION="${1:?usage: download.sh <version>}"
RECIPE="$(cd "$(dirname "$0")" && pwd)"
WHEELHOUSE="/srv/scratch/katana_ai/iris/wheelhouse/imaging/$VERSION"

if [ "$(hostname -s)" != "kdm" ]; then
    echo "Run this on the data mover (ssh katana-dm), not on $(hostname -s)."
    exit 1
fi

REQS="$RECIPE/requirements.lock"
[ -f "$REQS" ] || REQS="$RECIPE/requirements.in"

set +u
. /etc/profile.d/modules.sh
module load python/3.13.2
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
