#!/bin/bash
# bin/check's citable-versions check against throwaway workflow pages, each
# in a scratch tree with its own copy of bin/check. Prints each failed case
# and nothing on success, so bin/check can run it.
#
#   tests/bin/test_citable_versions.sh
#
# bin/check name: citable versions test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# page <pass|fail> <name> <cite block lines>: the check over a tree in
# $scratch/<name> whose one workflow page holds that cite block.
page() {
    local tree="$scratch/$2"
    site_tree "$tree" some-workflow:ct-lab:active
    printf '%s\n' '  <details id="cite">' '    <summary>Cite this workflow</summary>' \
        "$3" '  </details>' >> "$tree/workflows/some-workflow/index.html"
    expect "$1" "$scratch/$2" "citable versions on"
}

doi='<a href="https://doi.org/10.48546/workflowhub.workflow.1234.1">10.48546/workflowhub.workflow.1234.1</a>'

page pass none-yet '    <ul><li>No citable version yet.</li></ul>'
page pass one "    <ul><li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li></ul>"
page pass two-newest-first "    <ul>
      <li>${doi//1234.1/1234.2} · 2027-03-01 · commit <code>0377991e7f8cc94e51c91d1499a2cf5377f14e66</code></li>
      <li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li>
    </ul>"
page fail not-workflowhub '    <ul><li><a href="https://doi.org/10.5281/zenodo.1234">10.5281/zenodo.1234</a> · 2026-11-02 · commit <code>d2c15b3</code></li></ul>'
page fail workflowhub-but-not-a-workflow '    <ul><li>10.48546/workflowhub.datafile.12.1 · 2026-11-02 · commit <code>d2c15b3</code></li></ul>'
page fail no-date "    <ul><li>$doi · commit <code>d2c15b3</code></li></ul>"
page fail no-commit "    <ul><li>$doi · 2026-11-02</li></ul>"
page fail v-label "    <ul><li>v1 · $doi · 2026-11-02 · commit <code>d2c15b3</code></li></ul>"
page fail version-label "    <h3 class=\"sub\">Version 2</h3>
    <ul><li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li></ul>"
page fail placeholder-left "    <ul>
      <li>No citable version yet.</li>
      <li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li>
    </ul>"
