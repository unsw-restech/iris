#!/bin/bash
# bin/syspull against a fake `ssh` on PATH that records the command it was
# given. Prints each failed case and nothing on success, so bin/check can
# run it.
#
#   tests/bin/test_syspull.sh
#
# bin/check name: syspull test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# Adds its arguments to $fake/args and prints a stand-in report. A file
# named ssh-down makes it fail as ssh itself does (255), one named
# check-down does that to the readability check alone, and one named
# unreadable makes that check list a path and fail. The container check
# (bash -s) records the commit it was given; one named unpinned makes it
# name a version and fail, and one named pins-down makes it fail as ssh does.
cat > "$fake/ssh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '%s\n' "$@" >> "$dir/args"
[ -e "$dir/ssh-down" ] && { echo "ssh: connect to host katana: Connection refused" >&2; exit 255; }
if [ "$2" = bash ]; then
    cat > /dev/null
    [ -e "$dir/pins-down" ] && exit 255
    [ -e "$dir/unpinned" ] && { echo "microct/2, pinned by seg: no /x/microct/2.sif."; exit 1; }
    exit 0
fi
if [ "$2" = python3 ]; then
    cat > /dev/null
    [ -e "$dir/check-down" ] && exit 255
    [ -e "$dir/unreadable" ] && { echo "needs r--: /x/hidden"; exit 1; }
    exit 0
fi
echo "fake report"
EOF
chmod +x "$fake/ssh"

# expect <exit code> <output substring> <arg>...
expect() {
    local want="$1" grep_for="$2" out rc
    shift 2
    rm -f "$fake/args"
    out="$(PATH="$fake:$PATH" bin/syspull "$@" 2>&1)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "syspull $*: exit $rc, expected $want"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$grep_for" <<< "$out"; then
        echo "syspull $*: output lacks '$grep_for'"
        echo "$out" | sed 's/^/  /'
    fi
}
# sent <case> <fixed string>: the command ssh ran holds it.
sent() { grep -qF -- "$2" "$fake/args" 2>/dev/null || echo "syspull $1: ssh command lacks '$2'"; }
# not_sent <case> <extended regex>: the command ssh ran never matches it.
not_sent() { ! grep -qE -- "$2" "$fake/args" 2>/dev/null || echo "syspull $1: ssh command matches '$2'"; }

. lib/katana.sh
sys="$IRIS_SYSTEM_CLONE"

# The preview fetches and lists, and changes nothing in the clone.
expect 0 "fake report"
sent preview katana
sent preview "cd $sys"
sent preview "git fetch"
sent preview "HEAD..origin/main"
not_sent preview "git (pull|merge|reset|checkout|rebase|switch)"
sent preview "origin/main..HEAD"          # warns of the clone's own commits
sent preview "HEAD...origin/main"         # lists only what main brings
sent preview "bin/syspull --apply"        # the line the go-ahead quotes
not_sent preview "tail|head"              # every file listed, none dropped
sent preview "python3"                    # then what pilot testers can't read
# The commits follow the files, so a tail of the listing keeps them.
files="$(grep -n 'git diff --stat' "$fake/args" | cut -d: -f1)"
commits="$(grep -n 'git log --oneline HEAD..origin/main' "$fake/args" | cut -d: -f1)"
[ "$files" -lt "$commits" ] || echo "syspull preview: the commits come before the files"

# --apply moves the clone to exactly the commit that was previewed.
expect 0 "fake report" --apply 0123abc
sent apply "cd $sys"
sent apply "git merge --ff-only 0123abc"
sent apply "merge-base --is-ancestor 0123abc origin/main"
not_sent apply "git (pull|reset|checkout|rebase|switch)"
sent apply "not on origin/main"           # says why it refused
sent apply "rev-parse --abbrev-ref HEAD"  # refuses a clone not on main
sent apply "status --porcelain"           # refuses a clone with edits
sent apply "python3"                      # checks the deployed clone is readable

# A path pilot testers can't read: the preview warns, --apply fails.
touch "$fake/unreadable"
expect 0 "needs r--: /x/hidden"
expect 1 "fix their ACLs" --apply 0123abc
rm "$fake/unreadable"

# Anything else is a usage error, before ssh runs.
expect 2 "usage:" --apply
expect 2 "usage:" --apply "0123abc; rm -rf /"
expect 2 "usage:" pull
[ ! -e "$fake/args" ] || echo "syspull pull: ran ssh on a usage error"

# A version the deploy would pin with no container file in place: the
# preview names it, and --apply names it and deploys nothing.
expect 0 "fake report"
grep -qxF origin/main "$fake/args" || echo "syspull preview: the container check wasn't given origin/main"
touch "$fake/unpinned"
expect 0 "microct/2, pinned by seg: no /x/microct/2.sif."
expect 0 "--apply refuses"
expect 1 "nothing deployed" --apply 0123abc
expect 1 "microct/2, pinned by seg" --apply 0123abc
not_sent apply-unpinned "git merge"
rm "$fake/unpinned"
# A check that can't run says so; --apply deploys nothing without it.
touch "$fake/pins-down"
expect 0 "Couldn't check the containers"
expect 1 "nothing deployed" --apply 0123abc
not_sent apply-pins-down "git merge"
rm "$fake/pins-down"
# The check runs on the commit --apply deploys.
expect 0 "fake report" --apply 0123abc
grep -qxF 0123abc "$fake/args" || echo "syspull apply: the container check wasn't given 0123abc"

# ssh's own failure is the script's.
# A readability check that can't run says so, not that paths are unreadable.
touch "$fake/check-down"
expect 0 "Couldn't check"
rm "$fake/check-down"

touch "$fake/ssh-down"
expect 255 "Connection refused"
not_sent ssh-down "python3"               # a failed ssh stops before the check
