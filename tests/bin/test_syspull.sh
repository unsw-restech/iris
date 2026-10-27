#!/bin/bash
# bin/syspull against a fake `ssh` on PATH that records the command it was
# given. Prints each failed case and nothing on success, so bin/check can
# run it.
#
#   tests/bin/test_syspull.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# Adds its arguments to $fake/args and prints a stand-in report. A file
# named ssh-down makes it fail as ssh itself does (255), one named
# check-down does that to the readability check alone, and one named
# unreadable makes that check list a path and fail.
cat > "$fake/ssh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '%s\n' "$@" >> "$dir/args"
[ -e "$dir/ssh-down" ] && { echo "ssh: connect to host katana: Connection refused" >&2; exit 255; }
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

sys=/srv/scratch/katana_ai/iris/code

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

# ssh's own failure is the script's.
# A readability check that can't run says so, not that paths are unreadable.
touch "$fake/check-down"
expect 0 "Couldn't check"
rm "$fake/check-down"

touch "$fake/ssh-down"
expect 255 "Connection refused"
not_sent ssh-down "python3"               # a failed ssh stops before the check
