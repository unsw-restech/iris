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

# The fake lists one run, 7, of workflow $fake/workflow for HEAD's commit;
# watch exits with $fake/conclusion (0 without one); view --log holds a
# publish line among others.
mkdir "$fake/bin"
cat > "$fake/bin/gh" <<'FAKE'
#!/bin/bash
dir="$(cd "$(dirname "$0")/.." && pwd)"
case "$1 $2" in
    "run list")
        [ "$4" = "$(cat "$dir/workflow").yml" ] && cat "$dir/sha" ;;
    "run watch") exit "$(cat "$dir/conclusion" 2>/dev/null || echo 0)" ;;
    "run view")
        if [ "$4" = --log ]; then
            printf 'publish\tPush\t2026-11-09T01:00:00.0Z %s\n' \
                '  echo "Published $ref as $IRIS_ENV_REGISTRY@$digest"' \
                'Published ghcr.io/o/iris-env:microct-1 as ghcr.io/o/iris-env@sha256:abc'
        elif [ "$4" = --log-failed ]; then
            printf 'check\tRun\t2026-11-09T01:00:00.0Z the failing step\n'
        else
            echo "run 7 summary"
        fi ;;
esac
FAKE
printf '#!/bin/sh\n' > "$fake/bin/sleep"
chmod +x "$fake/bin/gh" "$fake/bin/sleep"
# The fake's --jq stands in for the real filter: it prints the run id only
# when the workflow matches.
echo 7 > "$fake/sha"

repo="$fake/repo"
mkdir -p "$repo/bin" "$repo/.github/workflows"
cp bin/ciwait "$repo/bin/"
touch "$repo/.github/workflows/check.yml" "$repo/.github/workflows/containers.yml"
git init -q --bare "$fake/origin.git"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm fixture
git -C "$repo" remote add origin "$fake/origin.git"
git -C "$repo" push -q origin HEAD:refs/heads/main 2> /dev/null
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

echo 1 > "$fake/conclusion"
out="$(run --workflow containers HEAD)"; rc=$?
[ "$rc" = 1 ] || fail "containers failing: exit $rc, expected 1"
grep -qx 'the failing step' <<< "$out" || fail "containers failing: didn't print the failed log"
[ "$(tail -1 <<< "$out")" = "ciwait: containers $sha failed (run 7)" ] || fail "containers failing: last line isn't the verdict"
rm "$fake/conclusion"

# The run is looked up under the workflow asked for: check's run isn't
# containers'.
echo check > "$fake/workflow"
out="$(run --workflow containers)"; rc=$?
[ "$rc" = 2 ] || fail "no containers run: exit $rc, expected 2"
grep -qF "no containers run for $sha" <<< "$out" || fail "no containers run: didn't say so"

out="$(run --workflow nonesuch)"; rc=$?
[ "$rc" = 2 ] && grep -qF usage: <<< "$out" || fail "unknown workflow: exit $rc, expected 2 with usage"
