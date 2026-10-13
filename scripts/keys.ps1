# Simplest way to set API keys: run this, then paste each key into the pop-up box (Ctrl+V).
#   powershell -ExecutionPolicy Bypass -File scripts\keys.ps1
# Leave a box empty and press Skip to keep what's already saved. Keys are hidden as you paste.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Ask($name, $hint) {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Save $name"
    $form.Size = New-Object Drawing.Size(520, 200)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"

    $label = New-Object Windows.Forms.Label
    $label.Text = "$hint`nPaste with Ctrl+V, then click Save. (Hidden as dots.)"
    $label.Location = New-Object Drawing.Point(12, 12)
    $label.Size = New-Object Drawing.Size(490, 50)
    $form.Controls.Add($label)

    $box = New-Object Windows.Forms.TextBox
    $box.UseSystemPasswordChar = $true
    $box.Location = New-Object Drawing.Point(12, 70)
    $box.Size = New-Object Drawing.Size(480, 24)
    $form.Controls.Add($box)

    $ok = New-Object Windows.Forms.Button
    $ok.Text = "Save"
    $ok.Location = New-Object Drawing.Point(316, 110)
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $skip = New-Object Windows.Forms.Button
    $skip.Text = "Skip"
    $skip.Location = New-Object Drawing.Point(410, 110)
    $skip.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($skip)
    $form.CancelButton = $skip

    $form.Add_Shown({ $box.Focus() })
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
    return $box.Text.Trim()
}

$keys = @(
    @("ROBLOX_API_KEY", "Roblox: create.roblox.com > Open Cloud > API Keys > your key > Copy"),
    @("ROBLOX_USER_ID", "Roblox: the number in your profile link roblox.com/users/NUMBER/profile"),
    @("CLOUDFLARE_ACCOUNT_ID", "Cloudflare: dashboard > Workers AI > Account ID"),
    @("CLOUDFLARE_API_TOKEN", "Cloudflare: My Profile > API Tokens > Workers AI token")
)

foreach ($k in $keys) {
    $name, $hint = $k
    $value = Ask $name $hint
    if (-not $value) { Write-Host "skipped  $name"; continue }
    $min = if ($name -match "_ID$") { 3 } else { 20 }
    if ($value.Length -lt $min -or $value -match "\s") {
        Write-Host "NOT saved $name - that doesn't look like a full key ($($value.Length) chars). Copy it again and re-run." -ForegroundColor Red
        continue
    }
    [Environment]::SetEnvironmentVariable($name, $value, "User")
    Write-Host "saved    $name ($($value.Length) characters)" -ForegroundColor Green
}

Write-Host ""
& (Join-Path $PSScriptRoot "check-secrets.ps1")
Write-Host "`nRestart PowerShell and Claude Code so they pick up the keys."
