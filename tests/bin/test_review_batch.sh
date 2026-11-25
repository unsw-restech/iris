#!/bin/bash
# bin/review-batch against fixture pull request data: a fake `gh` on PATH
# answers `gh pr list` and `gh pr view` from JSON files as gh prints them,
# a fake `docker` keeps a fake registry's tags in files, a fake
# `apptainer` under the real bin/envrun writes the container file a pull
# names, a fake bin/check runs the real bin/libcopy --check, and a
# throwaway origin holds each PR's head as refs/pull/<n>/head. The listing
# shows each ready PR with its diff and what it flags, ends with the one
# --apply line for the batch, and changes nothing: no merge, no push, no
# container copy, no branch or worktree. --apply merges the batch into a
# branch and worktree of its own, writes an author's container line as its
# digest alone, in lib/katana.sh and in a workflow's library copy, having
# first pulled an author's container into bin/envrun's cache by the
# author's ref unless the cache holds it, and prints the steps that
# follow, which the test runs, the copy and the push, to see them end
# where they promise; a copy alone naming a container whose digest main
# pins is rewritten with nothing to copy. It refuses, leaving nothing
# behind, a PR that moved or lost ready, a batch made before, a merge that
# fails, a pull that fails, an author's container under Docker, chosen as
# bin/envrun chooses it, and a copy naming a container main won't pin, and
# a batch bin/check fails, pushing and copying nothing. --copy leaves a
# tag already at the digest alone and refuses one at another. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_review_batch.sh
#
# bin/check name: review batch test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
. tests/bin/lib.sh
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# Fakes: gh answers `pr list` from $fake/prs.json and `pr view <n>` from
# $fake/view-<n>.json, or fails as gh does when $fake/gh-down exists.
# docker answers `buildx imagetools inspect` for a tag from
# $fake/registry/<tag>, its digest, and `create --tag` writes the source's
# digest there when given --prefer-index=false, or else, as buildx v0.38.1
# did on the desktop (#261), a manifest list's digest followed by " list",
# which inspect then reports with a list's media type; or create is denied
# as ghcr.io denies it when $fake/docker-denied exists. gh, docker and ssh
# each record their arguments, one call a line, in $fake/calls. gh refuses a call that doesn't name unsw-restech/iris,
# as the current directory's repo may be another (#207), and records it
# without the flag.
mkdir "$fake/bin"
cat > "$fake/bin/gh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")/.."
args=() named=""
while [ $# -gt 0 ]; do
    if [ "$1" = -R ] && [ "${2-}" = unsw-restech/iris ]; then named=1; shift 2
    else args+=("$1"); shift; fi
done
set -- "${args[@]}"
echo "gh $*" >> "$dir/calls"
[ -n "$named" ] || { echo "fake gh: no -R unsw-restech/iris: $*" >&2; exit 1; }
[ -e "$dir/gh-down" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
[ "$1 $2" = "pr list" ] && { cat "$dir/prs.json"; exit 0; }
[ "$1 $2" = "pr view" ] && [ -f "$dir/view-$3.json" ] && { cat "$dir/view-$3.json"; exit 0; }
exit 1
EOF
cat > "$fake/bin/docker" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")/.."
echo "docker $*" >> "$dir/calls"
[ "$1 $2" = "buildx imagetools" ] || exit 1
case "$3" in
    inspect)
        tag="${!#}"
        [ -f "$dir/registry/${tag##*:}" ] || { echo "ERROR: $tag: not found" >&2; exit 1; }
        read -r digest kind < "$dir/registry/${tag##*:}"
        type=application/vnd.oci.image.manifest.v1+json
        [ "$kind" != list ] || type=application/vnd.docker.distribution.manifest.list.v2+json
        printf '{"mediaType":"%s","digest":"%s","size":1}\n' "$type" "$digest" ;;
    create)
        shift 3
        dst="" index=1
        while [ $# -gt 1 ]; do
            case "$1" in
                --tag) dst="$2"; shift 2 ;;
                --prefer-index=false) index=""; shift ;;
                *) exit 1 ;;
            esac
        done
        [ -n "$dst" ] || exit 1
        [ ! -e "$dir/docker-denied" ] || { echo "ERROR: denied: permission_denied: write_package" >&2; exit 1; }
        mkdir -p "$dir/registry"
        digest="${1##*@}"
        # buildx's default, --prefer-index=true, wraps one source in a
        # manifest list of its own digest and tags that (#261).
        [ -z "$index" ] || digest="sha256:$(printf 'list of %s' "$digest" | sha256sum | cut -d' ' -f1) list"
        echo "$digest" > "$dir/registry/${dst##*:}" ;;
    *) exit 1 ;;
