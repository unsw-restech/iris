#!/bin/bash
# The bin/iris-* tools against a fake apptainer on the PATH, which only
# reports how it was called: each runs its own iris.* module from this
# clone's lib/, with the arguments it was given, in the researcher tools'
# container (IRIS_TOOLS_CONTAINER names a stand-in file) under --cleanenv,
# passing only lib/ on the Python path, USER, and IRIS_HOME and the display
# when set. A missing container stops with one line and never starts
# apptainer. Prints each failed case and nothing on success, so bin/check
# can run it.
#
#   tests/bin/test_iris_tools.sh
#
# bin/check name: iris tools test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
. lib/katana.sh || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
mkdir -p "$fake/bin"
cat > "$fake/bin/apptainer" <<'EOF'
#!/bin/bash
printf '[%s]' "$@"; echo
EOF
chmod +x "$fake/bin/apptainer"
: > "$fake/tools.sif"
lib="$PWD/lib"

# run <tool> <arg>...: the tool's output, with the fake apptainer first on
# the PATH and the stand-in container.
run() {
    local tool="$1"
    shift
    PATH="$fake/bin:$PATH" IRIS_TOOLS_CONTAINER="$fake/tools.sif" "$tool" "$@" 2>&1
}
# has <what> <output> <want>: <want> is in <output>, or the case fails.
has() { grep -qF -- "$3" <<< "$2" || { echo "$1: no $3 in"; echo "$2" | sed 's/^/  /'; }; }
lacks() { grep -qF -- "$3" <<< "$2" && { echo "$1: $3 in"; echo "$2" | sed 's/^/  /'; }; }

for tool in view:iris.view compare:iris.compare import:iris.tracking rebuild:iris.rebuild; do
    name="iris-${tool%%:*}" module="${tool#*:}"
    out="$(env -u IRIS_HOME -u DISPLAY -u XAUTHORITY USER=someone PYTHONPATH=/elsewhere SECRET=x \
        PATH="$fake/bin:$PATH" IRIS_TOOLS_CONTAINER="$fake/tools.sif" "bin/$name" "a b" c 2>&1)"
    has "bin/$name" "$out" "[exec][--cleanenv]"
    has "bin/$name" "$out" "[--env][PYTHONPATH=$lib]"
    has "bin/$name" "$out" "[--env][USER=someone]"
    has "bin/$name" "$out" "[$fake/tools.sif][python][-u][-m][$module][a b][c]"
    for unwanted in IRIS_HOME DISPLAY XAUTHORITY SECRET /elsewhere --nv; do
        lacks "bin/$name, with nothing else set" "$out" "$unwanted"
    done
done

# IRIS_HOME and the display pass through when set, so iris-view's napari
# reaches the Virtual Desktop's X server.
out="$(IRIS_HOME=/srv/scratch/someone/home DISPLAY=:7 XAUTHORITY=/home/someone/.Xauthority run bin/iris-view run)"
has "bin/iris-view in a desktop" "$out" "[--env][IRIS_HOME=/srv/scratch/someone/home]"
has "bin/iris-view in a desktop" "$out" "[--env][DISPLAY=:7]"
has "bin/iris-view in a desktop" "$out" "[--env][XAUTHORITY=/home/someone/.Xauthority]"

# A missing container stops each tool at once with one line naming it,
# and apptainer never starts. Without IRIS_TOOLS_CONTAINER the container
# is <folder>/<env>/<n>.sif (envs/README.md).
for name in iris-view iris-compare iris-import iris-rebuild; do
    out="$(PATH="$fake/bin:$PATH" IRIS_TOOLS_CONTAINER="$fake/none.sif" "bin/$name" 2>&1)" &&
        echo "bin/$name: exit 0 with no container"
    [ "$(wc -l <<< "$out")" = 1 ] || echo "bin/$name: more than one line with no container"
    has "bin/$name, no container" "$out" "$fake/none.sif"
    lacks "bin/$name, no container" "$out" "[exec]"
done
want="$IRIS_ENVS_FOLDER/$IRIS_TOOLS_ENV_VERSION.sif"
if [ ! -e "$want" ]; then
    out="$(env -u IRIS_TOOLS_CONTAINER PATH="$fake/bin:$PATH" bin/iris-view 2>&1)"
    has "bin/iris-view, its own container missing" "$out" "$want"
fi

# Firefox isn't in the container, so bin/iris-compare opens the host's at
# the URL iris.compare writes to IRIS_URL_FILE once MLflow answers. Here a
# fake apptainer plays iris.compare, and a fake firefox logs its arguments.
mkdir -p "$fake/compare"
cat > "$fake/compare/apptainer" <<'EOF'
#!/bin/bash
for a in "$@"; do
    case "$a" in IRIS_URL_FILE=*) echo "http://127.0.0.1:5123" > "${a#IRIS_URL_FILE=}" ;; esac
done
sleep 2
EOF
printf '%s\n' '#!/bin/bash' 'echo "$@" >> "$FIREFOX_LOG"' > "$fake/compare/firefox"
chmod +x "$fake/compare/apptainer" "$fake/compare/firefox"
out="$(FIREFOX_LOG="$fake/firefox.log" PATH="$fake/compare:$PATH" IRIS_TOOLS_CONTAINER="$fake/tools.sif" bin/iris-compare 2>&1)" ||
    echo "bin/iris-compare: failed with Firefox: $out"
[ "$(cat "$fake/firefox.log" 2>/dev/null)" = "http://127.0.0.1:5123" ] ||
    echo "bin/iris-compare: Firefox wasn't opened once at the URL; it got: $(cat "$fake/firefox.log" 2>/dev/null)"
# The URL file is in /tmp, which the container sees, whatever TMPDIR says:
# one outside the container's binds would leave the watcher waiting forever.
mkdir -p "$fake/tmpdir"
out="$(TMPDIR="$fake/tmpdir" run bin/iris-compare)"
has "bin/iris-compare with TMPDIR set" "$out" "[--env][IRIS_URL_FILE=/tmp/"
lacks "bin/iris-compare with TMPDIR set" "$out" "IRIS_URL_FILE=$fake/tmpdir"
# With no Firefox on the host, it says where to go instead.
mkdir -p "$fake/nofox"
ln -s "$fake/compare/apptainer" "$fake/nofox/apptainer"
out="$(PATH="$fake/nofox:/usr/bin:/bin" IRIS_TOOLS_CONTAINER="$fake/tools.sif" bin/iris-compare 2>&1)"
if ! command -v -p firefox > /dev/null; then
    has "bin/iris-compare without Firefox" "$out" "Firefox was not found: open http://127.0.0.1:5123 in a browser in this desktop."
fi

# The tools reach module/bin's links: one run through a link to bin/.
mkdir -p "$fake/link"
ln -s "$PWD/bin/iris-view" "$fake/link/iris-view"
out="$(run "$fake/link/iris-view" run)"
has "a link to bin/iris-view" "$out" "[-m][iris.view][run]"
has "a link to bin/iris-view" "$out" "[--env][PYTHONPATH=$lib]"
