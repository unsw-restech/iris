#!/bin/bash
# Check a built imaging image against this folder's recipe, as CI does after
# every build (.github/workflows/image.yml):
#
#   DISPLAY=<X display open to any client> envs/imaging/check-image.sh <image>
#
# Fails, naming what is wrong, unless:
#   - pip freeze inside the image is requirements.lock exactly
#   - every package in the lock imports (check_imports.py)
#   - PyTorch is compiled for sm_70, as the V100s need
#   - Qt's xcb platform plugin, its GLX integration and the PyQt5 modules
#     napari loads find every library they link
#   - napari draws a frame on $DISPLAY, which Xvfb -ac provides in CI
# Needs Docker.

set -euo pipefail

IMAGE="${1:?usage: check-image.sh <image>}"
RECIPE="$(cd "$(dirname "$0")" && pwd)"
: "${DISPLAY:?set DISPLAY to an X server that accepts any client, e.g. Xvfb :99 -ac}"

in_image() {
    docker run --rm -v "$RECIPE:/recipe:ro" -v /tmp/.X11-unix:/tmp/.X11-unix \
        -e DISPLAY -e MLFLOW_DISABLE_AGENT_HINT=1 "$IMAGE" "$@"
}

echo "== installed packages against requirements.lock"
if ! diff <(tr -d '\r' < "$RECIPE/requirements.lock") <(in_image python -m pip freeze); then
    echo "FAILED: the installed packages differ from requirements.lock (diff above)."
    exit 1
fi
echo "identical"

echo "== imports"
in_image python /recipe/check_imports.py /recipe/requirements.lock

echo "== PyTorch compiled for the V100s (sm_70)"
in_image python -c 'import torch; a = torch._C._cuda_getArchFlags(); print(a); assert "sm_70" in a.split(), "no sm_70: this PyTorch cannot run on the V100s"'

echo "== Qt libraries"
# shellcheck disable=SC2016  # expanded inside the image
missing=$(in_image bash -c 'q=$(python -c "import os, PyQt5; print(os.path.dirname(PyQt5.__file__))")
    ldd "$q"/Qt{Core,Gui,Widgets,OpenGL,Svg}.abi3.so "$q"/Qt5/plugins/platforms/libqxcb.so \
        "$q"/Qt5/plugins/xcbglintegrations/*.so | grep "not found" | sort -u')
if [ -n "$missing" ]; then
    echo "$missing"
    echo "FAILED: Qt can't find the libraries above; add their Debian packages to the Dockerfile."
    exit 1
fi
echo "all found"

echo "== napari draws a frame"
in_image python -c '
import numpy as np, napari
from vispy.gloo import gl
v = napari.Viewer(show=False)
v.add_image(np.random.rand(64, 64))
v.add_labels(np.ones((64, 64), dtype=np.uint8))
shot = v.screenshot(canvas_only=True, flash=False)
assert shot.size and shot.any(), "napari drew an empty frame"
print("napari", napari.__version__, "drew", shot.shape, "with", gl.glGetParameter(gl.GL_RENDERER))
v.close()'

echo "Image checks passed."
