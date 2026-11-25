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
. tests/bin/lib.sh
. lib/katana.sh

a=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
fake="$scratch/fake" repo="$scratch/repo" cache="$scratch/cache"
mkdir -p "$fake" "$repo/bin" "$repo/lib" "$repo/workflows/seg"
cp bin/envrun "$repo/bin/"
cp lib/katana.sh "$repo/lib/katana.sh"
digest_map "$repo/lib/katana.sh" "microct/1=$a" microct/2=unpublished || exit 1

# apptainer adds its arguments to $fake/apptainer.log, one call a line, and
# the registry login it was given, with its --authfile's contents, to
# $fake/auth, and that file's path to $fake/authfiles. Its pull writes the
# reference into the file it names. As the desktop's Apptainer 1.5 does, a
# pull fails on Docker Desktop's credential helper unless --authfile names
# an empty config, since it reads ~/.docker/config.json's credsStore and
# ignores DOCKER_CONFIG (#201).
cat > "$fake/apptainer" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '[%s]' "$@" >> "$dir/apptainer.log"; echo >> "$dir/apptainer.log"
[ "$1" = pull ] || exit 0
shift
authfile=""
while [[ "$1" == --* ]]; do
    [ "$1" != --authfile ] || { authfile="$2"; shift; }
    shift
done
echo "user=${APPTAINER_DOCKER_USERNAME-} password=${APPTAINER_DOCKER_PASSWORD-} authfile=$(cat "$authfile" 2>/dev/null)" >> "$dir/auth"
[ -z "$authfile" ] || echo "$authfile" >> "$dir/authfiles"
if [ "$(cat "$authfile" 2>/dev/null)" != "{}" ]; then
    echo 'FATAL:   While making image from oci registry: error fetching image to cache: ... conveyor failed to get: error getting credentials - err: exit status 1, out: `A specified logon session does not exist. It may already have been terminated.`' >&2
    exit 255
fi
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
# scratch tree's workflow folder with the fakes first on the PATH and no
# DOCKER_CONFIG of the caller's.
run() {
    local vars=()
    while [ "$1" != -- ]; do vars+=("$1"); shift; done
    shift
    (cd "$repo/workflows/seg" && env -u DOCKER_CONFIG PATH="$fake:$PATH" IRIS_ENV_CACHE="$cache" "${vars[@]}" ../../bin/envrun "$@" 2>&1)
}
has() { grep -qF -- "$3" <<< "$2" || { echo "$1: no $3 in"; echo "$2" | sed 's/^/  /'; }; }
lacks() { grep -qF -- "$3" <<< "$2" && { echo "$1: $3 in"; echo "$2" | sed 's/^/  /'; }; }
log() { cat "$fake/$1.log" 2>/dev/null; }

# With Apptainer, the first run pulls the version by digest alone into the
# cache, with no login, since the package is public (#132): gh's token,
# which the fake gh would give, is never used, nor any Docker login, since
# its --authfile is an empty config of its own (#201). It then runs the command in it under --cleanenv, the clone bound at its own
# path and the working folder kept.
file="$cache/${a#sha256:}.sif"
run -- microct/1 python -m unittest "a b" > /dev/null
out="$(log apptainer)"
has "first apptainer run" "$out" "docker://$IRIS_ENV_REGISTRY@$a]"
has "first apptainer run" "$out" "[exec][--cleanenv]"
has "first apptainer run" "$out" "[--bind][$repo]"
has "first apptainer run" "$out" "[--pwd][$repo/workflows/seg]"
has "first apptainer run" "$out" "[$file][python][-m][unittest][a b]"
lacks "first apptainer run" "$out" "gho_secret"
lacks "first apptainer run" "$out" "--nv"
[ "$(cat "$file" 2>/dev/null)" = "container docker://$IRIS_ENV_REGISTRY@$a" ] || echo "first apptainer run: no container file at $file"
[ "$(cat "$fake/auth" 2>/dev/null)" = "user= password= authfile={}" ] || echo "first apptainer run: pulled with $(cat "$fake/auth")"
# The empty auth file is envrun's own, gone once the pull is done.
if [ -s "$fake/authfiles" ]; then
    while read -r f; do
        [ ! -e "$f" ] || echo "first apptainer run: left its auth file $f"
    done < "$fake/authfiles"
