#!/bin/bash
# bin/envrun against a fake apptainer, docker and gh on the PATH, which only
# report how they were called; the fake apptainer's pull writes the
# reference it was given into the file. The command runs from a scratch
# tree holding its own lib/katana.sh. Prints each failed case and nothing
# on success, so bin/check can run it.
#
#   tests/bin/test_envrun.sh
#
# bin/check name: envrun test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. lib/katana.sh

a=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
fake="$scratch/fake" repo="$scratch/repo" cache="$scratch/cache"
mkdir -p "$fake" "$repo/bin" "$repo/lib" "$repo/workflows/seg"
cp bin/envrun "$repo/bin/"
cp lib/katana.sh "$repo/lib/katana.sh"
sed -i -e "/^declare -gA IRIS_ENV_DIGESTS=(/,/^)/c\\declare -gA IRIS_ENV_DIGESTS=(\n    [microct/1]=$a\n    [microct/2]=unpublished\n)" \
    "$repo/lib/katana.sh"

# apptainer adds its arguments to $fake/apptainer.log, one call a line, and
# the registry login it was given to $fake/auth; its pull writes the
# reference into the file it names.
cat > "$fake/apptainer" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '[%s]' "$@" >> "$dir/apptainer.log"; echo >> "$dir/apptainer.log"
[ "$1" = pull ] || exit 0
echo "user=${APPTAINER_DOCKER_USERNAME-} password=${APPTAINER_DOCKER_PASSWORD-}" >> "$dir/auth"
shift
while [[ "$1" == --* ]]; do shift; done
echo "container $2" > "$1"
EOF
printf '%s\n' '#!/bin/bash' 'printf "[%s]" "$@" >> "$(dirname "$0")/docker.log"; echo >> "$(dirname "$0")/docker.log"' > "$fake/docker"
cat > "$fake/gh" <<'EOF'
#!/bin/bash
case "$*" in
    "auth token") echo gho_secret ;;
    "api user --jq .login") echo PatrickTung ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$fake/apptainer" "$fake/docker" "$fake/gh"

# run [<var>=<value>...] -- <arg>...: bin/envrun's output, run from the
# scratch tree's workflow folder with the fakes first on the PATH.
run() {
    local vars=()
    while [ "$1" != -- ]; do vars+=("$1"); shift; done
    shift
    (cd "$repo/workflows/seg" && env PATH="$fake:$PATH" IRIS_ENV_CACHE="$cache" "${vars[@]}" ../../bin/envrun "$@" 2>&1)
}
has() { grep -qF -- "$3" <<< "$2" || { echo "$1: no $3 in"; echo "$2" | sed 's/^/  /'; }; }
lacks() { grep -qF -- "$3" <<< "$2" && { echo "$1: $3 in"; echo "$2" | sed 's/^/  /'; }; }
log() { cat "$fake/$1.log" 2>/dev/null; }

# With Apptainer, the first run pulls the version by digest alone into the
# cache, logged in with gh's token by environment, never on a command line,
# then runs the command in it under --cleanenv, the clone bound at its own
# path and the working folder kept.
sif="$cache/${a#sha256:}.sif"
run -- microct/1 python -m unittest "a b" > /dev/null
out="$(log apptainer)"
has "first apptainer run" "$out" "docker://$IRIS_ENV_REGISTRY@$a]"
has "first apptainer run" "$out" "[exec][--cleanenv]"
has "first apptainer run" "$out" "[--bind][$repo]"
has "first apptainer run" "$out" "[--pwd][$repo/workflows/seg]"
has "first apptainer run" "$out" "[$sif][python][-m][unittest][a b]"
lacks "first apptainer run" "$out" "gho_secret"
lacks "first apptainer run" "$out" "--nv"
[ "$(cat "$sif" 2>/dev/null)" = "container docker://$IRIS_ENV_REGISTRY@$a" ] || echo "first apptainer run: no container file at $sif"
[ "$(cat "$fake/auth" 2>/dev/null)" = "user=PatrickTung password=gho_secret" ] || echo "first apptainer run: pulled with $(cat "$fake/auth")"
# The second run pulls nothing.
rm "$fake/apptainer.log"
run -- microct/1 python -V > /dev/null
lacks "second apptainer run" "$(log apptainer)" "[pull]"
has "second apptainer run" "$(log apptainer)" "[$sif][python][-V]"

# With Docker, as in CI, the command runs in the container by digest, as
# this user, with the clone mounted at its own path; docker pulls it.
out="$(run IRIS_CONTAINER_RUNTIME=docker -- microct/1 python -V)"
out="$(log docker)"
has "docker run" "$out" "[run][--rm]"
has "docker run" "$out" "[--user][$(id -u):$(id -g)]"
has "docker run" "$out" "[--volume][$repo:$repo]"
has "docker run" "$out" "[--workdir][$repo/workflows/seg]"
has "docker run" "$out" "[$IRIS_ENV_REGISTRY@$a][python][-V]"

# A version that is unpublished or not in the map fails with one line and
# starts nothing.
rm -f "$fake/apptainer.log" "$fake/docker.log"
for v in microct/2 microct/7; do
    out="$(run -- "$v" python -V)" && echo "envrun $v: exit 0"
    [ "$(wc -l <<< "$out")" = 1 ] || { echo "envrun $v: not one line"; echo "$out" | sed 's/^/  /'; }
done
has "envrun unpublished" "$(run -- microct/2 python -V)" "unpublished"
[ -z "$(log apptainer)$(log docker)" ] || echo "envrun: started a container for a version it can't run"

# No command is a usage error.
out="$(run -- microct/1)" && echo "envrun with no command: exit 0"
has "envrun with no command" "$out" "usage:"
