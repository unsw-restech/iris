#!/bin/bash
# bin/check's rule that tests copy lib/katana.sh through tests/bin/lib.sh's
# katana_copy, against throwaway trees, and katana_copy itself: an author's
# container in the digest map is written as its digest alone, the org's own
# package named in full and every other line are kept, and a folder as the
# destination gets katana.sh in it. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_katana_copies.sh
#
# bin/check name: katana copies test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="tests copy lib/katana.sh through katana_copy"

# make_tree <name> <a line of tests/bin/test_x.sh>: a tree with that line
# in a test.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree"
    mkdir -p "$tree/tests/bin"
    printf '%s\n' '#!/bin/bash' "$2" > "$tree/tests/bin/test_x.sh"
    git -C "$tree" add -A
}

make_tree helper 'katana_copy "$repo/lib/katana.sh"'
expect pass "$scratch/helper" "$name"
make_tree other-copy 'cp "$repo/lib/katana.sh" "$other/lib/"'
expect pass "$scratch/other-copy" "$name"
make_tree in-prose '# a cp of lib/katana.sh that keeps the real map, as before'
expect pass "$scratch/in-prose" "$name"

make_tree cp 'cp lib/katana.sh "$repo/lib/katana.sh"'
expect fail "$scratch/cp" "$name"
make_tree cp-to-folder '    cp lib/katana.sh "$tools/lib/"'
expect fail "$scratch/cp-to-folder" "$name"
make_tree cp-quoted 'cp -p "lib/katana.sh" "$f"'
expect fail "$scratch/cp-quoted" "$name"
make_tree cp-among 'cp bin/envrun lib/katana.sh "$src/lib/"'
expect fail "$scratch/cp-among" "$name"

# katana_copy, from a tree whose lib/katana.sh names an author's container,
# the org's own package in full and a plain digest.
h=$(printf 'c%.0s' {1..64})
tree="$scratch/branch"
mkdir -p "$tree/lib" "$tree/out"
katana_copy "$tree/lib/katana.sh" || exit 1
digest_map "$tree/lib/katana.sh" "ct/1=sha256:$h" "ct/2=ghcr.io/alice-lab/iris-env@sha256:$h" \
    "ct/3=ghcr.io/unsw-restech/iris-env@sha256:$h" ct/4=unpublished || exit 1
(cd "$tree" && katana_copy out/file.sh && katana_copy out) || echo "katana_copy: failed"
want="$(sed 's|^    \[ct/2\]=ghcr.io/alice-lab/iris-env@|    [ct/2]=|' "$tree/lib/katana.sh")"
for f in "$tree/out/file.sh" "$tree/out/katana.sh"; do
    [ "$(cat "$f" 2> /dev/null)" = "$want" ] || { echo "katana_copy: ${f##*/} isn't lib/katana.sh with ct/2 as its digest alone:"; diff <(echo "$want") "$f" | sed 's/^/  /'; }
done
grep -qx "    \[ct/3\]=ghcr.io/unsw-restech/iris-env@sha256:$h" "$tree/out/katana.sh" || echo "katana_copy: rewrote the org's own package"
[ "$(stat -c %a "$tree/out/katana.sh")" = "$(stat -c %a "$tree/lib/katana.sh")" ] || echo "katana_copy: didn't keep lib/katana.sh's mode"

# Only the digest map is rewritten, so a line shaped like one in the lab
# table is kept, and so is a last line with no newline, as bin/libcopy's
# without_authors keeps them.
lab_table "$tree/lib/katana.sh" "ct-lab=ghcr.io/alice-lab/iris-env@sha256:$h" || exit 1
printf '%s' '# the last line' >> "$tree/lib/katana.sh"
(cd "$tree" && katana_copy out/tail.sh) || echo "katana_copy: failed on a last line with no newline"
grep -qx "    \[ct-lab\]=ghcr.io/alice-lab/iris-env@sha256:$h" "$tree/out/tail.sh" || echo "katana_copy: rewrote a line outside the digest map"
[ "$(tail -c 15 "$tree/out/tail.sh" | od -c)" = "$(printf '%s' '# the last line' | od -c)" ] ||
    echo "katana_copy: changed the last line or gave it a newline"
