param(
    [Parameter(Mandatory)]
    [string]$ZipPath,

    [Parameter(Mandatory)]
    [string]$Summary
)

$ErrorActionPreference = 'Stop'
$zip = Get-Item -LiteralPath $ZipPath
if ($zip.PSIsContainer -or $zip.Name -notmatch '^TheCommune-(\d+\.\d+\.\d+)\.zip$') {
    throw 'Provide a versioned TheCommune ZIP.'
}
$version = $Matches[1]
$secretPath = Join-Path (Split-Path -Parent $PSScriptRoot) '.local/discord-webhook.dpapi'
if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
    throw 'The local Discord webhook credential is missing.'
}
$secure = Get-Content -LiteralPath $secretPath -Raw | ConvertTo-SecureString
$webhook = [Net.NetworkCredential]::new('', $secure).Password
if ($webhook -notmatch '^https://discord\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$') {
    throw 'The stored credential is not a Discord webhook URL.'
}
$threadId = '1573664576703045703'
$payload = @{
    content = "The Commune $version — $Summary"
    allowed_mentions = @{parse = @()}
} | ConvertTo-Json -Compress
try {
    $message = Invoke-RestMethod -Method Post -Uri "${webhook}?thread_id=$threadId&wait=true" -Form @{
        payload_json = $payload
        'files[0]' = $zip
    }
} catch {
    $status = $_.Exception.Response.StatusCode
    throw "Discord upload failed (HTTP $status). Check the webhook and thread permissions."
}
if ($message.channel_id -ne $threadId -or -not $message.id) {
    throw 'Discord did not confirm the upload in Versions.'
}
Write-Output "https://discord.com/channels/1573065951283515482/$threadId/$($message.id)"
