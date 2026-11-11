#!/bin/bash
# bin/ocpull against a fake `ssh` on PATH that runs bin/ocpull-checkouts.sh
# here, on two throwaway checkouts of a throwaway fork, with katana_ai's
# scratch mapped to a folder of the test's own. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_ocpull.sh
#
# bin/check name: ocpull test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

. lib/katana.sh
scratch="${IRIS_INSTANCE_CHECKOUT%/*}"

# Adds its arguments to $fake/args. `bash -s` runs here, with every path in
# katana_ai's scratch moved to $fake/scratch. The readability check
# (python3) passes, lists a path and fails if a file named unreadable
# exists, or fails as ssh does (255) if one named check-down does. A file
# named ssh-down makes every call fail that way.
cat > "$fake/ssh" <<EOF
#!/bin/bash
dir="\$(dirname "\$0")"
printf '%s\n' "\$@" >> "\$dir/args"
[ -e "\$dir/ssh-down" ] && { echo "ssh: connect to host katana: Connection refused" >&2; exit 255; }
shift
from='$scratch'
if [ "\$1" = bash ]; then
    shift; exec bash "\${@//\$from/\$dir/scratch}"
fi
if [ "\$1" = python3 ]; then
    cat > /dev/null
    [ -e "\$dir/check-down" ] && exit 255
    [ -e "\$dir/unreadable" ] && { echo "needs r--: /x/hidden"; exit 1; }
    exit 0
fi
echo "fake ssh: unexpected \$*" >&2; exit 3
EOF
chmod +x "$fake/ssh"

# The fork: main at A, both checkouts detached there, each with its own
# manifest.yml kept out of git's sight (skip-worktree), as on Katana.
# Then main gains B and C, which the checkouts haven't fetched.
iris="$fake/scratch/${IRIS_INSTANCE_CHECKOUT##*/}"
test="$fake/scratch/${IRIS_TEST_INSTANCE_CHECKOUT##*/}"
src="$fake/src"
git init -q -b main "$src"
printf 'name: OpenComposer\n' > "$src/manifest.yml"
echo a > "$src/README.md"
git -C "$src" add -A && git -C "$src" commit -qm "A: the base"
git clone -q --bare "$src" "$fake/fork.git"
git -C "$src" remote add origin "$fake/fork.git"
for c in "$iris" "$test"; do
    git clone -q "$fake/fork.git" "$c"
    git -C "$c" checkout -q --detach main
    git -C "$c" update-index --skip-worktree manifest.yml
    printf 'name: %s\n' "${c##*/}" > "$c/manifest.yml"
done
echo b > "$src/README.md"
git -C "$src" commit -qam "B: the readme says b"
echo c > "$src/c.rb"
git -C "$src" add c.rb && git -C "$src" commit -qm "C: c.rb"
git -C "$src" push -q origin main
A=$(git -C "$src" rev-parse --short HEAD~2)
C=$(git -C "$src" rev-parse --short HEAD)

# expect <exit code> <output substring> <arg>...
expect() {
    local want="$1" grep_for="$2" out rc
    shift 2
    rm -f "$fake/args"
    out="$(PATH="$fake:$PATH" bin/ocpull "$@" 2>&1)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "ocpull $*: exit $rc, expected $want"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$grep_for" <<< "$out"; then
        echo "ocpull $*: output lacks '$grep_for'"
        echo "$out" | sed 's/^/  /'
    fi
}
# at <case> <commit>: both checkouts are at <commit>, each keeping its own manifest.yml.
at() {
    local c
    for c in "$iris" "$test"; do
        [ "$(git -C "$c" rev-parse --short HEAD)" = "$2" ] || echo "ocpull $1: ${c##*/} is at $(git -C "$c" log -1 --oneline), not $2"
        grep -qxF "name: ${c##*/}" "$c/manifest.yml" || echo "ocpull $1: ${c##*/} lost its own manifest.yml"
    done
}

# The listing names both checkouts, the commits a move would deploy to
# each, and the --apply line for the fork's main, and moves neither.
expect 0 "bin/ocpull --apply $C"
expect 0 "${iris##*/}"
expect 0 "${test##*/}"
expect 0 "B: the readme says b"
expect 0 "C: c.rb"
expect 0 "manifest.yml"                    # names the files each keeps its own copy of
at listing "$A"

