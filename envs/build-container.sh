#!/bin/bash
# Build one environment version's container with Docker, as CI does
# (.github/workflows/containers.yml). Never on Katana: an Apptainer build
# fails there (ADR-0008).
#
#   envs/build-container.sh <env>/<n> <local name>
#
# envs/build-kind.sh picks the recipe from the lock alone (ADR-0010). A
# version it calls a layer builds from envs/next.Dockerfile on top of the
# version before it, pulled by the digest lib/katana.sh's digest map gives
# it, so that version must be published first. One it calls fresh, a first
# version or one whose lock changes or removes a line of the one before it,
# builds from envs/<env>/1/Dockerfile and needs no other version; its note
# naming what it changes is printed first. The context is envs/<env>/<n>/,
# which holds its lock.

set -euo pipefail

VERSION="${1:?usage: envs/build-container.sh <env>/<n> <local name>}"
NAME="${2:?usage: envs/build-container.sh <env>/<n> <local name>}"
cd "$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=lib/katana.sh
. lib/katana.sh

iris_is_env_version "$VERSION" && [ -n "${IRIS_ENV_DIGESTS[$VERSION]+x}" ] ||
    { echo "$VERSION is not a version in lib/katana.sh's digest map"; exit 1; }
args=(--provenance=false --load -t "$NAME"
    --build-arg "VERSION=$VERSION" --build-arg "COMMIT=$(git rev-parse HEAD)")
recipe="$(envs/build-kind.sh "$VERSION")"
kind="$(head -n1 <<< "$recipe")"
note="$(sed -n 2p <<< "$recipe")"
[ -z "$note" ] || echo "NOTE: $note"
env="${VERSION%/*}"

if [ "$kind" = fresh ]; then
    echo "Building $VERSION fresh from envs/$env/1/Dockerfile."
    docker buildx build "${args[@]}" -f "envs/$env/1/Dockerfile" "envs/$VERSION"
else
    prev="$env/$((${VERSION##*/} - 1))"
    previous="$(iris_env_ref "$prev")" ||
        { echo "Publish $prev and put its digest in lib/katana.sh before building $VERSION as a layer on it."; exit 1; }
    echo "Building $VERSION as a layer on $previous."
    docker buildx build "${args[@]}" --build-arg "PREVIOUS=$previous" -f envs/next.Dockerfile "envs/$VERSION"
fi
