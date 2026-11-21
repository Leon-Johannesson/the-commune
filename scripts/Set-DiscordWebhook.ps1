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

if ($plain -notmatch '^https://discord\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$') {
    # Never include the entered value in the error: it would land in the log.
    throw 'That does not look like a Discord webhook URL. Nothing was written.'
}
$plain = $null

if (-not (Test-Path -LiteralPath $localDir -PathType Container)) {
    New-Item -ItemType Directory -Path $localDir | Out-Null
}
ConvertFrom-SecureString -SecureString $secure | Set-Content -LiteralPath $secretPath -Encoding utf8 -NoNewline

Write-Output "Stored DPAPI credential at .local/discord-webhook.dpapi for $env:USERNAME on $env:COMPUTERNAME."
Write-Output 'Only this Windows account on this machine can decrypt it.'