else
    echo "first apptainer run: pulled with no --authfile"
fi
# The second run pulls nothing.
rm "$fake/apptainer.log"
run -- microct/1 python -V > /dev/null
lacks "second apptainer run" "$(log apptainer)" "[pull]"
has "second apptainer run" "$(log apptainer)" "[$file][python][-V]"

# With Docker, as in CI, the command runs in the container by digest, as
# this user, with the clone mounted at its own path; docker pulls it.
out="$(run IRIS_CONTAINER_RUNTIME=docker -- microct/1 python -V)"
out="$(log docker)"
has "docker run" "$out" "[run][--rm]"
# docker's init is the container's PID 1, so the command gets the
# SIGTERM of a time limit, and the container has a name of its own, so a
# command that ignores it can be killed (#197).
has "docker run" "$out" "[--init][--name][iris-envrun-"
has "docker run" "$out" "[--user][$(id -u):$(id -g)]"
# The uid has no passwd entry in the container, so the user's name goes by
# environment, or torch's getpass.getuser() fails (CI run 42537470699).
has "docker run" "$out" "[--env][USER=$(id -un)]"
has "docker run" "$out" "[--volume][$repo:$repo]"
has "docker run" "$out" "[--workdir][$repo/workflows/seg]"
has "docker run" "$out" "[$IRIS_ENV_REGISTRY@$a][python][-V]"

# An author's version, published under their own account on their fork
# (#138), runs from that container by digest, so bin/check on the fork
# runs the workflow's tests in the version its form pins.
author="ghcr.io/an-author/iris-env@$a"
sed -i "s|^    \[microct/2\]=unpublished|    [microct/2]=$author|" "$repo/lib/katana.sh"
rm -f "$fake/docker.log"
run IRIS_CONTAINER_RUNTIME=docker -- microct/2 python -V > /dev/null
has "author's version" "$(log docker)" "[$author][python][-V]"
sed -i "s|^    \[microct/2\]=$author|    [microct/2]=unpublished|" "$repo/lib/katana.sh"

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
out="$(run -- --time-limit soon microct/1 python -V)" && echo "envrun --time-limit soon: exit 0"
has "envrun --time-limit soon" "$out" "usage:"

# --no-network runs the command with no network, under either runtime;
# without it, the container keeps the host's.
rm -f "$fake/apptainer.log" "$fake/docker.log"
run -- microct/1 python -V > /dev/null
lacks "apptainer run" "$(log apptainer)" "[--net]"
run -- --no-network microct/1 python -V > /dev/null
has "apptainer --no-network" "$(log apptainer)" "[exec][--cleanenv][--net][--network][none]"
run IRIS_CONTAINER_RUNTIME=docker -- microct/1 python -V > /dev/null
lacks "docker run" "$(log docker)" "[--network]"
run IRIS_CONTAINER_RUNTIME=docker -- --no-network microct/1 python -V > /dev/null
has "docker --no-network" "$(log docker)" "[--network][none]"

# --time-limit <seconds> stops a command that runs past it, saying so,
# and exits non-zero; the first run's pull doesn't count towards it.
# The fake apptainer's exec sleeps FAKE_EXEC_SLEEP seconds, its pull
# FAKE_PULL_SLEEP.
cat > "$fake/apptainer" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '[%s]' "$@" >> "$dir/apptainer.log"; echo >> "$dir/apptainer.log"
if [ "$1" != pull ]; then sleep "${FAKE_EXEC_SLEEP:-0}"; exit 0; fi
sleep "${FAKE_PULL_SLEEP:-0}"
shift
while [[ "$1" == --* ]]; do
    [ "$1" != --authfile ] || shift
    shift
done
echo "container $2" > "$1"
EOF
out="$(run FAKE_EXEC_SLEEP=5 -- --time-limit 1 microct/1 python -m unittest test_synthetic)" &&
    echo "envrun --time-limit 1 on a 5 s command: exit 0"
