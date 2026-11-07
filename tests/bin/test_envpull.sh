#!/bin/bash
# bin/envpull against a fake `ssh` on PATH that runs the command it is
# given here, with Katana's environments folder, the system clone and the
# home folder mapped to scratch folders, and a fake `apptainer` whose pull
# writes the reference it was given into the file. The command runs from a
# scratch tree holding its own lib/katana.sh and forms. Prints each failed
# case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_envpull.sh
#
# bin/check name: envpull test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. lib/katana.sh

a=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
b=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
fake="$scratch/fake" repo="$scratch/repo"
export REAL_ENVS="$IRIS_ENVS_FOLDER" REAL_CLONE="$IRIS_SYSTEM_CLONE"
export FAKE_ENVS="$scratch/envs" FAKE_CLONE="$scratch/clone" FAKE_HOME="$scratch/home"
mkdir -p "$fake" "$repo/bin" "$repo/lib" "$FAKE_ENVS" "$FAKE_CLONE" "$FAKE_HOME"
cp bin/envpull bin/envpull-dm.sh "$repo/bin/"
envs="$FAKE_ENVS"

# Adds the host and command to $fake/args, then runs the command as a
# remote shell would, in one string, with the Katana paths mapped. A file
# named ssh-down makes it fail as ssh itself does (255).
cat > "$fake/ssh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '%s\n' "$@" >> "$dir/args"
[ -e "$dir/ssh-down" ] && { echo "ssh: connect to host $1: Connection refused" >&2; exit 255; }
shift
cmd="$*"
cmd="${cmd//"$REAL_ENVS"/"$FAKE_ENVS"}"
cmd="${cmd//"$REAL_CLONE"/"$FAKE_CLONE"}"
cd "$FAKE_HOME" && HOME="$FAKE_HOME" bash -c "$cmd"
EOF
# Adds its arguments to $fake/pulls and the registry login it was given to
# $fake/auth. A file named pull-fails makes a pull fail as an unauthorised
# one does.
cat > "$fake/apptainer" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
echo "$*" >> "$dir/pulls"
echo "user=${APPTAINER_DOCKER_USERNAME-} password=${APPTAINER_DOCKER_PASSWORD-}" >> "$dir/auth"
[ -e "$dir/pull-fails" ] && { echo "FATAL: unauthorized: authentication required" >&2; exit 255; }
[ "$1" = pull ] || exit 2
shift
while [[ "$1" == --* ]]; do shift; done
echo "container $2" > "$1"
EOF
chmod +x "$fake/ssh" "$fake/apptainer"

