#!/bin/bash
# bin/check's "Katana constants" check against throwaway trees, each with
# its own copy of bin/check and lib/katana.sh: the copies that must stay
# literal (an imaging form's pane ENV_DIR and its Ruby test for the system
# clone, the modulefile's path, the form tests' system apps_dir) agree with
# lib/katana.sh, and no script under bin/, lib/ or module/ keeps a copy of
# its own. Prints each failed case and nothing on success, so bin/check can
# run it.
#
#   tests/bin/test_katana_constants.sh
#
# bin/check name: Katana constants test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="Katana constants match lib/katana.sh"
clone=/srv/scratch/katana_ai/iris/code
env=/srv/scratch/katana_ai/iris/envs/imaging/1

# make_tree <name>: a site whose seg workflow has an imaging form holding
# the literal copies, its form test, the modulefile and a tool that takes
# the constants from lib/katana.sh.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active
    mkdir -p "$tree/lib" "$tree/module/modulefiles" "$tree/workflows/seg/tests"
    cp lib/katana.sh "$tree/lib/katana.sh"
    printf '%s\n' \
        '<%-' \
        "  if @apps_dir && File.expand_path(@apps_dir) == \"$clone/workflows\"" \
        '    load_iris = "module load iris"' \
        '  end' \
        '-%>' \
        'script: |' \
        '  #!/bin/bash' \
        '  #PBS -A iris-seg' \
        "  ENV_DIR=$env" \
        '  source "$CODE/../../lib/iris-job.sh"' \
        "  cat > \"\$RUN_DIR/run.py\" <<'IRIS_RUN_PY_END'" \
        '<%= entry_code -%>' \
        '  IRIS_RUN_PY_END' \
        > "$tree/workflows/seg/form.yml.erb"
    printf '%s\n' 'class FormTest' "  SYSTEM_APPS_DIR = \"$clone/workflows\"" 'end' \
        > "$tree/workflows/seg/tests/test_form.rb"
    printf '%s\n' '#%Module1.0' "prepend-path PATH $clone/module/bin" > "$tree/module/modulefiles/iris"
    printf '%s\n' '#!/bin/bash' '. "$(dirname "$0")/../lib/katana.sh"' 'echo "$IRIS_ENV_DIR"' > "$tree/bin/iris-tool"
    git -C "$tree" add -A
}

# case <pass|fail> <name> <file> <sed script>: the check over a tree from
# make_tree with <sed script> applied to <file>.
case_() {
    local want="$1" tree="$scratch/$2" file="$3" script="$4"
    make_tree "$2"
    sed -i "$script" "$tree/$file"
    git -C "$tree" add -A
    expect "$want" "$tree" "$name"
}

make_tree clean
expect pass "$scratch/clean" "$name"

case_ pass crlf workflows/seg/form.yml.erb 's/$/\r/'
case_ pass crlf-modulefile module/modulefiles/iris 's/$/\r/'

# Each literal copy that drifts from lib/katana.sh fails.
case_ fail form-env workflows/seg/form.yml.erb 's|imaging/1$|imaging/2|'
case_ fail form-clone workflows/seg/form.yml.erb 's|iris/code/workflows|iris/code2/workflows|'
case_ fail modulefile module/modulefiles/iris 's|iris/code/module|iris/code2/module|'
case_ fail form-test workflows/seg/tests/test_form.rb 's|iris/code/workflows|iris/code2/workflows|'
# Bumping the environment in lib/katana.sh alone leaves the form behind.
case_ fail env-bump lib/katana.sh 's|^IRIS_ENV_DIR=.*|IRIS_ENV_DIR=/srv/scratch/katana_ai/iris/envs/imaging/2|'
# A copy that is missing can't be compared, so it fails too.
case_ fail form-no-env workflows/seg/form.yml.erb '/ENV_DIR=/d'
case_ fail modulefile-no-path module/modulefiles/iris '/prepend-path/d'

# A script that keeps its own copy of a constant fails, wherever it sits.
case_ fail tool-env bin/iris-tool "s|\"\$IRIS_ENV_DIR\"|$env|"
case_ fail tool-module bin/iris-tool 's|$IRIS_ENV_DIR|python/3.13.2|'
make_tree job-clone
mkdir -p "$scratch/job-clone/lib/tests/katana"
printf '%s\n' '#!/bin/bash' "CODE=$clone" > "$scratch/job-clone/lib/tests/katana/inspect.pbs"
git -C "$scratch/job-clone" add -A
expect fail "$scratch/job-clone" "$name"

# hello-world's form isn't an imaging form, so it pins no environment.
make_tree hello
mkdir -p "$scratch/hello/workflows/hello-world"
printf '%s\n' 'script: |' '  #!/bin/bash' '  #PBS -A iris-hello-world' '  echo "Hello"' \
    > "$scratch/hello/workflows/hello-world/form.yml.erb"
git -C "$scratch/hello" add -A
expect pass "$scratch/hello" "$name"
