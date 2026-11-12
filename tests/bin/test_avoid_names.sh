#!/bin/bash
# bin/check's rule that names keep to GLOSSARY.md's terms against throwaway
# trees, and .githooks/commit-msg's refusal of the same words, the ones
# .githooks/avoid-names lists, in a commit message. Prints each failed case
# and nothing on success, so bin/check can run it.
#
#   tests/bin/test_avoid_names.sh
#
# bin/check name: glossary names test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="name uses a glossary Avoid word"

# make_tree <name> <file> <line>: a passing site with <line> in <file>.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree"
    mkdir -p "$tree/$(dirname "$2")"
    printf '%s\n' "$3" > "$tree/$2"
    git -C "$tree" add -A
}

make_tree extension lib/job.sh 'apptainer exec "$IRIS_ENVS_FOLDER/microct/1.sif" python run.py'
expect pass "$scratch/extension" "$name"
make_tree inside-a-word lib/job.sh 'classify=1  # sift through the volumes'
expect pass "$scratch/inside-a-word" "$name"
make_tree glossary GLOSSARY.md '_Avoid_: Image, container image, SIF'
expect pass "$scratch/glossary" "$name"
make_tree adr docs/adr/0004-one-image.md 'into a sealed SIF beside the venv versions'
expect pass "$scratch/adr" "$name"

make_tree env-var lib/iris-job.sh 'IRIS_ENV_SIF="$folder/$v.sif"'
expect fail "$scratch/env-var" "$name"
make_tree local bin/envrun 'local sif="$cache/$digest.sif"'
expect fail "$scratch/local" "$name"
make_tree python-name lib/tests/test_job_lib.py 'sif_path = os.environ["IRIS_ENV_FILE"]'
expect fail "$scratch/python-name" "$name"
make_tree prose CONTRIBUTING.md 'Each version is one SIF on Katana.'
expect fail "$scratch/prose" "$name"

# "System OpenComposer" (#163) has no use outside the glossary: #163 left it
# in three files and its cleanup in lib/katana.sh, wrapped across a comment's
# line break. A workflow's library copy keeps lib/'s words at the commit it
# was copied from, so it is left to bin/libcopy.
make_tree system-oc-glossary GLOSSARY.md '_Avoid_: System OpenComposer, shared instance'
expect pass "$scratch/system-oc-glossary" "$name"
make_tree system-oc-comment lib/katana.sh '# the system OpenComposer serves its workflows/'
expect fail "$scratch/system-oc-comment" "$name"
make_tree system-oc-prose CONTRIBUTING.md 'System OpenComposer serves the system clone.'
expect fail "$scratch/system-oc-prose" "$name"
make_tree system-oc-wrapped lib/katana.sh "$(printf '# see AGENTS.md): the system\n# OpenComposer serves its workflows/')"
expect fail "$scratch/system-oc-wrapped" "$name"
make_tree system-oc-standard CODING_STANDARDS.md '#163 added "system OpenComposer" and left it'
expect fail "$scratch/system-oc-standard" "$name"
make_tree system-oc-copy workflows/seg/lib/katana.sh "$(printf '# the system\n# OpenComposer serves its workflows/')"
expect pass "$scratch/system-oc-copy" "$name"
make_tree shared-instance bin/syspull '# deploys to the shared instance'
expect fail "$scratch/shared-instance" "$name"
make_tree shared-instance-wrapped CONTRIBUTING.md "$(printf 'the shared\ninstance serves it')"
expect fail "$scratch/shared-instance-wrapped" "$name"
# A failure names the line a phrase starts on, and a deleted tracked file
# is skipped.
make_tree line-number lib/katana.sh "$(printf 'one\ntwo\n# the shared\n# instance')"
out="$("$scratch/line-number/bin/check" "$name" 2>&1)"
grep -qF 'lib/katana.sh:3: shared instance' <<< "$out" || { echo "line-number: wrong line"; echo "$out" | sed 's/^/  /'; }
make_tree deleted lib/gone.sh 'echo gone'
rm "$scratch/deleted/lib/gone.sh"
expect pass "$scratch/deleted" "$name"
make_tree shared-instances docs/agents/x.md 'two shared instances of nothing'
expect pass "$scratch/shared-instances" "$name"

# hook <pass|fail> <label> <message>: .githooks/commit-msg on <message>,
# printing <label> and the hook's output when its verdict is not the one
# wanted.
hook() {
    local out rc
    printf '%s\n' "$3" > "$scratch/$2.msg"
    out="$(.githooks/commit-msg "$scratch/$2.msg" 2>&1)"
    rc=$?
    if [ "$1" = pass ] && [ "$rc" != 0 ]; then
        echo "$2: hook refused the message"
    elif [ "$1" = fail ] && { [ "$rc" != 1 ] || ! grep -q 'Avoid word' <<< "$out"; }; then
        echo "$2: hook passed (exit $rc), expected a refusal"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

hook pass msg-clean "The shared OpenComposer ignores the key, as 1.9.0 reads keys by name"
hook pass msg-extension "bin/envpull-dm.sh writes microct/1.sif on the data mover"
hook fail msg-shared-instance "so the shared instance ignores the key"
hook fail msg-system-oc "Point the system OpenComposer at workflows/"
hook fail msg-sif "Each version is one SIF on Katana"
hook fail msg-wrapped "Merge #161: the form names its region, which the shared
instance ignores"
hook pass msg-comment-only "Fix a typo
# the shared instance, in a comment git strips"
