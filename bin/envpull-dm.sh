#!/bin/bash
# bin/envpull's side on the data mover, sent on stdin to `bash -s`:
#
#   bash -s -- <list|pull|remove> <env>/<n>|- <environments folder>
#       <system clone> <registry> <tools version>
#       [map:<env>/<n>=<digest>]... [pin:<env>/<n>=<slug>]...
#
# map: words are lib/katana.sh's digest map, pin: words the forms of the
# checkout bin/envpull ran from. The system clone's forms and the tools
# version pin versions too. See bin/envpull for what each mode does.

mode="$1" target="$2" folder="$3" clone="$4" registry="$5" tools="$6"
shift 6
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

# get <env>/<n> <strict>: pulls the version unless its file is there. An
# unpublished version is skipped, and fails only if <strict> is 1.
get() {
    local v="$1" d="${digest[$1]-}" sif="$folder/$1.sif" dir="$folder/${1%/*}" have part tmp
    case "$d" in
        sha256:*) ;;
        unpublished)
            echo "$v: unpublished, skipped: CI hasn't published it, so its digest in lib/katana.sh is 'unpublished'."
            return "$2" ;;
        *) echo "$v: not in lib/katana.sh's digest map, so it can't be pulled."; return 1 ;;
    esac
    if [ -e "$sif" ]; then
        have="$(cat "$folder/$v.digest" 2>/dev/null)"
        if [ "$have" = "$d" ]; then
            echo "$v: present, $sif at $d."
            return 0
        fi
        echo "$v: $sif is there, but its digest file holds '${have:-nothing}', not $d. Nothing pulled; replacing it needs Patrick's go-ahead naming that file."
        return 1
    fi
    login || return 1
    mkdir -p "$dir" || return 1
    part="$dir/.${v##*/}.sif.part" tmp="$dir/.${v##*/}.tmp"
    mkdir -p "$tmp" || return 1
    echo "$v: pulling $registry@$d"
    if ! APPTAINER_TMPDIR="$tmp" apptainer pull --disable-cache --force "$part" "docker://$registry@$d"; then
        rm -rf -- "$tmp" "$part"
        echo "$v: the pull failed; nothing written. Until the package is public, a pull needs $token."
        return 1
    fi
    rm -rf -- "$tmp"
    chmod a+r "$part" && mv -- "$part" "$sif" && echo "$d" > "$folder/$v.digest" || return 1
    echo "$v: pulled, $sif at $d."
}

case "$mode" in
    list)
        for v in $(printf '%s\n' "${!pinned[@]}" | sort); do
            echo "$v is pinned by ${pinned[$v]}."
            get "$v" 0 || status=1
        done
        for sif in "$folder"/*/*.sif; do
            [ -e "$sif" ] || continue
            v="${sif#"$folder"/}" v="${v%.sif}"
            [ -z "${pinned[$v]+x}" ] || continue
            echo
            echo "$sif: nothing pins $v. To remove it, get Patrick's go-ahead naming that file, then: bin/envpull --remove $v"
        done
        ;;
    pull)
        get "$target" 1 || status=1 ;;
    remove)
        sif="$folder/$target.sif"
        if [ -n "${pinned[$target]+x}" ]; then
            echo "envpull: $target is pinned by ${pinned[$target]}; nothing removed."
            status=1
        elif [ ! -e "$sif" ]; then
            echo "envpull: there is no $sif; nothing removed."
            status=1
        else
            rm -f -- "$sif" "$folder/$target.digest" || exit 1
            echo "Removed $sif and its digest file."
            case "${digest[$target]-}" in
                sha256:*) echo "bin/envpull --pull $target pulls it again by digest." ;;
            esac
        fi
        ;;
    *) echo "envpull-dm.sh: unknown mode $mode" >&2; exit 2 ;;
esac
exit "$status"
