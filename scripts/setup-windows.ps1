# One-shot setup for Windows. Run from the repo folder in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
# Safe to re-run. Installs: Rokit (+ Rojo, Selene, StyLua, Lune), Rojo Studio plugin,
# Python packages (pytest, pillow, kaggle, bpy = Blender), then runs the four checks.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Step "Python"
$py = $null
foreach ($c in @("py -3.13", "py -3", "python")) {
    try { & ([scriptblock]::Create("$c -c `"import sys; sys.exit(sys.version_info < (3, 10))`"")); if ($LASTEXITCODE -eq 0) { $py = $c; break } } catch {}
}
if (-not $py) {
    Write-Host "Python 3.13 not found - installing with winget..."
    winget install -e --id Python.Python.3.13 --accept-source-agreements --accept-package-agreements
    $py = "py -3.13"
}
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
& ([scriptblock]::Create("$py -m pip install --upgrade pip pytest pillow kaggle bpy"))

Step "Four checks"
$bash = "C:\Program Files\Git\bin\bash.exe"
if (Test-Path $bash) {
    & $bash -lc "export PATH=`"`$HOME/.rokit/bin:`$PATH`"; scripts/check.sh"
} else {
    Write-Host "Git Bash not found - install Git (winget install Git.Git) and run scripts/check.sh in Git Bash." -ForegroundColor Yellow
}

Write-Host "`nDone. Next: open Studio, run 'rojo serve' here, click Rojo > Connect. Then SETUP.md section 3 (MCP)." -ForegroundColor Green
