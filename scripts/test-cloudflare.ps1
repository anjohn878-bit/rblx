# Tests the saved Cloudflare keys without ever showing them.
#   powershell -ExecutionPolicy Bypass -File scripts\test-cloudflare.ps1
# Makes one tiny image with Flux -> out\cloudflare-test.png
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
$account = [Environment]::GetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", "User")
$token = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN", "User")
if (-not $account -or -not $token) {
    Write-Host "Missing CLOUDFLARE_ACCOUNT_ID or CLOUDFLARE_API_TOKEN - run scripts\keys.ps1 first." -ForegroundColor Red
    exit 1
}
if ($account -notmatch "^[0-9a-f]{32}$") {
    Write-Host "CLOUDFLARE_ACCOUNT_ID doesn't look right (should be 32 letters/numbers like 0-9 a-f, got $($account.Length) chars)." -ForegroundColor Red
    Write-Host "You may have pasted the token into the Account ID box. Re-run scripts\keys.ps1." -ForegroundColor Yellow
    exit 1
}

$headers = @{ Authorization = "Bearer $token" }
$url = "https://api.cloudflare.com/client/v4/accounts/$account/ai/run/@cf/black-forest-labs/flux-1-schnell"
$body = @{ prompt = "a shiny gold coin game icon, white background"; steps = 4 } | ConvertTo-Json
try {
    $r = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType "application/json" -Body $body
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Write-Host "Cloudflare said: HTTP $code" -ForegroundColor Red
    switch ($code) {
        401 { Write-Host "Token rejected - it was mistyped, deleted, or not saved fully. Make a new token and re-run keys.ps1." -ForegroundColor Yellow }
        403 { Write-Host "Token works but lacks permission - create it from the 'Workers AI' template (Workers AI: Read + Edit)." -ForegroundColor Yellow }
        404 { Write-Host "Account ID not found - check CLOUDFLARE_ACCOUNT_ID matches the account the token belongs to." -ForegroundColor Yellow }
        default { Write-Host $_.ErrorDetails.Message }
    }
    exit 1
}
New-Item -ItemType Directory -Force out | Out-Null
[IO.File]::WriteAllBytes((Join-Path (Get-Location) "out\cloudflare-test.png"), [Convert]::FromBase64String($r.result.image))
Write-Host "Cloudflare works! Test image saved to out\cloudflare-test.png" -ForegroundColor Green
Start-Process (Join-Path (Get-Location) "out\cloudflare-test.png")
