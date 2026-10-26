#!/bin/bash
# bin/check's module command folder check against throwaway repos, each
# with its own copy of bin/check. The check reads git's index, since a
# clone with core.symlinks off checks links out as plain files. Prints
# each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_module_commands.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# repo <pass|fail> <name> [<link>=<target>...]: the check over a repo in
# $scratch/<name> holding bin/iris-view, bin/iris-compare and
# bin/iris-rebuild, and module/bin with each <link> pointing at <target>
# (a plain file if <target> is "file").
repo() {
    local want="$1" dir="$scratch/$2" pair link target
    shift 2
    git init -q "$dir"
    mkdir -p "$dir/bin" "$dir/module/bin"
    cp bin/check "$dir/bin/check"
    for link in iris-view iris-compare iris-rebuild; do echo '#!/bin/bash' > "$dir/bin/$link"; done
    for pair in "$@"; do
        link="${pair%%=*}"; target="${pair#*=}"
        if [ "$target" = file ]; then echo '#!/bin/bash' > "$dir/module/bin/$link"
        else ln -s "$target" "$dir/module/bin/$link"
        fi
    done
    git -C "$dir" add -A
    expect "$want" "$dir" "module commands are"
}

good=(iris-view=../../bin/iris-view iris-compare=../../bin/iris-compare)

repo pass both-links "${good[@]}"
repo fail no-compare iris-view=../../bin/iris-view
repo fail extra-rebuild "${good[@]}" iris-rebuild=../../bin/iris-rebuild
repo fail extra-check "${good[@]}" check=../../bin/check
repo fail swapped iris-view=../../bin/iris-compare iris-compare=../../bin/iris-view
repo fail absolute iris-view="$scratch/absolute/bin/iris-view" iris-compare=../../bin/iris-compare
repo fail plain-file iris-view=file iris-compare=../../bin/iris-compare
repo fail outside-bin iris-view=../../lib/iris-view iris-compare=../../bin/iris-compare
repo fail dangling iris-view=../../bin/iris-viewer iris-compare=../../bin/iris-compare
repo fail none
