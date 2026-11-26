#!/bin/bash
# bin/ciwait against a fake `gh` on PATH, in a throwaway repo pushed to a
# throwaway origin. Prints each failed case and nothing on success, so
# bin/check can run it.
#
#   tests/bin/test_ciwait.sh
#
# bin/check name: ciwait test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# The fake lists the runs in $fake/runs, "<id> <event> <branch>" lines, as
# workflow $fake/workflow's runs of the commit --commit names; watch exits
# with $fake/conclusion (0 without one), or 1 for a run with a
# $fake/fail-<id>, and moves $fake/late's runs into $fake/runs, as GitHub
# lists a run that starts mid-wait; view --log holds a publish line among
# others. Each call must name unsw-restech/iris, not the current
# directory's repo, or the fake rejects it (#207), or the repo in
# $fake/ghrepo when there is one; it then drops the flag, so the cases
# below read the arguments ciwait gave otherwise. pr view, for the PR in
# $fake/pr, prints its head from $fake/prhead or its labels from
# $fake/labels, one a line, as --jq would, and moves $fake/late-labels'
# labels in after the first ask, as ready.yml labels a PR after its run.
mkdir "$fake/bin"
cat > "$fake/bin/gh" <<'FAKE'
#!/bin/bash
dir="$(cd "$(dirname "$0")/.." && pwd)"
want="$(cat "$dir/ghrepo" 2> /dev/null || echo unsw-restech/iris)"
args=() named=""
while [ $# -gt 0 ]; do
    if [ "$1" = -R ] && [ "${2-}" = "$want" ]; then named=1; shift 2
    else args+=("$1"); shift; fi
done
[ -n "$named" ] || { echo "fake gh: no -R $want: ${args[*]}" >&2; exit 1; }
set -- "${args[@]}"
case "$1 $2" in
    "run list")
        [ "$5 $6" = "--commit $(cat "$dir/sha")" ] || { echo "fake gh: run list without --commit <HEAD>: $*" >&2; exit 1; }
        if [ "$4" = "$(cat "$dir/workflow").yml" ]; then cat "$dir/runs"; fi ;;
    "run watch")
        if [ -f "$dir/late" ]; then cat "$dir/late" >> "$dir/runs"; rm "$dir/late"; fi
        [ ! -f "$dir/fail-$3" ] || exit 1
        exit "$(cat "$dir/conclusion" 2>/dev/null || echo 0)" ;;
    "run view")
        if [ "$4" = --log ]; then
            printf 'publish\tPush\t2026-11-09T01:00:00.0Z %s\n' \
                '  echo "Published $ref as $IRIS_ENV_REGISTRY@$digest"' \
                'Published ghcr.io/o/iris-env:microct-1 as ghcr.io/o/iris-env@sha256:abc'
        elif [ "$4" = --log-failed ]; then
            printf 'check\tRun\t2026-11-09T01:00:00.0Z the failing step\n'
        else
            echo "run $3 summary"
        fi ;;
    "pr view")
        [ "$3" = "$(cat "$dir/pr")" ] || { echo "fake gh: no pull request $3" >&2; exit 1; }
        case "$5" in
            headRefOid) cat "$dir/prhead" ;;
            labels)
                cat "$dir/labels"
                if [ -f "$dir/late-labels" ]; then cat "$dir/late-labels" >> "$dir/labels"; rm "$dir/late-labels"; fi ;;
            *) exit 1 ;;
        esac ;;
esac
FAKE
printf '#!/bin/sh\n' > "$fake/bin/sleep"
chmod +x "$fake/bin/gh" "$fake/bin/sleep"
# The fake's --jq stands in for the real filter: it prints the runs only
# when the workflow matches. HEAD is origin/main's tip, so main's push run
# is among them.
echo "7 push main" > "$fake/runs"

repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/.github/workflows"
cp bin/ciwait bin/github-repo.sh "$repo/bin/"
touch "$repo/.github/workflows/check.yml" "$repo/.github/workflows/containers.yml"
git init -q --bare "$fake/origin.git"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm fixture
git -C "$repo" remote add origin "$fake/origin.git"
git -C "$repo" push -q origin HEAD:refs/heads/main 2> /dev/null
git -C "$repo" rev-parse HEAD > "$fake/sha"
sha="$(git -C "$repo" rev-parse --short HEAD)"
run() { (cd "$repo" && PATH="$fake/bin:$PATH" bin/ciwait "$@" 2>&1); }
fail() { echo "ciwait $1"; }

