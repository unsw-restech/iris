#!/bin/bash
# bin/check's "broken local links" check against throwaway site trees.
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_local_links.sh
#
# bin/check name: local links test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="broken local links"

# links <pass|fail> <case> <file> <line>: the check over a site with <line>
# appended to <file>, made if it isn't there.
links() {
    site_tree "$scratch/$2" seg:ct-lab:active tumour:mr-lab:planned
    mkdir -p "$(dirname "$scratch/$2/$3")"
    echo "$4" >> "$scratch/$2/$3"
    git -C "$scratch/$2" add -A
    expect "$1" "$scratch/$2" "$name"
}

site_tree "$scratch/clean" seg:ct-lab:active tumour:mr-lab:planned
expect pass "$scratch/clean" "$name"

links pass page-to-page workflows/seg/index.html '<a href="../tumour/">Tumour</a>'
links pass anchor-to-a-lab workflows/seg/index.html '<a href="../../#mr-lab">MR</a>'
links pass external workflows/seg/index.html '<a href="https://example.org/missing/">Elsewhere</a>'
links fail missing-page workflows/seg/index.html '<a href="../gone/">Gone</a>'
links fail missing-anchor guide/index.html '<a href="../#no-such-lab">Labs</a>'
links fail missing-anchor-on-same-page index.html '<a href="#nowhere">Up</a>'
links pass anchor-on-same-page index.html '<a href="#workflows">Up</a>'
links fail readme-link README.md 'See [the guide](guide/missing.html).'
links pass readme-link-ok README.md 'See [the guide](guide/).'
links fail site-url-in-a-doc CONTRIBUTING.md 'Read https://docs.restech.unsw.edu.au/iris/guide/#nowhere first.'
links pass site-url-ok CONTRIBUTING.md 'Read https://docs.restech.unsw.edu.au/iris/workflows/seg/ first.'
links pass md-anchor CONTRIBUTING.md $'### 7. CI and `ready`\nSee [CI](#7-ci-and-ready).'
links pass md-anchor-to-a-repeat CONTRIBUTING.md $'## Notes\n## Notes\nSee [the second](#notes-1).'
links fail md-anchor-missing CONTRIBUTING.md 'See [the old steps](#from-proposal-to-doi).'
links fail md-anchor-in-a-fence CONTRIBUTING.md $'```\n## Hidden\n```\nSee [it](#hidden).'
links pass md-link-in-a-fence CONTRIBUTING.md $'```\n[x](nowhere.md)\n```'
links fail md-anchor-in-another-file CONTRIBUTING.md 'See [its map](README.md#no-such-heading).'
links pass md-anchor-in-another-file-ok CONTRIBUTING.md 'See [its map](README.md#iris).'
links fail md-link-in-a-subfolder docs/x.md 'See [the ADR](adr/missing.md).'
links pass md-link-in-a-tilde-fence CONTRIBUTING.md $'~~~\n[x](nowhere.md)\n~~~'
links pass md-link-in-inline-code CONTRIBUTING.md 'Write `[x](nowhere.md)` for a link.'
links pass md-anchor-to-a-heading-with-a-link CONTRIBUTING.md $'## See [the guide](guide/) now\n[it](#see-the-guide-now)'
links pass md-link-to-a-folder CONTRIBUTING.md 'See [the workflows](workflows/).'
