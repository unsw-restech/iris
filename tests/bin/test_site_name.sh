#!/bin/bash
# bin/check's "one site name across pages, README and CITATION.cff" check
# against throwaway trees, each with its own copy of bin/check. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_site_name.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# site <pass|fail> <name> <landing logo> <guide logo> <CITATION.cff title>
#      <README citation title>: the check over a tree in $scratch/<name>
# with a landing page and a guide page carrying those logos, and a
# CITATION.cff and README.md carrying those titles ("" leaves the file out).
site() {
    local dir="$scratch/$2"
    mkdir -p "$dir/bin" "$dir/guide"
    cp bin/check "$dir/bin/check"
    echo "<nav><a href=\"./\"><span class=\"nav-logo-text\">$3</span></a></nav>" > "$dir/index.html"
    printf '<nav>\r\n  <span class="nav-logo-text">%s</span>\r\n</nav>\r\n' "$4" > "$dir/guide/index.html"
    [ -z "$5" ] || printf 'cff-version: 1.2.0\ntitle: "%s"\ntype: software\n' "$5" > "$dir/CITATION.cff"
    [ -z "$6" ] || printf '# IRIS\n\n   > ResTech. *%s*, workflow `w`.\n' "$6" > "$dir/README.md"
    expect "$1" "$dir" "one site name"
}

t='IRIS: Intelligent Research Imaging Suite'

site pass same 'UNSW IRIS' 'UNSW IRIS' "$t" "$t"
site fail logos-differ 'UNSW IRIS' 'IRIS' "$t" "$t"
site fail readme-title-stale 'UNSW IRIS' 'UNSW IRIS' "$t" 'IRIS: the AI Imaging Gateway'
site fail readme-title-truncated 'UNSW IRIS' 'UNSW IRIS' "$t, the Gateway" "$t"
site pass no-citation 'UNSW IRIS' 'UNSW IRIS' '' "$t"
site pass no-readme 'UNSW IRIS' 'UNSW IRIS' "$t" ''
