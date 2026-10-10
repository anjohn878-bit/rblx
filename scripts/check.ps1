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

$py = "py"
$pyArgs = @("-3.13")
& $py @pyArgs -c "import pytest" 2>$null
if ($LASTEXITCODE -ne 0) { $py = "python"; $pyArgs = @() }

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
