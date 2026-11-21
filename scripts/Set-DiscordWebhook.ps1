<#
.SYNOPSIS
Stores this machine's Discord release webhook for Post-Version.ps1.

.DESCRIPTION
Prompts for the webhook URL and writes it to .local/discord-webhook.dpapi
encrypted with Windows DPAPI, which is scoped to the current user on the
current machine. The URL is never echoed, logged or written in clear text, and
.local/ is ignored by Git. Run this once per authorized workstation:

    powershell -ExecutionPolicy Bypass -File scripts\Set-DiscordWebhook.ps1

Paste the URL at the prompt in your own terminal. Do not pass it as an
argument: command lines land in shell history.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $root '.local'
$secretPath = Join-Path $localDir 'discord-webhook.dpapi'

if (Test-Path -LiteralPath $secretPath -PathType Leaf) {
    $answer = Read-Host 'A credential is already stored. Replace it? (y/N)'
    if ($answer -ne 'y') { Write-Output 'Kept the existing credential.'; return }
}

$secure = Read-Host -AsSecureString 'Discord webhook URL (input hidden)'
$plain = [Net.NetworkCredential]::new('', $secure).Password

# Discord hands out canary/ptb hosts, the legacy discordapp.com domain, and
# sometimes an explicit API version, so accept all of them.
$pattern = '^https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/(\d+)/([A-Za-z0-9_.-]+)$'
$trimmed = $plain.Trim()
if ($trimmed -notmatch $pattern) {
    # Describe the shape only. Never echo the value: it would land in the log.
    $length = $trimmed.Length
    $host_ = if ($trimmed -match '^https?://([^/]+)/') { $Matches[1] } else { '(no https://host/ prefix)' }
    $segments = if ($length -gt 0) { ($trimmed -split '/').Count } else { 0 }
    $odd = ($trimmed.ToCharArray() | Where-Object { $_ -notmatch '[A-Za-z0-9_./:-]' }).Count
    Write-Warning "Input did not match a webhook URL. Length: $length. Host: $host_. Slash-separated segments: $segments. Characters outside the expected set: $odd."
    if ($length -eq 0) {
        Write-Warning 'Nothing was captured. Some terminals ignore Ctrl+V at a hidden prompt - try right-click paste.'
    }
    throw 'That does not look like a Discord webhook URL. Nothing was written.'
}
if ($trimmed -ne $plain) { $secure = ConvertTo-SecureString -String $trimmed -AsPlainText -Force }
$plain = $null
$trimmed = $null

if (-not (Test-Path -LiteralPath $localDir -PathType Container)) {
    New-Item -ItemType Directory -Path $localDir | Out-Null
}
ConvertFrom-SecureString -SecureString $secure | Set-Content -LiteralPath $secretPath -Encoding utf8 -NoNewline

Write-Output "Stored DPAPI credential at .local/discord-webhook.dpapi for $env:USERNAME on $env:COMPUTERNAME."
Write-Output 'Only this Windows account on this machine can decrypt it.'
