#!/bin/bash
# How an environment version is built, from its lock alone (ADR-0010):
#
#   envs/build-kind.sh <env>/<n>
#
# Prints "layer" when <env>/<n>'s lock keeps every line of the lock of the
# version before it, which envs/next.Dockerfile builds as one layer on that
# version, and "fresh" for a first version or one whose lock changes or
# removes a line, which builds from envs/<env>/1/Dockerfile like a first
# version. A version that changes pins gets a second line, a note naming
# the packages it changes and removes, which envs/build-container.sh and
# bin/check print without failing. Exits 1, with one line, when a lock it
# needs is missing. Lines compare with comments and surrounding spaces
# dropped, and a package by its normalised name.

set -euo pipefail

VERSION="${1:?usage: envs/build-kind.sh <env>/<n>}"
cd "$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=lib/katana.sh
. <(tr -d '\r' < lib/katana.sh)
iris_is_env_version "$VERSION" ||
    { echo "$VERSION is not <env>/<n>, with <n> counting from 1" >&2; exit 1; }
n="${VERSION##*/}"
lock="envs/$VERSION/requirements.lock"
[ -f "$lock" ] || { echo "No $lock." >&2; exit 1; }
[ "$n" -gt 1 ] || { echo fresh; exit 0; }
prev="${VERSION%/*}/$((n - 1))"
[ -f "envs/$prev/requirements.lock" ] || { echo "No envs/$prev/requirements.lock before $VERSION." >&2; exit 1; }

tr -d '\r' < "envs/$prev/requirements.lock" | awk -v v="$VERSION" -v prev="$prev" '
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
        if (nc + nr == 0) { print "layer"; exit }
        print "fresh"
        s = ""
        if (nc) s = "changes " list(changed, nc)
        if (nr) s = s (nc ? " and " : "") "removes " list(removed, nr)
        print v " " s ", which " prev " pins, so it is built fresh, not as a layer on " prev
    }' <(tr -d '\r' < "$lock") -
