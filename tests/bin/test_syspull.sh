#!/bin/bash
# bin/syspull against a fake `ssh` on PATH that records the command it was
# given. Prints each failed case and nothing on success, so bin/check can
# run it.
#
#   tests/bin/test_syspull.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# Records its arguments in $fake/args and prints a stand-in report. A file
# named ssh-down makes it fail as ssh itself does (255).
cat > "$fake/ssh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '%s\n' "$@" > "$dir/args"
[ -e "$dir/ssh-down" ] && { echo "ssh: connect to host katana: Connection refused" >&2; exit 255; }
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

# --apply moves the clone to exactly the commit that was previewed.
expect 0 "fake report" --apply 0123abc
sent apply "cd $sys"
sent apply "git merge --ff-only 0123abc"
sent apply "merge-base --is-ancestor 0123abc origin/main"
not_sent apply "git (pull|reset|checkout|rebase|switch)"

# Anything else is a usage error, before ssh runs.
expect 2 "usage:" --apply
expect 2 "usage:" --apply "0123abc; rm -rf /"
expect 2 "usage:" pull
[ ! -e "$fake/args" ] || echo "syspull pull: ran ssh on a usage error"

# ssh's own failure is the script's.
touch "$fake/ssh-down"
expect 255 "Connection refused"
