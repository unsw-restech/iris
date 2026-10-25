#!/bin/bash
# bin/check's citable-versions check against throwaway workflow pages in a
# scratch folder, which IRIS_CHECK_PAGES points it at. Prints each failed
# case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_citable_versions.sh

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# expect <pass|fail> <name> <cite block lines>: the check over one workflow
# page, $scratch/<name>/some-workflow/index.html, holding that cite block.
expect() {
    local want="$1" name="$2" page out rc
    page="$scratch/$name/some-workflow/index.html"
    mkdir -p "$(dirname "$page")"
    printf '%s\n' '<div class="page">' '  <h1 class="wf-title">Some workflow</h1>' \
        '  <details id="cite">' '    <summary>Cite this workflow</summary>' \
        "$3" '  </details>' '</div>' > "$page"
    out="$(IRIS_CHECK_PAGES="$scratch/$name" bin/check "citable versions on" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "$name failed on a good page"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep -q '^FAIL: citable versions on' <<< "$out"; }; then
        echo "$name passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

doi='<a href="https://doi.org/10.48546/workflowhub.workflow.1234.1">10.48546/workflowhub.workflow.1234.1</a>'

expect pass none-yet '    <ul><li>No citable version yet.</li></ul>'
expect pass one "    <ul><li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li></ul>"
expect pass two-newest-first "    <ul>
      <li>${doi//1234.1/1234.2} · 2027-03-01 · commit <code>0377991e7f8cc94e51c91d1499a2cf5377f14e66</code></li>
      <li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li>
    </ul>"
expect fail not-workflowhub '    <ul><li><a href="https://doi.org/10.5281/zenodo.1234">10.5281/zenodo.1234</a> · 2026-11-02 · commit <code>d2c15b3</code></li></ul>'
expect fail workflowhub-but-not-a-workflow '    <ul><li>10.48546/workflowhub.datafile.12.1 · 2026-11-02 · commit <code>d2c15b3</code></li></ul>'
expect fail no-date "    <ul><li>$doi · commit <code>d2c15b3</code></li></ul>"
expect fail no-commit "    <ul><li>$doi · 2026-11-02</li></ul>"
expect fail v-label "    <ul><li>v1 · $doi · 2026-11-02 · commit <code>d2c15b3</code></li></ul>"
expect fail version-label "    <h3 class=\"sub\">Version 2</h3>
    <ul><li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li></ul>"
expect fail placeholder-left "    <ul>
      <li>No citable version yet.</li>
      <li>$doi · 2026-11-02 · commit <code>d2c15b3</code></li>
    </ul>"
