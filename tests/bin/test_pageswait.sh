#!/bin/bash
# bin/pageswait against a fake `curl` on PATH. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_pageswait.sh
#
# bin/check name: pageswait test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# A clone, with bin/pageswait committed, whose origin/main serves
# page/index.html, the catalogue's index.html and notes.md, each holding
# "new marker". pageswait runs from its bin/, in a folder outside any clone.
clone="$fake/clone"
git init -q -b main "$fake/src"
mkdir -p "$fake/src/page" "$fake/src/bin" "$fake/elsewhere"
cp bin/pageswait "$fake/src/bin/"
for f in page/index.html index.html notes.md; do echo "<p>new marker</p>" > "$fake/src/$f"; done
git -C "$fake/src" add -A && git -C "$fake/src" commit -qm A
git clone -q "$fake/src" "$clone"
cd "$fake/elsewhere" || exit 1

# The fake fails like a 404 (exit 22) until it has been called
# $fake/live-after times, then serves a page holding "new marker".
# With no live-after file it never goes live.
cat > "$fake/curl" <<'FAKE'
#!/bin/bash
dir="$(dirname "$0")"
n=$(( $(cat "$dir/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/calls"
if [ -e "$dir/live-after" ] && [ "$n" -ge "$(cat "$dir/live-after")" ]; then
    echo "<p>new marker</p>"
else
    echo "curl: (22) The requested URL returned error: 404" >&2
    exit 22
fi
FAKE
chmod +x "$fake/curl"
# pageswait's 10s polls cost nothing against a sleep that returns at once.
printf '#!/bin/sh\n' > "$fake/sleep"
chmod +x "$fake/sleep"

# expect <exit code> <output substring> <live-after or ""> <arg>...
# The timeout stops a wait that never ends (124) from hanging bin/check.
expect() {
    local want="$1" grep_for="$2" live="$3" out rc
    shift 3
    rm -f "$fake/calls" "$fake/live-after"
    [ -n "$live" ] && echo "$live" > "$fake/live-after"
    out="$(PATH="$fake:$PATH" timeout 20 "$clone/bin/pageswait" "$@" 2>&1)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "pageswait $*: exit $rc, expected $want"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$grep_for" <<< "$out"; then
        echo "pageswait $*: output lacks '$grep_for'"
        echo "$out" | sed 's/^/  /'
    fi
}

expect 0 "live after 0s" 1 page/ "new marker"
expect 0 "live after 20s: https://docs.restech.unsw.edu.au/iris/page/" 3 page/ "new marker"
[ "$(cat "$fake/calls")" = 3 ] || echo "pageswait: polled $(cat "$fake/calls") times, expected 3"
expect 1 "'new marker' not on" "" page/ "new marker"
[ "$(cat "$fake/calls")" = 18 ] || echo "pageswait: polled $(cat "$fake/calls") times before giving up, expected 18"
expect 0 "live after 0s: https://docs.restech.unsw.edu.au/iris/" 1 "" "new marker"
expect 0 "live after 0s" 1 notes.md "new marker"
expect 2 "page is a folder, which Pages serves as page/" 1 page "new marker"
# A marker origin/main's page lacks, a pattern among them, or a page it
# lacks, fails before the first poll.
expect 2 "'old marker' is not in origin/main's page/index.html" 1 page/ "old marker"
expect 2 "is not in origin/main's page/index.html" 1 page/ "new.marker"
[ ! -e "$fake/calls" ] || echo "pageswait: polled for a marker origin/main lacks"
expect 2 "origin/main has no gone.md" 1 gone.md "new marker"
expect 2 "origin/main has no gone/index.html" 1 gone/ "new marker"
# The marker is checked against origin/main, not the working tree.
echo "<p>newer marker</p>" > "$clone/page/index.html"
expect 2 "'newer marker' is not in origin/main's" 1 page/ "newer marker"
expect 2 "usage:" "" page/