# --apply moves both to the commit listed, each keeping its own manifest.yml.
expect 0 "$C" --apply "$C"
at apply "$C"
expect 0 "nothing to deploy"

# commit <file> <content> <message>: a commit on the fork's main; prints its short hash.
commit() {
    printf '%s\n' "$2" > "$src/$1"
    git -C "$src" add "$1" && git -C "$src" commit -qm "$3" && git -C "$src" push -q origin main
    git -C "$src" rev-parse --short HEAD
}
D=$(commit d.rb d "D: d.rb")

# A checkout with uncommitted changes: neither moves.
echo edited > "$test/README.md"
expect 1 "has uncommitted changes" --apply "$D"
expect 1 "nothing deployed" --apply "$D"
at dirty "$C"
git -C "$test" checkout -q -- README.md

# A move that fails in the second checkout puts the first back.
echo mine > "$test/d.rb"
expect 1 "back where it was" --apply "$D"
at half-moved "$C"
rm "$test/d.rb"

expect 0 "$D" --apply "$D"
at apply-d "$D"

# A move that changes a file the checkouts keep their own copy of: neither
# moves, and it says how to take the change.
E=$(commit manifest.yml "name: upstream's" "E: upstream's manifest")
expect 0 "--apply refuses"
expect 1 "git update-index --no-skip-worktree 'manifest.yml'" --apply "$E"
at own-copy "$D"
# It names every checkout's steps at once, each saving its copy apart.
export HOME="$fake/home"
mkdir "$HOME"
for c in "$iris" "$test"; do
    expect 1 "cp 'manifest.yml' '$HOME/manifest.yml.${c##*/}'" --apply "$E"
done
# Following them, the move goes through, and each copy merges back.
steps="$(PATH="$fake:$PATH" bin/ocpull --apply "$E" 2>&1 | sed -n "s/^  cp /cp /p")"
for c in "$iris" "$test"; do
    (cd "$c" && eval "$(grep -F "${c##*/}'" <<< "$steps")") || echo "ocpull own-copy: the steps failed in ${c##*/}"
done
expect 0 "$E" --apply "$E"
for c in "$iris" "$test"; do
    cp "$HOME/manifest.yml.${c##*/}" "$c/manifest.yml"
    git -C "$c" update-index --skip-worktree manifest.yml
done
at own-copy-taken "$E"

# A commit off the fork's main, or one behind the checkouts, moves neither.
git -C "$src" checkout -q -b side
echo s > "$src/s.rb" && git -C "$src" add s.rb && git -C "$src" commit -qm "S: off main"
git -C "$src" push -q origin side
S=$(git -C "$src" rev-parse --short HEAD)
expect 1 "is not on the fork's main" --apply "$S"
at off-main "$E"
expect 1 "doesn't follow" --apply "$A"
at backwards "$E"
expect 1 "is not a commit" --apply 0123abc

# Anything else is a usage error, before ssh runs.
expect 2 "usage:" --apply
expect 2 "usage:" --apply "0123abc; rm -rf /"
expect 2 "usage:" pull
[ ! -e "$fake/args" ] || echo "ocpull pull: ran ssh on a usage error"

# ssh's own failure is the script's.
touch "$fake/ssh-down"
expect 255 "Connection refused"
expect 255 "Connection refused" --apply "$D"
rm "$fake/ssh-down"

# What pilot testers can't read in a checkout: the listing warns, and
# --apply, which has moved them, fails.
PATH="$fake:$PATH" bin/ocpull > /dev/null 2>&1
grep -qxF python3 "$fake/args" || echo "ocpull listing: no readability check"
touch "$fake/unreadable"
expect 0 "needs r--: /x/hidden"
expect 1 "fix their ACLs" --apply "$E"
at unreadable "$E"
rm "$fake/unreadable"
# A readability check that can't run says so, not that paths are unreadable.
touch "$fake/check-down"
expect 0 "Couldn't check what pilot testers can read"
expect 1 "couldn't check what pilot testers can read" --apply "$E"
rm "$fake/check-down"