echo check > "$fake/workflow"
out="$(run)" || fail "check passing: exit $?, expected 0"
[ "$(tail -1 <<< "$out")" = "ciwait: check $sha passed" ] || { fail "check passing: last line isn't the verdict:"; echo "$out" | sed 's/^/  /'; }
! grep -q '^Published' <<< "$out" || fail "printed publish lines for check"

echo containers > "$fake/workflow"
out="$(run --workflow containers)" || fail "containers passing: exit $?, expected 0"
grep -qx 'Published ghcr.io/o/iris-env:microct-1 as ghcr.io/o/iris-env@sha256:abc' <<< "$out" ||
    { fail "containers passing: didn't print the publish line:"; echo "$out" | sed 's/^/  /'; }
[ "$(grep -c 'Published' <<< "$out")" = 1 ] || fail "containers passing: printed the step's echo command too"
[ "$(tail -1 <<< "$out")" = "ciwait: containers $sha passed" ] || fail "containers passing: last line isn't the verdict"

# A branch's run publishes nothing, and says so.
printf '#!/bin/bash\nfor a; do [ "$a" = --log ] && exit 0; done\nexec "%s" "$@"\n' "$fake/bin/gh" > "$fake/gh-nolog"
mkdir "$fake/nolog"; mv "$fake/gh-nolog" "$fake/nolog/gh"; chmod +x "$fake/nolog/gh"
out="$(cd "$repo" && PATH="$fake/nolog:$fake/bin:$PATH" bin/ciwait --workflow containers 2>&1)" || fail "containers passing on a branch: exit $?, expected 0"
grep -qx "No Published line: this run published nothing." <<< "$out" || fail "containers passing on a branch: didn't say nothing was published"

echo 1 > "$fake/conclusion"
out="$(run --workflow containers HEAD)"; rc=$?
[ "$rc" = 1 ] || fail "containers failing: exit $rc, expected 1"
grep -qx 'the failing step' <<< "$out" || fail "containers failing: didn't print the failed log"
[ "$(tail -1 <<< "$out")" = "ciwait: containers $sha failed (run 7)" ] || fail "containers failing: last line isn't the verdict"
rm "$fake/conclusion"

# --workflow may come before or after the commit; a second commit, a
# --workflow with no name or any other option is a usage error.
out="$(run HEAD --workflow containers)" || fail "commit before --workflow: exit $?, expected 0"
[ "$(tail -1 <<< "$out")" = "ciwait: containers $sha passed" ] || { fail "commit before --workflow: last line isn't the containers verdict:"; echo "$out" | sed 's/^/  /'; }
for args in "HEAD HEAD" "HEAD --workflow" "--workflow=containers"; do
    # shellcheck disable=SC2086
    out="$(run $args)"; rc=$?
    [ "$rc" = 2 ] && grep -qF usage: <<< "$out" || fail "$args: exit $rc, expected 2 with usage"
done

# The run is looked up under the workflow asked for: check's run isn't
# containers'.
echo check > "$fake/workflow"
out="$(run --workflow containers)"; rc=$?
[ "$rc" = 2 ] || fail "no containers run: exit $rc, expected 2"
grep -qF "no containers run for $sha" <<< "$out" || fail "no containers run: didn't say so"

out="$(run --workflow nonesuch)"; rc=$?
[ "$rc" = 2 ] && grep -qF usage: <<< "$out" || fail "unknown workflow: exit $rc, expected 2 with usage"

# Every run of the commit is waited for, whatever its event: a failing
# pull_request run fails it, beside passing push runs (#250).
printf '%s\n' "7 push main" "8 pull_request 9-fix" "9 push 9-fix" > "$fake/runs"
touch "$fake/fail-8"
out="$(run)"; rc=$?
[ "$rc" = 1 ] || fail "failing pull_request run: exit $rc, expected 1"
for id in 7 8 9; do
    grep -q "^== check run $id " <<< "$out" || fail "failing pull_request run: didn't wait for run $id"
