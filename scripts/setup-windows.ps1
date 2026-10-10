# One-shot setup for Windows. Run from the repo folder in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
# Safe to re-run. Installs: Rokit (+ Rojo, Selene, StyLua, Lune), Rojo Studio plugin,
# Python packages (pytest, pillow, kaggle, bpy = Blender), then runs the four checks.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Step "Python"
# bpy (Blender as a Python module) only ships for specific Python versions - 3.13 is the safe one.
$has313 = $false
try { py -3.13 -c "pass" 2>$null; $has313 = ($LASTEXITCODE -eq 0) } catch {}
if (-not $has313) {
    Write-Host "Installing Python 3.13 (needed for Blender's bpy)..."
    try { py install 3.13 } catch {}
    try { py -3.13 -c "pass" 2>$null; $has313 = ($LASTEXITCODE -eq 0) } catch {}
    if (-not $has313) {
        winget install -e --id Python.Python.3.13 --accept-source-agreements --accept-package-agreements
    }
}
$py = "py -3.13"
Write-Host "Using: $py"

Step "Rokit"
$rokitBin = Join-Path $env:USERPROFILE ".rokit\bin"
if (-not (Get-Command rokit -ErrorAction SilentlyContinue) -and -not (Test-Path "$rokitBin\rokit.exe")) {
    Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
}
$env:PATH = "$rokitBin;$env:PATH"
rokit install

Step "Rojo Studio plugin"
rojo plugin install

Step "Python packages (bpy is ~400 MB, be patient)"
& ([scriptblock]::Create("$py -m pip install --upgrade pip pytest pillow kaggle"))
# Separate so a bpy failure can't block the other packages.
& ([scriptblock]::Create("$py -m pip install bpy"))
if ($LASTEXITCODE -ne 0) { Write-Host "bpy failed - install Blender from blender.org instead and tell Claude." -ForegroundColor Yellow }

Step "Four checks"
& powershell -ExecutionPolicy Bypass -File scripts\check.ps1

Write-Host "`nDone. Next: open Studio, run 'rojo serve' here, click Rojo > Connect. Then SETUP.md section 3 (MCP)." -ForegroundColor Green
