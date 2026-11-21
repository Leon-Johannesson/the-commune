<#
.SYNOPSIS
Stores this machine's Discord release webhook for Post-Version.ps1.

.DESCRIPTION
Writes the webhook URL to .local/discord-webhook.dpapi encrypted with Windows
DPAPI, which is scoped to the current user on the current machine. The URL is
never echoed, logged or written in clear text, and .local/ is ignored by Git.

Copy the webhook URL, then run:

    powershell -ExecutionPolicy Bypass -File scripts\Set-DiscordWebhook.ps1 -FromClipboard

-FromClipboard avoids the hidden prompt entirely. Several terminals drop a
pasted value at a Read-Host -AsSecureString prompt, registering only the first
character. Use -FromFile for a URL saved in a text file; the file is deleted
afterwards. With no switch the script falls back to the hidden prompt.

Never pass the URL as an argument: command lines land in shell history.
#>
[CmdletBinding(DefaultParameterSetName = 'Prompt')]
param(
    [Parameter(ParameterSetName = 'Clipboard')]
    [switch]$FromClipboard,

    [Parameter(ParameterSetName = 'File', Mandatory)]
    [string]$FromFile
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $root '.local'
$secretPath = Join-Path $localDir 'discord-webhook.dpapi'

if (Test-Path -LiteralPath $secretPath -PathType Leaf) {
    $answer = Read-Host 'A credential is already stored. Replace it? (y/N)'
    if ($answer -ne 'y') { Write-Output 'Kept the existing credential.'; return }
}

$entered = $null
if ($FromClipboard) {
    if (-not (Get-Command Get-Clipboard -ErrorAction SilentlyContinue)) {
        throw 'Get-Clipboard is unavailable on this host. Use -FromFile instead.'
    }
    $entered = Get-Clipboard -Raw
    if ([string]::IsNullOrWhiteSpace($entered)) {
        throw 'The clipboard is empty. Copy the webhook URL first, then re-run.'
    }
    Write-Output 'Read the URL from the clipboard.'
} elseif ($FromFile) {
    if (-not (Test-Path -LiteralPath $FromFile -PathType Leaf)) { throw "No such file: $FromFile" }
    $entered = Get-Content -LiteralPath $FromFile -Raw
    Write-Output "Read the URL from $FromFile."
} else {
    $secureInput = Read-Host -AsSecureString 'Discord webhook URL (input hidden)'
    $entered = [Net.NetworkCredential]::new('', $secureInput).Password
}

# Discord hands out canary/ptb hosts, the legacy discordapp.com domain, and
# sometimes an explicit API version, so accept all of them.
$pattern = '^https://(?:canary\.|ptb\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\d+/[A-Za-z0-9_.-]+$'
$trimmed = "$entered".Trim()
$entered = $null

if ($trimmed -notmatch $pattern) {
    # Describe the shape only. Never echo the value: it would land in the log.
    $length = $trimmed.Length
    $hostName = if ($trimmed -match '^https?://([^/]+)/') { $Matches[1] } else { '(no https://host/ prefix)' }
    $segments = if ($length -gt 0) { ($trimmed -split '/').Count } else { 0 }
    $odd = ($trimmed.ToCharArray() | Where-Object { $_ -notmatch '[A-Za-z0-9_./:-]' }).Count
    Write-Warning "Input did not match a webhook URL. Length: $length. Host: $hostName. Slash-separated segments: $segments. Characters outside the expected set: $odd."
    if ($length -le 1) {
        Write-Warning 'Almost nothing was captured. Copy the URL and re-run with -FromClipboard.'
    }
    if ($trimmed -match '\?') {
        Write-Warning 'The URL carries a query string. Post-Version.ps1 appends its own, so remove everything from the "?" onward.'
    }
    $trimmed = $null
    throw 'That does not look like a Discord webhook URL. Nothing was written.'
}

if (-not (Test-Path -LiteralPath $localDir -PathType Container)) {
    New-Item -ItemType Directory -Path $localDir | Out-Null
}
$secure = ConvertTo-SecureString -String $trimmed -AsPlainText -Force
$trimmed = $null
ConvertFrom-SecureString -SecureString $secure | Set-Content -LiteralPath $secretPath -Encoding utf8 -NoNewline

if ($FromFile) {
    Remove-Item -LiteralPath $FromFile -Force
    Write-Output "Deleted $FromFile."
}

Write-Output "Stored DPAPI credential at .local/discord-webhook.dpapi for $env:USERNAME on $env:COMPUTERNAME."
Write-Output 'Only this Windows account on this machine can decrypt it.'