done
grep -qx "== check run 8 (pull_request, 9-fix) for $sha" <<< "$out" || fail "failing pull_request run: didn't name its event and branch"
grep -qx 'the failing step' <<< "$out" || fail "failing pull_request run: didn't print the failed log"
[ "$(tail -1 <<< "$out")" = "ciwait: check $sha failed (run 8)" ] || { fail "failing pull_request run: last line isn't the verdict:"; echo "$out" | sed 's/^/  /'; }
touch "$fake/fail-9"
out="$(run)"
[ "$(tail -1 <<< "$out")" = "ciwait: check $sha failed (run 8, 9)" ] || fail "two failing runs: last line doesn't name both"
rm "$fake/fail-8" "$fake/fail-9"

# A run that GitHub lists only after the first wait is waited for too.
echo "7 push main" > "$fake/runs"
echo "8 pull_request 9-fix" > "$fake/late"
out="$(run)" || fail "late run: exit $?, expected 0"
grep -q "^== check run 8 " <<< "$out" || fail "late run: didn't wait for it"
[ "$(grep -c '^== check run 7 ' <<< "$out")" = 1 ] || fail "late run: waited for run 7 twice"
echo "7 push main" > "$fake/runs"
echo "8 pull_request 9-fix" > "$fake/late"
touch "$fake/fail-8"
out="$(run)"; rc=$?
[ "$rc" = 1 ] || fail "failing late run: exit $rc, expected 1"
[ "$(tail -1 <<< "$out")" = "ciwait: check $sha failed (run 8)" ] || fail "failing late run: last line doesn't name it"
rm "$fake/fail-8"

# At origin/main's tip, a branch's finished runs don't stand in for main's
# push run: with none of main's, it waits, then says so.
printf '%s\n' "8 pull_request 9-fix" "9 push 9-fix" > "$fake/runs"
out="$(run)"; rc=$?
[ "$rc" = 2 ] || fail "no main push run: exit $rc, expected 2"
grep -qF "no check run of main's push for $sha" <<< "$out" || fail "no main push run: didn't say so"

# Off main's tip, a branch's runs are enough.
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m branch
git -C "$repo" push -q origin HEAD:refs/heads/9-fix 2> /dev/null
git -C "$repo" rev-parse HEAD > "$fake/sha"
sha="$(git -C "$repo" rev-parse --short HEAD)"
out="$(run)" || fail "branch commit: exit $?, expected 0"
[ "$(tail -1 <<< "$out")" = "ciwait: check $sha passed" ] || { fail "branch commit: last line isn't the verdict:"; echo "$out" | sed 's/^/  /'; }

# --pr waits on a pull request's head, which an author's fork holds, so it
# isn't on origin, then for the ready label (#201).
echo 257 > "$fake/pr"
printf 'f%.0s' {1..40} > "$fake/prhead"
cp "$fake/prhead" "$fake/sha"
psha=fffffff
echo "8 pull_request 201-author" > "$fake/runs"
printf '%s\n' outside-folder ready > "$fake/labels"
out="$(run --pr 257)" || { fail "--pr ready: exit $?, expected 0:"; echo "$out" | sed 's/^/  /'; }
grep -qx "== check run 8 (pull_request, 201-author) for $psha" <<< "$out" || fail "--pr ready: didn't wait for the PR's run"
[ "$(tail -1 <<< "$out")" = "ciwait: check $psha passed; #257 is ready" ] || { fail "--pr ready: last line isn't the verdict:"; echo "$out" | sed 's/^/  /'; }
echo outside-folder > "$fake/labels"
echo ready > "$fake/late-labels"
out="$(run --pr 257)" || fail "--pr ready late: exit $?, expected 0"
[ "$(tail -1 <<< "$out")" = "ciwait: check $psha passed; #257 is ready" ] || fail "--pr ready late: last line isn't the verdict"
echo outside-folder > "$fake/labels"
out="$(run --pr 257)"; rc=$?
[ "$rc" = 2 ] && [ "$(tail -1 <<< "$out")" = "ciwait: check $psha passed; #257 isn't ready after 2 min" ] ||
    { fail "--pr never ready: exit $rc, expected 2 saying so:"; echo "$out" | sed 's/^/  /'; }
touch "$fake/fail-8"
out="$(run --pr 257)"; rc=$?
[ "$rc" = 1 ] && [ "$(tail -1 <<< "$out")" = "ciwait: check $psha failed (run 8)" ] ||
    { fail "--pr failing run: exit $rc, expected 1 naming run 8:"; echo "$out" | sed 's/^/  /'; }