esac
EOF
printf '#!/bin/bash\necho "ssh $*" >> "$(dirname "$0")/../calls"\nexit 1\n' > "$fake/bin/ssh"
# apptainer, under the real bin/envrun: `pull ... <file> docker://<ref>`
# writes <file>, or fails as Apptainer 1.5.0's pull of a digest ghcr.io
# lacks did on the desktop (2026-11-25) when $fake/pull-fails exists, and
# `exec` runs nothing.
cat > "$fake/bin/apptainer" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")/.."
echo "apptainer $*" >> "$dir/calls"
case "$1" in
    pull)
        ref="${!#}"
        ref="${ref#docker://}"
        [ ! -e "$dir/pull-fails" ] || { echo "FATAL:   While making image from oci registry: error fetching image to cache: failed to get checksum for docker://$ref: reading manifest ${ref#*@} in ${ref%@*}: manifest unknown" >&2; exit 255; }
        echo "container of ${!#}" > "${@: -2:1}" ;;
    exec) ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$fake/bin/"*

a64=$(printf 'a%.0s' {1..64}) b64=$(printf 'b%.0s' {1..64})
src="$fake/src" clone="$fake/iris"
commit() { git -C "$src" add -A && git -C "$src" commit -qm "$1"; }

# main: the ct-lab section with seg's card, the seg workflow, the lab
# table [ct-lab]=ct/1, ct/1's recipe, the rest of the job side as stubs,
# the tools under test, a bin/check that fails when RB_CHECK_FAIL is set
# or bin/libcopy --check prints a problem, and a bin/katana-test whose
# --tested says the batch needs no run.
mkdir -p "$src/bin" "$src/lib/iris" "$src/workflows/seg/src" "$src/envs/ct/1"
cp bin/review-batch bin/outside-folder bin/github-repo.sh bin/libcopy bin/envrun "$src/bin/"
for f in iris-job.sh iris/__init__.py iris/dataset.py iris/labels.py iris/record.py iris/rundir.py iris/volume.py; do
    echo "# lib/$f" > "$src/lib/$f"
done
cat > "$src/bin/check" <<'EOF'
#!/bin/bash
[ -z "${RB_CHECK_FAIL-}" ] || { echo "check: FAILED"; exit 1; }
copies="$("$(dirname "$0")/libcopy" --check)"
[ -z "$copies" ] || { echo "$copies"; echo "check: FAILED"; exit 1; }
echo "All checks passed."
EOF
printf '#!/bin/bash\n[ "$1" = --tested ]\n' > "$src/bin/katana-test"
chmod +x "$src/bin/check" "$src/bin/katana-test"
cp lib/katana.sh "$src/lib/"
lab_table "$src/lib/katana.sh" ct-lab=ct/1 || exit 1
digest_map "$src/lib/katana.sh" "ct/1=sha256:$b64" || exit 1
printf '%s\n' '<div class="lab" id="ct-lab">' '    <a href="workflows/seg/" class="workflow-card">' \
    '      <div class="card-name">seg</div>' '    </a>' '</div>' > "$src/index.html"
echo "print(1)" > "$src/workflows/seg/src/run.py"
echo "numpy==2.0" > "$src/envs/ct/1/requirements.lock"
echo "# IRIS" > "$src/README.md"
git init -q -b main "$src"
commit main

# PR 7: seg's next code in ct/2, an author's container, with a run proof
# whose digest isn't the one the map names, and seg's library copy made
# after it, so the copy names the author's container too.
git -C "$src" checkout -q -b pr7
echo "print(2)" > "$src/workflows/seg/src/run.py"
mkdir -p "$src/envs/ct/2"
printf '%s\n' "numpy==2.0" "scipy==1.14" > "$src/envs/ct/2/requirements.lock"
sed -i 's|^    \[ct/1\]=.*|&\n    [ct/2]=ghcr.io/alice-lab/iris-env@sha256:'"$a64"'|' "$src/lib/katana.sh"
printf '{"format": 1, "workflow": "seg", "environment": {"version": "ct/2", "digest": "sha256:%s"}}\n' "$b64" \
    > "$src/workflows/seg/run-proof.json"
