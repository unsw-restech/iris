#!/bin/bash
# Check a built container against its version's recipe, as CI does after
# every build and before any publish (.github/workflows/containers.yml):
#
#   DISPLAY=<X display open to any client> envs/check-container.sh <local name> <env>/<n>
#
# Fails, naming what is wrong, unless:
#   - pip freeze inside it is envs/<env>/<n>/requirements.lock exactly
#   - every package in the lock imports (check_imports.py)
#   - PyTorch is compiled for sm_70, as the V100s need
# and, for a version whose lock pins napari (iris-view):
#   - Qt's xcb platform plugin, its GLX integration and the PyQt5 modules
#     napari loads find every library they link
#   - napari draws a frame on $DISPLAY, which Xvfb -ac provides in CI;
#     offscreen Qt has no OpenGL and draws nothing
# Needs Docker.

set -euo pipefail

NAME="${1:?usage: envs/check-container.sh <local name> <env>/<n>}"
VERSION="${2:?usage: envs/check-container.sh <local name> <env>/<n>}"
ENVS="$(cd "$(dirname "$0")" && pwd)"
LOCK="$ENVS/$VERSION/requirements.lock"
[ -f "$LOCK" ] || { echo "No $LOCK."; exit 1; }

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

echo "== PyTorch compiled for the V100s (sm_70)"
in_container python -c 'import torch; a = torch._C._cuda_getArchFlags(); print(a); assert "sm_70" in a.split(), "no sm_70: this PyTorch cannot run on the V100s"'

if ! grep -qiE '^napari==' "$LOCK"; then
    echo "No napari in the lock, so no Qt or drawing checks."
    echo "Container checks passed."
    exit 0
fi

: "${DISPLAY:?set DISPLAY to an X server that accepts any client, e.g. Xvfb :99 -ac}"

echo "== Qt libraries"
# shellcheck disable=SC2016  # expanded inside the container
missing=$(in_container bash -c 'q=$(python -c "import os, PyQt5; print(os.path.dirname(PyQt5.__file__))")
    ldd "$q"/Qt{Core,Gui,Widgets,OpenGL,Svg}.abi3.so "$q"/Qt5/plugins/platforms/libqxcb.so \
        "$q"/Qt5/plugins/xcbglintegrations/*.so | grep "not found" | sort -u')
if [ -n "$missing" ]; then
    echo "$missing"
    echo "FAILED: Qt can't find the libraries above; add their Debian packages to the first version's Dockerfile."
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
