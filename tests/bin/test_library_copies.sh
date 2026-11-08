#!/bin/bash
# bin/libcopy and bin/check's library copies check against throwaway repos,
# each with its own copy of bin/check and bin/libcopy: a copy bin/libcopy
# makes passes, and one edited by hand, missing a file, holding a file
# that isn't the job side's, or recording a commit outside HEAD's history
# fails, as does an imaging form with no copy. Prints each failed case and
# nothing on success, so bin/check can run it.
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

# A Windows working copy can hold CRLF files; the copy is compared as git
# stores it.
copied crlf
printf '%s\n' '* text=auto eol=lf' > "$scratch/crlf/.gitattributes"
commit crlf
sed -i 's/$/\r/' "$scratch/crlf/workflows/seg/lib/iris/record.py" "$scratch/crlf/workflows/seg/lib/copied-from"
expect pass "$scratch/crlf" "$name"
