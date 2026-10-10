# Store an API key as a Windows user environment variable without it showing on
# screen, in PowerShell history, or in any chat. Usage (from the repo folder):
#   powershell -ExecutionPolicy Bypass -File scripts\set-secret.ps1 ROBLOX_API_KEY
# Then restart PowerShell / Claude Code so they see it.
param([Parameter(Mandatory = $true)][string]$Name)

$secure = Read-Host "Paste the value for $Name (it stays hidden), then press Enter" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
if (-not $value) { Write-Host "Nothing entered - not saved." -ForegroundColor Yellow; exit 1 }
[Environment]::SetEnvironmentVariable($Name, $value, "User")
$shown = if ($value.Length -gt 8) { $value.Substring(0, 4) + "..." + $value.Substring($value.Length - 2) } else { "****" }
Write-Host "Saved $Name ($shown, $($value.Length) chars). Restart PowerShell/Claude Code to use it." -ForegroundColor Green