commit "seg on ct/2"
"$src/bin/libcopy" seg > /dev/null || exit 1
grep -q alice-lab "$src/workflows/seg/lib/katana.sh" || { echo "review-batch fixture: seg's copy lacks the author's line"; exit 1; }
commit "seg's library copy"
pr7=$(git -C "$src" rev-parse HEAD)

# PR 9: a page edit and a README edit, which bin/outside-folder flags,
# and a new version left unpublished.
git -C "$src" checkout -q -b pr9 main
echo "<h1>seg</h1>" > "$src/workflows/seg/index.html"
echo "# IRIS, changed" > "$src/README.md"
mkdir -p "$src/envs/ct/2"
echo "numpy==2.1" > "$src/envs/ct/2/requirements.lock"
sed -i 's|^    \[ct/1\]=.*|&\n    [ct/2]=unpublished|' "$src/lib/katana.sh"
commit "seg's page"
pr9=$(git -C "$src" rev-parse HEAD)

# PR 12: a page edit alone, nothing to flag.
git -C "$src" checkout -q -b pr12 main
echo "<h1>seg, again</h1>" > "$src/workflows/seg/index.html"
commit "seg's heading"
pr12=$(git -C "$src" rev-parse HEAD)

# PRs 14 and 15: seg's library copy made while lib/katana.sh named an
# author's container for ct/1, then lib/katana.sh back to ct/1's digest
# alone, as main pins it. #14's copy names the container of that digest,
# which IRIS's package holds; #15's names another, which it doesn't.
copy_only() { # copy_only <number> <hex>
    git -C "$src" checkout -q -b "pr$1" main
    sed -i "s|^    \[ct/1\]=.*|    [ct/1]=ghcr.io/alice-lab/iris-env@sha256:$2|" "$src/lib/katana.sh"
    commit "ct/1 as alice-lab's"
    "$src/bin/libcopy" seg > /dev/null || exit 1
    commit "seg's library copy"
    sed -i "s|^    \[ct/1\]=.*|    [ct/1]=sha256:$b64|" "$src/lib/katana.sh"
    commit "ct/1 by its digest"
}
copy_only 14 "$b64"
pr14=$(git -C "$src" rev-parse HEAD)
copy_only 15 "$a64"
pr15=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q main

git clone -q --bare "$src" "$fake/origin.git"
for n in 7 9 12 14 15; do git -C "$src" push -q "$fake/origin.git" "pr$n:refs/pull/$n/head"; done
git clone -q "$fake/origin.git" "$clone"

# pr <number> <head> <title> <login> <mergeable> [<label>...]: one PR as
# gh pr list --json prints it.
pr() {
    local n="$1" head="$2" title="$3" login="$4" mergeable="$5" labels="" l
    shift 5
    for l in "$@"; do labels+="${labels:+,}{\"id\":\"L$l\",\"name\":\"$l\",\"description\":\"\",\"color\":\"0e8a16\"}"; done
    printf '{"author":{"id":"U1","is_bot":false,"login":"%s","name":""},"baseRefName":"main","body":"Body of #%s.\\r\\nUrgent: a quick fix.","headRefOid":"%s","labels":[%s],"mergeable":"%s","number":%s,"title":"%s","url":"https://github.com/unsw-restech/iris/pull/%s"}' \
        "$login" "$n" "$head" "$labels" "$mergeable" "$n" "$title" "$n"
}
# Newest first, as gh lists them.
printf '[%s,%s,%s]\n' "$(pr 12 "$pr12" "seg's heading" carol MERGEABLE ready)" \
    "$(pr 9 "$pr9" "seg's page" bob CONFLICTING ready outside-folder)" \
    "$(pr 7 "$pr7" "seg on ct/2" alice-lab MERGEABLE ready)" > "$fake/prs.json"

refs_before=$(git -C "$fake/origin.git" for-each-ref; git -C "$clone" for-each-ref refs/heads; git -C "$clone" worktree list)

