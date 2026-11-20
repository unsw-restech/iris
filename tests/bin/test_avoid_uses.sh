#!/bin/bash
# bin/avoid-uses, which lists every use of a GLOSSARY.md _Avoid_ word, in
# files and standard input, and with --new each use in tracked files of a
# word the _Avoid_ lists gained since origin/main; then bin/check's rule
# on that, against throwaway trees: #231's glossary commit made "batch" an
# Avoid word while Review batch still used it.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_avoid_uses.sh
#
# bin/check name: avoid-uses test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

fail() { echo "avoid-uses $case: $1"; }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
# glossary <tree> <Image set's Avoid list>: a GLOSSARY.md of three entries.
glossary() {
    printf '%s\n' "# Glossary" "" \
        "**Image set**:" "A folder of 2D images a run segments." "_Avoid_: $2" "" \
        "**Container**:" "The file a run starts inside." "_Avoid_: Image, container image" "" \
        "**Transfer**:" "Moving a dataset to Katana." "_Avoid_: Collection, except when quoting Globus" > "$1/GLOSSARY.md"
}

repo="$scratch/repo"
mkdir -p "$repo/bin"
cp bin/avoid-uses "$repo/bin/"
git -C "$repo" init -q -b main
glossary "$repo" "Stack"
printf '%s\n' "Each image set is read." "A container image is pulled." "The STACK of" "slices." \
    "See train/stack/x and stack.py." "Except when quoting Globus." "A stack and a stack." > "$repo/text.md"
echo "Nothing to see." > "$repo/clean.md"
commit "$repo" fixture
git -C "$repo" update-ref refs/remotes/origin/main HEAD

case="a file"
out="$("$repo/bin/avoid-uses" "$repo/text.md")"; code=$?
[ "$code" = 1 ] || fail "exit $code, not 1"
want=("$repo/text.md:2: \"container image\", the Avoid word of Container: A container image is pulled."
      "$repo/text.md:3: \"Stack\", the Avoid word of Image set: The STACK of"
      "$repo/text.md:7: \"Stack\", the Avoid word of Image set: A stack and a stack.")
for w in "${want[@]}"; do grep -qxF -- "$w" <<< "$out" || fail "no line '$w'"; done
[ "$(wc -l <<< "$out")" = 3 ] || fail "not 3 lines: image inside a term, a path, \"except\" or a repeat on one line was listed:
$out"

case="standard input"
out="$("$repo/bin/avoid-uses" - < "$repo/text.md")"
grep -qxF -- "-:3: \"Stack\", the Avoid word of Image set: The STACK of" <<< "$out" || fail "no line for '-'"

case="a clean file"
out="$("$repo/bin/avoid-uses" "$repo/clean.md")"; code=$?
[ "$code" = 0 ] && [ -z "$out" ] || fail "exit $code: $out"

case="--words"
out="$("$repo/bin/avoid-uses" --words)"
[ "$out" = $'Stack\nImage\ncontainer image\nCollection' ] || fail "listed: $out"

case="no word gained"
out="$("$repo/bin/avoid-uses" --new)"; code=$?
[ "$code" = 0 ] && [ -z "$out" ] || fail "exit $code: $out"

# "batch" joins Image set's list; Stack moves to Container's, so isn't new.
case="a word gained"
mkdir -p "$repo/_archive/old" "$repo/docs/adr" "$repo/workflows/w/lib"
glossary "$repo" "batch"
sed -i 's/^_Avoid_: Image, container image$/_Avoid_: Image, container image, stack/' "$repo/GLOSSARY.md"
echo "Review the batch." > "$repo/notes.md"
echo "An old batch." > "$repo/_archive/old/form.md"
echo "A decided batch." > "$repo/docs/adr/0001-batch.md"
echo "# a batch" > "$repo/workflows/w/lib/copy.py"
commit "$repo" batch
out="$("$repo/bin/avoid-uses" --new)"; code=$?
[ "$code" = 1 ] || fail "exit $code, not 1"
[ "$out" = 'notes.md:1: "batch", the Avoid word of Image set: Review the batch.' ] || fail "listed:
$out"

# Another entry's definition uses the new word; its own _Avoid_ line doesn't.
case="a word gained, used in the glossary"
sed -i 's/^Moving a dataset to Katana.$/Moving a batch of datasets to Katana./' "$repo/GLOSSARY.md"
commit "$repo" glossary-use
out="$("$repo/bin/avoid-uses" --new)"
[ "$out" = 'GLOSSARY.md:12: "batch", the Avoid word of Image set: Moving a batch of datasets to Katana.
notes.md:1: "batch", the Avoid word of Image set: Review the batch.' ] || fail "listed:
$out"

# A word two entries list is one line naming both.
case="a word on two lists"
printf '%s\n' "**Run**:" "One submission of a form." "_Avoid_: batch" >> "$repo/GLOSSARY.md"
echo "A batch." > "$repo/one.md"
out="$("$repo/bin/avoid-uses" "$repo/one.md")"
[ "$out" = "$repo/one.md:1: \"batch\", the Avoid word of Image set, Run: A batch." ] || fail "listed:
$out"

case="a base given"
out="$("$repo/bin/avoid-uses" --new HEAD)"; code=$?
[ "$code" = 0 ] && [ -z "$out" ] || fail "exit $code: $out"
"$repo/bin/avoid-uses" --new no-such-commit 2> /dev/null; code=$?
[ "$code" = 2 ] || fail "no-such-commit: exit $code, not 2"

# bin/check's rule, on a site tree with its own origin/main.
name="new glossary Avoid word still used"
make_site() {
    local tree="$scratch/$1"
    site_tree "$tree"
    cp bin/avoid-uses "$tree/bin/"
    glossary "$tree" "Stack"
    echo "Review the batch." > "$tree/notes.md"
    commit "$tree" fixture
    git -C "$tree" update-ref refs/remotes/origin/main HEAD
    glossary "$tree" "Stack, batch"
}

case="check"
make_site used
expect fail "$scratch/used" "$name"
out="$("$scratch/used/bin/check" "$name" 2>&1)"
grep -qF 'notes.md:1: "batch", the Avoid word of Image set' <<< "$out" || fail "the failure doesn't name the use: $out"

make_site reworded
echo "Review the pull requests." > "$scratch/reworded/notes.md"
expect pass "$scratch/reworded" "$name"

# A use kept on purpose, as <word>:<path>, passes and covers that file only;
# the pair fails once the file no longer uses the word, or no _Avoid_ list
# names it.
kept() { sed -i "s|^new_avoid_kept=()\$|new_avoid_kept=(\"$2\")|" "$scratch/$1/bin/check"
    grep -qxF "new_avoid_kept=(\"$2\")" "$scratch/$1/bin/check" || fail "bin/check has no new_avoid_kept=() line"; }
make_site kept
kept kept batch:notes.md
expect pass "$scratch/kept" "$name"
echo "Another batch." > "$scratch/kept/more.md"
git -C "$scratch/kept" add -A
expect fail "$scratch/kept" "$name"
make_site kept-reworded
kept kept-reworded batch:notes.md
echo "Review the pull requests." > "$scratch/kept-reworded/notes.md"
expect fail "$scratch/kept-reworded" "$name"
make_site kept-unlisted
kept kept-unlisted batch:notes.md
glossary "$scratch/kept-unlisted" "Stack"
expect fail "$scratch/kept-unlisted" "$name"

# With no origin/main there is no base, so nothing is new.
make_site no-main
git -C "$scratch/no-main" update-ref -d refs/remotes/origin/main
expect pass "$scratch/no-main" "$name"
