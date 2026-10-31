# Sourced by the fixture tests of bin/check's site checks, from the repo
# root. Each test builds scratch trees that hold a copy of bin/check, which
# checks the tree it sits in.

# expect <pass|fail> <tree> <check name>: runs <tree>/bin/check on the
# checks whose name holds <check name>, and prints the tree's name and the
# output if the verdict isn't the one wanted. A failure must be that
# check's own.
expect() {
    local want="$1" tree="$2" name="$3" out rc
    out="$("$tree/bin/check" "$name" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "${tree##*/}: failed, expected a pass"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep '^FAIL: ' <<< "$out" | grep -qF -- "$name"; }; then
        echo "${tree##*/}: passed (exit $rc), expected a failure"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

# site_tree <tree> [<slug>:<lab>:<tier>]...: a site in <tree> that passes
# bin/check's site rules, as a git repo with every file added, holding a
# copy of bin/check and
#   - index.html: a lab section (id="<lab>") per lab, in the order given,
#     holding a card per workflow whose status label follows its tier; an
#     unmaintained workflow has no card
#   - workflows/<slug>/index.html per workflow, its breadcrumb linking its
#     lab, with the unmaintained-banner if it is unmaintained
#   - guide/ and contribute/ pages; every page has the same logo
#   - CONTRIBUTING.md: a tier table row per tier given, and a line citing
#     a job for each active workflow
#   - README.md: a repo map naming bin/ and, with a workflow,
#     workflows/<workflow>/
# <tier> is active (Run and verified), testing (Run, browser run
# pending), planned or unmaintained. A test then breaks the part its rule
# reads; a rule that reads git's index needs git -C <tree> add -A after.
site_tree() {
    local tree="$1" spec slug lab tier t list planned labs=()
    shift
    local -A title=([active]="Run and verified" [testing]="Run, browser run pending" [planned]=Planned [unmaintained]=Unmaintained)
    local -A status=([active]=Active [testing]=Testing [planned]=Planned)
    mkdir -p "$tree/bin" "$tree/guide" "$tree/contribute"
    cp bin/check "$tree/bin/check"
    for spec in "$@"; do
        IFS=: read -r slug lab tier <<< "$spec"
        [[ " ${labs[*]} " == *" $lab "* ]] || labs+=("$lab")
        mkdir -p "$tree/workflows/$slug"
        {
            echo '<nav><a href="../../"><span class="nav-logo-text">UNSW IRIS</span></a></nav>'
            echo "<div class=\"breadcrumb\"><a href=\"../../\">IRIS</a> / <a href=\"../../#$lab\">$lab</a> / $slug</div>"
            [ "$tier" != unmaintained ] ||
                echo '<div class="unmaintained-banner"><strong>Unmaintained.</strong> This workflow cannot be run.</div>'
            echo "<h1 class=\"wf-title\">$slug</h1>"
        } > "$tree/workflows/$slug/index.html"
    done
    {
        echo '<nav><a href="./"><span class="nav-logo-text">UNSW IRIS</span></a></nav>'
        echo '<section id="workflows">'
        for t in "${labs[@]}"; do
            echo "  <div class=\"lab\" id=\"$t\">"
            for spec in "$@"; do
                IFS=: read -r slug lab tier <<< "$spec"
                [ "$lab" = "$t" ] && [ "$tier" != unmaintained ] || continue
                planned=""; [ "$tier" != planned ] || planned=" planned"
                echo "    <a href=\"workflows/$slug/\" class=\"workflow-card$planned\">"
                echo "      <div class=\"card-name\">$slug</div>"
                echo "      <span><span class=\"status-dot$planned\"></span> ${status[$tier]}</span>"
                echo '    </a>'
            done
            echo '  </div>'
        done
        echo '</section>'
    } > "$tree/index.html"
    for t in guide contribute; do
        printf '%s\n' '<nav><a href="../"><span class="nav-logo-text">UNSW IRIS</span></a></nav>' "<h1>$t</h1>" \
            > "$tree/$t/index.html"
    done
    {
        printf '%s\n' '| Tier | Workflows | What exists |' '|---|---|---|'
        for t in active testing planned unmaintained; do
            list=""
            for spec in "$@"; do
                IFS=: read -r slug lab tier <<< "$spec"
                [ "$tier" != "$t" ] || list+="${list:+, }\`$slug\`"
            done
            [ -z "$list" ] || echo "| **${title[$t]}** | $list | Page |"
        done
        echo
        for spec in "$@"; do
            IFS=: read -r slug lab tier <<< "$spec"
            [ "$tier" != active ] || echo "\`$slug\` ran from the system OnDemand (job 1001)."
        done
    } > "$tree/CONTRIBUTING.md"
    {
        printf '%s\n' '# IRIS' '' '| Path | What it holds |' '|---|---|' '| `bin/` | Tools |'
        [ $# = 0 ] || echo '| `workflows/<workflow>/` | A workflow |'
    } > "$tree/README.md"
    git init -q "$tree"
    git -C "$tree" add -A
}
