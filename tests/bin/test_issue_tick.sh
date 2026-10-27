#!/bin/bash
# bin/issue-tick against a fake `gh` on PATH. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_issue_tick.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# `gh issue view` prints $fake/body; `gh issue edit` saves stdin to
# $fake/edited, so a case that must not edit leaves no such file.
cat > "$fake/gh" <<'FAKE'
#!/bin/bash
dir="$(dirname "$0")"
case "$2" in
    view) cat "$dir/body" ;;
    edit) cat > "$dir/edited" ;;
esac
FAKE
chmod +x "$fake/gh"

body='## Acceptance criteria

- [ ] The sample dataset arrives in `/srv/scratch/<zID>/` intact
- [ ] **Open in Globus** appears under **Files**
  - [ ] Nested box with a back\slash
- [x] Already ticked box, written as "- [ ] " in text
```
- [ ] Fenced box
```
- [ ] Twin box one
- [ ] Twin box two'

# expect <exit code> <output substring> <arg>...
expect() {
    local want="$1" grep_for="$2" out rc
    shift 2
    printf '%s\n' "$body" > "$fake/body"
    rm -f "$fake/edited"
    out="$(PATH="$fake:$PATH" bin/issue-tick "$@" 2>&1)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "issue-tick $*: exit $rc, expected $want"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$grep_for" <<< "$out"; then
        echo "issue-tick $*: output lacks '$grep_for'"
        echo "$out" | sed 's/^/  /'
    fi
}

expect 0 "ticked on #95: **Open in Globus**" 95 'The sample dataset' '**Open in Globus**' 'Nested box with a back\slash'
want="${body//- \[ \] The/- [x] The}"
want="${want//- \[ \] \*\*Open/- [x] **Open}"
want="${want//- \[ \] Nested/- [x] Nested}"
[ "$(cat "$fake/edited" 2>/dev/null)" = "$want" ] || { echo "issue-tick: edited body differs:"; diff <(echo "$want") "$fake/edited" | sed 's/^/  /'; }

expect 0 "every box already ticked" 95 'Already ticked'
[ -e "$fake/edited" ] && echo "issue-tick: edited a body with nothing to tick"
expect 1 "matches 2 boxes" 95 'The sample dataset' 'Twin box'
[ -e "$fake/edited" ] && echo "issue-tick: edited a body although a prefix matched two boxes"
expect 1 "matches 0 boxes" 95 'No such box'
expect 1 "matches 0 boxes" 95 'Fenced box'
expect 1 "matches 0 boxes" 95 'sample dataset'
expect 2 "usage:" 95
