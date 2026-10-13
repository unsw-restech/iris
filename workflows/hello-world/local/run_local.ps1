# ===============================================================
#  IRIS - Hello World workflow (local / Docker - Windows)
#  Requires: Docker Desktop for Windows
#
#  Deliberately ASCII-only: Windows PowerShell 5.1 reads a UTF-8
#  file without a BOM as ANSI, and a non-ASCII byte can decode to
#  a quote character that breaks the parse.
#
#  Docs: https://patricktung.github.io/iris/workflows/hello-world/
# ===============================================================

$OUTDIR = "$HOME\iris-hello-world"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

Write-Host "========================================"
Write-Host "  IRIS Hello World - Local (Docker)"
Write-Host "========================================"
Write-Host ""
Write-Host "Output directory: $OUTDIR"
Write-Host ""

docker run --rm `
  -v "${OUTDIR}:/output" `
  ubuntu:22.04 `
  bash -c '
    {
      echo "========================================"
      echo "  IRIS Hello World - Success"
      echo "========================================"
      echo "Timestamp : $(date)"
      echo "Hostname  : $(hostname)"
      echo "OS        : $(uname -o)"
      echo "CPUs      : $(nproc)"
      echo ""
      echo "If you can read this, your local IRIS"
      echo "Docker setup is working correctly."
      echo "========================================"
    } | tee /output/hello_world_result.txt
  '

Write-Host ""
Write-Host "Result written to: $OUTDIR\hello_world_result.txt"
Write-Host ""
Write-Host "========================================"
Write-Host "  IRIS Hello World - Complete"
Write-Host "========================================"
