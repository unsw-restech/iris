#!/bin/bash
# bin/libcopy and bin/check's library copies check against throwaway repos,
# each with its own copy of bin/check and bin/libcopy: a copy bin/libcopy
# makes passes, and one edited by hand, missing a file, holding a file
# that isn't the job side's, or recording a commit outside HEAD's history
# fails, as does an imaging form with no copy, while a lib/ holding only
# ignored files, or one deeper than a workflow's own, is no copy. The
# review batch's rewrite of an author's container line in a copy's
# katana.sh to its digest alone passes, and any other change there fails.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_library_copies.sh
#
# bin/check name: library copies test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="workflows' library copies match lib/ at the commit they record"
job_side=(iris-job.sh katana.sh iris/__init__.py iris/dataset.py iris/labels.py iris/record.py iris/rundir.py iris/volume.py)

commit() {
    git -C "$scratch/$1" add -A
    git -C "$scratch/$1" -c user.name=t -c user.email=t@example.org commit -q -m "${2:-change}"
}

# make_tree <name>: a site whose seg workflow has an imaging form (its
# script opens the entry script's heredoc), with lib/ holding the job side
# and a shared module, all committed, and no copy yet.
make_tree() {
    local tree="$scratch/$1" f
    site_tree "$tree" seg:ct-lab:active
    cp bin/libcopy "$tree/bin/libcopy"
    mkdir -p "$tree/lib/iris"
    for f in "${job_side[@]}"; do echo "# lib/$f" > "$tree/lib/$f"; done
    echo "# shared" > "$tree/lib/iris/tracking.py"
    printf '%s\n' 'script: |' '  #!/bin/bash' "  cat > \"\$RUN_DIR/run.py\" <<'IRIS_RUN_PY_END'" '  IRIS_RUN_PY_END' \
        > "$tree/workflows/seg/form.yml.erb"
    commit "$1" "The library"
}

# copied <name>: make_tree, then bin/libcopy seg, committed.
copied() {
    make_tree "$1"
    "$scratch/$1/bin/libcopy" seg > /dev/null || echo "$1: bin/libcopy seg failed"
    commit "$1" "seg's copy"
}

copied clean
expect pass "$scratch/clean" "$name"
# The copy is the job side and the commit, nothing of the shared side.
for f in "${job_side[@]}"; do
    cmp -s "$scratch/clean/lib/$f" "$scratch/clean/workflows/seg/lib/$f" || echo "clean: workflows/seg/lib/$f is not lib/$f"
done
[ ! -e "$scratch/clean/workflows/seg/lib/iris/tracking.py" ] || echo "clean: the copy holds the shared side's tracking.py"
[ "$(cat "$scratch/clean/workflows/seg/lib/copied-from")" = "$(git -C "$scratch/clean" rev-parse HEAD~1)" ] ||
    echo "clean: copied-from is not the commit the copy was made from"

# An imaging form needs a copy.
make_tree no-copy
expect fail "$scratch/no-copy" "$name"
# A form that is no imaging form, such as hello-world's, needs none.
make_tree plain-form
printf '%s\n' 'script: |' '  #!/bin/bash' > "$scratch/plain-form/workflows/seg/form.yml.erb"
expect pass "$scratch/plain-form" "$name"

# A copy is never edited by hand, committed or not.
copied hand-edit
echo "# a fix" >> "$scratch/hand-edit/workflows/seg/lib/iris/record.py"
expect fail "$scratch/hand-edit" "$name"
commit hand-edit
expect fail "$scratch/hand-edit" "$name"
out="$("$scratch/hand-edit/bin/check" "$name" 2>&1)"
grep -q 'workflows/seg/lib/iris/record.py.*bin/libcopy seg' <<< "$out" ||
    { echo "hand-edit: the message doesn't name the file and bin/libcopy seg"; echo "$out" | sed 's/^/  /'; }

copied missing-file
rm "$scratch/missing-file/workflows/seg/lib/iris/volume.py"
commit missing-file
expect fail "$scratch/missing-file" "$name"

copied extra-file
cp "$scratch/extra-file/lib/iris/tracking.py" "$scratch/extra-file/workflows/seg/lib/iris/"
commit extra-file
expect fail "$scratch/extra-file" "$name"

# The library moving on leaves a copy behind, not wrong: its owner decides
# when to update, and copying again records the newer commit.
copied behind
echo "# newer" >> "$scratch/behind/lib/iris/record.py"
commit behind
expect pass "$scratch/behind" "$name"
"$scratch/behind/bin/libcopy" seg > /dev/null
commit behind
expect pass "$scratch/behind" "$name"
grep -q newer "$scratch/behind/workflows/seg/lib/iris/record.py" || echo "behind: copying again did not update the copy"

# A branch that doesn't touch lib/ records the commit that last changed the
# job side, which is already on main, not the branch's own commit.
make_tree branch
git -C "$scratch/branch" checkout -q -b new-workflow
echo "page" >> "$scratch/branch/workflows/seg/index.html"
commit branch "The workflow's page"
"$scratch/branch/bin/libcopy" seg > /dev/null
[ "$(cat "$scratch/branch/workflows/seg/lib/copied-from")" = "$(git -C "$scratch/branch" rev-parse HEAD~1)" ] ||
    echo "branch: copied-from is not the commit that last changed the job side"

# It copies what the commit holds, so it refuses uncommitted job side edits.
make_tree uncommitted
echo "# draft" >> "$scratch/uncommitted/lib/iris/rundir.py"
"$scratch/uncommitted/bin/libcopy" seg > /dev/null 2>&1 && echo "uncommitted: bin/libcopy copied with lib/ uncommitted"
[ ! -e "$scratch/uncommitted/workflows/seg/lib" ] || echo "uncommitted: bin/libcopy wrote a copy"

