#!/bin/bash
# envs/report-workflows.sh in a scratch tree holding its own lib/katana.sh
# and a fake bin/envrun, which logs how it was called and fails, printing
# a few lines, for a workflow folder named in FAKE_FAIL. The containers
# workflow runs the script on each version it builds (#150). Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_report_workflows.sh
#
# bin/check name: report workflows test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
. tests/bin/lib.sh
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

repo="$scratch/repo"
mkdir -p "$repo/bin" "$repo/lib" "$repo/envs"
cp envs/report-workflows.sh "$repo/envs/"
katana_copy "$repo/lib/"
cat > "$repo/bin/envrun" <<'EOF'
#!/bin/bash
echo "$PWD $*" >> "$(dirname "$0")/envrun.log"
slug="${PWD%/tests}"; slug="${slug##*/}"
if [[ " ${FAKE_FAIL-} " == *" $slug "* ]]; then
    for i in $(seq 1 60); do echo "$slug line $i"; done
    exit 1
fi
echo OK
EOF
chmod +x "$repo/bin/envrun"

# workflow <slug> <version> [<test file>...]: a workflow whose form pins
# <version>, with each test file given.
workflow() {
    local slug="$1" version="$2" t
    shift 2
    mkdir -p "$repo/workflows/$slug"
    printf '%s\n' 'script: |' "  IRIS_ENV_VERSION=$version" > "$repo/workflows/$slug/form.yml.erb"
    for t in "$@"; do
        mkdir -p "$repo/workflows/$slug/tests"
        echo 'import unittest' > "$repo/workflows/$slug/tests/$t"
    done
}

# run <env>/<n> [<var>=<value>...]: the script's output, its exit status in
# rc and its summary in $scratch/summary.
run() {
    local version="$1"
    shift
    rm -f "$repo/bin/envrun.log" "$scratch/summary"
    out="$(env GITHUB_STEP_SUMMARY="$scratch/summary" "$@" "$repo/envs/report-workflows.sh" iris-env-build:local "$version" 2>&1)"
    rc=$?
    summary="$(cat "$scratch/summary" 2>/dev/null)"
    calls="$(cat "$repo/bin/envrun.log" 2>/dev/null)"
}
has() { grep -qF -- "$3" <<< "$2" || { echo "$1: no '$3' in"; echo "$2" | sed 's/^/  /'; }; }
lacks() { ! grep -qF -- "$3" <<< "$2" || { echo "$1: '$3' in"; echo "$2" | sed 's/^/  /'; }; }

workflow seg microct/1 test_synthetic.py test_rundir.py
workflow broke microct/1 test_synthetic.py
workflow host-only microct/1 test_job.py
echo '# bin/check: on the host' >> "$repo/workflows/host-only/tests/test_job.py"
workflow untested microct/1
workflow already microct/2 test_synthetic.py
workflow histo histo/3 test_synthetic.py
workflow viewer tools/1 test_synthetic.py

# A version after microct/1 runs the tests of every workflow pinning an
# earlier microct, in the container just built, as bin/check runs them:
# from the tests folder, on CPU, with no network and its time limit, the
# host's test files left out.
run microct/2 FAKE_FAIL=broke
[ "$rc" = 0 ] || { echo "a failing workflow: exit $rc, expected 0"; echo "$out" | sed 's/^/  /'; }
has "seg's run" "$calls" "$repo/workflows/seg/tests --no-network --time-limit 120 --container iris-env-build:local microct/2 python -m unittest test_rundir test_synthetic"
has "broke's run" "$calls" "$repo/workflows/broke/tests --no-network"
for slug in host-only untested already histo viewer; do
    lacks "$slug's run" "$calls" "/workflows/$slug/"
done

# The summary lists each with its result, and a failure's first lines.
has "summary" "$summary" "| \`seg\` | \`microct/1\` | passed |"
has "summary" "$summary" "| \`broke\` | \`microct/1\` | **failed** |"
has "summary" "$summary" "| \`host-only\` | \`microct/1\` | no tests run in a container |"
has "summary" "$summary" "| \`untested\` | \`microct/1\` | no tests run in a container |"
has "summary" "$summary" "broke line 1"
has "summary" "$summary" "broke line 30"
lacks "summary" "$summary" "broke line 31"
lacks "summary" "$summary" "already"
lacks "summary" "$summary" "histo"
has "log" "$out" "broke: failed"

# A first version has nothing before it: the summary says so and nothing runs.
run histo/1
[ "$rc" = 0 ] || echo "histo/1: exit $rc"
[ -z "$calls" ] || { echo "histo/1: ran tests"; echo "$calls" | sed 's/^/  /'; }
has "histo/1 summary" "$summary" "No workflow pins an earlier version of \`histo\`"

# A later version of another environment runs only that one's workflows.
run histo/4
has "histo/4" "$calls" "/workflows/histo/tests"
lacks "histo/4" "$calls" "/workflows/seg/"

# A version that isn't <env>/<n> is a usage error.
run microct
[ "$rc" = 2 ] || echo "microct: exit $rc, expected 2"
