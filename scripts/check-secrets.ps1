# Shows which keys are set (never their values).
$names = "ROBLOX_API_KEY", "ROBLOX_USER_ID", "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN"
foreach ($n in $names) {
    $v = [Environment]::GetEnvironmentVariable($n, "User")
    if ($v) { Write-Host "OK      $n" -ForegroundColor Green } else { Write-Host "MISSING $n" -ForegroundColor Yellow }
}
$kaggle = Join-Path $env:USERPROFILE ".kaggle\kaggle.json"
if (Test-Path $kaggle) { Write-Host "OK      kaggle.json" -ForegroundColor Green }
elseif ([Environment]::GetEnvironmentVariable("KAGGLE_KEY", "User")) { Write-Host "OK      KAGGLE_USERNAME/KAGGLE_KEY" -ForegroundColor Green }
else { Write-Host "MISSING kaggle.json (or KAGGLE_USERNAME + KAGGLE_KEY)" -ForegroundColor Yellow }
