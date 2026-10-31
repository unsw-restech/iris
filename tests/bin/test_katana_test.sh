#!/bin/bash
# bin/katana-test against a fake `ssh` on PATH, run in a throwaway repo. The
# fake keeps the tree it was sent and the command it was given; with
# $fake/run-remote it also runs that command here, Katana's scratch, module
# system and qsub swapped for fakes. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_katana_test.sh
#
# bin/check name: katana-test test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# Records its arguments in $fake/args and its stdin in $fake/tree.tar, and
# exits with the code in $fake/exit-code (0 without one). With
# $fake/run-remote, it runs the command it was given instead, on the tree,
# with /srv/scratch/$USER as $fake/scratch, a module system that loads
# nothing and the log wait cut to $fake/run-remote's seconds.
mkdir "$fake/bin" "$fake/scratch"
cat > "$fake/bin/ssh" <<'EOF'
#!/bin/bash
dir="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$@" > "$dir/args"
cat > "$dir/tree.tar"
if [ -f "$dir/run-remote" ]; then
    cmd="$(sed -e "s|/srv/scratch/[$]USER|$dir/scratch|g" -e "s|/etc/profile.d/modules.sh|$dir/modules.sh|g" \
        -e "s|log_wait=[0-9]*|log_wait=$(cat "$dir/run-remote")|" <<< "${*: -1}")"
    exec bash -c "$cmd" < "$dir/tree.tar"
fi
exit "$(cat "$dir/exit-code" 2>/dev/null || echo 0)"
EOF
echo 'module() { :; }' > "$fake/modules.sh"
# Like qsub -W block=true, returns once the job has run, with its exit
# status; but PBS copies the -o log into place later, so the fake writes it
# a second after returning, or never with $fake/no-log.
cat > "$fake/bin/qsub" <<'EOF'
#!/bin/bash
dir="$(cd "$(dirname "$0")/.." && pwd)"
while [ $# -gt 1 ]; do [ "$1" = -o ] && log="$2"; shift; done
[ -f "$dir/no-log" ] || { sleep 1; printf '%s\n' "test_one (test_job_lib.T) ... ok" "exit 0 12:00:00" > "$log"; } &
exit 0
EOF
chmod +x "$fake/bin/ssh" "$fake/bin/qsub"

# A repo holding the script, a tracked file and a link like module/bin's.
repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/module/bin" "$repo/module/tests"
cp bin/katana-test "$repo/bin/"
echo 'exit 0' > "$repo/module/tests/test_module.sh"
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
grep -qF 'git init -q' "$fake/args" || fail "doesn't make the tree a repo for the job-library test"
# The library's Katana job is submitted once, from lib/tests, never once per
# workflow.
grep -qF 'lib/tests/katana/job_lib.pbs' "$fake/args" || fail "doesn't submit lib/tests/katana/job_lib.pbs"
! grep -qF 'workflows/*/tests/katana' "$fake/args" || fail "submits a Katana job once per workflow"
[ "$(grep -c 'qsub ' "$fake/args")" = 1 ] || fail "has $(grep -c 'qsub ' "$fake/args") qsub lines, expected 1"
grep -q 'qsub .*-W block=true' "$fake/args" || fail "doesn't wait on the job-library test"
grep -q 'qsub .*-m abe' "$fake/args" || fail "submits the job-library test without -m abe"

# A failing test on Katana fails the script.
echo 1 > "$fake/exit-code"
if run > /dev/null; then fail "exit 0 when a test failed on Katana"; fi

# Run there: the job-library log, which PBS delivers after qsub returns, is
# waited for and shown.
rm "$fake/exit-code"
mkdir -p "$repo/workflows/seg/tests"
echo 'exit 0' > "$repo/workflows/seg/tests/test_form.rb"
git -C "$repo" add workflows
echo 10 > "$fake/run-remote"
out="$(run)" || fail "on Katana with every test passing: exit $?, expected 0"
grep -qF "test_one (test_job_lib.T) ... ok" <<< "$out" ||
    { fail "didn't show the job-library log PBS delivered after qsub returned:"; echo "$out" | sed 's/^/  /'; }
# A log that never arrives fails, saying so, rather than passing silently.
touch "$fake/no-log"
echo 2 > "$fake/run-remote"
if out="$(run)"; then fail "exit 0 when the job-library log never arrived"; fi
grep -qF "job_lib.log" <<< "$out" || { fail "didn't name the missing job-library log:"; echo "$out" | sed 's/^/  /'; }
[ -z "$(ls "$fake/scratch")" ] || fail "left its scratch folder behind"