rm "$fake/fail-8"
out="$(run --pr 258)"; rc=$?
[ "$rc" = 2 ] && grep -qF "ciwait: no head for #258" <<< "$out" || fail "--pr unknown: exit $rc, expected 2 saying so"
for args in "--pr 257 HEAD" "HEAD --pr 257" "--pr 257 --repo ." "--pr" "--pr x" "--pr 257 --pr 258"; do
    # shellcheck disable=SC2086
    out="$(run $args)"; rc=$?
    [ "$rc" = 2 ] && grep -qF usage: <<< "$out" || fail "$args: exit $rc, expected 2 with usage"
done

# A commit not on origin is refused, naming --pr for a fork's head.
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m local
out="$(run)"; rc=$?
[ "$rc" = 2 ] && grep -qF "is not on origin; push it first, or, for a pull request's head on a fork, wait with --pr <n>" <<< "$out" ||
    { fail "unpushed commit: exit $rc, expected 2 naming --pr:"; echo "$out" | sed 's/^/  /'; }

# --repo waits on another clone's CI: its commit, its origin/main and its
# only workflow, under the GitHub repo its origin's URL names, resolving a
# relative path from the caller's directory. The fork's origin is a GitHub
# URL that insteadOf points at a local bare repo, so it fetches offline.
fork="$fake/OpenComposer"
mkdir -p "$fork/.github/workflows"
touch "$fork/.github/workflows/tests.yml"
git init -q --bare "$fake/fork.git"
git -C "$fork" init -q
git -C "$fork" config url."$fake/fork.git".insteadOf https://github.com/unsw-restech/OpenComposer.git
git -C "$fork" remote add origin https://github.com/unsw-restech/OpenComposer.git
git -C "$fork" add -A
git -C "$fork" -c user.name=t -c user.email=t@t commit -qm fork
git -C "$fork" push -q origin HEAD:refs/heads/main 2> /dev/null
git -C "$fork" rev-parse HEAD > "$fake/sha"
fsha="$(git -C "$fork" rev-parse --short HEAD)"
echo unsw-restech/OpenComposer > "$fake/ghrepo"
echo tests > "$fake/workflow"
echo "7 push main" > "$fake/runs"
out="$(run --repo ../OpenComposer)" || { fail "--repo: exit $?, expected 0:"; echo "$out" | sed 's/^/  /'; }
[ "$(tail -1 <<< "$out")" = "ciwait: tests $fsha passed" ] || { fail "--repo: last line isn't the fork's tests verdict:"; echo "$out" | sed 's/^/  /'; }
printf '%s\n' "7 push main" "8 pull_request 9-fix" > "$fake/runs"
touch "$fake/fail-8"
out="$(run --repo ../OpenComposer)"; rc=$?
[ "$rc" = 1 ] && [ "$(tail -1 <<< "$out")" = "ciwait: tests $fsha failed (run 8)" ] ||
    { fail "--repo, failing pull_request run: exit $rc, expected 1 naming run 8:"; echo "$out" | sed 's/^/  /'; }
rm "$fake/fail-8"

# A repo with neither check.yml nor a single workflow needs --workflow.
touch "$fork/.github/workflows/other.yml"
out="$(run --repo ../OpenComposer)"; rc=$?
[ "$rc" = 2 ] && grep -qF "name it with --workflow" <<< "$out" || fail "--repo, two workflows: exit $rc, expected 2 asking for --workflow"
echo "7 push main" > "$fake/runs"
out="$(run --repo ../OpenComposer --workflow tests)" || fail "--repo --workflow tests: exit $?, expected 0"
rm "$fork/.github/workflows/other.yml"

# A path outside any repo, or an origin that isn't on GitHub, says so.
mkdir "$fake/plain"
out="$(run --repo ../plain)"; rc=$?
[ "$rc" = 2 ] && grep -qF "ciwait: ../plain isn't in a git repo" <<< "$out" || fail "--repo outside a repo: exit $rc, expected 2 saying so"
git -C "$fork" remote set-url origin "$fake/fork.git"
out="$(run --repo ../OpenComposer)"; rc=$?
[ "$rc" = 2 ] && grep -qF "isn't a GitHub repo" <<< "$out" || fail "--repo, local origin: exit $rc, expected 2 saying so"
