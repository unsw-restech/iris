#!/bin/bash
# bin/check's "no full paths to iris-view or iris-compare" check against
# throwaway trees, each with its own copy of bin/check. Prints each failed
# case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_module_paths.sh
#
# bin/check name: module paths test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="full paths to iris-view or iris-compare"
full=/srv/scratch/katana_ai/iris/code/bin

# A form that prints the module lines from the system clone and builds the
# dev clone's full paths in Ruby, as the microCT form does.
form() {
    printf '%s\n' \
        '<%-' \
        '  # Rendered from any other clone, the commands are that clone'"'"'s' \
        '  # bin/iris-view and bin/iris-compare in full.' \
        '  from_system_clone = File.expand_path(@apps_dir.to_s) == "/srv/scratch/katana_ai/iris/code/workflows"' \
        '  bin = File.expand_path(File.join(@apps_dir.to_s, "..", "bin"))' \
        '  iris_view = from_system_clone ? "iris-view" : File.join(bin, "iris-view")' \
        '  iris_compare = from_system_clone ? "iris-compare" : "#{bin}/iris-compare"' \
        '-%>' \
        'form:' \
        '  experiment:' \
        '    help: "to compare runs, run <%= from_system_clone ? "module load iris and then iris-compare" : iris_compare %>."' \
        'script: |' \
        '  <%- if from_system_clone -%>' \
        '  echo "module load iris"' \
        '  <%- end -%>' \
        '  echo "<%= iris_view %> $RUN_DIR"' \
        '  echo "<%= iris_compare %>"'
}

# make_tree <name>: a tree in $scratch/<name> whose pages, form and README
# give only the module commands, with a full path to iris-rebuild in the
# guide and README, and the wrappers' full paths in maintainer text.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active
    mkdir -p "$tree/_archive/old"
    printf '%s\n' '<p>Run <code>module load iris</code>, then <code>iris-view</code>.</p>' \
        "<p>If it is lost, run <code>$full/iris-rebuild</code>.</p>" >> "$tree/guide/index.html"
    echo '<p>Run <code>iris-compare</code>.</p>' >> "$tree/workflows/seg/index.html"
    form > "$tree/workflows/seg/form.yml.erb"
    printf '%s\n' '| `module/bin/` | `module load iris` gives you `iris-view` and `iris-compare`.' \
        "If your tracking store is lost, \`$full/iris-rebuild\` rebuilds it |" >> "$tree/README.md"
    printf '%s\n' '├── bin/' '│   ├── iris-view    # bin/iris-view, the wrapper' >> "$tree/CONTRIBUTING.md"
    printf '%s\n' '#!/bin/bash' '# bin/iris-compare runs the importer first.' > "$tree/bin/iris-import"
    echo "help: \"run $full/iris-compare\"" > "$tree/_archive/old/form.yml.erb"
}

# site <pass|fail> <name> [<file> <line>]: the check over a tree from
# make_tree, with <line> appended to <file>. A failure must name the file
# and the line.
site() {
    local want="$1" tree="$scratch/$2" out n
    make_tree "$2"
    if [ $# -ge 4 ]; then
        echo "$4" >> "$tree/$3"
        n=$(wc -l < "$tree/$3")
    fi
    git -C "$tree" add -A
    expect "$want" "$tree" "$name"
    if [ "$want" = fail ]; then
        out="$("$tree/bin/check" "$name" 2>&1)"
        grep -qF -- "$3:$n:" <<< "$out" || { echo "$2: failure doesn't name $3:$n"; echo "$out" | sed 's/^/  /'; }
    fi
}

site pass clean
site pass rebuild-in-page workflows/seg/index.html "<p>Or run <code>$full/iris-rebuild</code>.</p>"
site fail view-in-page workflows/seg/index.html "<p>Run <code>$full/iris-view</code> on the run.</p>"
site fail compare-in-guide guide/index.html "<p>Run <code>$full/iris-compare</code>.</p>"
site fail dev-clone-in-page workflows/seg/index.html '<p>Run <code>~/iris/bin/iris-view</code>.</p>'
site fail compare-in-readme README.md "Then run \`$full/iris-compare\`."
site fail view-in-form-text workflows/seg/form.yml.erb "  echo \"$full/iris-view \$RUN_DIR\""
site fail compare-in-form-variable workflows/seg/form.yml.erb '  echo "$IRIS_BIN/iris-compare"'
site fail form-output-tag workflows/seg/form.yml.erb \
    '    help: "run <%= File.expand_path(File.join(@apps_dir.to_s, "..", "bin", "iris-compare")) %> in a terminal."'
site fail form-output-join-variable workflows/seg/form.yml.erb \
    '    help: "run <%= File.join(bin, "iris-compare") %> in a terminal."'

# A copy of the site outside git's index, such as a worktree under
# .claude/worktrees/, isn't read: only tracked pages are.
make_tree untracked-copy
git -C "$scratch/untracked-copy" add -A
mkdir -p "$scratch/untracked-copy/old-worktree/guide"
echo "<p>Run <code>$full/iris-view</code>.</p>" > "$scratch/untracked-copy/old-worktree/guide/index.html"
expect pass "$scratch/untracked-copy" "$name"
