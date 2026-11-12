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
# exits with the code in $fake/exit-code (0 without one); to katana-dm, in
# $fake/dm-args and $fake/dm-stdin, exiting with $fake/dm-exit-code's. With
# $fake/run-remote, it runs the command it was given instead, on the tree,
# with /srv/scratch/$USER as $fake/scratch, a module system that loads
# nothing and the log wait cut to $fake/run-remote's seconds.
mkdir "$fake/bin" "$fake/scratch"
cat > "$fake/bin/ssh" <<'EOF'
#!/bin/bash
dir="$(cd "$(dirname "$0")/.." && pwd)"
# The data mover only ever gets the stand-in container's pull, kept apart.
if [ "$1" = katana-dm ]; then
    printf '%s\n' "$@" > "$dir/dm-args"
    cat > "$dir/dm-stdin"
    exit "$(cat "$dir/dm-exit-code" 2>/dev/null || echo 0)"
fi
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

# A repo holding the script, the push hook, a tracked file and a link like
# module/bin's.
repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/module/bin" "$repo/module/tests" "$repo/lib/tests/katana" "$repo/.githooks"
cp bin/katana-test "$repo/bin/"
cp .githooks/pre-push "$repo/.githooks/"
cp lib/tests/katana/stand-in.sh "$repo/lib/tests/katana/"
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

# The stand-in container the job-library test runs in goes down through the
# data mover, before anything runs on Katana, and a failed pull stops it.
grep -qxF -- "bash -s -- --pull" "$fake/dm-args" && cmp -s "$fake/dm-stdin" lib/tests/katana/stand-in.sh ||
    fail "doesn't send lib/tests/katana/stand-in.sh --pull to katana-dm"
rm "$fake/args"
echo 1 > "$fake/dm-exit-code"
if run > /dev/null; then fail "exit 0 when the stand-in container's pull failed"; fi
[ ! -f "$fake/args" ] || fail "ran on Katana after the stand-in container's pull failed"
rm "$fake/dm-exit-code"

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

# A passing run records the tree it tested, by the tested files alone, and
# a failing one records nothing.
rm -f "$fake/no-log" "$fake/run-remote" "$fake/exit-code"
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -qam "$1"; }
tested() { (cd "$repo" && bin/katana-test --tested "$@"); }
commit "state so far"
run > /dev/null || fail "clean tree before the stamp cases: exit $?, expected 0"
tested || fail "--tested: exit $?, expected 0 for the tree a passing run tested"
tested HEAD HEAD || fail "--tested HEAD HEAD: exit $?, expected 0"
echo again > "$repo/tracked.txt"; commit "an untested file"
tested || fail "--tested: exit $? after a change to an untested file, expected 0"
echo 'exit 0 # edited' > "$repo/module/tests/test_module.sh"; commit "a tested file"
if tested; then fail "--tested: exit 0 after a change to module/"; fi
if tested HEAD HEAD~; then fail "--tested HEAD HEAD~: exit 0, though module/ differs from the base"; fi
tested HEAD~ HEAD~2 || fail "--tested HEAD~ HEAD~2: exit $?, expected 0 for unchanged tested files"
echo 1 > "$fake/exit-code"
run > /dev/null
if tested; then fail "--tested: exit 0 after a failing run"; fi
rm "$fake/exit-code"
mkdir -p "$repo/workflows/seg/lib/iris" "$repo/workflows/seg/tests" "$repo/lib/tests/katana"
# The tests it runs count too: 3c1201f changed lib/tests/form_helper.rb alone,
# went to main untested and failed a form test there (#172).
for f in workflows/seg/form.yml.erb workflows/seg/lib/katana.sh workflows/seg/lib/iris/rundir.py lib/iris-job.sh \
    workflows/seg/tests/test_form.rb lib/tests/form_helper.rb lib/tests/test_job_lib.py lib/tests/katana/job_lib.pbs; do
    run > /dev/null
    echo "# $f" >> "$repo/$f"; git -C "$repo" add "$f"; commit "$f"
    if tested; then fail "--tested: exit 0 after a change to $f"; fi
done

# The push hook: a push to main whose tested files changed needs a passing
# run of that commit, or IRIS_KATANA_UNTESTED; any other push goes through.
# A checkout whose bin/katana-test has no --tested says so.
zero=0000000000000000000000000000000000000000
push() { # push <remote ref> <local sha> <remote sha>
    (cd "$repo" && echo "refs/heads/x $2 $1 $3" | .githooks/pre-push origin url 2>&1)
}
head="$(git -C "$repo" rev-parse HEAD)" prev="$(git -C "$repo" rev-parse HEAD~)"
out="$(push refs/heads/main "$head" "$prev")" && fail "pre-push: let an untested change to main through"
grep -qF "${head:0:7}" <<< "$out" || { fail "pre-push: refusal doesn't name the commit:"; echo "$out" | sed 's/^/  /'; }
push refs/heads/main "$head" "$zero" > /dev/null && fail "pre-push: let an untested commit through as main's first"
push refs/heads/spec "$head" "$prev" > /dev/null || fail "pre-push: refused a push to a branch other than main"
push refs/heads/main "$zero" "$prev" > /dev/null || fail "pre-push: refused deleting a ref"
out="$(IRIS_KATANA_UNTESTED="Katana down" push refs/heads/main "$head" "$prev")" ||
    fail "pre-push: refused with IRIS_KATANA_UNTESTED set"
grep -qF "Katana down" <<< "$out" || fail "pre-push: didn't repeat IRIS_KATANA_UNTESTED's reason"
run > /dev/null
push refs/heads/main "$head" "$prev" > /dev/null || fail "pre-push: refused a commit a passing run tested"
echo late > "$repo/tracked.txt"; commit "untested file after the run"
push refs/heads/main "$(git -C "$repo" rev-parse HEAD)" "$head" > /dev/null || fail "pre-push: refused a change to untested files only"
cp "$repo/bin/katana-test" "$fake/katana-test"
printf '#!/bin/bash\necho "usage: bin/katana-test" >&2; exit 2\n' > "$repo/bin/katana-test"
out="$(push refs/heads/main "$head" "$prev")" && fail "pre-push: let a push through with a bin/katana-test that has no --tested"
grep -qF "has no --tested" <<< "$out" || { fail "pre-push: didn't say bin/katana-test has no --tested:"; echo "$out" | sed 's/^/  /'; }
cp "$fake/katana-test" "$repo/bin/katana-test"

# A workflow's own tests and code outside lib/ aren't the library's.
run > /dev/null
mkdir -p "$repo/workflows/seg/tests" "$repo/workflows/seg/src"
for f in workflows/seg/tests/test_synthetic.py workflows/seg/src/run.py; do
    echo "# $f" >> "$repo/$f"; git -C "$repo" add "$f"; commit "$f"
    tested || fail "--tested: exit $? after a change to $f only, expected 0"
done
