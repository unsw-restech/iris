# Sourced from the repo root by the fixture tests of bin/check's site
# checks, which build scratch trees each holding a copy of bin/check, which
# checks the tree it sits in, by every test that gives a scratch copy of
# lib/katana.sh a digest map or a lab table of its own, and by every test
# that copies lib/katana.sh, through katana_copy.

# The opening lines of lib/katana.sh's digest map and lab table, which the
# helpers below match whole.
_DIGEST_MAP_OPEN='declare -gA IRIS_ENV_DIGESTS=('
_LAB_TABLE_OPEN='declare -gA IRIS_LAB_ENVS=('

# katana_copy <dest>: copies lib/katana.sh to <dest>, a file or a folder,
# with each digest map line naming an author's container written as its
# digest alone, as main always pins it. An author's pull request names its
# container there, and a fixture copied from that as it is tests the
# branch's map, not main's: two of tests/bin/test_check_passed.sh's
# pre-push cases failed on author branches that way (5ff5995, then #201's
# ad7d228). It is bin/libcopy's without_authors, the rewrite the review
# batch makes, which bin/libcopy can't share since running it copies; keep
# the two alike. bin/check's "tests copy lib/katana.sh through katana_copy"
# holds every test to it. It returns 1 if the copy fails.
katana_copy() {
    local dest="$1" line key value in_map="" nl=$'\n' out=""
    [ -d "$dest" ] && dest="${dest%/}/katana.sh"
    cp lib/katana.sh "$dest" || return 1
    while IFS= read -r line || { nl=""; [ -n "$line" ]; }; do
        if [ "$line" = "$_DIGEST_MAP_OPEN" ]; then
            in_map=1
        elif [ -n "$in_map" ] && [ "$line" = ")" ]; then
            in_map=""
        elif [ -n "$in_map" ] && [[ "$line" =~ ^(    \[[^]]+\]=)([^[:space:]]+)$ ]]; then
            # Kept before iris_is_author_env, whose own =~ resets them. It
            # runs in a subshell, so the caller keeps none of what
            # lib/katana.sh sets.
            key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
            if (. lib/katana.sh && iris_is_author_env "$value"); then line="$key${value#*@}"; fi
        fi
        out+="$line$nl"
    done < lib/katana.sh
    # Written over the copy, which keeps lib/katana.sh's mode, as cp alone did.
    printf '%s' "$out" > "$dest"
}

# digest_map <file> [--tools <env>/<n>] [<env>/<n>=<value>]...: replaces the
# whole digest map (IRIS_ENV_DIGESTS) in <file>, a scratch copy of
# lib/katana.sh, with one "    [<env>/<n>]=<value>" line per entry, in the
# order given, and with --tools sets IRIS_TOOLS_ENV_VERSION to <env>/<n>.
# It leaves the rest of the file alone. If an entry isn't <key>=<value>, as
# _table_set says, or the map, its closing ")" or, with --tools, the tools
# version line isn't there, or the file doesn't end up holding exactly what
# was asked, it prints why, naming <file>, and returns 1, so no fixture
# keeps the real map's versions by mistake.
digest_map() {
    local file="$1" tools=""
    shift
    if [ "${1-}" = --tools ]; then tools="$2"; shift 2; fi
    # Checked here as well as in _table_set, so a missing map fails before
    # the tools line check below, as it did before #211.
    _digest_map_open digest_map "$file" || return 1
    if [ -n "$tools" ] && ! grep -q '^IRIS_TOOLS_ENV_VERSION=' "$file"; then
        echo "digest_map: $file has no IRIS_TOOLS_ENV_VERSION= line to set"
        return 1
    fi
    _table_set digest_map "$file" "$_DIGEST_MAP_OPEN" "digest map" "$@" || return 1
    [ -n "$tools" ] || return 0
    TOOLS_="$tools" awk '/^IRIS_TOOLS_ENV_VERSION=/ { print "IRIS_TOOLS_ENV_VERSION=" ENVIRON["TOOLS_"]; next } { print }' \
        "$file" > "$file.digest-map" && mv "$file.digest-map" "$file" || return 1
    if ! grep -qxF "IRIS_TOOLS_ENV_VERSION=$tools" "$file"; then
        echo "digest_map: $file's tools version isn't $tools"
        return 1
    fi
}

