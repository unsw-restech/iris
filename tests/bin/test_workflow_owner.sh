#!/bin/bash
# bin/check's workflow-owner check against throwaway repo trees: a copy of
# bin/check in a scratch folder checks the workflows and CODEOWNERS beside
# it. Prints each failed case and nothing on success, so bin/check can run
# it.
#
#   tests/bin/test_workflow_owner.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# A tree in $scratch/<name> holding bin/check and a catalogue that passes:
# a workflow with a form, an owner on its page and a CODEOWNERS line;
# hello-world, which has a form and no owner; and a Planned workflow,
# which has a page and no form.
make_tree() {
    local tree="$scratch/$1"
    mkdir -p "$tree/bin" "$tree/.github" "$tree/workflows/seg" "$tree/workflows/hello-world" "$tree/workflows/later"
    cp bin/check "$tree/bin/check"
    touch "$tree/workflows/seg/form.yml.erb" "$tree/workflows/hello-world/form.yml.erb"
    owner_line jdoe "Jane Doe" > "$tree/workflows/seg/index.html"
    echo '<h1 class="wf-title">Hello world</h1>' > "$tree/workflows/hello-world/index.html"
    echo '<h1 class="wf-title">Later</h1>' > "$tree/workflows/later/index.html"
    printf '%s\n' '# Workflow owners' '/workflows/seg/ @jdoe' > "$tree/.github/CODEOWNERS"
}

# The page line naming <login> (<name>) as the workflow owner.
owner_line() {
    echo "  <p class=\"wf-owner\">Workflow owner: <a href=\"https://github.com/$1\" target=\"_blank\">$2</a></p>"
}

# expect <pass|fail> <name>: the check over $scratch/<name>, which the
# caller has built and changed.
expect() {
    local out rc
    out="$("$scratch/$2/bin/check" "workflow owner on the page" 2>&1)"
    rc=$?
    if [ "$1" = pass ] && [ "$rc" != 0 ]; then
        echo "$2 failed, expected a pass"
    elif [ "$1" = fail ] && { [ "$rc" != 1 ] || ! grep -q '^FAIL: workflow owner' <<< "$out"; }; then
        echo "$2 passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

make_tree clean
expect pass clean

make_tree no-owner-on-page
echo '<h1 class="wf-title">Seg</h1>' > "$scratch/no-owner-on-page/workflows/seg/index.html"
expect fail no-owner-on-page

make_tree no-codeowners-line
echo '# Workflow owners' > "$scratch/no-codeowners-line/.github/CODEOWNERS"
expect fail no-codeowners-line

make_tree no-codeowners-file
rm "$scratch/no-codeowners-file/.github/CODEOWNERS"
expect fail no-codeowners-file

make_tree line-for-missing-folder
echo '/workflows/gone/ @jdoe' >> "$scratch/line-for-missing-folder/.github/CODEOWNERS"
expect fail line-for-missing-folder

make_tree line-for-planned
echo '/workflows/later/ @jdoe' >> "$scratch/line-for-planned/.github/CODEOWNERS"
expect fail line-for-planned

make_tree line-for-hello-world
echo '/workflows/hello-world/ @jdoe' >> "$scratch/line-for-hello-world/.github/CODEOWNERS"
expect pass line-for-hello-world

make_tree line-for-other-paths
echo '/bin/ @jdoe' >> "$scratch/line-for-other-paths/.github/CODEOWNERS"
expect pass line-for-other-paths

make_tree codeowners-names-someone-else
printf '%s\n' '/workflows/seg/ @someone' > "$scratch/codeowners-names-someone-else/.github/CODEOWNERS"
expect fail codeowners-names-someone-else

make_tree codeowners-adds-a-co-owner
printf '%s\n' '/workflows/seg/ @someone @jdoe' > "$scratch/codeowners-adds-a-co-owner/.github/CODEOWNERS"
expect pass codeowners-adds-a-co-owner

make_tree crlf
sed -i 's/$/\r/' "$scratch/crlf/.github/CODEOWNERS" "$scratch/crlf/workflows/seg/index.html"
expect pass crlf
