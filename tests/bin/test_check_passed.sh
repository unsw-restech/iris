#!/bin/bash
# bin/check-passed and the push hook's use of it, in a throwaway repo with
# no bin/katana-test, so the hook's Katana part skips itself. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_check_passed.sh
#
# bin/check name: check-passed test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/.githooks"
cp bin/check-passed "$repo/bin/"
cp .githooks/pre-push "$repo/.githooks/"
echo one > "$repo/a.txt"
git -C "$repo" init -q -b main
git -C "$repo" add -A
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -q "$@"; }
commit -m fixture
record() { "$repo/bin/check-passed" --record; }
passed() { "$repo/bin/check-passed" "$1"; }
fail() { echo "check-passed $1"; }

# Nothing recorded: no commit has passed.
passed HEAD && fail "HEAD passed with nothing recorded"
passed no-such-commit; [ $? = 2 ] || fail "an unknown commit: exit not 2"

# A clean tree records HEAD's tree.
record || fail "--record on a clean tree: exit $?"
passed HEAD || fail "HEAD didn't pass after recording it clean"

# A pass before committing covers the commit holding those edits, a new
# git add -N file included, and leaves the real index alone.
echo two > "$repo/a.txt"
echo new > "$repo/b.txt"
git -C "$repo" add -N b.txt
before="$(git -C "$repo" status --porcelain)"
record || fail "--record with edits and a git add -N file: exit $?"
[ "$(git -C "$repo" status --porcelain)" = "$before" ] || fail "--record changed the index"
git -C "$repo" add -A
commit -m edits
passed HEAD || fail "the commit holding the recorded edits didn't pass"
passed HEAD~ || fail "an earlier recorded commit stopped passing"

# A commit holding only some of the recorded edits, or a later edit, didn't pass.
echo three > "$repo/a.txt"
echo three > "$repo/b.txt"
record
git -C "$repo" add a.txt
commit -m "half the edits"
passed HEAD && fail "a commit holding half the recorded edits passed"
git -C "$repo" checkout -q b.txt

# A branch merged with a newer main is a tree neither side passed as.
git -C "$repo" switch -q -c side
echo side > "$repo/c.txt"; git -C "$repo" add c.txt; commit -m side
record
git -C "$repo" switch -q main
echo main > "$repo/d.txt"; git -C "$repo" add d.txt; commit -m main
record
git -C "$repo" switch -q side
git -C "$repo" -c user.name=t -c user.email=t@t merge -q -m merge main
passed HEAD && fail "a merge with a newer main passed, though only each side was checked"
passed HEAD^1 || fail "the branch before the merge didn't pass"
merged="$(git -C "$repo" rev-parse HEAD)"

# A worktree's pass counts in the main clone: they share the record.
git -C "$repo" worktree add -q "$fake/wt" "$merged" 2> /dev/null
"$fake/wt/bin/check-passed" --record || fail "--record in a worktree: exit $?"
passed "$merged" || fail "a worktree's pass didn't count in the main clone"

# The push hook: a push to main needs a pass of that commit, or
# IRIS_UNCHECKED; any other push, or a delete, goes through.
zero=0000000000000000000000000000000000000000
push() { # push <remote ref> <local sha> <remote sha>
    (cd "$repo" && echo "refs/heads/x $2 $1 $3" | .githooks/pre-push origin url 2>&1)
}
echo late > "$repo/a.txt"; git -C "$repo" add a.txt; commit -m "unchecked"
head="$(git -C "$repo" rev-parse HEAD)"
out="$(push refs/heads/main "$head" "$merged")" && fail "pre-push: let an unchecked commit to main through"
grep -qF "${head:0:7}" <<< "$out" || { fail "pre-push: refusal doesn't name the commit:"; echo "$out" | sed 's/^/  /'; }
push refs/heads/main "$head" "$zero" > /dev/null && fail "pre-push: let an unchecked commit through as main's first"
push refs/heads/side "$head" "$merged" > /dev/null || fail "pre-push: refused a push to a branch other than main"
push refs/heads/main "$zero" "$merged" > /dev/null || fail "pre-push: refused deleting a ref"
out="$(IRIS_UNCHECKED="CI only" push refs/heads/main "$head" "$merged")" || fail "pre-push: refused with IRIS_UNCHECKED set"
grep -qF "CI only" <<< "$out" || fail "pre-push: didn't repeat IRIS_UNCHECKED's reason"
push refs/heads/main "$merged" "$zero" > /dev/null || fail "pre-push: refused a commit a full pass checked"
