# Sourced by the fixture tests of bin/check's site checks, from the repo
# root. Each test builds scratch trees under $scratch that hold a copy of
# bin/check, which checks the tree it sits in.

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# expect <pass|fail> <tree> <check name>: runs $scratch/<tree>/bin/check on
# the checks whose name holds <check name>, and prints <tree> and the output
# if the verdict isn't the one wanted. A failure must be that check's own.
expect() {
    local want="$1" tree="$2" name="$3" out rc
    out="$("$scratch/$tree/bin/check" "$name" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "$tree: failed, expected a pass"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep '^FAIL: ' <<< "$out" | grep -qF -- "$name"; }; then
        echo "$tree: passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}
