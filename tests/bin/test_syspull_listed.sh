#!/bin/bash
# bin/syspull's record of the origin/main each listing ran against, and
# .githooks/pre-push's refusal of a push to main with no listing since main
# last moved, in a throwaway repo against a fake `ssh` on PATH. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_syspull_listed.sh
#
# bin/check name: syspull listed test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
. tests/bin/lib.sh

# The listing names origin/main as $fake/main holds it, first, as Katana's
# side of bin/syspull does. A file named ssh-down makes it fail as ssh does.
cat > "$fake/ssh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
[ -e "$dir/ssh-down" ] && { echo "ssh: connect to host katana: Connection refused" >&2; exit 255; }
if [ "$2" = bash ] || [ "$2" = python3 ]; then cat > /dev/null; exit 0; fi
echo "origin/main $(cat "$dir/main")"
echo "System clone /x/code: main at 1234567 fixture"
echo "To deploy them: bin/syspull --apply 89abcde"
EOF
chmod +x "$fake/ssh"

repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/lib" "$repo/.githooks"
cp bin/syspull bin/syspull-pins.sh bin/pilot-readable.py "$repo/bin/"
cp lib/katana.sh "$repo/lib/"
# A digest map of IRIS's own, so a branch whose real map names an author's
# container, as each author's pull request does, doesn't make pre-push
# refuse every push to main here for that.
digest_map "$repo/lib/katana.sh" "ct/1=sha256:$(printf 'a%.0s' {1..64})" || exit 1
cp .githooks/pre-push "$repo/.githooks/"
git -C "$repo" init -q -b main
git -C "$repo" add -A
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -q "$@"; }
commit -m fixture
old="$(git -C "$repo" rev-parse HEAD)"
commit --allow-empty -m next
new="$(git -C "$repo" rev-parse HEAD)"
zero=0000000000000000000000000000000000000000
fail() { echo "syspull listed: $1"; }
listing() { (cd "$repo" && PATH="$fake:$PATH" bin/syspull 2>&1); }
push() { # push <remote ref> <local sha> <remote sha>
    (cd "$repo" && echo "refs/heads/x $2 $1 $3" | .githooks/pre-push origin url 2>&1)
}

# No listing yet: --listed says no, not a usage error, and a push to main
# is refused, naming main's commit.
(cd "$repo" && bin/syspull --listed "$old"); [ $? = 1 ] || fail "--listed with no record yet: not 1"
out="$(push refs/heads/main "$new" "$old")" && fail "pre-push let a push to main through with no listing"
grep -qF "${old:0:7}" <<< "$out" || { fail "the refusal doesn't name main's commit:"; echo "$out" | sed 's/^/  /'; }
grep -qF "bin/syspull" <<< "$out" || fail "the refusal doesn't name bin/syspull"

# A listing against main as the push finds it lets the push through, and
# shows the listing without the line it records from.
echo "$old" > "$fake/main"
out="$(listing)" || fail "the listing failed: $out"
grep -qF "System clone /x/code" <<< "$out" || fail "the listing wasn't shown: $out"
grep -q "^origin/main " <<< "$out" && fail "the listing shows its origin/main record line"
push refs/heads/main "$new" "$old" > /dev/null || fail "pre-push refused a push to main listed against"

# Main moved since the listing: refused until a new one.
push refs/heads/main "$new" "$new" > /dev/null && fail "pre-push let a push through after main moved since the listing"
echo "$new" > "$fake/main"
listing > /dev/null
push refs/heads/main "$new" "$new" > /dev/null || fail "pre-push refused after a new listing"

# A deploy clears the record: the listing after one push, run before its
# --apply, never counts for the next push.
(cd "$repo" && PATH="$fake:$PATH" bin/syspull --apply "${new:0:7}" > /dev/null 2>&1) || fail "--apply failed"
push refs/heads/main "$new" "$new" > /dev/null && fail "a listing from before the last deploy let the next push through"
listing > /dev/null

# --listed answers for a full commit only.
(cd "$repo" && bin/syspull --listed "$new") || fail "--listed: no for a listed commit"
(cd "$repo" && bin/syspull --listed "$old"); [ $? = 1 ] || fail "--listed: not 1 for an unlisted commit"
(cd "$repo" && bin/syspull --listed "${new:0:7}" 2> /dev/null); [ $? = 2 ] || fail "--listed: a short commit isn't a usage error"

# IRIS_NO_SYSPULL lets one through, repeating its reason; other branches,
# deletes and main's first commit need no listing.
other="$(printf 'f%.0s' {1..40})"
out="$(IRIS_NO_SYSPULL="Katana down" push refs/heads/main "$new" "$other")" || fail "pre-push refused with IRIS_NO_SYSPULL set"
grep -qF "Katana down" <<< "$out" || fail "pre-push didn't repeat IRIS_NO_SYSPULL's reason"
push refs/heads/side "$new" "$other" > /dev/null || fail "pre-push refused a push to another branch"
push refs/heads/main "$zero" "$other" > /dev/null || fail "pre-push refused deleting a ref"
push refs/heads/main "$new" "$zero" > /dev/null || fail "pre-push refused main's first commit"

# A listing that fails records nothing and keeps ssh's exit status.
echo "$other" > "$fake/main"
touch "$fake/ssh-down"
listing > /dev/null; rc=$?
[ "$rc" = 255 ] || fail "a failed listing exited $rc, not ssh's 255"
rm "$fake/ssh-down"
push refs/heads/main "$new" "$other" > /dev/null && fail "a failed listing was recorded"

# A worktree's listing counts in the main clone: they share the record.
git -C "$repo" worktree add -q "$fake/wt" HEAD 2> /dev/null
(cd "$fake/wt" && PATH="$fake:$PATH" bin/syspull > /dev/null 2>&1)
push refs/heads/main "$new" "$other" > /dev/null || fail "a worktree's listing didn't count in the main clone"