# A recorded commit outside HEAD's history, as after a rebase or a squash
# merge, or not a commit at all, fails.
copied rewritten
git -C "$scratch/rewritten" checkout -q -b side
echo "# side" >> "$scratch/rewritten/lib/iris/record.py"
commit rewritten "A side change"
"$scratch/rewritten/bin/libcopy" seg > /dev/null
side=$(cat "$scratch/rewritten/workflows/seg/lib/copied-from")
git -C "$scratch/rewritten" checkout -q -
git -C "$scratch/rewritten" show "side:lib/iris/record.py" > "$scratch/rewritten/workflows/seg/lib/iris/record.py"
echo "$side" > "$scratch/rewritten/workflows/seg/lib/copied-from"
commit rewritten
expect fail "$scratch/rewritten" "$name"

copied not-a-commit
echo "0123456789abcdef0123456789abcdef01234567" > "$scratch/not-a-commit/workflows/seg/lib/copied-from"
commit not-a-commit
expect fail "$scratch/not-a-commit" "$name"

# A lib/ holding only ignored files, such as the __pycache__/ a branch
# switch leaves behind for a workflow the new branch lacks, is no copy; a
# new copy not yet committed still is, so its hand edit fails.
copied ignored
printf '%s\n' '__pycache__/' > "$scratch/ignored/.gitignore"
commit ignored
mkdir -p "$scratch/ignored/workflows/gone/lib/iris/__pycache__"
touch "$scratch/ignored/workflows/gone/lib/iris/__pycache__/record.cpython-313.pyc"
expect pass "$scratch/ignored" "$name"

copied untracked-copy
mkdir -p "$scratch/untracked-copy/workflows/new"
"$scratch/untracked-copy/bin/libcopy" new > /dev/null
echo "# a fix" >> "$scratch/untracked-copy/workflows/new/lib/iris/record.py"
expect fail "$scratch/untracked-copy" "$name"

# Only a workflow's own lib/ is a copy, not a lib/ deeper in its folder.
copied nested
mkdir -p "$scratch/nested/workflows/seg/src/lib"
echo "x = 1" > "$scratch/nested/workflows/seg/src/lib/a.py"
commit nested
expect pass "$scratch/nested" "$name"

# A Windows working copy can hold CRLF files; the copy is compared as git
# stores it.
copied crlf
printf '%s\n' '* text=auto eol=lf' > "$scratch/crlf/.gitattributes"
commit crlf
sed -i 's/$/\r/' "$scratch/crlf/workflows/seg/lib/iris/record.py" "$scratch/crlf/workflows/seg/lib/copied-from"
expect pass "$scratch/crlf" "$name"

# The review batch rewrites an author's container line in a copy's
# katana.sh to its digest alone, as it does in lib/katana.sh (#256): that
# rewrite passes, and any other difference still fails. lib/katana.sh is
# the real one, with ct/2 an author's container, ct/3 the org's own package
# named in full, and the lab table holding an author's container too, which
# is outside the digest map.
a64=$(printf 'a%.0s' {1..64}) b64=$(printf 'b%.0s' {1..64})
author="ghcr.io/alice-lab/iris-env@sha256:$a64"
# rewritten <name> <sed script>: a copy of lib/katana.sh as above, made by
# bin/libcopy and committed, then <sed script> run on the copy's katana.sh,
# committed.
rewritten() {
    make_tree "$1"
    katana_copy "$scratch/$1/lib/katana.sh"
    digest_map "$scratch/$1/lib/katana.sh" "ct/1=sha256:$b64" "ct/2=$author" \
        "ct/3=ghcr.io/unsw-restech/iris-env@sha256:$b64" || exit 1
    lab_table "$scratch/$1/lib/katana.sh" "ct-lab=$author" || exit 1
    commit "$1" "ct/2 is an author's"
    "$scratch/$1/bin/libcopy" seg > /dev/null || echo "$1: bin/libcopy seg failed"
    commit "$1" "seg's copy"
    sed -i "$2" "$scratch/$1/workflows/seg/lib/katana.sh"
    commit "$1" "The copy, rewritten"
}
rewritten batch "s|^    \[ct/2\]=.*|    [ct/2]=sha256:$a64|"
expect pass "$scratch/batch" "$name"
# The same rewrite with CRLF line ends in the working copy.
printf '%s\n' '* text=auto eol=lf' > "$scratch/batch/.gitattributes"
commit batch
sed -i 's/$/\r/' "$scratch/batch/workflows/seg/lib/katana.sh"
expect pass "$scratch/batch" "$name"
# A digest that isn't the author's line's.
rewritten other-digest "s|^    \[ct/2\]=.*|    [ct/2]=sha256:$b64|"
expect fail "$scratch/other-digest" "$name"
# The org's own package named in full is no author's container.
rewritten org-line "s|^    \[ct/3\]=.*|    [ct/3]=sha256:$b64|"
expect fail "$scratch/org-line" "$name"
# The rewrite outside the digest map, in the lab table.
rewritten outside-map "s|^    \[ct-lab\]=.*|    [ct-lab]=sha256:$a64|"
expect fail "$scratch/outside-map" "$name"
# The rewrite with another line changed too.
rewritten and-more "s|^    \[ct/2\]=.*|    [ct/2]=sha256:$a64|; s|^IRIS_ENV_REGISTRY=.*|&x|"
expect fail "$scratch/and-more" "$name"
# The rewrite with the file's last newline dropped.
rewritten no-newline "s|^    \[ct/2\]=.*|    [ct/2]=sha256:$a64|"
truncate -s -1 "$scratch/no-newline/workflows/seg/lib/katana.sh"
commit no-newline
expect fail "$scratch/no-newline" "$name"