failures=0
fail() { echo "$*"; failures=1; }
# run <arg>...: bin/review-batch in the clone with the fakes on PATH, into
# $out and $rc.
# bin/envrun's cache is $fake/cache, and it picks Apptainer, the fake's,
# unless IRIS_CONTAINER_RUNTIME says otherwise or $run_path, the PATH it
# runs with if set, has no apptainer.
unset IRIS_CONTAINER_RUNTIME
run() { rm -f "$fake/calls"; out="$(IRIS_ENV_CACHE="$fake/cache" PATH="${run_path:-$fake/bin:$PATH}" "$clone/bin/review-batch" "$@" 2>&1)"; rc=$?; }
has() { grep -qF -- "$1" <<< "$out" || fail "review-batch ${2:-listing}: output lacks '$1'"; }
lacks() { ! grep -qF -- "$1" <<< "$out" || fail "review-batch ${2:-listing}: output has '$1'"; }
show() { [ "$failures" = 0 ] || echo "$out" | sed 's/^/  /'; failures=0; }

run
[ "$rc" = 0 ] || fail "review-batch listing: exit $rc, expected 0"
grep -q '^gh pr list .*--label ready' "$fake/calls" || fail "review-batch listing: didn't ask gh for the ready PRs"
grep -q '^gh pr list .*--base main' "$fake/calls" || fail "review-batch listing: didn't limit the PRs to those into main"
# Each PR, oldest first, with its author, its body and its diff.
has "#7 seg on ct/2"; has "#9 seg's page"; has "#12 seg's heading"
[ "$(grep -n '#7 seg on ct/2' <<< "$out" | sed -n 1p | cut -d: -f1)" -lt "$(grep -n "#12 seg's heading" <<< "$out" | sed -n 1p | cut -d: -f1)" ] ||
    fail "review-batch listing: #12 comes before #7"
has "alice-lab"; has "Urgent: a quick fix."
has "+print(2)"; has "+# IRIS, changed"; has "workflows/seg/src/run.py"
# What each flags: the author's container to copy, its proof's other
# digest, what bin/outside-folder lists, a conflict, a version to publish.
has "ct/2: copy ghcr.io/alice-lab/iris-env@sha256:$a64 into ghcr.io/unsw-restech/iris-env"
has "run-proof.json ran ct/2 at sha256:$b64"
has "outside its folder: README.md"
has "conflicts with main"
has "ct/2 is unpublished"
has "Nothing flagged."
# The one yes: every PR, oldest first, pinned at the head reviewed.
has "bin/review-batch --apply 7:${pr7:0:12} 9:${pr9:0:12} 12:${pr12:0:12}"
# It changed nothing.
grep -vq '^gh pr list' "$fake/calls" && fail "review-batch listing: ran more than gh pr list: $(grep -v '^gh pr list' "$fake/calls")"
[ "$(git -C "$fake/origin.git" for-each-ref; git -C "$clone" for-each-ref refs/heads; git -C "$clone" worktree list)" = "$refs_before" ] ||
    fail "review-batch listing: changed a branch, a worktree or origin"
show

# No ready PR: nothing to review and no --apply line.
echo '[]' > "$fake/prs.json"
run
[ "$rc" = 0 ] || fail "review-batch empty: exit $rc, expected 0"
has "No ready pull requests" empty; lacks "--apply" empty
show

# gh can't list them: says so, exits 2.
touch "$fake/gh-down"
run
[ "$rc" = 2 ] || fail "review-batch gh-down: exit $rc, expected 2"
has "error connecting" gh-down
show
rm "$fake/gh-down"

# Usage errors exit 2 before anything runs.
for args in "--apply" "--apply 7" "--apply 7:zz" "--apply 7:abc1234;x" "bogus" \
    "--copy ct/2" "--copy ct/2 sha256:$a64" "--copy ct/2 ghcr.io/unsw-restech/iris-env@sha256:$a64" \
    "--copy nope ghcr.io/alice-lab/iris-env@sha256:$a64"; do
    # shellcheck disable=SC2086  # each case is its words
    run $args
    [ "$rc" = 2 ] || fail "review-batch $args: exit $rc, expected 2"
    has "usage:" "$args"
    [ ! -e "$fake/calls" ] || fail "review-batch $args: ran $(cat "$fake/calls")"
    show
done

# ── --apply ───────────────────────────────────────────────────────────
# view <number> <head> [<label>...]: PR <number>, open into main, as gh pr
# view --json prints it, into $fake/view-<number>.json.
view() {
    local n="$1" head="$2" labels="" l
    shift 2
    for l in "$@"; do labels+="${labels:+,}{\"id\":\"L$l\",\"name\":\"$l\",\"description\":\"\",\"color\":\"0e8a16\"}"; done
    printf '{"baseRefName":"main","headRefOid":"%s","labels":[%s],"number":%s,"state":"OPEN","title":"PR %s"}\n' \
        "$head" "$labels" "$n" "$n" > "$fake/view-$n.json"
}
main_sha=$(git -C "$clone" rev-parse origin/main)
branch="review-batch-${main_sha:0:7}" wt="$clone/.claude/worktrees/review-batch-${main_sha:0:7}"
state() { git -C "$fake/origin.git" for-each-ref; git -C "$clone" for-each-ref refs/heads; git -C "$clone" worktree list; }
before=$(state)
# left <case>: the batch left nothing behind and copied nothing.
left() {
    [ "$(state)" = "$before" ] || fail "review-batch $1: left a branch, a worktree or an origin change: $(state)"
    [ ! -e "$wt" ] || fail "review-batch $1: left $wt"
    ! grep -q '^docker' "$fake/calls" 2> /dev/null || fail "review-batch $1: ran docker"
}
view 7 "$pr7" ready; view 9 "$pr9" ready outside-folder; view 12 "$pr12" ready
view 14 "$pr14" ready; view 15 "$pr15" ready

# A PR whose head moved since the listing, or that lost ready: refused
# before anything is merged.
view 7 "$pr12" ready
run --apply "7:${pr7:0:12}" "12:${pr12:0:12}"
[ "$rc" = 1 ] || fail "review-batch moved: exit $rc, expected 1"
has "#7 has moved on to ${pr12:0:12} since the listing; nothing merged" moved; left moved
show
view 7 "$pr7"
run --apply "7:${pr7:0:12}" "12:${pr12:0:12}"
[ "$rc" = 1 ] || fail "review-batch unready: exit $rc, expected 1"
has "#7 isn't labelled ready; nothing merged" unready; left unready
show
view 7 "$pr7" ready

# A batch on this main made before, its branch or its worktree: refused.
git -C "$clone" branch -q "$branch" origin/main
run --apply "7:${pr7:0:12}"
[ "$rc" = 1 ] || fail "review-batch branch-there: exit $rc, expected 1"
has "$branch or its worktree $wt is already there" branch-there
git -C "$clone" branch -q -D "$branch"
left branch-there
show
mkdir -p "$wt"
run --apply "7:${pr7:0:12}"
[ "$rc" = 1 ] || fail "review-batch worktree-there: exit $rc, expected 1"
has "is already there" worktree-there
[ -z "$(ls -A "$wt")" ] || fail "review-batch worktree-there: wrote into $wt"
rmdir "$wt"
left worktree-there
show

# A merge that fails, #9's ct/2 line against #7's: the merge is undone and
# the batch's worktree and branch removed.
run --apply "7:${pr7:0:12}" "9:${pr9:0:12}"
[ "$rc" = 1 ] || fail "review-batch conflict: exit $rc, expected 1"
has "the merge of #9 failed (above); nothing merged, and the batch's worktree and branch are removed" conflict
left conflict
show

# bin/check failing on the batch: nothing pushed or copied, and the steps
# it prints to make the batch again, run, let --apply make it again.
RB_CHECK_FAIL=1 run --apply "7:${pr7:0:12}" "12:${pr12:0:12}"
[ "$rc" = 1 ] || fail "review-batch check-fails: exit $rc, expected 1"
has "check: FAILED" check-fails
has "bin/check failed on the batch (above); nothing pushed or copied" check-fails
lacks "git push" check-fails
[ "$(git -C "$fake/origin.git" rev-parse main)" = "$main_sha" ] || fail "review-batch check-fails: moved origin's main"
! grep -q '^docker' "$fake/calls" || fail "review-batch check-fails: ran docker"
git -C "$clone" worktree remove "$wt" || fail "review-batch check-fails: its 'git worktree remove $wt' failed"
git -C "$clone" branch -q -D "$branch" || fail "review-batch check-fails: its 'git branch -D $branch' failed"
left check-fails
show

# Only a library copy names an author's container, one whose digest
# lib/katana.sh already pins: the copy pins it by its digest alone, the
# commit says so, and there is nothing to copy.
run --apply "14:${pr14:0:12}"
[ "$rc" = 0 ] || fail "review-batch copy-only: exit $rc, expected 0"
tip=$(git -C "$clone" rev-parse -q --verify "refs/heads/$branch") || fail "review-batch copy-only: no branch $branch"
grep -qx "    \[ct/1\]=sha256:$b64" <(git -C "$clone" show "$tip:workflows/seg/lib/katana.sh") ||
    fail "review-batch copy-only: seg's library copy doesn't pin ct/1 by its digest alone"
[ "$(git -C "$clone" log -1 --format=%s "$tip")" = "The review batch pins ct/1 by its digest alone in workflows/seg/lib/katana.sh, as lib/katana.sh already does" ] ||
    fail "review-batch copy-only: the rewrite's commit message is '$(git -C "$clone" log -1 --format=%s "$tip")'"
has "bin/check passed on the batch" copy-only
lacks "--copy" copy-only
git -C "$clone" worktree remove --force "$wt"
git -C "$clone" branch -q -D "$branch"
left copy-only
show

# A library copy naming an author's container lib/katana.sh doesn't pin,
# whose digest IRIS's package would lack: refused, naming the copy.
run --apply "15:${pr15:0:12}"
[ "$rc" = 1 ] || fail "review-batch copy-unpinned: exit $rc, expected 1"
has "workflows/seg/lib/katana.sh names ghcr.io/alice-lab/iris-env@sha256:$a64 for ct/1" copy-unpinned
has "nothing merged, and the batch's worktree and branch are removed" copy-unpinned
left copy-unpinned
show

# Under Docker, a batch with an author's container is refused before any
# merge, since only Apptainer's cache, keyed by the hex alone, runs it
# under the org's ref before its copy. One without goes ahead.
IRIS_CONTAINER_RUNTIME=docker run --apply "12:${pr12:0:12}" "7:${pr7:0:12}"
[ "$rc" = 1 ] || fail "review-batch docker: exit $rc, expected 1"
has "#7 names ghcr.io/alice-lab/iris-env@sha256:$a64 for ct/2, and the batch's bin/check needs Apptainer" docker
has "nothing merged" docker
! grep -q '^apptainer' "$fake/calls" || fail "review-batch docker: ran apptainer"
left docker
show
IRIS_CONTAINER_RUNTIME=docker run --apply "12:${pr12:0:12}"
[ "$rc" = 0 ] || fail "review-batch docker-no-author: exit $rc, expected 0"
has "bin/check passed on the batch" docker-no-author
git -C "$clone" worktree remove --force "$wt"
git -C "$clone" branch -q -D "$branch"
left docker-no-author
show

# With IRIS_CONTAINER_RUNTIME unset and no apptainer on the PATH, both
# copies of the runtime choice, bin/review-batch's and bin/envrun's, pick
# Docker: the same refusal as above, and bin/envrun asks docker, not
# apptainer, for main's ct/1: only the calls count, since the fake docker
# answers nothing but buildx imagetools. $fake/noapp holds a link to every
# command on the PATH, the fakes first, but apptainer.
mkdir "$fake/noapp"
IFS=: read -ra path_dirs <<< "$PATH"
for d in "$fake/bin" "${path_dirs[@]}"; do
    for f in "$d"/*; do
        n="${f##*/}"
        [ "$n" = apptainer ] || [ -e "$fake/noapp/$n" ] || [ ! -x "$f" ] || [ -d "$f" ] || ln -s "$f" "$fake/noapp/$n"
    done
