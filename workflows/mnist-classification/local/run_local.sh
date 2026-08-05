#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARES — MNIST image classification (local)
#  Runs exactly the same training script as the Katana job.
#
#  Requires: Python 3 with PyTorch. Nothing else — MNIST is read
#  with the standard library, so torchvision is not needed.
#
#      pip install torch
#
#  A GPU is used automatically if torch can see one.
#
#  Docs: https://patricktung.github.io/ares/workflows/mnist-classification/
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

OUTDIR="${ARES_OUTDIR:-$HOME/ares-mnist-classification}"
DATADIR="$OUTDIR/data"
EPOCHS="${ARES_EPOCHS:-3}"
PYTHON="${ARES_PYTHON:-python3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAIN_SCRIPT="$SCRIPT_DIR/../src/train_mnist.py"

echo "========================================"
echo "  ARES MNIST classification — Local"
echo "========================================"
echo ""

if [ ! -f "$TRAIN_SCRIPT" ]; then
    echo "ERROR: cannot find $TRAIN_SCRIPT"
    exit 1
fi

if ! "$PYTHON" -c "import torch" > /dev/null 2>&1; then
    echo "ERROR: PyTorch is not importable with '$PYTHON'."
    echo ""
    echo "Install it with:"
    echo "    $PYTHON -m pip install torch"
    echo ""
    echo "Or point this script at a different interpreter:"
    echo "    ARES_PYTHON=/path/to/python bash run_local.sh"
    exit 1
fi

"$PYTHON" - <<'PY'
import torch
print(f"PyTorch : {torch.__version__}")
print(f"Device  : {'cuda - ' + torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu (a few minutes)'}")
PY

echo "Output  : $OUTDIR"
echo ""

mkdir -p "$OUTDIR" "$DATADIR"

"$PYTHON" "$TRAIN_SCRIPT" \
    --data-dir "$DATADIR" \
    --outdir "$OUTDIR" \
    --epochs "$EPOCHS"

echo ""
echo "Results written to: $OUTDIR"
echo "  metrics.json          final accuracy and per-epoch history"
echo "  confusion_matrix.txt  10x10, rows are true labels"
echo "  training_log.txt      full run log"
echo "  model.pt              trained weights"
echo ""
echo "========================================"
echo "  ARES MNIST classification — Complete"
echo "========================================"
