# The four gates, native PowerShell (same as scripts/check.sh). Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File scripts\check.ps1
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:PATH = "$env:USERPROFILE\.rokit\bin;$env:PATH"
New-Item -ItemType Directory -Force build | Out-Null

function Gate($label, [scriptblock]$cmd) {
    Write-Host $label -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $label" -ForegroundColor Red
        exit 1
    }
}

# Python 3.13 is the one with bpy (Blender). `py` isn't always visible (e.g. inside Claude Code's
# shell), so also look in the standard install folder before falling back to plain python.
$py313 = Join-Path $env:LOCALAPPDATA "Python\pythoncore-3.13-64\python.exe"
$py = "python"
$pyArgs = @()
if (Test-Path $py313) {
    $py = $py313
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $py = "py"
    $pyArgs = @("-3.13")
}
& $py @pyArgs -m pytest --version *> $null
if ($LASTEXITCODE -ne 0) { & $py @pyArgs -m pip install -q pytest pillow }

Gate "1/4 rojo build" { rojo build default.project.json -o build/game.rbxl | Out-Null }
Gate "2/4 tests (lune)" { lune run tests/run }
Gate "2/4 tests (python)" { & $py @pyArgs -m pytest -q tests/python }

Write-Host "3/4 selene" -ForegroundColor Cyan
if (-not (Test-Path roblox.yml)) { selene generate-roblox-std 2>$null | Out-Null }
if (Test-Path roblox.yml) {
    Gate "3/4 selene (roblox std)" { selene src }
} else {
    Write-Host "   (Roblox API dump unreachable - using roblox_offline std)"
    Gate "3/4 selene (offline std)" { selene --config selene.offline.toml src }
}

Gate "4/4 stylua" { stylua --check src tests }
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