# map <entry>...: the scratch tree's digest map holds these lines alone,
# and its researcher tools use microct/1.
map() {
    local entries="" e
    for e in "$@"; do entries+="\n    $e"; done
    cp lib/katana.sh "$repo/lib/katana.sh"
    sed -i -e "/^declare -gA IRIS_ENV_DIGESTS=(/,/^)/c\\declare -gA IRIS_ENV_DIGESTS=($entries\n)" \
        -e 's|^IRIS_TOOLS_ENV_VERSION=.*|IRIS_TOOLS_ENV_VERSION=microct/1|' "$repo/lib/katana.sh"
}
# pin <tree> <slug> <version>: <tree>'s form <slug> pins <version>.
pin() {
    mkdir -p "$1/workflows/$2"
    printf '%s\n' 'script: |' '  #!/bin/bash' "  #PBS -A iris-$2" "  IRIS_ENV_VERSION=$3" > "$1/workflows/$2/form.yml.erb"
}
# reset: no forms anywhere, no container files, no token, no fakes' records.
reset() {
    rm -rf "$repo/workflows" "$FAKE_CLONE/workflows" "${envs:?}"/* "$FAKE_HOME/.config"
    rm -f "$fake/args" "$fake/pulls" "$fake/auth" "$fake/pull-fails" "$fake/ssh-down"
}

# expect <exit code> <output substring> <arg>...
expect() {
    local want="$1" grep_for="$2" out rc
    shift 2
    out="$(PATH="$fake:$PATH" "$repo/bin/envpull" "$@" 2>&1)"
    rc=$?
    if [ "$rc" != "$want" ]; then
        echo "envpull $*: exit $rc, expected $want"
        echo "$out" | sed 's/^/  /'
    elif ! grep -qF -- "$grep_for" <<< "$out"; then
        echo "envpull $*: output lacks '$grep_for'"
        echo "$out" | sed 's/^/  /'
    fi
}
# no_pull <case>: apptainer never ran.
no_pull() { [ ! -e "$fake/pulls" ] || { echo "envpull $1: pulled"; sed 's/^/  /' "$fake/pulls"; }; }
# holds <case> <file> <text>: <file> holds exactly the line <text>.
holds() { [ "$(cat "$2" 2>/dev/null)" = "$3" ] || echo "envpull $1: $2 holds '$(cat "$2" 2>/dev/null)', expected '$3'"; }

# An unpublished version is skipped, not an error, and nothing is pulled.
reset; map '[microct/1]=unpublished'; pin "$repo" seg microct/1
expect 0 "microct/1: unpublished"
no_pull unpublished
grep -qxF katana-dm "$fake/args" 2>/dev/null || echo "envpull unpublished: didn't run on the data mover"

# A pinned, published version missing from Katana is pulled by digest alone,
# into <folder>/<env>/<n>.sif with its digest beside it.
reset; map "[microct/1]=$a"; pin "$repo" seg microct/1
expect 0 "pulled"
holds pull "$envs/microct/1.sif" "container docker://$IRIS_ENV_REGISTRY@$a"
holds pull "$envs/microct/1.digest" "$a"
# Run again, the file is there and nothing is pulled.
rm -f "$fake/pulls"
expect 0 "microct/1: present"
no_pull present

# A file whose digest file disagrees with the map is reported and kept.
echo "$b" > "$envs/microct/1.digest"
expect 1 "not $a"
no_pull mismatch
holds mismatch "$envs/microct/1.sif" "container docker://$IRIS_ENV_REGISTRY@$a"
rm "$envs/microct/1.digest"
expect 1 "holds 'nothing'"
no_pull no-digest

# A container file nothing pins is listed with the go-ahead it needs, and
# kept; --remove takes it and its digest file, and says how to get it back.
reset; map "[microct/1]=$a" "[microct/2]=$b"; pin "$repo" seg microct/1
mkdir -p "$envs/microct"
echo old > "$envs/microct/2.sif"; echo "$b" > "$envs/microct/2.digest"
expect 0 "bin/envpull --remove microct/2"
expect 0 "$envs/microct/2.sif: nothing pins microct/2"
[ -e "$envs/microct/2.sif" ] || echo "envpull list: removed an unpinned file"
expect 0 "bin/envpull --pull microct/2 pulls it again" --remove microct/2
[ ! -e "$envs/microct/2.sif" ] && [ ! -e "$envs/microct/2.digest" ] || echo "envpull --remove: kept the file or its digest"
# ... and --pull brings it back by digest, though nothing pins it.
rm -f "$fake/pulls"
expect 0 "microct/2: pulled" --pull microct/2
holds pull-back "$envs/microct/2.sif" "container docker://$IRIS_ENV_REGISTRY@$b"
holds pull-back "$envs/microct/2.digest" "$b"
# A pinned version is never removed.
expect 1 "pinned by seg in this checkout" --remove microct/1
[ -e "$envs/microct/1.sif" ] || echo "envpull --remove: removed a pinned file"
expect 1 "there is no" --remove microct/3

# The researcher tools' version and the system clone's forms pin versions
# too: they are pulled, and never listed for removal or removed.
reset; map "[microct/1]=$a" "[bril/1]=$b"; pin "$FAKE_CLONE" mri bril/1
expect 0 "bril/1: pulled"
holds tools "$envs/microct/1.digest" "$a"
holds clone "$envs/bril/1.digest" "$b"
expect 0 "bril/1 is pinned by mri in the system clone"
expect 1 "pinned by the researcher tools" --remove microct/1
expect 1 "pinned by mri in the system clone" --remove bril/1
[ -e "$envs/bril/1.sif" ] || echo "envpull --remove: removed a file the system clone pins"

# --pull of a version that can't be pulled fails, pulling nothing.
reset; map '[microct/1]=unpublished'
expect 1 "unpublished" --pull microct/1
expect 1 "not in lib/katana.sh's digest map" --pull microct/7
no_pull pull-unpublished

# The token file on Katana logs the pull in, by environment, never in a
# command line; one others can read is refused.
reset; map "[microct/1]=$a"
mkdir -p "$FAKE_HOME/.config/iris"
echo "PatrickTung:ghp_secret" > "$FAKE_HOME/.config/iris/ghcr-token"
chmod 600 "$FAKE_HOME/.config/iris/ghcr-token"
expect 0 "pulled"
holds token "$fake/auth" "user=PatrickTung password=ghp_secret"
! grep -qF ghp_secret "$fake/args" "$fake/pulls" || echo "envpull token: the token is on a command line"
rm -rf "$envs/microct" "$fake/pulls"
chmod 640 "$FAKE_HOME/.config/iris/ghcr-token"
expect 1 "chmod 600"
no_pull token-readable
# Without one, the pull goes without a login.
reset; map "[microct/1]=$a"
expect 0 "pulled"
holds no-token "$fake/auth" "user= password="

# A failed pull leaves nothing behind, and points at the token.
reset; map "[microct/1]=$a"; touch "$fake/pull-fails"
expect 1 ".config/iris/ghcr-token"
[ -z "$(ls -A "$envs/microct" 2>/dev/null)" ] || { echo "envpull pull-fails: left files"; ls -A "$envs/microct" | sed 's/^/  /'; }

# Anything else is a usage error, before ssh runs.
reset
expect 2 "usage:" --remove
expect 2 "usage:" --remove "microct/1; rm -rf /"
expect 2 "usage:" --pull ../1
expect 2 "usage:" microct/1
[ ! -e "$fake/args" ] || echo "envpull: ran ssh on a usage error"

# ssh's own failure is the command's.
touch "$fake/ssh-down"
expect 255 "Connection refused"
