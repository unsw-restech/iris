# The imaging environment as a container image (ADR-0004): requirements.lock
# installed into a venv on a digest-pinned Python, plus the system libraries
# napari's Qt needs for iris-view. It holds the environment only, never
# workflow code: a run binds its clone in. CUDA comes from the lock's wheels
# and the driver from the host (apptainer --nv).
#
# CI builds, checks and publishes it (.github/workflows/image.yml); README.md
# in this folder covers how a build becomes a pinned version.

FROM python:3.13.2-slim-bookworm@sha256:6b3223eb4d93718828223966ad316909c39813dee3ee9395204940500792b740

# What ldd finds missing from the base image for Qt's xcb platform plugin, its
# GLX integration and the PyQt5 modules napari loads (check-image.sh fails on
# any it still can't find). libgl1-mesa-dri renders in software where the
# host binds no GPU driver, as in a Virtual Desktop; fonts-dejavu-core gives
# fontconfig a font, without which napari's labels draw empty. git is for
# GitPython, which mlflow imports and which fails to import without it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libdbus-1-3 libegl1 libfontconfig1 libfreetype6 libgl1 libgl1-mesa-dri \
        libglib2.0-0 libx11-6 libx11-xcb1 libxcb-glx0 libxcb-icccm4 \
        libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
        libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 \
        libxcb-xinerama0 libxcb-xkb1 libxcb1 libxext6 libxkbcommon-x11-0 \
        libxkbcommon0 fonts-dejavu-core git \
    && rm -rf /var/lib/apt/lists/*

# A venv, as on Katana, so pip freeze lists the lock and nothing else, and a
# researcher's ~/.local packages (Apptainer binds $HOME) stay off the path.
ENV PATH=/opt/iris-imaging/bin:$PATH
COPY requirements.lock /tmp/requirements.lock
RUN python -m venv /opt/iris-imaging \
    && pip install --no-cache-dir --only-binary=:all: \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        -r /tmp/requirements.lock \
    && rm /tmp/requirements.lock

ARG COMMIT=unknown
LABEL org.opencontainers.image.source=https://github.com/unsw-restech/iris \
      org.opencontainers.image.revision=$COMMIT \
      org.opencontainers.image.description="IRIS imaging environment: envs/imaging/README.md" \
      org.opencontainers.image.licenses=Apache-2.0