has "envrun past its time limit" "$out" "ran past its 1 s limit"
out="$(run FAKE_EXEC_SLEEP=0 -- --time-limit 3 microct/1 python -V)" ||
    { echo "envrun --time-limit 3 on a quick command: exit non-zero"; echo "$out" | sed 's/^/  /'; }
rm -rf "$cache"
out="$(run FAKE_PULL_SLEEP=2 -- --time-limit 1 microct/1 python -V)" ||
    { echo "envrun --time-limit 1 with a 2 s pull: exit non-zero"; echo "$out" | sed 's/^/  /'; }
# Docker pulls a container it doesn't have before the limit starts.
cat > "$fake/docker" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")"
printf '[%s]' "$@" >> "$dir/docker.log"; echo >> "$dir/docker.log"
case "$1" in
    image) [ -f "$dir/pulled" ] ;;
    pull) sleep "${FAKE_PULL_SLEEP:-0}"; touch "$dir/pulled" ;;
    run) sleep "${FAKE_EXEC_SLEEP:-0}" ;;
esac
EOF
rm -f "$fake/docker.log"
out="$(run IRIS_CONTAINER_RUNTIME=docker FAKE_PULL_SLEEP=2 -- --time-limit 1 microct/1 python -V)" ||
    { echo "docker --time-limit 1 with a 2 s pull: exit non-zero"; echo "$out" | sed 's/^/  /'; }
has "docker --time-limit, first run" "$(log docker)" "[pull][-q][$IRIS_ENV_REGISTRY@$a]"
lacks "docker --time-limit, first run" "$(log docker)" "[kill]"
rm -f "$fake/docker.log"
out="$(run IRIS_CONTAINER_RUNTIME=docker FAKE_EXEC_SLEEP=5 -- --time-limit 1 microct/1 python -V)" &&
    echo "docker --time-limit 1 on a 5 s command: exit 0"
has "docker past its time limit" "$out" "ran past its 1 s limit"
lacks "docker --time-limit, second run" "$(log docker)" "[pull]"
# A command past its limit has its container killed by name, since
# killing the docker client leaves the container running (#197).
name="$(sed -n 's/^\[run\].*\[--name\]\[\([^]]*\)\].*/\1/p' "$fake/docker.log")"
has "docker past its time limit" "$(log docker)" "[kill][${name:-no name}]"

# --container <local name> runs the command in a container built under
# that name and not yet published, such as the one the containers workflow
# just built (#150), under Docker whatever the runtime, with the same
# flags; it pulls nothing, and the version needn't be published.
cat > "$fake/docker" <<'EOS'
#!/bin/bash
printf '[%s]' "$@" >> "$(dirname "$0")/docker.log"; echo >> "$(dirname "$0")/docker.log"
EOS
rm -f "$fake/docker.log" "$fake/apptainer.log"
out="$(run -- --container iris-env-build:local --no-network microct/2 python -V)" ||
    { echo "envrun --container: exit non-zero"; echo "$out" | sed 's/^/  /'; }
out="$(log docker)"
has "envrun --container" "$out" "[--network][none]"
has "envrun --container" "$out" "[--volume][$repo:$repo]"
has "envrun --container" "$out" "[iris-env-build:local][python][-V]"
lacks "envrun --container" "$out" "[pull]"
[ -z "$(log apptainer)" ] || echo "envrun --container: ran apptainer"
out="$(run -- --container microct/1 python -V)" && echo "envrun --container with no name: exit 0"
has "envrun --container with no name" "$out" "usage:"

