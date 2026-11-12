#!/bin/bash
# bin/check's untracked-file check against throwaway trees, and that a file
# added with git add -N, as its failure says, is one the other checks read.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_untracked.sh
#
# bin/check name: untracked files test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="untracked file the checks can't see"

site_tree "$scratch/clean"
expect pass "$scratch/clean" "$name"

site_tree "$scratch/new-file"
mkdir -p "$scratch/new-file/lib/tests"
echo '# loads python/3.13.2' > "$scratch/new-file/lib/tests/test_new.rb"
expect fail "$scratch/new-file" "$name"

site_tree "$scratch/ignored"
printf '%s\n' plan.md > "$scratch/ignored/.gitignore"
git -C "$scratch/ignored" add .gitignore
echo '# Plan' > "$scratch/ignored/plan.md"
expect pass "$scratch/ignored" "$name"

# Added with -N, the file passes this check and the name check reads it.
site_tree "$scratch/intent-to-add"
echo 'Each version is one SIF on Katana.' > "$scratch/intent-to-add/notes.md"
git -C "$scratch/intent-to-add" add -N notes.md
expect pass "$scratch/intent-to-add" "$name"
expect fail "$scratch/intent-to-add" "name uses a glossary Avoid word"
