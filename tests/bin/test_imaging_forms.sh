#!/bin/bash
# The rules bin/check applies to imaging forms, against throwaway trees: an
# imaging form is one whose script carries its entry script in a heredoc
# (GLOSSARY.md), whatever else it drops, and hello-world's form is not one.
# Each imaging form's rendered script is checked by lib/tests/imaging_form.rb,
# whose own tests (lib/tests/test_imaging_form.rb) break each part; these
# cases check which forms bin/check hands it, and that it needs Ruby.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_imaging_forms.sh
#
# bin/check name: imaging forms test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# make_tree <name>: a site whose seg workflow has the reference imaging form
# and entry script, beside hello-world's form, and the form checker.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active
    mkdir -p "$tree/workflows/seg/src" "$tree/workflows/hello-world" "$tree/lib/tests"
    sed 's/#PBS -A iris-microct-2d-segmentation/#PBS -A iris-seg/' workflows/microct-2d-segmentation/form.yml.erb \
        > "$tree/workflows/seg/form.yml.erb"
    cp workflows/microct-2d-segmentation/src/run.py "$tree/workflows/seg/src/"
    cp workflows/hello-world/form.yml.erb "$tree/workflows/hello-world/"
    cp lib/tests/form_helper.rb lib/tests/imaging_form.rb "$tree/lib/tests/"
}

name="imaging forms' rendered scripts"

# hello-world's form, which carries no entry script, is not checked.
make_tree clean
expect pass "$scratch/clean" "$name"

make_tree no-source
sed -i '/iris-job\.sh/d' "$scratch/no-source/workflows/seg/form.yml.erb"
expect fail "$scratch/no-source" "$name"

# Dropping ENV_DIR and the record call too still leaves an imaging form,
# so it is still checked.
make_tree no-source-no-env
sed -i '/iris-job\.sh/d; /ENV_DIR=/d; /<%= entry_script %>/d' "$scratch/no-source-no-env/workflows/seg/form.yml.erb"
expect fail "$scratch/no-source-no-env" "$name"

# A heredoc that never ends still opens the entry script, so it is checked.
make_tree no-end-marker
sed -i '/^<%= entry_code -%>$/{n;d}' "$scratch/no-end-marker/workflows/seg/form.yml.erb"
expect fail "$scratch/no-end-marker" "$name"

# A form with an environment but no entry script heredoc isn't an imaging
# form.
make_tree env-only
printf '%s\n' 'script: |' '  #!/bin/bash' '  #PBS -A iris-seg' '  ENV_DIR=/srv/scratch/katana_ai/iris/envs/imaging/1' \
    > "$scratch/env-only/workflows/seg/form.yml.erb"
expect pass "$scratch/env-only" "$name"

# A Windows working copy can hold a CRLF form; it is still found and checked.
make_tree crlf
sed -i 's/$/\r/' "$scratch/crlf/workflows/seg/form.yml.erb"
expect pass "$scratch/crlf" "$name"
sed -i '/iris-job\.sh/d' "$scratch/crlf/workflows/seg/form.yml.erb"
expect fail "$scratch/crlf" "$name"

# Without Ruby the check fails, naming how to install it, rather than
# passing on a machine that cannot run it.
make_tree no-ruby
mkdir "$scratch/no-ruby-bin"
for c in /usr/bin/*; do
    case "${c##*/}" in ruby*) ;; *) ln -s "$c" "$scratch/no-ruby-bin/" ;; esac
done
out="$(PATH="$scratch/no-ruby-bin" "$scratch/no-ruby/bin/check" "$name" 2>&1)"
grep -qF 'sudo apt install ruby' <<< "$out" && grep -q "^FAIL: $name" <<< "$out" ||
    { echo "no-ruby: expected a failure naming sudo apt install ruby"; echo "$out" | sed 's/^/  /'; }

# The heredoc that carries the entry script is the one heredoc script:
# allows; any other is still refused.
expect pass "$scratch/clean" "form script: and check: sections"
make_tree other-heredoc
sed -i "s|^  iris_done|  cat > x <<EOF\n  EOF\n  iris_done|" "$scratch/other-heredoc/workflows/seg/form.yml.erb"
expect fail "$scratch/other-heredoc" "form script: and check: sections"
