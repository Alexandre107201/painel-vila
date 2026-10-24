$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
# OS-held exclusive lock releases even on crash; no interaction with Teknisa.
try {
  $lock = [System.IO.File]::Open((Join-Path $PSScriptRoot 'capture.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch [System.IO.IOException] { exit 0 }
try {
  $log = Join-Path $PSScriptRoot 'capture.log'
  if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Move-Item $log "$log.1" -Force }
  Add-Content $log (Get-Date -Format o)
  & '.\.venv\Scripts\python.exe' '.\capture.py' *>> $log
  $result = $LASTEXITCODE
} finally { $lock.Dispose() }
exit $result
