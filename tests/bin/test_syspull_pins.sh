#!/bin/bash
# bin/syspull-pins.sh against a scratch repo standing in for the system
# clone, whose lib/katana.sh names a scratch environments folder. Prints
# each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_syspull_pins.sh
#
# bin/check name: syspull pins test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
here="$PWD"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
clone="$tmp/clone" envs="$tmp/envs"
a=sha256:$(printf 'a%.0s' {1..64}) b=sha256:$(printf 'b%.0s' {1..64})

git init -q "$clone"
mkdir -p "$clone/lib" "$clone/workflows/seg" "$envs/microct"
sed -e "s|^IRIS_ENVS_FOLDER=.*|IRIS_ENVS_FOLDER=$envs|" \
    -e "s|^    \[microct/1\]=.*|    [microct/1]=$a\n    [microct/2]=$b|" lib/katana.sh > "$clone/lib/katana.sh"
printf 'script: |\n  IRIS_ENV_VERSION=microct/2\n' > "$clone/workflows/seg/form.yml.erb"
git -C "$clone" add -A
git -C "$clone" -c user.name=t -c user.email=t@t commit -qm pins

# expect <exit code> <output substring> [<commit>]: run it on <commit>,
# the clone's HEAD unless given.
expect() {
    local out rc
    out="$(bash -s -- "$clone" "${3:-HEAD}" < "$here/bin/syspull-pins.sh" 2>&1)"
    rc=$?
    if [ "$rc" != "$1" ]; then
        echo "syspull-pins: exit $rc, expected $1"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$2" <<< "$out"; then
        echo "syspull-pins: output lacks '$2'"
        echo "$out" | sed 's/^/  /'
    fi
}

# Nothing on Katana: both the form's version and the researcher tools' are named.
expect 1 "microct/2, pinned by seg: no $envs/microct/2.sif"
expect 1 "microct/1, pinned by the researcher tools: no $envs/microct/1.sif"

# A container file whose digest file disagrees with the map is named.
for n in 1 2; do echo container > "$envs/microct/$n.sif"; done
echo "$a" > "$envs/microct/1.digest"
echo "$a" > "$envs/microct/2.digest"
expect 1 "microct/2, pinned by seg: $envs/microct/2.digest holds '$a', not $b"

# Every pinned version in place with its digest: silent, exit 0.
echo "$b" > "$envs/microct/2.digest"
expect 0 ""
out="$(bash -s -- "$clone" HEAD < "$here/bin/syspull-pins.sh" 2>&1)"
[ -z "$out" ] || echo "syspull-pins: printed '$out' with every container in place"

# A commit from before containers, whose lib/katana.sh has no helpers,
# pins nothing.
echo 'IRIS_SYSTEM_CLONE=/x' > "$clone/lib/katana.sh"
git -C "$clone" -c user.name=t -c user.email=t@t commit -qam "before #122"
rm -rf "$envs/microct"
expect 0 ""

# A commit the clone doesn't have, even after a fetch, is exit 2.
expect 2 "not a commit" 0123abc
