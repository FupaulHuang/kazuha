#Requires -Version 5.1
[CmdletBinding()]
param([string]$Workspace = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
$Workspace = [IO.Path]::GetFullPath($Workspace)
$archiveName = 'composa-1.4.0-win-x64.zip'
$expected = '1d3d8d5f1af258d2d82541b62a3b5a14cacb638f74bb4ccf2049e874833eb162'
$downloadDirectory = Join-Path $Workspace 'downloads'
$archive = Join-Path $downloadDirectory $archiveName
$portableDirectory = Join-Path $Workspace 'dist\portable'
$appDirectory = Join-Path $portableDirectory 'composa-1.4.0-win-x64'

New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    $partial = "$archive.part"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/dvdstelt/Composa/releases/download/v1.4.0/$archiveName" -OutFile $partial
    if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $expected) {
        throw "Downloaded archive checksum differs from the published value. It remains at $partial for inspection and will not be extracted."
    }
    Move-Item -LiteralPath $partial -Destination $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) {
    throw 'Existing archive checksum differs from the published value. Refusing to extract it.'
}
if (Test-Path -LiteralPath $appDirectory) {
    Write-Host "Verified archive. Portable directory already exists; leaving it unchanged: $appDirectory"
    return
}
New-Item -ItemType Directory -Force -Path $portableDirectory | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $portableDirectory
if (-not (Test-Path -LiteralPath (Join-Path $appDirectory 'composa.exe'))) {
    throw 'Expected executable was absent after extraction.'
}
Write-Host "Portable app ready: $appDirectory\composa.exe"
