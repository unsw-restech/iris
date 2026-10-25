#!/bin/bash
# bin/check's pre-launch pairing against copies of the site in a scratch
# repo: the Run buttons' /pun/dev/ or /pun/sys/ and every pre-launch notice
# (the README's, and "Proposals open at launch" on the contribute page, in
# CONTRIBUTING and in the proposal form) switch together at launch. Prints
# each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_prelaunch.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# Each pre-launch notice, as <file>|<text>.
notices=(
    'README.md|not open to researchers yet'
    'contribute/index.html|Proposals open at launch'
    'CONTRIBUTING.md|Proposals open at launch'
    '.github/ISSUE_TEMPLATE/proposal.yml|Proposals open at launch'
)

# A scratch repo at $scratch/<name> holding bin/check, the site's pages and
# every file with a notice, as in this working tree.
copy_site() {
    local repo="$scratch/$1"
    mkdir -p "$repo"
    git ls-files -z --cached --others --exclude-standard bin/check '*.html' "${notices[@]%%|*}" ':(exclude)_archive' |
        xargs -0 cp --parents -t "$repo"
    git init -q "$repo"
    git -C "$repo" add -A
}

# The scratch repo's Run buttons, moved to /pun/sys/.
launch_buttons() {
    git -C "$scratch/$1" grep -lz 'pun/dev/OpenComposer' -- '*.html' |
        (cd "$scratch/$1" && xargs -0 sed -i 's|pun/dev/OpenComposer|pun/sys/OpenComposer|g')
}

# Removes every line holding notice $2 (<file>|<text>) in the scratch repo $1.
drop_notice() {
    sed -i "/${2#*|}/d" "$scratch/$1/${2%%|*}"
}

# pairing <pass|fail> <name>: the pairing check over $scratch/<name>.
pairing() {
    expect "$1" "$scratch/$2" "notices match the Run buttons"
}

copy_site pre-launch
pairing pass pre-launch

copy_site launched
launch_buttons launched
for notice in "${notices[@]}"; do drop_notice launched "$notice"; done
pairing pass launched

for notice in "${notices[@]}"; do
    name="${notice%%|*}"; name="${name//\//-}"
    copy_site "$name-notice-gone"
    drop_notice "$name-notice-gone" "$notice"
    pairing fail "$name-notice-gone"

    copy_site "$name-notice-left"
    launch_buttons "$name-notice-left"
    for other in "${notices[@]}"; do
        [ "$other" = "$notice" ] || drop_notice "$name-notice-left" "$other"
    done
    pairing fail "$name-notice-left"
done
