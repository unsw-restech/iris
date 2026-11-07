# Every later version of an environment, <env>/<n> for n > 1: the version
# before it, pulled by digest, plus the packages <env>/<n>'s lock adds, as
# one new layer. The registry stores the layers the two share only once.
# bin/check fails a lock that removes or changes a package the version
# before it pinned, so pip installs only what is new: every other line is
# already satisfied.
#
# envs/build-container.sh <env>/<n> builds it, with envs/<env>/<n>/ as the
# context and PREVIOUS the version before it by digest alone
# (ghcr.io/unsw-restech/iris-env@sha256:<hex>), from lib/katana.sh's
# digest map.

ARG PREVIOUS
FROM ${PREVIOUS}

COPY requirements.lock /opt/iris-build/requirements.lock
RUN pip install --no-cache-dir --only-binary=:all: --no-deps \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        -r /opt/iris-build/requirements.lock \
    && rm -r /opt/iris-build

ARG VERSION=unknown
ARG COMMIT=unknown
LABEL org.opencontainers.image.revision=$COMMIT \
      org.opencontainers.image.version=$VERSION
