# tools/1, the researcher tools' environment's first version (#149): what
# iris-view, iris-compare, the importer and rebuild need, at microct/1's
# pins, so iris-view behaves as it did there, installed into a venv on the
# same digest-pinned Python 3.13.2, plus the system libraries napari's Qt
# needs. It is microct/1's recipe without PyTorch, so a change to the
# viewer's packages never touches a lab's environment. It holds the
# environment only, never IRIS code: the tools run lib/ from the clone
# (bin/iris-python).
#
# CI builds, checks and publishes it (.github/workflows/containers.yml);
# ../../README.md covers how. A later version whose lock only adds is built
# on top of the one before it by ../../next.Dockerfile; one that changes or
# removes a pin is built fresh from this file with its own lock
# (../../build-kind.sh, ADR-0010). This file is never edited once
# published.

# python:3.13.2-slim-bookworm, pinned by digest alone: Apptainer refuses a
# reference that has both a tag and a digest.
FROM python@sha256:6b3223eb4d93718828223966ad316909c39813dee3ee9395204940500792b740

# What ldd finds missing from the base for Qt's xcb platform plugin, its
# GLX integration and the PyQt5 modules napari loads (check-container.sh
# fails on any it still can't find). libgl1-mesa-dri renders in software
# where the host binds no GPU driver, as in a Virtual Desktop;
# fonts-dejavu-core gives fontconfig a font, without which napari's labels
# draw empty. git is for GitPython, which mlflow imports and which fails to
# import without it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libdbus-1-3 libegl1 libfontconfig1 libfreetype6 libgl1 libgl1-mesa-dri \
        libglib2.0-0 libx11-6 libx11-xcb1 libxcb-glx0 libxcb-icccm4 \
        libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
        libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 \
        libxcb-xinerama0 libxcb-xkb1 libxcb1 libxext6 libxkbcommon-x11-0 \
        libxkbcommon0 fonts-dejavu-core git \
    && rm -rf /var/lib/apt/lists/*

# A venv, so pip freeze lists the lock and nothing else, and a researcher's
# ~/.local packages (Apptainer binds $HOME) stay off the path. Its python is
# first on the PATH, which Apptainer keeps under --cleanenv. The lock goes
# outside /tmp, which an Apptainer build mounts over from the host.
ENV PATH=/opt/iris-env/bin:$PATH
COPY requirements.lock /opt/iris-build/requirements.lock
RUN python -m venv /opt/iris-env \
    && pip install --no-cache-dir --only-binary=:all: \
        -r /opt/iris-build/requirements.lock \
    && rm -r /opt/iris-build

# OCI annotation keys, which GHCR reads to link the package to this repo.
ARG VERSION=unknown
ARG COMMIT=unknown
LABEL org.opencontainers.image.source=https://github.com/unsw-restech/iris \
      org.opencontainers.image.revision=$COMMIT \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.description="IRIS environment: envs/README.md" \
      org.opencontainers.image.licenses=Apache-2.0
