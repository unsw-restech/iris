#!/bin/bash
# bin/envpull's side on the data mover, sent on stdin to `bash -s`:
#
#   bash -s -- <list|pull|remove|login> <env>/<n>|- <environments folder>
#       <system clone> <registry> <tools version>
#       [map:<env>/<n>=<digest>]... [pin:<env>/<n>=<slug>]...
#
# map: words are lib/katana.sh's digest map, pin: words the forms of the
# checkout bin/envpull ran from. The system clone's forms and the tools
# version pin versions too. See bin/envpull for what each mode does.

mode="$1" target="$2" folder="$3" clone="$4" registry="$5" tools="$6"
shift 6
# Copies of lib/katana.sh's iris_is_env_version pattern and iris_form_pins,
# since this runs on the data mover over stdin and can't source the clone.
version='^[a-z0-9-]+/[1-9][0-9]*$'
token="$HOME/.config/iris/ghcr-token"
declare -A digest=() pinned=()
# pin <env>/<n> <by>: <by> pins the version.
pin() { pinned[$1]="${pinned[$1]:+${pinned[$1]}, }$2"; }

for a in "$@"; do
    case "$a" in
        map:*=*) a="${a#map:}"; digest[${a%%=*}]="${a#*=}" ;;
        pin:*=*) a="${a#pin:}"; pin "${a%%=*}" "${a#*=} in this checkout" ;;
    esac
done
pin "$tools" "the researcher tools"
status=0
for f in "$clone"/workflows/*/form.yml.erb; do
    [ -f "$f" ] || continue
    slug="$(basename "$(dirname "$f")")"
    while IFS= read -r v; do
        if [[ "$v" =~ $version ]]; then pin "$v" "$slug in the system clone"
        else echo "$f pins '$v', which is no <env>/<n>."; status=1
        fi
    done < <(tr -d '\r' < "$f" | sed -nE 's/^  IRIS_ENV_VERSION=(.*)$/\1/p')
done

# login: the registry login from the token file, if there is one. Until the
# package is public, pulls need it.
login() {
    local line
    [ -e "$token" ] || return 0
    if [ -n "$(find "$token" -perm /077)" ]; then
        echo "$token can be read by others; chmod 600 it. Nothing pulled."
        return 1
    fi
    IFS= read -r line < "$token"
    if ! [[ "$line" =~ ^[^:]+:.+$ ]]; then
        echo "$token should hold one line, <GitHub login>:<token>. Nothing pulled."
        return 1
    fi
    export APPTAINER_DOCKER_USERNAME="${line%%:*}" APPTAINER_DOCKER_PASSWORD="${line#*:}"
}

# no_digest <env>/<n>: prints why the map gives the version no digest to
# pull it by, "unpublished" or "not in lib/katana.sh's digest map", or
# nothing if it gives one.
no_digest() {
    case "${digest[$1]-}" in
        sha256:*) ;;
        unpublished) echo unpublished ;;
        *) echo "not in lib/katana.sh's digest map" ;;
    esac
}

# get <env>/<n> <strict>: pulls the version unless its file is there. An
# unpublished version is skipped, and fails only if <strict> is 1.
get() {
    local v="$1" d="${digest[$1]-}" file="$folder/$1.sif" dir="$folder/${1%/*}" why have part dpart tmp
    why="$(no_digest "$v")"
    if [ "$why" = unpublished ]; then
        echo "$v: unpublished, skipped: CI hasn't published it, so its digest in lib/katana.sh is 'unpublished'."
        return "$2"
    elif [ -n "$why" ]; then
        echo "$v: $why, so it can't be pulled."
        return 1
    fi
    if [ -e "$file" ]; then
        have="$(cat "$folder/$v.digest" 2>/dev/null)"
        if [ "$have" = "$d" ]; then
            echo "$v: present, $file at $d."
            return 0
        fi
        echo "$v: $file is there, but its digest file holds '${have:-nothing}', not $d. Nothing pulled; replacing it needs Patrick's go-ahead naming that file."
        return 1
    fi
    login || return 1
    mkdir -p "$dir" || return 1
    part="$dir/.${v##*/}.sif.part" dpart="$dir/.${v##*/}.digest.part" tmp="$dir/.${v##*/}.tmp"
    mkdir -p "$tmp" || return 1
    echo "$v: pulling $registry@$d"
    # build, not pull, for --mksquashfs-args: the data mover caps each user
    # at 4 GB, and Katana's apptainer.conf gives mksquashfs every CPU
    # (procs = 0), whose buffers went over it and got it killed (2026-11-10).
    if ! APPTAINER_TMPDIR="$tmp" apptainer build --disable-cache --force \
        --mksquashfs-args "-processors 4 -mem 1G" "$part" "docker://$registry@$d"; then
        rm -rf -- "$tmp" "$part"
        echo "$v: the pull failed; nothing written. Until the package is public, a pull needs $token."
        return 1
    fi
    rm -rf -- "$tmp"
    # Each file goes in by rename, the digest file first: killed between
    # the two, the folder holds a digest file and no container file, which
    # the next run pulls again, never a container file without its digest,
    # which only Patrick's go-ahead can replace. Temporary files a kill
    # leaves are overwritten by the next pull.
    if ! { chmod a+r "$part" && echo "$d" > "$dpart" && chmod a+r "$dpart" &&
        mv -- "$dpart" "$folder/$v.digest" && mv -- "$part" "$file"; }; then
        rm -f -- "$part" "$dpart"
        echo "$v: could not put the pulled file in place; no container file written."
        return 1
    fi
    echo "$v: pulled, $file at $d."
}