# Under Docker, a pull that fails because Docker's credential helper does
# (credsStore pointing at a Windows helper with no logon session behind
# it) is retried once with DOCKER_CONFIG at an empty config of its own,
# which the public package needs no login for, and that config is removed
# afterwards (#247). The fake docker's pull fails on the credential error
# #247 saw, or on FAKE_CRED_ERROR, unless DOCKER_CONFIG holds a
# config.json of {}; with FAKE_PULL_ERROR it fails with that error
# instead, whatever the config, and with FAKE_RETRY_ERROR it fails with
# that error under any DOCKER_CONFIG.
cat > "$fake/docker" <<'EOS'
#!/bin/bash
dir="$(dirname "$0")"
printf '[%s]' "$@" >> "$dir/docker.log"; echo "[DOCKER_CONFIG=${DOCKER_CONFIG-}]" >> "$dir/docker.log"
case "$1" in
    image) [ -f "$dir/pulled" ] ;;
    pull)
        [ -z "${DOCKER_CONFIG-}" ] || echo "$DOCKER_CONFIG" >> "$dir/configs"
        if [ -n "${FAKE_PULL_ERROR-}" ]; then echo "$FAKE_PULL_ERROR" >&2; exit 1; fi
        if [ -n "${FAKE_RETRY_ERROR-}" ] && [ -n "${DOCKER_CONFIG-}" ]; then echo "$FAKE_RETRY_ERROR" >&2; exit 1; fi
        if [ "$(cat "${DOCKER_CONFIG:-/nonexistent}/config.json" 2>/dev/null)" != "{}" ]; then
            echo "${FAKE_CRED_ERROR:-Error getting credentials - err: exit status 1, out: \`A specified logon session does not exist. It may already have been terminated.\`}" >&2
            exit 1
        fi
        touch "$dir/pulled" ;;
esac
EOS
# cred_case <case> [<error>]: a pull failing on a credential error, #247's
# or <error>, is retried once, the command runs, and the retry's config
# is gone.
cred_case() {
    local out retry_config
    rm -f "$fake/docker.log" "$fake/pulled" "$fake/configs"
    out="$(run IRIS_CONTAINER_RUNTIME=docker ${2:+FAKE_CRED_ERROR="$2"} -- --no-network microct/1 true)" ||
        { echo "$1: exit non-zero"; echo "$out" | sed 's/^/  /'; }
    [ "$(grep -c '^\[pull\]' "$fake/docker.log" 2>/dev/null)" = 2 ] ||
        { echo "$1: not pulled twice"; log docker | sed 's/^/  /'; }
    has "$1" "$(log docker)" "[run][--rm]"
    retry_config="$(cat "$fake/configs" 2>/dev/null)"
    [ -n "$retry_config" ] && [ ! -e "$retry_config" ] ||
        echo "$1: no retry config, or it is still there: ${retry_config:-none}"
}
cred_case "docker pull with a failing credential helper"
# Docker's lowercase wording, which `docker pull` printed on the desktop
# on 2026-11-21 with DOCKER_CONFIG holding
# {"credsStore":"nonexistent-helper"}, a helper that isn't installed.
cred_case "docker pull with a missing credential helper" \
    'error getting credentials - err: exec: "docker-credential-nonexistent-helper": executable file not found in $PATH, out: ``'
# Any other pull failure is not retried: the run fails with that pull's
# error and runs nothing.
rm -f "$fake/docker.log" "$fake/pulled" "$fake/configs"
out="$(run IRIS_CONTAINER_RUNTIME=docker FAKE_PULL_ERROR="manifest unknown" -- --no-network microct/1 true)" &&
    echo "docker pull failing on another error: exit 0"
has "docker pull failing on another error" "$out" "manifest unknown"
[ "$(grep -c '^\[pull\]' "$fake/docker.log" 2>/dev/null)" = 1 ] ||
    { echo "docker pull failing on another error: not pulled once"; log docker | sed 's/^/  /'; }
lacks "docker pull failing on another error" "$(log docker)" "[run]"
# A retry that fails too fails the run with the retry's error, runs
# nothing and still removes its config.
rm -f "$fake/docker.log" "$fake/pulled" "$fake/configs"
out="$(run IRIS_CONTAINER_RUNTIME=docker FAKE_RETRY_ERROR="denied: no anonymous access" -- --no-network microct/1 true)" &&
    echo "docker pull whose retry fails: exit 0"
has "docker pull whose retry fails" "$out" "denied: no anonymous access"
lacks "docker pull whose retry fails" "$(log docker)" "[run]"
retry_config="$(cat "$fake/configs" 2>/dev/null)"
[ -n "$retry_config" ] && [ ! -e "$retry_config" ] ||
    echo "docker pull whose retry fails: no retry config, or it is still there: ${retry_config:-none}"