done
run_path="$fake/noapp" run --apply "12:${pr12:0:12}" "7:${pr7:0:12}"
[ "$rc" = 1 ] || fail "review-batch no-apptainer: exit $rc, expected 1"
has "#7 names ghcr.io/alice-lab/iris-env@sha256:$a64 for ct/2, and the batch's bin/check needs Apptainer" no-apptainer
left no-apptainer
(cd "$clone" && IRIS_ENV_CACHE="$fake/cache" PATH="$fake/noapp" bin/envrun ct/1 true > /dev/null 2>&1)
grep -q '^docker image inspect ' "$fake/calls" || fail "review-batch no-apptainer: bin/envrun didn't pick docker: $(cat "$fake/calls")"
! grep -q '^apptainer' "$fake/calls" || fail "review-batch no-apptainer: bin/envrun ran apptainer"
rm -f "$fake/calls"
show

# #7's author's container already in bin/envrun's cache: nothing pulled.
mkdir -p "$fake/cache"
echo "container of ct/2" > "$fake/cache/$a64.sif"
run --apply "7:${pr7:0:12}"
[ "$rc" = 0 ] || fail "review-batch cached: exit $rc, expected 0"
! grep -q '^apptainer pull' "$fake/calls" || fail "review-batch cached: pulled $(grep '^apptainer pull' "$fake/calls")"
git -C "$clone" worktree remove --force "$wt"
git -C "$clone" branch -q -D "$branch"
left cached
show

