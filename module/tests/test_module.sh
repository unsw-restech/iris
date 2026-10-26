#!/bin/bash
# The iris modulefile through Katana's Environment Modules: `module use` on
# this copy's modulefiles folder, then `module load iris`, puts the system
# clone's module/bin first on the PATH and nothing from bin/, and `module
# unload iris` restores the PATH. It doesn't resolve the links there: the
# system clone has them only once it has pulled this change. Run it on
# Katana from a scratch copy of the working tree, as a member of
# katana_ai_ro (see AGENTS.md); it prints each failure and exits 1 if any.
#
#   bash module/tests/test_module.sh
#
# No `set -u`: the module scripts reference unset variables.

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
commands=/srv/scratch/katana_ai/iris/code/module/bin
failed=0
fail() { echo "FAIL: $*"; failed=1; }

. /etc/profile.d/modules.sh || { echo "FAIL: no Environment Modules here; run it on Katana"; exit 1; }
module purge
module use "$PWD/module/modulefiles"
before="$PATH"

module load iris || fail "module load iris"
[ "$PATH" = "$commands:$before" ] ||
    fail "module load iris should prepend only $commands; PATH went from $before to $PATH"
# Terse listing: a "Currently Loaded Modulefiles:" header, then one per line.
loaded=$(module -t list 2>&1 | grep -v ':$' | tr '\n' ' ')
[ "$loaded" = "iris " ] || fail "module load iris should load only iris; loaded: $loaded"
for cmd in iris-rebuild iris-import check ciwait; do
    found=$(command -v "$cmd") && fail "$cmd is on the PATH after module load iris: $found"
done

module unload iris || fail "module unload iris"
[ "$PATH" = "$before" ] || fail "module unload iris left PATH as $PATH, not $before"

[ "$failed" = 0 ] && echo "Module test passed."
exit "$failed"
