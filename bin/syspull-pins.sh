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

clone="$1" c="$2"
cd "$clone" || exit 2
git rev-parse -q --verify "$c^{commit}" > /dev/null || git fetch -q origin 2> /dev/null
git rev-parse -q --verify "$c^{commit}" > /dev/null || { echo "$c is not a commit in $clone."; exit 2; }
# shellcheck source=lib/katana.sh
. <(git show "$c:lib/katana.sh") || exit 2
# Before #122 nothing ran in a container, so no helpers means no pins.
declare -F iris_form_pins > /dev/null || exit 0
declare -A by=()
# pin <env>/<n> <by>: <by> pins the version.
pin() { by[$1]="${by[$1]:+${by[$1]}, }$2"; }

pin "$IRIS_TOOLS_ENV_VERSION" "the researcher tools"
while IFS= read -r f; do
    slug="${f#workflows/}" slug="${slug%/form.yml.erb}"
    while IFS= read -r v; do
        pin "$v" "$slug"
    done < <(git show "$c:$f" | iris_form_pins /dev/stdin)
done < <(git ls-tree -r --name-only "$c" workflows | grep -E '^workflows/[^/]+/form[.]yml[.]erb$')

status=0
for v in $(printf '%s\n' "${!by[@]}" | sort); do
    d="${IRIS_ENV_DIGESTS[$v]-}" file="$(iris_env_file "$v")"
    digest_file="${file%.sif}.digest"
    have="$(cat "$digest_file" 2> /dev/null)"
    if [ ! -f "$file" ]; then
        echo "$v, pinned by ${by[$v]}: no $file."
        status=1
    elif [ "$have" != "$d" ]; then
        echo "$v, pinned by ${by[$v]}: $digest_file holds '${have:-nothing}', not ${d:-a digest}."
        status=1
    fi
done
exit "$status"