# A pull of an author's container that fails: the batch is undone, as a
# failed merge is, with one line naming the version and the author's ref.
rm -rf "$fake/cache"
touch "$fake/pull-fails"
run --apply "7:${pr7:0:12}" "12:${pr12:0:12}"
[ "$rc" = 1 ] || fail "review-batch pull-fails: exit $rc, expected 1"
has "the pull of ct/2's container, ghcr.io/alice-lab/iris-env@sha256:$a64, into bin/envrun's cache failed (above); nothing merged, and the batch's worktree and branch are removed" pull-fails
lacks "Running its bin/check" pull-fails
[ ! -e "$fake/cache/$a64.sif" ] || fail "review-batch pull-fails: left $a64.sif in the cache"
left pull-fails
show
rm "$fake/pull-fails"
# Its step, --apply again once the pull works, and the Docker refusal's,
# --apply with Apptainer, are the batch below.

# The batch, #7 and #12: merged in order on its own branch, #7's author
# container line written as its digest alone and committed, and the steps
# printed in order, the copy before the push.
run --apply "7:${pr7:0:12}" "12:${pr12:0:12}"
[ "$rc" = 0 ] || fail "review-batch apply: exit $rc, expected 0"
tip=$(git -C "$clone" rev-parse -q --verify "refs/heads/$branch") || fail "review-batch apply: no branch $branch"
[ "$(git -C "$wt" rev-parse HEAD 2> /dev/null)" = "$tip" ] || fail "review-batch apply: $wt isn't at the batch's tip"
[ "$(git -C "$clone" log --format=%s "$main_sha..$tip^" --first-parent)" = "$(printf '%s\n' 'Merge #12: PR 12' 'Merge #7: PR 7')" ] ||
    fail "review-batch apply: the batch's merges aren't #7 then #12: $(git -C "$clone" log --oneline --first-parent "$main_sha..$tip")"
