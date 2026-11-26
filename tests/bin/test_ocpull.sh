#!/bin/bash
# bin/ocpull against a fake `ssh` on PATH that runs bin/ocpull-checkouts.sh
# here, on two throwaway checkouts of a throwaway fork, with katana_ai's
# scratch mapped to a folder of the test's own and a throwaway home folder
# holding the dev install. Prints each failed case and nothing on success,
# so bin/check can run it.
#
#   tests/bin/test_ocpull.sh
#
# bin/check name: ocpull test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
. tests/bin/lib.sh
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# Katana's home folder and the desktop's are one here, the test's own.
export HOME="$fake/home"
mkdir "$HOME"

. lib/katana.sh
scratch="${IRIS_INSTANCE_CHECKOUT%/*}"

# Adds its arguments to $fake/args. `bash -s` runs here, with every path in
# katana_ai's scratch moved to $fake/scratch. The readability check
# (python3) passes, lists a path and fails if a file named unreadable
# exists, or fails as ssh does (255) if one named check-down does. A
# command line on the dev install (cd ~/...) runs here as Katana's
# shell would run it. A file named ssh-down makes every call fail that way.
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
case "\$1" in "cd ~/"*) exec bash -c "\$1" ;; esac
echo "fake ssh: unexpected \$*" >&2; exit 3
EOF
chmod +x "$fake/ssh"

# The fork: main at A, both checkouts detached there, each with its own
# manifest.yml kept out of git's sight (skip-worktree), as on Katana.
# The dev install, in the home folder, is a clone of the fork there too.
# Then main gains B and C, which none of them has fetched.
dev="$HOME/$IRIS_DEV_INSTALL"
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
git clone -q "$fake/fork.git" "$dev"
git -C "$dev" checkout -q --detach main
echo b > "$src/README.md"
git -C "$src" commit -qam "B: the readme says b"
echo c > "$src/c.rb"
git -C "$src" add c.rb && git -C "$src" commit -qm "C: c.rb"
git -C "$src" push -q origin main
A=$(git -C "$src" rev-parse --short HEAD~2)
C=$(git -C "$src" rev-parse --short HEAD)

# bin/ocpull runs from a copy of the tools it needs, beside a form test
# helper whose header names the commit helper_at gives it.
tools="$fake/iris"
mkdir -p "$tools/bin" "$tools/lib/tests"
cp bin/ocpull bin/ocpull-checkouts.sh bin/pilot-readable.py "$tools/bin/"
katana_copy "$tools/lib/"
helper_at() {
    printf '# Render a form.yml.erb the way the IRIS fork of OpenComposer does at\n# %s, the commit bin/ocpull keeps the IRIS instance'"'"'s and the test\n' "$1" \
        > "$tools/lib/tests/form_helper.rb"
}
helper_at "$A"

