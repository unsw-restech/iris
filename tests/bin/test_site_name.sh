#!/bin/bash
# bin/check's "page logos match; README cites CITATION.cff's title" check
# against throwaway trees, each with its own copy of bin/check. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_site_name.sh
#
# bin/check name: site name test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# logo <text> <page>: makes <text> the logo in <page>'s top bar, or with
# "" drops the top bar.
logo() {
    if [ -z "$1" ]; then sed -i '/nav-logo-text/d' "$2"; else sed -i "s|nav-logo-text\">[^<]*<|nav-logo-text\">$1<|" "$2"; fi
}

# site <pass|fail> <name> <landing logo> <workflow page logo>
#      <CITATION.cff title line> <README text>: the check over a tree in
# $scratch/<name>, a site_tree with one workflow page. The guide and
# contribute pages carry the landing logo, the guide's wrapped over CRLF
# lines. CITATION.cff holds its title line, and README.md ends with the
# README text ("" leaves either file out).
site() {
    local dir="$scratch/$2"
    site_tree "$dir" some-workflow:ct-lab:active
    logo "$3" "$dir/index.html"
    printf '<nav>\r\n  <span class="nav-logo-text">\r\n    %s\r\n  </span>\r\n</nav>\r\n' "$3" > "$dir/guide/index.html"
    logo "$3" "$dir/contribute/index.html"
    logo "$4" "$dir/workflows/some-workflow/index.html"
    [ -z "$5" ] || printf 'cff-version: 1.2.0\n%s\ntype: software\n' "$5" > "$dir/CITATION.cff"
    if [ -z "$6" ]; then rm "$dir/README.md"; else printf '%s\n' "$6" >> "$dir/README.md"; fi
    expect "$1" "$dir" "page logos match"
}

t='IRIS: Intelligent Research Imaging Suite'
cff="title: \"$t\""
quote="   > ResTech. *$t*, workflow \`w\`."

site pass same 'UNSW IRIS' 'UNSW IRIS' "$cff" "$quote"
site fail logos-differ 'UNSW IRIS' 'IRIS' "$cff" "$quote"
site fail workflow-page-has-no-logo 'UNSW IRIS' '' "$cff" "$quote"
site fail readme-title-stale 'UNSW IRIS' 'UNSW IRIS' "$cff" '   > ResTech. *IRIS: the AI Imaging Gateway*.'
site fail readme-title-truncated 'UNSW IRIS' 'UNSW IRIS' "title: \"$t, the Gateway\"" "$quote"
site fail title-only-outside-the-quote 'UNSW IRIS' 'UNSW IRIS' "$cff" "See *$t* below."
site fail cff-title-unquoted 'UNSW IRIS' 'UNSW IRIS' "title: $t" "$quote"
site pass no-citation 'UNSW IRIS' 'UNSW IRIS' '' "$quote"
site pass no-readme 'UNSW IRIS' 'UNSW IRIS' "$cff" ''
