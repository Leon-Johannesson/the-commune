# Builds TheCommune-<version>.zip with TheCommune/ at the archive root.
#
# Compress-Archive writes backslash entry names, which is off-spec and can
# break strict extractors, so this builds the archive entry by entry with
# forward slashes. Keep this file pure ASCII: Windows PowerShell 5.1 reads a
# BOM-less file as Windows-1252 and a stray byte can terminate a string.
#
#   powershell -ExecutionPolicy Bypass -File scripts\New-Package.ps1
#
# Pass -Suffix forever to build TheCommune-<version>-forever.zip, the name
# WowUp uses to match a non-Retail game flavour.

[CmdletBinding()]
param(
    [string] $Suffix = "",
    [string] $OutDir = ""
)

$ErrorActionPreference = "Stop"

$repo   = Split-Path -Parent $PSScriptRoot
$addon  = Join-Path $repo "TheCommune"
$tocPath = Join-Path $addon "TheCommune.toc"

if (-not (Test-Path $tocPath)) { throw "Cannot find $tocPath" }

$versionLine = Select-String -Path $tocPath -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
if ($null -eq $versionLine) { throw "No '## Version:' line in $tocPath" }
$version = $versionLine.Matches[0].Groups[1].Value.Trim()

# Refuse to package a half-bumped release: the toc and Core.lua must agree.
$coreLine = Select-String -Path (Join-Path $addon "Core.lua") -Pattern 'TC\.version\s*=\s*"([^"]+)"' | Select-Object -First 1
if ($null -eq $coreLine) { throw "No TC.version in Core.lua" }
$coreVersion = $coreLine.Matches[0].Groups[1].Value
if ($coreVersion -ne $version) {
    throw "Version mismatch: TheCommune.toc says $version, Core.lua says $coreVersion"
}

$name = "TheCommune-$version"
if ($Suffix -ne "") { $name = "$name-$Suffix" }
if ($OutDir -eq "") { $OutDir = $repo }
$zipPath = Join-Path $OutDir "$name.zip"

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$stream  = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
$count   = 0

try {
    $files = Get-ChildItem -Path $addon -Recurse -File |
        Where-Object { $_.Extension -notin @(".zip", ".bak", ".log") } |
        Sort-Object FullName
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($addon.Length).TrimStart("\", "/")
        $entryName = "TheCommune/" + ($relative -replace "\\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $count++
    }
}
finally {
    $archive.Dispose()
    $stream.Dispose()
}

Write-Output "Packaged $count files into $zipPath"
Write-Output "Version: $version"
