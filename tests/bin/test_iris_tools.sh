#!/bin/bash
# The bin/iris-* tools against a fake imaging environment: each, run with
# ENV_DIR naming a folder whose bin/python only reports how it was called,
# runs its own iris.* module from this clone's lib/ with the arguments it
# was given. Prints each failed case and nothing on success, so bin/check
# can run it.
#
#   tests/bin/test_iris_tools.sh
#
# bin/check name: iris tools test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
mkdir -p "$fake/env/bin"
cat > "$fake/env/bin/python" <<'EOF'
#!/bin/bash
echo "PYTHONPATH=$PYTHONPATH"
printf '[%s]' "$@"; echo
EOF
chmod +x "$fake/env/bin/python"

lib="$PWD/lib"
for tool in view:iris.view compare:iris.compare import:iris.tracking rebuild:iris.rebuild; do
    name="iris-${tool%%:*}" module="${tool#*:}"
    out="$(ENV_DIR="$fake/env" PYTHONPATH='' "bin/$name" "a b" c 2>&1)"
    want="[-u][-m][$module][a b][c]"
    grep -qxF -- "$want" <<< "$out" || { echo "bin/$name: python ran with something other than $want"; echo "$out" | sed 's/^/  /'; }
    grep -qxF -- "PYTHONPATH=$lib" <<< "$out" || { echo "bin/$name: lib/ isn't first on PYTHONPATH"; echo "$out" | sed 's/^/  /'; }
done

# The tools reach module/bin's links: one run through a link to bin/.
mkdir -p "$fake/link"
ln -s "$PWD/bin/iris-view" "$fake/link/iris-view"
out="$(ENV_DIR="$fake/env" "$fake/link/iris-view" run 2>&1)"
grep -qxF "[-u][-m][iris.view][run]" <<< "$out" || { echo "a link to bin/iris-view: $out"; }
