#!/bin/bash
# bin/check's pre-launch pairing against copies of the site in a scratch
# repo: the Run buttons' /pun/dev/ or /pun/sys/, the README's notice and
# the contribute page's notice switch together at launch. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_prelaunch.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

readme_notice='not open to researchers yet'
contribute_notice='Proposals open at launch'

# A scratch repo at $scratch/<name> holding bin/check, the README and the
# site's pages, as in this working tree.
copy_site() {
    local repo="$scratch/$1"
    mkdir -p "$repo"
    git ls-files -z --cached --others --exclude-standard bin/check README.md '*.html' ':(exclude)_archive' |
        xargs -0 cp --parents -t "$repo"
    git init -q "$repo"
    git -C "$repo" add -A
}

# The scratch repo's Run buttons, moved to /pun/sys/.
launch_buttons() {
    git -C "$scratch/$1" grep -lz 'pun/dev/OpenComposer' -- '*.html' |
        (cd "$scratch/$1" && xargs -0 sed -i 's|pun/dev/OpenComposer|pun/sys/OpenComposer|g')
}

# Removes every line holding $3 from $2 in the scratch repo $1.
drop_notice() {
    sed -i "/$3/d" "$scratch/$1/$2"
}

# expect <pass|fail> <name>: the pairing check over $scratch/<name>.
expect() {
    local out rc
    out="$("$scratch/$2/bin/check" "notices match the Run buttons" 2>&1)"
    rc=$?
    if [ "$1" = pass ] && [ "$rc" != 0 ]; then
        echo "$2: failed, expected a pass"
    elif [ "$1" = fail ] && [ "$rc" != 1 ]; then
        echo "$2: passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

copy_site pre-launch
expect pass pre-launch

copy_site contribute-notice-gone
drop_notice contribute-notice-gone contribute/index.html "$contribute_notice"
expect fail contribute-notice-gone

copy_site readme-notice-gone
drop_notice readme-notice-gone README.md "$readme_notice"
expect fail readme-notice-gone

copy_site contribute-notice-left
launch_buttons contribute-notice-left
drop_notice contribute-notice-left README.md "$readme_notice"
expect fail contribute-notice-left

copy_site launched
launch_buttons launched
drop_notice launched README.md "$readme_notice"
drop_notice launched contribute/index.html "$contribute_notice"
expect pass launched