grep -q "copies ct/2's container" <<< "$(git -C "$clone" log -1 --format=%s "$tip")" || fail "review-batch apply: its tip isn't the digest map's rewrite"
grep -qx "    \[ct/2\]=sha256:$a64" <(git -C "$clone" show "$tip:lib/katana.sh") ||
    fail "review-batch apply: the batch's digest map doesn't pin ct/2 by its digest alone"
! grep -q alice-lab <<< "$(git -C "$clone" show "$tip:lib/katana.sh")" || fail "review-batch apply: the batch's digest map still names the author's container"
# seg's library copy too, in the same commit, which the copy rule passes.
grep -qx "    \[ct/2\]=sha256:$a64" <(git -C "$clone" show "$tip:workflows/seg/lib/katana.sh") ||
    fail "review-batch apply: seg's library copy doesn't pin ct/2 by its digest alone"
! grep -q alice-lab <<< "$(git -C "$clone" show "$tip:workflows/seg/lib/katana.sh")" || fail "review-batch apply: seg's library copy still names the author's container"
[ "$(git -C "$clone" diff --name-only "$tip^" "$tip" | sort)" = "$(printf '%s\n' lib/katana.sh workflows/seg/lib/katana.sh)" ] ||
    fail "review-batch apply: the rewrite's commit changes $(git -C "$clone" diff --name-only "$tip^" "$tip" | tr '\n' ' ')"
