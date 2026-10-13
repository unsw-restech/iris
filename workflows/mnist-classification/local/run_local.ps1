# ===============================================================
#  IRIS - MNIST image classification (local - Windows)
#  Runs exactly the same training script as the Katana job.
#
#  Requires: Python 3 with PyTorch. Nothing else - MNIST is read
#  with the standard library, so torchvision is not needed.
#
#      pip install torch
#
#  A GPU is used automatically if torch can see one.
#
#  Deliberately ASCII-only: Windows PowerShell 5.1 reads a UTF-8
#  file without a BOM as ANSI, and a non-ASCII byte can decode to
#  a quote character that breaks the parse.
#
#  Docs: https://patricktung.github.io/iris/workflows/mnist-classification/
# ===============================================================

$ErrorActionPreference = "Stop"

$OutDir = if ($env:IRIS_OUTDIR) { $env:IRIS_OUTDIR } else { "$HOME\iris-mnist-classification" }
$Epochs = if ($env:IRIS_EPOCHS) { $env:IRIS_EPOCHS } else { "3" }
$Python = if ($env:IRIS_PYTHON) { $env:IRIS_PYTHON } else { "python" }

$DataDir = Join-Path $OutDir "data"
$TrainScript = Join-Path $PSScriptRoot "..\src\train_mnist.py"

Write-Host "========================================"
Write-Host "  IRIS MNIST classification - Local"
Write-Host "========================================"
Write-Host ""

if (-not (Test-Path $TrainScript)) {
    Write-Host "ERROR: cannot find $TrainScript"
    exit 1
}

& $Python -c "import torch" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: PyTorch is not importable with '$Python'."
    Write-Host ""
    Write-Host "Install it with:"
    Write-Host "    $Python -m pip install torch"
    Write-Host ""
    Write-Host "Or point this script at a different interpreter:"
    Write-Host "    `$env:IRIS_PYTHON='C:\path\to\python.exe'; .\run_local.ps1"
    exit 1
}

& $Python -c "import torch; print('PyTorch : ' + torch.__version__); print('Device  : ' + ('cuda - ' + torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu (a few minutes)'))"

Write-Host "Output  : $OutDir"
Write-Host ""

New-Item -ItemType Directory -Force -Path $OutDir, $DataDir | Out-Null

& $Python $TrainScript --data-dir $DataDir --outdir $OutDir --epochs $Epochs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Training failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Results written to: $OutDir"
Write-Host "  metrics.json          final accuracy and per-epoch history"
Write-Host "  confusion_matrix.txt  10x10, rows are true labels"
Write-Host "  training_log.txt      full run log"
Write-Host "  model.pt              trained weights"
Write-Host ""
Write-Host "========================================"
Write-Host "  IRIS MNIST classification - Complete"
Write-Host "========================================"