# digest_map_add <file> <env>/<n>=<value>: adds "    [<env>/<n>]=<value>"
# as the first line of <file>'s digest map, keeping the rest, and fails as
# digest_map does, naming <file>, if the entry isn't <key>=<value>, the map
# isn't there or the line didn't go in.
digest_map_add() {
    local file="$1" line
    line="$(_table_entries digest_map_add "$file" "$2")" || { echo "$line"; return 1; }
    _digest_map_open digest_map_add "$file" || return 1
    OPEN_="$_DIGEST_MAP_OPEN" LINE_="$line" awk '{ print } $0 == ENVIRON["OPEN_"] { print ENVIRON["LINE_"] }' \
        "$file" > "$file.digest-map" && mv "$file.digest-map" "$file" || return 1
    # A here-string, not a pipe: grep -q stops at its first match, and a
    # writer still holding output would then meet a closed pipe (#239).
    if ! grep -qxF -- "$line" <<< "$(_table_lines "$file" "$_DIGEST_MAP_OPEN")"; then
        echo "digest_map_add: $file's digest map didn't take $2"
        return 1
    fi
}

# lab_table <file> [<lab>=<env>/<n>]...: replaces the whole lab table
# (IRIS_LAB_ENVS) in <file>, a scratch copy of lib/katana.sh, with one
# "    [<lab>]=<env>/<n>" line per entry, in the order given, leaving the
# rest of the file alone. If an entry isn't <key>=<value>, as _table_set
# says, or the table or its closing ")" isn't there, or the table doesn't
# end up holding exactly the entries given, it prints why, naming <file>,
# and returns 1, so no fixture keeps the real table's labs by mistake.
lab_table() {
    local file="$1"
    shift
    _table_set lab_table "$file" "$_LAB_TABLE_OPEN" "lab table" "$@"
}

# _digest_map_open <caller> <file>: fails, naming <caller> and <file>,
# unless <file> has the map's opening line and a ")" line after it.
_digest_map_open() {
    _table_open "$1" "$2" "$_DIGEST_MAP_OPEN" "digest map"
}

# _table_set <caller> <file> <open> <noun> [<key>=<value>]...: the core of
# digest_map and lab_table. It replaces the lines between <file>'s <open>
# line and the ")" line after it with one "    [<key>]=<value>" line per
# entry, then checks the table holds exactly those lines. Each entry is
# shaped as _table_entries says, the key bare, as lib/katana.sh writes it
# inside its brackets. On any failure it
# prints why, naming <caller>, <file> and, for a misshapen entry, the
# entry, and returns 1; a misshapen entry or a missing table leaves <file>
# unwritten.
_table_set() {
    local caller="$1" file="$2" open="$3" noun="$4" lines
    shift 4
    lines="$(_table_entries "$caller" "$file" "$@")" || { echo "$lines"; return 1; }
    _table_open "$caller" "$file" "$open" "$noun" || return 1
    OPEN_="$open" LINES_="$lines" awk '
        in_table { if ($0 == ")") { in_table = 0; if (ENVIRON["LINES_"] != "") print ENVIRON["LINES_"]; print }; next }
        $0 == ENVIRON["OPEN_"] { print; in_table = 1; next }
        { print }' "$file" > "$file.table" && mv "$file.table" "$file" || return 1
    if [ "$(_table_lines "$file" "$open")" != "$lines" ]; then
        echo "$caller: $file's $noun isn't the entries given: $*"
        return 1
    fi
}

# _table_entries <caller> <file> [<key>=<value>]...: prints one
# "    [<key>]=<value>" line per entry, or, for the first entry that isn't
# <key>=<value> with a non-empty <key> holding no [, ] or =, prints why,
# naming <caller>, the entry and <file>, and returns 1.
_table_entries() {
    local caller="$1" file="$2" e key
    shift 2
    for e in "$@"; do
        key="${e%%=*}"
        if [ "$key" = "$e" ] || [ -z "$key" ] || [[ "$key" == *[][]* ]]; then
            echo "$caller: '$e' for $file isn't <key>=<value> with no [, ] or = in <key>"
            return 1
        fi
        printf '    [%s]=%s\n' "$key" "${e#*=}"
    done
}

