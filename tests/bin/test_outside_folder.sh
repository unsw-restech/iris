#!/bin/bash
# bin/outside-folder against throwaway repos, each a main branch and a pull
# request's branch off it: a PR that changes only a workflow's folder, its
# card in index.html and its lab's recipe is not flagged; one that changes
# anything else is, each flagged path named once. Prints each failed case
# and nothing on success, so bin/check can run it.
#
#   tests/bin/test_outside_folder.sh
#
# bin/check name: out-of-folder flag test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

commit() {
    git -C "$scratch/$1" add -A
    git -C "$scratch/$1" -c user.name=t -c user.email=t@example.org commit -q -m "${2:-change}"
}

# card <slug>: a catalogue card's lines.
card() {
    printf '%s\n' "    <a href=\"workflows/$1/\" class=\"workflow-card\">" \
        "      <div class=\"card-name\">$1</div>" '    </a>'
}

# make_repo <name>: a repo whose main holds the ct-lab section, with seg's
# card, and the mri-lab section, with mri's; the seg and mri workflows; the
# lab table [ct-lab]=ct/1 and [mri-lab]=mr/2 and the digest map's ct/1 and
# mr/2; the ct and mr recipes; a CONTRIBUTING.md whose tier table has seg
# Run and verified, citing its job, and bone and knee Planned; and
# bin/outside-folder. Then a branch, pr, checked out.
make_repo() {
    local r="$scratch/$1"
    mkdir -p "$r/bin" "$r/lib" "$r/workflows/seg/src" "$r/workflows/mri" "$r/envs/ct/1" "$r/envs/mr/2"
    cp bin/outside-folder "$r/bin/"
    katana_copy "$r/lib/katana.sh"
    lab_table "$r/lib/katana.sh" ct-lab=ct/1 mri-lab=mr/2 || exit 1
    digest_map "$r/lib/katana.sh" "ct/1=sha256:$(printf 'a%.0s' {1..64})" "mr/2=sha256:$(printf 'b%.0s' {1..64})" || exit 1
    {
        echo '# For workflow authors'
        echo
        echo '| Tier | Workflows | What exists |'
        echo '|---|---|---|'
        echo '| **Run and verified** | `hello-world` (onboarding), `seg` (CT) | Page, form |'
        echo '| **Planned** | `bone`, `knee` (CT) | Page only |'
        echo
        echo '`seg` ran from the test instance (job 1).'
        echo
        echo 'The end.'
    } > "$r/CONTRIBUTING.md"
    {
        echo '<h1>IRIS</h1>'
        echo '  <div class="lab" id="ct-lab">'
        card seg
        echo '  </div>'
        echo
        echo '  <div class="lab" id="mri-lab">'
        card mri
        echo '  </div>'
        echo '<footer>IRIS</footer>'
    } > "$r/index.html"
    echo "print(1)" > "$r/workflows/seg/src/run.py"
    echo "script: |" > "$r/workflows/mri/form.yml.erb"
    echo "numpy" > "$r/envs/ct/requirements.in"
    echo "numpy==2.0" > "$r/envs/ct/1/requirements.lock"
    echo "scipy" > "$r/envs/mr/requirements.in"
    echo "# check" > "$r/bin/check"
    echo "# repo" > "$r/README.md"
    git init -q -b main "$r"
    commit "$1" main
    git -C "$r" checkout -q -b pr
}

# expect <name> <want exit> [<flagged line>...]: bin/outside-folder main in
# repo <name> exits <want exit> and prints exactly the lines given.
expect() {
    local name="$1" want="$2" out rc
    shift 2
    out="$(cd "$scratch/$name" && bin/outside-folder main 2>&1)"
    rc=$?
    [ "$rc" = "$want" ] || echo "$name: exit $rc, expected $want"
    [ "$out" = "$(printf '%s\n' "$@")" ] || {
        echo "$name: printed"; echo "$out" | sed 's/^/  /'
        echo "  expected"; printf '%s\n' "$@" | sed 's/^/  /'
    }
}

# The workflow's folder alone, files added and removed: not flagged.
make_repo folder
echo "print(2)" > "$scratch/folder/workflows/seg/src/run.py"
echo "x" > "$scratch/folder/workflows/seg/new.txt"
commit folder
expect folder 0

# A new workflow: its folder and its card, added in its lab's section with
# the blank line before it, and its lab's next environment version in the
# lab's recipe: not flagged.
make_repo new
mkdir -p "$scratch/new/workflows/bone" "$scratch/new/envs/ct/2"
echo "script: |" > "$scratch/new/workflows/bone/form.yml.erb"
awk -v c="$(echo; card bone)" '{ print } /^  <div class="lab" id="ct-lab">$/ { f = 1 } f && /^    <\/a>$/ { print c; f = 0 }' \
    "$scratch/new/index.html" > "$scratch/new/index.tmp"
mv "$scratch/new/index.tmp" "$scratch/new/index.html"
echo "numpy scipy" > "$scratch/new/envs/ct/requirements.in"
echo "numpy==2.0" > "$scratch/new/envs/ct/2/requirements.lock"
commit new
expect new 0

# Editing its own card's text: not flagged.
make_repo own-card
sed -i 's|<div class="card-name">seg</div>|<div class="card-name">Segmentation</div>|' "$scratch/own-card/index.html"
echo "print(2)" > "$scratch/own-card/workflows/seg/src/run.py"
commit own-card
expect own-card 0

