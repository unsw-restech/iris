#!/bin/bash
# bin/ocpull's side on Katana, sent on stdin to `bash -s`:
#
#   bash -s -- list <checkout>...
#   bash -s -- apply <sha> <checkout>...
#
# Fetches each checkout of the IRIS fork of OpenComposer. list prints, for
# each, the commits and files a move to the fork's main would deploy, all
# against the one tip it names in the --apply line it ends with. apply
# moves every checkout to <sha>, detached, or none: it first checks each
# one, and refuses all unless <sha> is on the fork's main, at or after the
# checkout's commit, the checkout has no uncommitted changes, and the move
# changes no file it keeps its own copy of, naming every problem in every
# checkout. A move that fails anyway puts the checkouts already moved back
# where they were. Exits 1 on a refusal.

# skipped: the files this checkout keeps its own copy of (git's
# skip-worktree), such as manifest.yml, into the array skip.
skipped() { mapfile -t skip < <(git ls-files -v | sed -n 's/^S //p'); }

list() {
    local c tip n own dirty touched
    local -a skip
    for c in "$@"; do
        git -C "$c" fetch -q origin || return
    done
    tip=$(git -C "$1" rev-parse origin/main) || return
    for c in "$@"; do
        cd "$c" || return
        echo "Checkout $c: at $(git log -1 --format='%h %s')"
        dirty=$(git status --porcelain --untracked-files=no)
        [ -z "$dirty" ] || printf 'Uncommitted changes, which --apply refuses:\n%s\n' "$dirty"
        own=$(git log --oneline "$tip..HEAD")
        [ -z "$own" ] || printf 'Commits not on the fork'"'"'s main, which --apply refuses to leave:\n%s\n' "$own"
        skipped
        if [ ${#skip[@]} -gt 0 ]; then
            echo "Keeps its own copy of: ${skip[*]}"
            touched=$(git diff --name-only HEAD "$tip" -- "${skip[@]}")
            [ -z "$touched" ] || printf 'The move changes these, so --apply refuses until they are merged by hand (it says how):\n%s\n' "$touched"
        fi
        n=$(git rev-list --count "HEAD..$tip")
        if [ "$n" = 0 ]; then
            echo "Up to date with the fork's main: nothing to deploy."
        else
            echo
            git diff --stat=200 --stat-graph-width=20 "HEAD...$tip"
            echo
            echo "$n commits would deploy to $c:"
            git log --oneline "HEAD..$tip"
        fi
        echo
    done
    echo "To move every checkout to the fork's main: bin/ocpull --apply $(git rev-parse --short "$tip")"
}

# refuse <why>: names why apply moved nothing, and fails.
refuse() { echo "ocpull: $*; nothing deployed." >&2; exit 1; }

apply() {
    local sha="$1" c full want="" f i back owncopy=""
    local -a skip touched problems=() moved=() was=()
    shift
    for c in "$@"; do
        cd "$c" && git fetch -q origin || refuse "couldn't fetch the fork in $c"
        full=$(git rev-parse -q --verify "$sha^{commit}") || refuse "$sha is not a commit in $c"
        want="${want:-$full}"
        [ "$full" = "$want" ] || refuse "$sha names different commits in the checkouts"
        git merge-base --is-ancestor "$full" origin/main || refuse "$sha is not on the fork's main"
        git merge-base --is-ancestor HEAD "$full" ||
            problems+=("$c is at $(git log -1 --format='%h %s'), which $sha doesn't follow; a move back goes by a revert on the fork's main")
        [ -z "$(git status --porcelain --untracked-files=no)" ] || problems+=("$c has uncommitted changes")
        skipped
        [ ${#skip[@]} -gt 0 ] || continue
        mapfile -t touched < <(git diff --name-only HEAD "$full" -- "${skip[@]}")
        [ ${#touched[@]} -gt 0 ] || continue
        for f in "${touched[@]}"; do
            back="$HOME/${f//\//_}.${c##*/}"
            echo "$c keeps its own $f, which $sha changes. To take the change, in $c:"
            echo "  cp '$f' '$back' && git update-index --no-skip-worktree '$f' && git checkout -- '$f'"
            echo "  Until the move, $c serves the fork's own $f."
        done >&2
        owncopy=1
        problems+=("the move would overwrite files $c keeps its own copy of")
    done
    if [ ${#problems[@]} -gt 0 ]; then
        [ -z "$owncopy" ] || echo "Then rerun this --apply, merge each saved copy's lines into the new file, and git update-index --skip-worktree it." >&2
        for i in "${problems[@]}"; do echo "ocpull: $i." >&2; done
        refuse "${#problems[@]} problem(s) above"
    fi
    for c in "$@"; do
        cd "$c" || exit
        was+=("$(git rev-parse HEAD)")
        if ! git checkout -q --detach "$want"; then
            back="every checkout is back where it was"
            for i in "${!moved[@]}"; do
                git -C "${moved[$i]}" checkout -q --detach "${was[$i]}" || {
                    echo "ocpull: couldn't put ${moved[$i]} back at ${was[$i]}." >&2
                    back="the checkouts are on different commits; put them back by hand"
                }
            done
            echo "ocpull: couldn't move $c to $sha, so $back." >&2
            exit 1
        fi
        moved+=("$c")
    done
    for c in "$@"; do echo "$c: at $(git -C "$c" log -1 --format='%h %s')"; done
}

case "$1" in
    list) shift; list "$@" ;;
    apply) shift; apply "$@" ;;
    *) echo "ocpull-checkouts.sh: usage: bash -s -- list|apply <sha> <checkout>..." >&2; exit 2 ;;
esac
