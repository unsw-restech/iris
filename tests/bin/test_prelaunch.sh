#!/bin/bash
# bin/check's pre-launch pairing against copies of the site in a scratch
# repo: every pre-launch notice (the README's and the landing page's pilot
# notices, and "Proposals open at launch" on the contribute page, in
# CONTRIBUTING and in the proposal form) goes together at launch, and Run
# buttons on /pun/dev/ need them all. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_prelaunch.sh
#
# bin/check name: pre-launch pairing test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# Each pre-launch notice, as <file>|<text>.
notices=(
    'README.md|work only for pilot testers until launch'
    'index.html|work only for pilot testers until launch'
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

# The scratch repo's Run buttons, moved back to /pun/dev/; with a file
# argument, that file's only.
dev_buttons() {
    git -C "$scratch/$1" grep -lz 'pun/sys/OpenComposer' -- "${2:-*.html}" |
        (cd "$scratch/$1" && xargs -0 sed -i 's|pun/sys/OpenComposer|pun/dev/OpenComposer|g')
}

# Removes every line holding notice $2 (<file>|<text>) in the scratch repo $1.
drop_notice() {
    sed -i "/${2#*|}/d" "$scratch/$1/${2%%|*}"
}

# pairing <pass|fail> <name>: the pairing check over $scratch/<name>.
pairing() {
    expect "$1" "$scratch/$2" "notices match the Run buttons"
}

copy_site pilot
pairing pass pilot

copy_site dev
dev_buttons dev
pairing pass dev

copy_site split
dev_buttons split workflows/hello-world/index.html
pairing fail split

copy_site launched
for notice in "${notices[@]}"; do drop_notice launched "$notice"; done
pairing pass launched

for notice in "${notices[@]}"; do
    name="${notice%%|*}"; name="${name//\//-}"
    copy_site "$name-dev-notice-gone"
    dev_buttons "$name-dev-notice-gone"
    drop_notice "$name-dev-notice-gone" "$notice"
    pairing fail "$name-dev-notice-gone"

    copy_site "$name-notice-gone"
    drop_notice "$name-notice-gone" "$notice"
    pairing fail "$name-notice-gone"

    copy_site "$name-notice-left"
    for other in "${notices[@]}"; do
        [ "$other" = "$notice" ] || drop_notice "$name-notice-left" "$other"
    done
    pairing fail "$name-notice-left"
done