# What bin/new-workflow writes in CONTRIBUTING.md for a Planned workflow,
# bone: its slug moved from the Planned row to Run and verified, and the
# line citing its job after the table: not flagged.
make_repo scaffold
mkdir -p "$scratch/scaffold/workflows/bone"
echo "script: |" > "$scratch/scaffold/workflows/bone/form.yml.erb"
sed -i -e 's/^| \*\*Run and verified\*\* | .* (CT) |/| **Run and verified** | `hello-world` (onboarding), `seg`, `bone` (CT) |/' \
    -e 's/^| \*\*Planned\*\* | .* (CT) |/| **Planned** | `knee` (CT) |/' \
    -e 's/^`seg` ran from the test instance (job 1)\.$/&\n\n`bone` ran from the test instance (job {{TODO: its job}})./' \
    "$scratch/scaffold/CONTRIBUTING.md"
commit scaffold
expect scaffold 0

# CONTRIBUTING.md beyond its own tier table lines: another workflow's
# entry in a row, another's job line, or any other line: flagged once.
for c in 's/`knee` (CT)/`knee` (MRI)/' 's/(job 1)/(job 2)/' 's/^The end\.$/The end!/'; do
    make_repo tier-other
    mkdir -p "$scratch/tier-other/workflows/bone"
    echo "script: |" > "$scratch/tier-other/workflows/bone/form.yml.erb"
    sed -i -e 's/^| \*\*Run and verified\*\* | .* (CT) |/| **Run and verified** | `hello-world` (onboarding), `seg`, `bone` (CT) |/' \
        -e 's/^| \*\*Planned\*\* | `bone`, /| **Planned** | /' -e "$c" "$scratch/tier-other/CONTRIBUTING.md"
    commit tier-other
    expect tier-other 1 "CONTRIBUTING.md (beyond the tier table's lines for bone)"
    rm -rf "$scratch/tier-other"
done

# A new environment version of its lab's environment: its digest map line,
# its lab's lab table line pointing at it, and its recipe: not flagged.
make_repo new-version
mkdir -p "$scratch/new-version/envs/ct/2"
echo "print(2)" > "$scratch/new-version/workflows/seg/src/run.py"
echo "numpy==2.0" > "$scratch/new-version/envs/ct/2/requirements.lock"
sed -i -e 's|^    \[ct-lab\]=ct/1$|    [ct-lab]=ct/2|' \
    -e "s|^    \\[mr/2\\]=.*|&\\n    [ct/2]=ghcr.io/jdoe/iris-env@sha256:$(printf 'c%.0s' {1..64})|" \
    "$scratch/new-version/lib/katana.sh"
commit new-version
expect new-version 0

# lib/katana.sh beyond that: another environment's new version, a change
# to a version already in the map, another lab's line, or any other line:
# flagged once.
for c in "s|^    \\[mr/2\\]=.*|&\\n    [mr/3]=unpublished|" \
    "s|^    \\[ct/1\\]=.*|    [ct/1]=unpublished|" \
    's|^    \[mri-lab\]=mr/2$|    [mri-lab]=ct/1|' \
    's|^IRIS_PYTHON_MODULE=.*|IRIS_PYTHON_MODULE=python/9|'; do
    make_repo katana-other
    echo "print(2)" > "$scratch/katana-other/workflows/seg/src/run.py"
    sed -i -e "$c" "$scratch/katana-other/lib/katana.sh"
    commit katana-other
    expect katana-other 1 "lib/katana.sh (beyond ct's new versions in the digest map and ct-lab's lab table line)"
    rm -rf "$scratch/katana-other"
done

# Shared code, the README and another lab's recipe beside the workflow:
# each flagged, by path, in path order.
make_repo shared
echo "print(2)" > "$scratch/shared/workflows/seg/src/run.py"
echo "# changed" > "$scratch/shared/bin/check"
echo "# changed" > "$scratch/shared/README.md"
echo "scipy numpy" > "$scratch/shared/envs/mr/requirements.in"
commit shared
expect shared 1 README.md bin/check envs/mr/requirements.in

# index.html outside the workflow's card, or another workflow's card:
# flagged once, as index.html.
make_repo page
echo "print(2)" > "$scratch/page/workflows/seg/src/run.py"
sed -i 's|<footer>IRIS</footer>|<footer>IRIS!</footer>|' "$scratch/page/index.html"
commit page
expect page 1 "index.html (outside the card of seg)"
make_repo other-card
echo "print(2)" > "$scratch/other-card/workflows/seg/src/run.py"
sed -i 's|<div class="card-name">mri</div>|<div class="card-name">MRI</div>|' "$scratch/other-card/index.html"
commit other-card
expect other-card 1 "index.html (outside the card of seg)"

# Two workflows' folders: flagged, naming both, since a PR is for one.
make_repo two
echo "print(2)" > "$scratch/two/workflows/seg/src/run.py"
echo "script: |x" > "$scratch/two/workflows/mri/form.yml.erb"
commit two
expect two 1 "workflows/ (more than one workflow's folder: mri seg)"

# No workflow at all: everything it changes is flagged.
make_repo none
echo "# changed" > "$scratch/none/README.md"
sed -i 's|<footer>IRIS</footer>|<footer>IRIS!</footer>|' "$scratch/none/index.html"
commit none
expect none 1 README.md index.html

# A file moved out of the folder is flagged where it went.
make_repo moved
git -C "$scratch/moved" mv workflows/seg/src/run.py bin/run.py
commit moved
expect moved 1 bin/run.py

# A base that isn't a commit, or no base, is a usage error.
out="$(cd "$scratch/moved" && bin/outside-folder nosuch 2>&1)"
[ $? = 2 ] || echo "bin/outside-folder nosuch: not exit 2"
out="$(cd "$scratch/moved" && bin/outside-folder 2>&1)"
[ $? = 2 ] || echo "bin/outside-folder with no base: not exit 2"
grep -q usage: <<< "$out" || echo "bin/outside-folder with no base: no usage line"