grep -q "workflows/seg/lib/katana.sh" <<< "$(git -C "$clone" log -1 --format=%s "$tip")" || fail "review-batch apply: the rewrite's commit message doesn't name seg's library copy"
git -C "$wt" diff --quiet HEAD || fail "review-batch apply: left uncommitted changes in $wt"
has "bin/check passed on the batch" apply
# With an empty cache, #7's author's container was pulled into it by the
# author's ref, before the rewrite, and the rewritten line resolves to it:
# bin/envrun runs ct/2 from the batch's worktree pulling nothing.
[ "$(grep -c '^apptainer pull' "$fake/calls")" = 1 ] && grep -q "^apptainer pull .* docker://ghcr.io/alice-lab/iris-env@sha256:$a64\$" "$fake/calls" ||
    fail "review-batch apply: didn't pull the author's container once by its ref: $(grep '^apptainer' "$fake/calls")"
[ -f "$fake/cache/$a64.sif" ] || fail "review-batch apply: the cache lacks $a64.sif"
rm -f "$fake/calls"
(cd "$wt" && IRIS_ENV_CACHE="$fake/cache" PATH="$fake/bin:$PATH" bin/envrun ct/2 true) || fail "review-batch apply: bin/envrun ct/2 failed in the batch"
! grep -q '^apptainer pull' "$fake/calls" || fail "review-batch apply: the rewritten ct/2 line didn't resolve to the cached file"
mapfile -t steps < <(sed -nE 's/^  [0-9]+\. //p' <<< "$out")
want=("bin/review-batch --copy ct/2 ghcr.io/alice-lab/iris-env@sha256:$a64" "bin/syspull" "git push origin $tip:main" "bin/ciwait $tip"
    "ssh katana 'cd ~/iris && git pull --ff-only'" "$wt/bin/envpull" "bin/syspull")
[ "$(printf '%s\n' "${steps[@]}")" = "$(printf '%s\n' "${want[@]}")" ] ||
    fail "review-batch apply: printed the steps $(printf '\n    %s' "${steps[@]}")"
show

# Its steps, run as printed from the clone: the copy puts the author's
# container in IRIS's package at its digest, and the push makes the batch
# main, pinning that digest. The listing between them and the rest need
# Katana and CI.
for step in "${steps[0]}" "${steps[2]}"; do
    rm -f "$fake/calls"
    out="$(cd "$clone" && PATH="$fake/bin:$PATH" bash -c "$step" 2>&1)" || fail "review-batch step '$step' failed"
done
[ "$(cat "$fake/registry/ct-2" 2> /dev/null)" = "sha256:$a64" ] || fail "review-batch steps: the copy left ct-2 at '$(cat "$fake/registry/ct-2" 2> /dev/null)'"
[ "$(git -C "$fake/origin.git" rev-parse main)" = "$tip" ] || fail "review-batch steps: the push left origin's main at $(git -C "$fake/origin.git" rev-parse main)"
show

# ── --copy ────────────────────────────────────────────────────────────
# The tag already at that digest: nothing copied. At another: refused.
run --copy ct/2 "ghcr.io/alice-lab/iris-env@sha256:$a64"
[ "$rc" = 0 ] || fail "review-batch copy-again: exit $rc, expected 0"
has "nothing to copy" copy-again
! grep -q 'imagetools create' "$fake/calls" || fail "review-batch copy-again: copied it again"
show
run --copy ct/2 "ghcr.io/alice-lab/iris-env@sha256:$b64"
[ "$rc" = 1 ] || fail "review-batch copy-other: exit $rc, expected 1"
has "ghcr.io/unsw-restech/iris-env:ct-2 is at sha256:$a64, not sha256:$b64" copy-other
! grep -q 'imagetools create' "$fake/calls" || fail "review-batch copy-other: copied over it"
[ "$(cat "$fake/registry/ct-2")" = "sha256:$a64" ] || fail "review-batch copy-other: changed ct-2"
show
# A copy ghcr.io denies: refused, naming the org owner it may need.
touch "$fake/docker-denied"
run --copy ct/3 "ghcr.io/alice-lab/iris-env@sha256:$b64"
[ "$rc" = 1 ] || fail "review-batch copy-denied: exit $rc, expected 1"
has "permission_denied" copy-denied
has "one of the org's owners" copy-denied
[ ! -e "$fake/registry/ct-3" ] || fail "review-batch copy-denied: tagged ct-3"
# Every copy asks buildx for the source's own manifest, not a list (#261).
grep -q 'imagetools create --prefer-index=false ' "$fake/calls" || fail "review-batch copy-denied: created without --prefer-index=false"
show
