# Store an API key as a Windows user environment variable without it showing on
# screen, in PowerShell history, or in any chat.
#
# Easiest: copy the key (Copy button on the website), then run:
#   powershell -ExecutionPolicy Bypass -File scripts\set-secret.ps1 ROBLOX_API_KEY -FromClipboard
# Or type/paste it into the hidden prompt (Ctrl+V) by leaving off -FromClipboard.
# Then restart PowerShell / Claude Code so they see it.
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$FromClipboard
)

if ($FromClipboard) {
    $value = (Get-Clipboard -Raw)
    if ($value) { $value = $value.Trim() }
    Set-Clipboard -Value " "  # don't leave the key sitting on the clipboard
} else {
    $secure = Read-Host "Paste the value for $Name with Ctrl+V (it stays hidden), then press Enter" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not $value) { Write-Host "Nothing found - not saved. Copy the key first." -ForegroundColor Yellow; exit 1 }
# Sanity: API keys/tokens are long; IDs are at least a few digits. A 1-char value means the paste failed.
$min = if ($Name -match "_ID$") { 3 } else { 20 }
if ($value.Length -lt $min) {
    Write-Host "Only $($value.Length) character(s) received - the paste didn't work. Not saved." -ForegroundColor Red
    Write-Host "Copy the key again and run this with -FromClipboard." -ForegroundColor Yellow
    exit 1
}
if ($value -match "\s") {
    Write-Host "The value contains spaces/new lines - you probably copied extra text. Not saved." -ForegroundColor Red
    exit 1
}

[Environment]::SetEnvironmentVariable($Name, $value, "User")
Write-Host "Saved $Name ($($value.Length) characters). Restart PowerShell/Claude Code to use it." -ForegroundColor Green
