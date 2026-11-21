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
# Keep this file pure ASCII: it has no BOM, so Windows PowerShell 5.1 decodes
# it as Windows-1252 and a literal em dash breaks the enclosing string.
$dash = [char]0x2014
$payload = @{
    content = "The Commune $version $dash $Summary"
    allowed_mentions = @{parse = @()}
} | ConvertTo-Json -Compress
$uri = "${webhook}?thread_id=$threadId&wait=true"
try {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $message = Invoke-RestMethod -Method Post -Uri $uri -Form @{
            payload_json = $payload
            'files[0]' = $zip
        }
    } else {
        # Windows PowerShell 5.1 has no -Form, and pwsh is not installed on
        # every authorized workstation, so assemble the multipart body by hand.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $boundary = [Guid]::NewGuid().ToString()
        $LF = "`r`n"
        $encoding = [Text.Encoding]::UTF8
        $head = "--$boundary$LF" +
            "Content-Disposition: form-data; name=`"payload_json`"$LF" +
            "Content-Type: application/json$LF$LF" +
            "$payload$LF" +
            "--$boundary$LF" +
            "Content-Disposition: form-data; name=`"files[0]`"; filename=`"$($zip.Name)`"$LF" +
            "Content-Type: application/zip$LF$LF"
        $stream = New-Object IO.MemoryStream
        $headBytes = $encoding.GetBytes($head)
        $stream.Write($headBytes, 0, $headBytes.Length)
        $fileBytes = [IO.File]::ReadAllBytes($zip.FullName)
        $stream.Write($fileBytes, 0, $fileBytes.Length)
        $tailBytes = $encoding.GetBytes("$LF--$boundary--$LF")
        $stream.Write($tailBytes, 0, $tailBytes.Length)
        $message = Invoke-RestMethod -Method Post -Uri $uri -ContentType "multipart/form-data; boundary=$boundary" -Body $stream.ToArray()
        $stream.Dispose()
    }
} catch {
    $status = $_.Exception.Response.StatusCode
    throw "Discord upload failed (HTTP $status). Check the webhook and thread permissions."
}
if ($message.channel_id -ne $threadId -or -not $message.id) {
    throw 'Discord did not confirm the upload in Versions.'
}
Write-Output "https://discord.com/channels/1573065951283515482/$threadId/$($message.id)"
