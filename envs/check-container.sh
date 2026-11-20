#!/bin/bash
# Check a built container against its version's recipe, as CI does after
# every build and before any publish (.github/workflows/containers.yml):
#
#   DISPLAY=<X display open to any client> envs/check-container.sh <local name> <env>/<n>
#
# Fails, naming what is wrong, unless:
#   - pip freeze inside it is envs/<env>/<n>/requirements.lock exactly
#   - every package in the lock imports (check_imports.py)
# for a version whose lock pins torch:
#   - PyTorch is compiled for sm_70, as the V100s need
# and, for a version whose lock pins napari (iris-view):
#   - the lock pins one Qt binding, PyQt5 or PyQt6
#   - that binding's xcb platform plugin, its GLX integration and the
#     modules napari loads find every library they link
#   - napari draws a frame on $DISPLAY, which Xvfb -ac provides in CI;
#     offscreen Qt has no OpenGL and draws nothing
# Needs Docker.

set -euo pipefail

NAME="${1:?usage: envs/check-container.sh <local name> <env>/<n>}"
VERSION="${2:?usage: envs/check-container.sh <local name> <env>/<n>}"
ENVS="$(cd "$(dirname "$0")" && pwd)"
LOCK="$ENVS/$VERSION/requirements.lock"
[ -f "$LOCK" ] || { echo "No $LOCK."; exit 1; }

# The Qt binding napari draws with is whichever one the lock pins, read
# before any Docker run so a lock with neither fails at once.
QT=
if grep -qiE '^napari==' "$LOCK"; then
    # Each binding pinned, by its name before ==, any case, written PyQt5 or PyQt6.
    pinned=$(sed -nE 's/^pyqt([56])[[:space:]]*==.*/PyQt\1/Ip' "$LOCK" | sort -u | tr '\n' ' ')
    case "$pinned" in
        "PyQt5 "|"PyQt6 ") QT="${pinned% }" ;;
        "") echo "FAILED: envs/$VERSION/requirements.lock pins napari but neither PyQt5 nor PyQt6."; exit 1 ;;
        *) echo "FAILED: envs/$VERSION/requirements.lock pins both PyQt5 and PyQt6; pin one."; exit 1 ;;
    esac
fi

in_container() {
    docker run --rm -v "$ENVS:/recipe:ro" -v /tmp/.X11-unix:/tmp/.X11-unix \
        -e DISPLAY -e MLFLOW_DISABLE_AGENT_HINT=1 "$NAME" "$@"
}

echo "== installed packages against $VERSION's requirements.lock"
if ! diff <(tr -d '\r' < "$LOCK") <(in_container python -m pip freeze); then
    echo "FAILED: the installed packages differ from envs/$VERSION/requirements.lock (diff above)."
    exit 1
fi
echo "identical"

echo "== imports"
in_container python /recipe/check_imports.py "/recipe/$VERSION/requirements.lock"

if grep -qiE '^torch==' "$LOCK"; then
    echo "== PyTorch compiled for the V100s (sm_70)"
    in_container python -c 'import torch; a = torch._C._cuda_getArchFlags(); print(a); assert "sm_70" in a.split(), "no sm_70: this PyTorch cannot run on the V100s"'
else
    echo "No torch in the lock, so no GPU arch check."
fi

if [ -z "$QT" ]; then
    echo "No napari in the lock, so no Qt or drawing checks."
    echo "Container checks passed."
    exit 0
fi

: "${DISPLAY:?set DISPLAY to an X server that accepts any client, e.g. Xvfb :99 -ac}"

case "$QT" in
    PyQt5) modules="Core Gui Widgets OpenGL Svg" ;;
    PyQt6) modules="Core Gui Widgets OpenGL OpenGLWidgets Svg" ;;
esac

echo "== Qt libraries ($QT)"
# shellcheck disable=SC2016  # expanded inside the container
missing=$(in_container bash -c 'b=$1; q=$(python -c "import os, $b; print(os.path.dirname($b.__file__))")
    libs=(); for m in $2; do libs+=("$q/Qt$m.abi3.so"); done
    ldd "${libs[@]}" "$q/Qt${b#PyQt}/plugins/platforms/libqxcb.so" \
        "$q/Qt${b#PyQt}"/plugins/xcbglintegrations/*.so | grep "not found" | sort -u' _ "$QT" "$modules")
if [ -n "$missing" ]; then
    echo "$missing"
    echo "FAILED: Qt can't find the libraries above; add their Debian packages to envs/$VERSION/Dockerfile, the version's own beside its lock, since a published Dockerfile is never edited."
    exit 1
fi
echo "all found"

echo "== napari draws a frame"
in_container python -c '
import numpy as np, napari
from vispy.gloo import gl
v = napari.Viewer(show=False)
v.add_image(np.random.rand(64, 64))
v.add_labels(np.ones((64, 64), dtype=np.uint8))
shot = v.screenshot(canvas_only=True, flash=False)
assert shot.size and shot.any(), "napari drew an empty frame"
print("napari", napari.__version__, "drew", shot.shape, "with", gl.glGetParameter(gl.GL_RENDERER))
v.close()'

echo "Container checks passed."
