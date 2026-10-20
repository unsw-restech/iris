#!/bin/bash
# bin/qwait against a fake `ssh` on PATH, which warns on stderr on every
# call like a stale connection-sharing socket (#41). Prints each failed
# case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_qwait.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT

# Job IDs pick the fake's answer: a number finished with exit 0, fail
# finished with exit 3, slow is running on the first poll, and anything
# else is unknown to qstat, as a warning read as a job ID would be.
# A file named ssh-down makes the next query fail as ssh itself (255).
cat > "$fake/ssh" <<'EOF'
#!/bin/bash
echo "mux_client_request_session: session request failed: Session open refused by peer" >&2
[ "$1" = -n ] && { echo "last log line"; exit 0; }
dir="$(dirname "$0")"
[ -e "$dir/ssh-down" ] && { rm "$dir/ssh-down"; echo "ssh: connect to host katana: Connection refused" >&2; exit 255; }
shift 3
cat > /dev/null
for id in "$@"; do
    case "$id" in
        fail) echo "fail F 3 /x/fail.OU" ;;
        slow) if [ -e "$dir/slow-seen" ]; then echo "slow F 0 /x/slow.OU"; else touch "$dir/slow-seen"; echo "slow R - /x/slow.OU"; fi ;;
        *[!0-9]*) echo "qstat $id: qstat: Unknown Job Id $id" >&2; exit 1 ;;
        *) echo "$id F 0 /x/$id.OU" ;;
    esac
done
EOF
chmod +x "$fake/ssh"

# expect <exit code> <stderr substring or ""> <job id>...
# The timeout stops a wait that never ends (124) from hanging bin/check.
expect() {
    local want="$1" grep_for="$2" err rc
    shift 2
    rm -f "$fake/slow-seen"
    err="$(PATH="$fake:$PATH" QWAIT_INTERVAL=0 timeout 20 bin/qwait "$@" 2>&1 >/dev/null)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "qwait $*: exit $rc, expected $want"
        echo "$err" | sed 's/^/  /'
    elif [ -n "$grep_for" ] && ! grep -qF "$grep_for" <<< "$err"; then
        echo "qwait $*: stderr lacks '$grep_for'"
        echo "$err" | sed 's/^/  /'
    fi
}

expect 0 "" 1 2
expect 1 "" 1 fail
expect 0 "" slow 1
expect 2 "Unknown Job Id bad" bad
expect 2 "Unknown Job Id bad" 1 bad
touch "$fake/ssh-down"
expect 0 "" 1
