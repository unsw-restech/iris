#!/bin/bash
# bin/syspull's container check, sent on stdin to `bash -s` on Katana:
#
#   bash -s -- <system clone> <commit>
#
# Names each environment version <commit> pins, by its forms and the
# researcher tools, whose container file isn't in the environments folder
# with the digest <commit>'s digest map gives, one line each. Exits 0 if
# every one is in place, 1 if any isn't, and 2 if it can't tell. A pinned
# version that isn't in place stops every job of its form, so bin/syspull
# --apply deploys nothing until bin/envpull puts it in. Reads lib/katana.sh
# as <commit> holds it, so it checks what the deploy would run.

clone="$1" commit="$2"
cd "$clone" || exit 2
git rev-parse -q --verify "$commit^{commit}" > /dev/null || git fetch -q origin 2> /dev/null
git rev-parse -q --verify "$commit^{commit}" > /dev/null || { echo "$commit is not a commit in $clone."; exit 2; }
# shellcheck source=lib/katana.sh
. <(git show "$commit:lib/katana.sh") || exit 2
# Before #122 nothing ran in a container, so no helpers means no pins.
declare -F iris_form_pins > /dev/null || exit 0
# A copy of bin/envpull-dm.sh's pin(): a helper in lib/katana.sh would be
# missing from the older commits this reads.
declare -A pinned=()
# pin <env>/<n> <by>: <by> pins the version.
pin() { pinned[$1]="${pinned[$1]:+${pinned[$1]}, }$2"; }

pin "$IRIS_TOOLS_ENV_VERSION" "the researcher tools"
while IFS= read -r f; do
    slug="${f#workflows/}" slug="${slug%/form.yml.erb}"
    while IFS= read -r v; do
        pin "$v" "$slug"
    done < <(git show "$commit:$f" | iris_form_pins /dev/stdin)
done < <(git ls-tree -r --name-only "$commit" workflows | grep -E '^workflows/[^/]+/form[.]yml[.]erb$')

status=0
for v in $(printf '%s\n' "${!pinned[@]}" | sort); do
    d="${IRIS_ENV_DIGESTS[$v]-}" file="$(iris_env_file "$v")"
    digest_file="${file%.sif}.digest"
    have="$(cat "$digest_file" 2> /dev/null)"
    # bin/envpull can't pull these, so they get their own lines.
    if [ -z "$d" ]; then
        echo "$v, pinned by ${pinned[$v]}: not in $commit's digest map."
        status=1
    elif [ "$d" = unpublished ]; then
        echo "$v, pinned by ${pinned[$v]}: unpublished in $commit's digest map, so there is no container to pull."
        status=1
    elif [ ! -f "$file" ]; then
        echo "$v, pinned by ${pinned[$v]}: no $file."
        status=1
    elif [ "$have" != "$d" ]; then
        echo "$v, pinned by ${pinned[$v]}: $digest_file holds '${have:-nothing}', not $d."
        status=1
    fi
done
exit "$status"
