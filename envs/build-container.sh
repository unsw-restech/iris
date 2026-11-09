#!/bin/bash
# Build one environment version's container with Docker, as CI does
# (.github/workflows/containers.yml). Never on Katana: an Apptainer build
# fails there (ADR-0008).
#
#   envs/build-container.sh <env>/<n> <local name>
#
# <env>/1 builds from envs/<env>/1/Dockerfile. A later version builds from
# envs/next.Dockerfile on top of the version before it, pulled by the
# digest lib/katana.sh's digest map gives it, so that version must be
# published first. The context is envs/<env>/<n>/, which holds its lock.

set -euo pipefail

VERSION="${1:?usage: envs/build-container.sh <env>/<n> <local name>}"
NAME="${2:?usage: envs/build-container.sh <env>/<n> <local name>}"
cd "$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=lib/katana.sh
. lib/katana.sh

iris_is_env_version "$VERSION" && [ -n "${IRIS_ENV_DIGESTS[$VERSION]+x}" ] ||
    { echo "$VERSION is not a version in lib/katana.sh's digest map"; exit 1; }
n="${VERSION##*/}"
args=(--provenance=false --load -t "$NAME"
    --build-arg "VERSION=$VERSION" --build-arg "COMMIT=$(git rev-parse HEAD)")

if [ "$n" = 1 ]; then
    docker buildx build "${args[@]}" -f "envs/$VERSION/Dockerfile" "envs/$VERSION"
else
    previous="$(iris_env_ref "${VERSION%/*}/$((n - 1))")" ||
        { echo "Publish ${VERSION%/*}/$((n - 1)) and put its digest in lib/katana.sh before building $VERSION."; exit 1; }
    docker buildx build "${args[@]}" --build-arg "PREVIOUS=$previous" -f envs/next.Dockerfile "envs/$VERSION"
fi
