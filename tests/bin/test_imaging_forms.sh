#!/bin/bash
# The rules bin/check applies to imaging forms, against throwaway trees: an
# imaging form is one whose script carries its entry script in a heredoc
# (GLOSSARY.md), whatever else it drops, and hello-world's form is not one.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_imaging_forms.sh
#
# bin/check name: imaging forms test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# An imaging form's script, as far as these rules read it.
imaging_script() {
    printf '%s\n' \
        'script: |' \
        '  #!/bin/bash' \
        '  #PBS -A iris-seg' \
        '  ENV_DIR=/srv/scratch/katana_ai/iris/envs/imaging/1' \
        '  source "$CODE/../../lib/iris-job.sh"' \
        "  cat > \"\$RUN_DIR/run.py\" <<'IRIS_RUN_PY_END'" \
        '<%= entry_code -%>' \
        '  IRIS_RUN_PY_END' \
        '  python "$RUN_DIR/run.py"'
}

# make_tree <name>: a site whose seg workflow has an imaging form, beside
# hello-world's plain form, which sources nothing.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active
    mkdir -p "$tree/workflows/hello-world"
    imaging_script > "$tree/workflows/seg/form.yml.erb"
    printf '%s\n' 'script: |' '  #!/bin/bash' '  #PBS -A iris-hello-world' '  echo "Hello"' \
        > "$tree/workflows/hello-world/form.yml.erb"
}

name="imaging forms source the job library"

make_tree clean
expect pass "$scratch/clean" "$name"

make_tree no-source
sed -i '/iris-job\.sh/d' "$scratch/no-source/workflows/seg/form.yml.erb"
expect fail "$scratch/no-source" "$name"

# Dropping ENV_DIR too still leaves an imaging form, so it is still checked.
make_tree no-source-no-env
sed -i '/iris-job\.sh/d; /ENV_DIR=/d' "$scratch/no-source-no-env/workflows/seg/form.yml.erb"
expect fail "$scratch/no-source-no-env" "$name"

# A form with an environment but no entry script heredoc isn't an imaging
# form.
make_tree env-only
printf '%s\n' 'script: |' '  #!/bin/bash' '  #PBS -A iris-seg' '  ENV_DIR=/srv/scratch/katana_ai/iris/envs/imaging/1' \
    > "$scratch/env-only/workflows/seg/form.yml.erb"
expect pass "$scratch/env-only" "$name"

make_tree crlf
sed -i 's/$/\r/' "$scratch/crlf/workflows/seg/form.yml.erb"
expect pass "$scratch/crlf" "$name"