case "$mode" in
    list)
        for v in $(printf '%s\n' "${!pinned[@]}" | sort); do
            echo "$v is pinned by ${pinned[$v]}."
            get "$v" 0 || status=1
        done
        for file in "$folder"/*/*.sif; do
            [ -e "$file" ] || continue
            v="${file#"$folder"/}" v="${v%.sif}"
            [ -z "${pinned[$v]+x}" ] || continue
            echo
            why="$(no_digest "$v")"
            if [ -n "$why" ]; then
                echo "$file: nothing pins $v, but it is $why, so bin/envpull --pull couldn't bring it back and bin/envpull --remove keeps it."
            else
                echo "$file: nothing pins $v. To remove it, get Patrick's go-ahead naming that file, then: bin/envpull --remove $v"
            fi
        done
        ;;
    pull)
        get "$target" 1 || status=1 ;;
    login)
        # Says only what login() decides, never any part of the file's line,
        # so its output is safe to show anywhere. The token file alone
        # decides the status, not a malformed pin found above.
        if [ ! -e "$token" ]; then
            echo "There is no $token, so a pull goes without a login, which works only if the package is public."
            status=1
        elif login; then
            echo "$token is one <GitHub login>:<token> line, mode 600: a pull logs in with it."
            status=0
        else
            status=1
        fi
        ;;
    remove)
        # Removing is not a one-way door only because --pull undoes it, so
        # a version the map gives no digest is never removed (#125).
        file="$folder/$target.sif" why="$(no_digest "$target")"
        if [ -n "${pinned[$target]+x}" ]; then
            echo "envpull: $target is pinned by ${pinned[$target]}; nothing removed."
            status=1
        elif [ ! -e "$file" ]; then
            echo "envpull: there is no $file; nothing removed."
            status=1
        elif [ -n "$why" ]; then
            echo "envpull: $target is $why, so bin/envpull --pull couldn't bring it back; nothing removed."
            status=1
        else
            rm -f -- "$file" "$folder/$target.digest" || exit 1
            echo "Removed $file and its digest file."
            echo "bin/envpull --pull $target pulls it again by digest."
        fi
        ;;
    *) echo "envpull-dm.sh: unknown mode $mode" >&2; exit 2 ;;
esac
exit "$status"
