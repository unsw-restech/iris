#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARES — MNIST image classification: one-time preparation
#
#  Run this ON A KATANA LOGIN NODE, not inside a job.
#
#  It downloads the MNIST dataset (~11 MB) into scratch, so the
#  job itself runs entirely offline. That matters if compute
#  nodes have no direct outbound internet.
#
#  There is nothing else to prepare — the PyTorch environment
#  comes from `module load`, so there is no image to pull and
#  nothing to install.
#
#  Safe to re-run: existing files are skipped.
# ═══════════════════════════════════════════════════════════════

# ── Parameters (keep in step with ares_mnist_classification.pbs) ─
OUTDIR="/srv/scratch/$USER/ares-mnist-classification"
DATADIR="/srv/scratch/$USER/ares-mnist-classification/data"
PYTORCH_MODULE="pytorch/1.13.1"
# ───────────────────────────────────────────────────────────────

set -euo pipefail

MNIST_URL="https://ossci-datasets.s3.amazonaws.com/mnist"
MNIST_FILES="train-images-idx3-ubyte.gz train-labels-idx1-ubyte.gz t10k-images-idx3-ubyte.gz t10k-labels-idx1-ubyte.gz"

echo "========================================"
echo "  ARES MNIST classification — prepare"
echo "========================================"
echo ""

if [ ! -d "/srv/scratch/$USER" ]; then
    echo "ERROR: /srv/scratch/$USER does not exist."
    echo "Are you on Katana? Scratch is created on first login."
    exit 1
fi

mkdir -p "$OUTDIR" "$DATADIR"

# Katana may route outbound traffic through a proxy. curl and urllib both
# pick this up from the environment; this just makes it visible in the log.
if [ -n "${HTTPS_PROXY:-${https_proxy:-}}" ]; then
    echo "Using proxy: ${HTTPS_PROXY:-$https_proxy}"
    echo ""
fi

# ── 1. Dataset ──────────────────────────────────────────────────
echo "[1/2] MNIST dataset -> $DATADIR"
for f in $MNIST_FILES; do
    if [ -f "$DATADIR/$f" ]; then
        echo "      already present: $f"
        continue
    fi
    echo "      downloading:     $f"
    # Download to .part so an interrupted transfer can't leave a truncated
    # archive that the job would then fail to parse.
    if ! curl -fsSL "$MNIST_URL/$f" -o "$DATADIR/$f.part"; then
        rm -f "$DATADIR/$f.part"
        echo "ERROR: failed to download $f — check network access from this node."
        exit 1
    fi
    mv "$DATADIR/$f.part" "$DATADIR/$f"
done
echo "      total: $(du -sh "$DATADIR" | cut -f1)"
echo ""

# ── 2. Check the module resolves ────────────────────────────────
echo "[2/2] Checking $PYTORCH_MODULE"
if ! type module > /dev/null 2>&1; then
    for init in /etc/profile.d/modules.sh /usr/share/Modules/init/bash; do
        # shellcheck disable=SC1090
        [ -f "$init" ] && . "$init" && break
    done
fi

if type module > /dev/null 2>&1; then
    set +u
    module purge
    if module load "$PYTORCH_MODULE" 2> /dev/null; then
        set -u
        if python3 -c "import torch; print('      torch', torch.__version__, '- CUDA', torch.version.cuda or 'none')" 2> /dev/null; then
            echo "      module OK"
        else
            echo "      WARNING: module loaded but 'import torch' failed."
        fi
    else
        set -u
        echo "      WARNING: could not load '$PYTORCH_MODULE'."
        echo "      Run 'module avail pytorch' and update PYTORCH_MODULE in both"
        echo "      this script and ares_mnist_classification.pbs."
    fi
else
    echo "      WARNING: 'module' command unavailable on this node."
fi
echo ""

echo "========================================"
echo "  Prepared. Submit the job with:"
echo ""
echo "    qsub ares_mnist_classification.pbs"
echo ""
echo "  Results will appear in:"
echo "    $OUTDIR"
echo "========================================"
