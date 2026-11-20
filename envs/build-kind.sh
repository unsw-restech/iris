#!/bin/bash
# How an environment version is built, and from which recipe (ADR-0010):
#
#   envs/build-kind.sh <env>/<n>
#
# Prints "layer" when <env>/<n> carries no Dockerfile of its own and its
# lock keeps every line of the lock of the version before it, which
# envs/next.Dockerfile builds as one layer on that version. Any other
# version, a first one, one that carries its own Dockerfile or one whose
# lock changes or removes a line, is built fresh: it prints
# "fresh <Dockerfile>", naming the Dockerfile of the nearest version at or
# before it that has one, so a version's own is the file named Dockerfile
# beside its lock. A later version built fresh gets a second line, a note
# naming the packages it changes and removes and saying whether it carries
# its own Dockerfile, which envs/build-container.sh and bin/check print
# without failing. Exits 1, with one line, when a lock or Dockerfile it
# needs is missing. Lines compare with comments and surrounding spaces
# dropped, and a package by its normalised name.

set -euo pipefail

VERSION="${1:?usage: envs/build-kind.sh <env>/<n>}"
cd "$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=lib/katana.sh
. <(tr -d '\r' < lib/katana.sh)
iris_is_env_version "$VERSION" ||
    { echo "$VERSION is not <env>/<n>, with <n> counting from 1" >&2; exit 1; }
env="${VERSION%/*}"
n="${VERSION##*/}"
lock="envs/$VERSION/requirements.lock"
[ -f "$lock" ] || { echo "No $lock." >&2; exit 1; }

# fresh: the first line for a fresh build, naming the nearest Dockerfile.
fresh() {
    local i
    for ((i = n; i >= 1; i--)); do
        [ ! -f "envs/$env/$i/Dockerfile" ] || { echo "fresh envs/$env/$i/Dockerfile"; return; }
    done
    echo "No Dockerfile in envs/$env/1/ or a later version up to $VERSION." >&2
    exit 1
}

[ "$n" -gt 1 ] || { fresh; exit 0; }
prev="$env/$((n - 1))"
[ -f "envs/$prev/requirements.lock" ] || { echo "No envs/$prev/requirements.lock before $VERSION." >&2; exit 1; }

# What the lock changes and removes of the one before it, empty if nothing.
pins="$(tr -d '\r' < "envs/$prev/requirements.lock" | awk '
    function key(s) { s = tolower(s); sub(/[ =<>!~;@\[].*/, "", s); gsub(/[-_.]+/, "-", s); return s }
    function list(a, n,   i, s) { for (i = 1; i <= n; i++) s = s (i == 1 ? "" : i == n ? " and " : ", ") a[i]; return s }
    { sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    $0 == "" { next }
    FNR == NR { now[$0] = 1; by[key($0)] = $0; next }
    !($0 in now) {
        if (key($0) in by) changed[++nc] = $0 " to " by[key($0)]
        else removed[++nr] = $0
    }
    END {
        if (nc) s = "changes " list(changed, nc)
        if (nr) s = s (nc ? " and " : "") "removes " list(removed, nr)
        print s
    }' <(tr -d '\r' < "$lock") -)"
own=""
[ ! -f "envs/$VERSION/Dockerfile" ] || own=1
[ -n "$pins$own" ] || { echo layer; exit 0; }

fresh
if [ -z "$own" ]; then
    echo "$VERSION $pins, which $prev pins, so it is built fresh, not as a layer on $prev"
elif [ -z "$pins" ]; then
    echo "$VERSION carries its own Dockerfile, so it is built fresh from it, not as a layer on $prev"
else
    echo "$VERSION $pins, which $prev pins, and carries its own Dockerfile, so it is built fresh from it, not as a layer on $prev"
fi
