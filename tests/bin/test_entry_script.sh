#!/bin/bash
# bin/check's "imaging forms embed their entry script" check against
# throwaway trees, each with its own copy of bin/check. Prints each failed
# case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_entry_script.sh
#
# bin/check name: entry script test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="imaging forms embed their entry script"

# An imaging form that embeds src/run.py in its script: as the microCT
# form does (ADR-0006).
imaging_form() {
    printf '%s\n' \
        '<% code = @apps_dir ? File.expand_path(File.join(@apps_dir, @OC_DIR_NAME)) : "" %>' \
        '<%- entry_script = "src/run.py" -%>' \
        '<%- entry_code = code.empty? ? "" : File.read(File.join(code, entry_script)).gsub(/^(?=.)/, "  ") -%>' \
        'form:' \
        '  epochs:' \
        '    widget: number' \
        'script: |' \
        '  #!/bin/bash' \
        '  #PBS -A iris-seg' \
        '  CODE="<%= code %>"' \
        '  ENV_DIR=/srv/scratch/katana_ai/iris/envs/imaging/1' \
        '  source "$CODE/../../lib/iris-job.sh"' \
        '' \
        "  cat > \"\$RUN_DIR/run.py\" <<'IRIS_RUN_PY_END'" \
        '<%= entry_code -%>' \
        '  IRIS_RUN_PY_END' \
        '  iris_record_edits <%= entry_script %>' \
        '  python "$RUN_DIR/run.py" --epochs #{epochs}' \
        'check: |' \
        '  oc_assert(@epochs.to_i > 0, "Epochs must be positive.")'
}

# make_tree <name>: a tree in $scratch/<name> holding bin/check, an imaging
# form that embeds its entry script, and hello-world's plain form, which
# embeds nothing.
make_tree() {
    local tree="$scratch/$1"
    mkdir -p "$tree/bin" "$tree/workflows/seg/src" "$tree/workflows/hello-world"
    cp bin/check "$tree/bin/check"
    imaging_form > "$tree/workflows/seg/form.yml.erb"
    printf '%s\n' 'import sys' '' 'print(f"{sys.argv}")  # a dict: {"a": 1}' > "$tree/workflows/seg/src/run.py"
    printf '%s\n' 'script: |' '  #!/bin/bash' '  #PBS -A iris-hello-world' '  echo "Hello #{name}"' > "$tree/workflows/hello-world/form.yml.erb"
}

# embeds <pass|fail> <name>: the check over $scratch/<name>, which the
# caller has built and changed.
embeds() {
    expect "$1" "$scratch/$2" "$name"
}

make_tree clean
embeds pass clean
# The heredoc that carries the entry script is the one heredoc script: allows.
expect pass "$scratch/clean" "form script: and check: sections"

make_tree no-embed
imaging_form | grep -v 'entry_' > "$scratch/no-embed/workflows/seg/form.yml.erb"
embeds fail no-embed

make_tree no-heredoc
imaging_form | grep -v 'IRIS_RUN_PY_END' > "$scratch/no-heredoc/workflows/seg/form.yml.erb"
embeds fail no-heredoc

make_tree missing-entry-script
rm "$scratch/missing-entry-script/workflows/seg/src/run.py"
embeds fail missing-entry-script

make_tree ocomposer-substitution
echo 'print("#{epochs}")' >> "$scratch/ocomposer-substitution/workflows/seg/src/run.py"
embeds fail ocomposer-substitution

make_tree erb-tag
echo '# <%= 1 %>' >> "$scratch/erb-tag/workflows/seg/src/run.py"
embeds fail erb-tag

# Any other heredoc in script: is still refused.
make_tree other-heredoc
sed -i "s|^  python |  cat > x <<EOF\n  EOF\n  python |" "$scratch/other-heredoc/workflows/seg/form.yml.erb"
expect fail "$scratch/other-heredoc" "form script: and check: sections"

# The job must record the edits between writing run.py and running it, so a
# run.py that Python cannot start still leaves its diff.
make_tree no-record
grep -v 'iris_record_edits' "$scratch/no-record/workflows/seg/form.yml.erb" > "$scratch/no-record.erb"
mv "$scratch/no-record.erb" "$scratch/no-record/workflows/seg/form.yml.erb"
embeds fail no-record
