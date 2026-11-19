#!/bin/bash
# bin/check's "manifest descriptions hold no <" check against throwaway site
# trees. OpenComposer's form writes a manifest's description into the page
# as raw HTML, so a <placeholder> vanishes (#220). Prints each failed case
# and nothing on success, so bin/check can run it.
#
#   tests/bin/test_manifest_description.sh
#
# bin/check name: manifest description test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="manifest descriptions hold no <"

# manifest_tree <case>: a site with one workflow, whose manifest is standard input.
manifest_tree() {
    site_tree "$scratch/$1" seg:ct-lab:active
    cat > "$scratch/$1/workflows/seg/manifest.yml"
}

# failure_says <case> <text>...: the check's output on <case> holds each <text>.
failure_says() {
    local case="$1" want out
    shift
    out="$("$scratch/$case/bin/check" "$name" 2>&1)"
    for want in "$@"; do
        grep -qF -- "$want" <<< "$out" || { echo "$case: the failure doesn't say $want:"; echo "$out" | sed 's/^/  /'; }
    done
}

manifest_tree braces <<'EOF'
name: Segmentation
description: |
  Everything lands in `{dataset}/runs/{job ID}/`.
EOF
expect pass "$scratch/braces" "$name"

manifest_tree block <<'EOF'
name: Segmentation
description: |
  Everything lands in `<dataset>/runs/<job ID>/`.
EOF
expect fail "$scratch/block" "$name"
failure_says block workflows/seg/manifest.yml HTML '{like this}'

manifest_tree one-line <<'EOF'
description: "Results go to <dataset>"
EOF
expect fail "$scratch/one-line" "$name"

# The last line of the description, with the file's line endings Windows's.
manifest_tree crlf <<'EOF'
description: |
  Results go to
  <dataset>
EOF
sed -i 's/$/\r/' "$scratch/crlf/workflows/seg/manifest.yml"
expect fail "$scratch/crlf" "$name"

# Every < here is outside the description's value.
manifest_tree outside <<'EOF'
# A comment naming <dataset>, above the description.
name: Segmentation <2D>
description: |
  Everything lands in `{dataset}/runs/{job ID}/`.
# A comment naming <job ID>, below it.
owner:
  description: <not the manifest's description>
EOF
expect pass "$scratch/outside" "$name"

manifest_tree trailing-comment <<'EOF'
description: Results go to the dataset # under <dataset>
EOF
expect pass "$scratch/trailing-comment" "$name"

# A manifest the check can't read fails rather than passing unread.
manifest_tree unreadable <<'EOF'
description: "never closed
EOF
expect fail "$scratch/unreadable" "$name"
failure_says unreadable workflows/seg/manifest.yml

# OpenComposer never serves _archive/.
manifest_tree archived <<'EOF'
description: Results go to the dataset
EOF
mkdir -p "$scratch/archived/_archive/old"
echo 'description: Results go to <dataset>' > "$scratch/archived/_archive/old/manifest.yml"
expect pass "$scratch/archived" "$name"