# expect <exit code> <output substring> <arg>...
expect() {
    local want="$1" grep_for="$2" out rc
    shift 2
    rm -f "$fake/args"
    out="$(PATH="$fake:$PATH" "$tools/bin/ocpull" "$@" 2>&1)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "ocpull $*: exit $rc, expected $want"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$grep_for" <<< "$out"; then
        echo "ocpull $*: output lacks '$grep_for'"
        echo "$out" | sed 's/^/  /'
    fi
}
# lacks <output substring> <arg>...: bin/ocpull's output doesn't hold it.
lacks() {
    local out
    out="$(PATH="$fake:$PATH" "$tools/bin/ocpull" "${@:2}" 2>&1)"
    ! grep -qF -- "$1" <<< "$out" || { echo "ocpull ${*:2}: output has '$1'"; echo "$out" | sed 's/^/  /'; }
}
# dev_at <case> <commit>: the dev install is at <commit>.
dev_at() {
    [ "$(git -C "$dev" rev-parse --short HEAD)" = "$2" ] || echo "ocpull $1: the dev install is at $(git -C "$dev" log -1 --oneline), not $2"
}
# move_dev <sha>: runs the line --apply printed to move the dev install to
# <sha>, its output in $moved.
move_dev() {
    moved=$(PATH="$fake:$PATH" bash -c "$(devline "$1")" 2>&1)
}
# devline <sha>: the line --apply prints to move the dev install to <sha>.
devline() {
    # shellcheck disable=SC2088  # the ~ is for Katana's shell, in the printed line
    local d="~/$IRIS_DEV_INSTALL"
    printf "ssh katana 'cd %s && { git diff --quiet HEAD && [ -z \"\$(git ls-files -v | grep \"^S\")\" ] || { echo \"ocpull: %s has uncommitted changes or keeps its own copy of a file (skip-worktree), so nothing moved it; move it by hand.\" >&2; exit 1; }; } && git fetch -q origin && git checkout -q --detach %s'" \
        "$d" "$d" "$1"
}
# refused <case>: the dev install line refused, saying why.
refused() {
    grep -qF "ocpull: ~/$IRIS_DEV_INSTALL has uncommitted changes" <<< "$moved" || printf 'ocpull %s: the line refused without its message\n%s\n' "$1" "$(sed 's/^/  /' <<< "$moved")"
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
# It says which commit the dev install is on, and that it is behind.
expect 0 "Dev install ~/$IRIS_DEV_INSTALL: at $A A: the base, behind $C;"
dev_at listing "$A"
# listed_before_apply <case> <line>: the listing's line just before its
# --apply line is <line>.
listed_before_apply() {
    local before
    before=$(PATH="$fake:$PATH" "$tools/bin/ocpull" 2>&1 | grep -B1 -F "bin/ocpull --apply" | sed -n 1p)
    [ "$before" = "$2" ] || printf 'ocpull listing %s: before the --apply line, %s\n  not %s\n' "$1" "$before" "$2"
}
# The form test helper renders as A, not the tip C: the listing says so up
# front, just before the --apply line, rather than --apply after the deploy.
listed_before_apply helper-behind "ocpull: lib/tests/form_helper.rb renders as $A; bring it, and its header's commit, to $C (bin/helper-compare $C shows where its rendering differs, and passes once none does), and commit that before pushing, since --apply exits 1 after the deploy until it does."

# --apply moves both to the commit listed, each keeping its own manifest.yml,
# and passes when the form test helper already renders as that commit.
helper_at "$C"
expect 0 "$C" --apply "$C"
at apply "$C"
expect 0 "nothing to deploy"
# --apply leaves the dev install where it was, and ends with the line that
# moves it to the same commit, which refuses an install with uncommitted
# changes.
dev_at apply "$A"
out="$(PATH="$fake:$PATH" "$tools/bin/ocpull" --apply "$C" 2>&1)"
[ "$(tail -n1 <<< "$out")" = "$(devline "$C")" ] || printf 'ocpull --apply %s: last line is not the dev install line\n%s\n' "$C" "$(sed 's/^/  /' <<< "$out")"
echo edited > "$dev/README.md"
move_dev "$C" && echo "ocpull dev-dirty: the line moved a dev install with uncommitted changes"
refused dev-dirty
dev_at dev-dirty "$A"
git -C "$dev" checkout -q -- README.md
# It refuses an install that keeps its own copy of a file, which a move
# could overwrite, as --apply refuses such a checkout.
git -C "$dev" update-index --skip-worktree manifest.yml
move_dev "$C" && echo "ocpull dev-own-copy: the line moved a dev install keeping its own copy of a file"
refused dev-own-copy
dev_at dev-own-copy "$A"
git -C "$dev" update-index --no-skip-worktree manifest.yml
move_dev "$C" || echo "ocpull dev-move: the line failed"
dev_at dev-move "$C"
# On the tip, the listing says so, and --apply prints no line.
expect 0 "Dev install ~/$IRIS_DEV_INSTALL: at $C C: c.rb, already on $C."
lacks "ssh katana" --apply "$C"

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

# A move past the commit the form test helper's header names deploys, then
# fails, naming the helper to bring up to the new commit.
expect 1 "lib/tests/form_helper.rb still renders as $C" --apply "$D"
at apply-d "$D"
# It still ends with the dev install's line.
expect 1 "$(devline "$D")" --apply "$D"
move_dev "$D" || echo "ocpull dev-move-d: the line failed"
helper_at "$D"
expect 0 "nothing to deploy"
# With the helper on the tip already, the listing doesn't warn.
listed_before_apply helper-on-tip ""

# A move that changes a file the checkouts keep their own copy of: neither
# moves, and it says how to take the change.
E=$(commit manifest.yml "name: upstream's" "E: upstream's manifest")
expect 0 "--apply refuses"
expect 1 "git update-index --no-skip-worktree 'manifest.yml'" --apply "$E"
at own-copy "$D"
# It names every checkout's steps at once, each saving its copy apart.
for c in "$iris" "$test"; do
    expect 1 "cp 'manifest.yml' '$HOME/manifest.yml.${c##*/}'" --apply "$E"
done
# Following them, the move goes through, and each copy merges back.
steps="$(PATH="$fake:$PATH" "$tools/bin/ocpull" --apply "$E" 2>&1 | sed -n "s/^  cp /cp /p")"
for c in "$iris" "$test"; do
    (cd "$c" && eval "$(grep -F "${c##*/}'" <<< "$steps")") || echo "ocpull own-copy: the steps failed in ${c##*/}"
done
helper_at "$E"
expect 0 "$E" --apply "$E"
for c in "$iris" "$test"; do
    cp "$HOME/manifest.yml.${c##*/}" "$c/manifest.yml"
    git -C "$c" update-index --skip-worktree manifest.yml
done
at own-copy-taken "$E"

# A dev install that isn't there: the listing says so, and --apply passes
# without a line.
mv "$dev" "$fake/dev-away"
expect 0 "Dev install ~/$IRIS_DEV_INSTALL: not there, so nothing moves it."
expect 0 "$E" --apply "$E"
lacks "ssh katana" --apply "$E"
mv "$fake/dev-away" "$dev"

# A commit off the fork's main, or one behind the checkouts, moves neither.
git -C "$src" checkout -q -b side
echo s > "$src/s.rb" && git -C "$src" add s.rb && git -C "$src" commit -qm "S: off main"
git -C "$src" push -q origin side
S=$(git -C "$src" rev-parse --short HEAD)
expect 1 "is not on the fork's main" --apply "$S"
at off-main "$E"
# A dev install off the fork's main: the listing and --apply name its
# commit and send it to the IRIS maintainer, with no line to move it,
# since a move goes only forward along the fork's main.
git -C "$dev" fetch -q origin && git -C "$dev" checkout -q --detach "$S"
expect 0 "Dev install ~/$IRIS_DEV_INSTALL: at $S S: off main, ahead of $E or off the fork's main; ask the IRIS maintainer where it goes."
expect 0 "The dev install ~/$IRIS_DEV_INSTALL is at $S S: off main, ahead of $E or off the fork's main, so nothing here moves it; ask the IRIS maintainer where it goes." --apply "$E"
lacks "ssh katana" --apply "$E"
dev_at dev-other "$S"
git -C "$dev" checkout -q --detach "$E"
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
PATH="$fake:$PATH" "$tools/bin/ocpull" > /dev/null 2>&1
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
