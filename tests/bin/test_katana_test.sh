#!/bin/bash
# bin/katana-test against a fake `ssh` on PATH, run in a throwaway repo. The
# fake keeps the tree it was sent and the command it was given. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_katana_test.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# Records its arguments in $fake/args and its stdin in $fake/tree.tar, and
# exits with the code in $fake/exit-code (0 without one).
mkdir "$fake/bin"
cat > "$fake/bin/ssh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")/.."
printf '%s\n' "$@" > "$dir/args"
cat > "$dir/tree.tar"
exit "$(cat "$dir/exit-code" 2>/dev/null || echo 0)"
EOF
chmod +x "$fake/bin/ssh"

# A repo holding the script, a tracked file and a link like module/bin's.
repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/module/bin"
cp bin/katana-test "$repo/bin/"
echo committed > "$repo/tracked.txt"
ln -s ../../bin/katana-test "$repo/module/bin/link"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm fixture
run() { (cd "$repo" && PATH="$fake/bin:$PATH" bin/katana-test 2>&1); }
fail() { echo "katana-test $1"; }

# A clean tree sends HEAD, links kept as links.
run > /dev/null || fail "clean tree: exit $?, expected 0"
tar tvf "$fake/tree.tar" | grep -q '^l.* module/bin/link -> \.\./\.\./bin/katana-test' ||
    fail "sent module/bin/link as something other than a link"
tar xOf "$fake/tree.tar" tracked.txt | grep -qx committed || fail "clean tree: tracked.txt isn't HEAD's"

# Uncommitted edits to tracked files go; untracked files stay behind.
echo edited > "$repo/tracked.txt"
echo new > "$repo/untracked.txt"
run > /dev/null
tar xOf "$fake/tree.tar" tracked.txt | grep -qx edited || fail "didn't send the uncommitted edit"
! tar tf "$fake/tree.tar" | grep -q untracked.txt || fail "sent an untracked file"
[ "$(git -C "$repo" stash list | wc -l)" = 0 ] || fail "left a stash entry"
grep -qx edited "$repo/tracked.txt" || fail "changed the working tree"

# A new file under workflows/ or module/ that git doesn't track is named,
# since a form test there would be skipped.
mkdir -p "$repo/workflows/new/tests"
echo "# test" > "$repo/workflows/new/tests/test_form.rb"
run | grep -qF "workflows/new/tests/test_form.rb" || fail "didn't name an untracked file under workflows/"
rm -r "$repo/workflows"

# Run from elsewhere, it sends its own clone.
(cd / && PATH="$fake/bin:$PATH" "$repo/bin/katana-test" > /dev/null 2>&1) || fail "failed when run from outside its clone"
tar xOf "$fake/tree.tar" tracked.txt | grep -qx edited || fail "run from elsewhere: didn't send its own clone"

# On Katana: a folder of its own in scratch, deleted on exit, and both tests.
grep -qF 'mktemp -d "/srv/scratch/$USER/' "$fake/args" || fail "doesn't make its own scratch folder"
grep -qF 'trap' "$fake/args" && grep -qF 'rm -rf "$d"' "$fake/args" || fail "doesn't delete its folder on exit"
grep -qF 'workflows/*/tests/test_form.rb' "$fake/args" || fail "doesn't run the form tests"
grep -qF 'module/tests/test_module.sh' "$fake/args" || fail "doesn't run the module test"

# A failing test on Katana fails the script.
echo 1 > "$fake/exit-code"
if run > /dev/null; then fail "exit 0 when a test failed on Katana"; fi