# _table_open <caller> <file> <open> <noun>: fails, naming <caller>, <file>
# and <noun>, unless <file> has the <open> line and a ")" line after it.
_table_open() {
    if ! grep -qxF -- "$3" "$2"; then
        echo "$1: $2 has no '$3' line to replace"
        return 1
    fi
    # One reader of the file itself, so no writer is left holding output
    # when the match is found (#239).
    if ! OPEN_="$3" awk '
        in_table && $0 == ")" { found = 1; exit }
        $0 == ENVIRON["OPEN_"] { in_table = 1 }
        END { exit !found }' "$2"; then
        echo "$1: $2's $4 has no closing ) line"
        return 1
    fi
}

# _table_lines <file> <open>: the lines between <file>'s <open> line and the
# ")" line after it, read in one pass of the file itself (#239).
_table_lines() {
    OPEN_="$2" awk '
        in_table && $0 == ")" { exit }
        in_table { print }
        $0 == ENVIRON["OPEN_"] { in_table = 1 }' "$1"
}

# expect <pass|fail> <tree> <check name>: runs <tree>/bin/check on the
# checks whose name holds <check name>, and prints the tree's name and the
# output if the verdict isn't the one wanted. A failure must be that
# check's own, and named again on the run's last line, FAILED: <names>.
expect() {
    local want="$1" tree="$2" name="$3" out rc
    out="$("$tree/bin/check" "$name" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "${tree##*/}: failed, expected a pass"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep -qF -- "$name" <<< "$(grep '^FAIL: ' <<< "$out")"; }; then
        echo "${tree##*/}: passed (exit $rc), expected a failure"
    elif [ "$want" = fail ] && ! grep -qF -- "$name" <<< "$(tail -n1 <<< "$out" | grep '^FAILED: ')"; then
        echo "${tree##*/}: its last line doesn't name the failed check: $(tail -n1 <<< "$out")"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

# site_tree <tree> [<slug>:<lab>:<tier>]...: a site in <tree> that passes
# bin/check's site rules, as a git repo with every file added, holding a
# copy of bin/check, the Avoid-word list it reads (.githooks/avoid-names) and
#   - index.html: a lab tile per lab, linking #<lab> and counting its
#     active and planned workflows, then a lab section (id="<lab>") per lab,
#     in the order given, holding a card per workflow whose status label
#     follows its tier; an unmaintained workflow has no card
#   - workflows/<slug>/index.html per workflow, its breadcrumb linking its
#     lab, with the unmaintained-banner if it is unmaintained
#   - guide/ and contribute/ pages; every page has the same logo
#   - CONTRIBUTING.md: a tier table row per tier given, and a line citing
#     a job for each active workflow
#   - README.md: a repo map naming bin/ and, with a workflow,
#     workflows/<workflow>/
# <tier> is active (Run and verified), planned or unmaintained. A test then breaks the part its rule
# reads; a rule that reads git's index needs git -C <tree> add -A after.
site_tree() {
    local tree="$1" spec slug lab tier t list planned active labs=()
    shift
    local -A title=([active]="Run and verified" [planned]=Planned [unmaintained]=Unmaintained)
    local -A status=([active]=Active [planned]=Planned)
    mkdir -p "$tree/bin" "$tree/guide" "$tree/contribute" "$tree/.githooks"
    cp bin/check "$tree/bin/check"
    cp .githooks/avoid-names .githooks/avoid-names.pl "$tree/.githooks/"
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
        echo '  <div class="lab-tiles">'
        for t in "${labs[@]}"; do
            active=0; planned=0
            for spec in "$@"; do
                IFS=: read -r slug lab tier <<< "$spec"
                [ "$lab" = "$t" ] || continue
                [ "$tier" != active ] || active=$((active + 1))
                [ "$tier" != planned ] || planned=$((planned + 1))
            done
            echo "    <a href=\"#$t\" class=\"lab-tile\">"
            echo "      <span class=\"lab-tile-name\">$t</span>"
            echo "      <span class=\"lab-tile-counts\">$active active · $planned planned</span>"
            echo '    </a>'
        done
        echo '  </div>'
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
        for t in active planned unmaintained; do
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
