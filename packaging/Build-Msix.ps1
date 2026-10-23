#requires -Version 7.2
<#
.SYNOPSIS
Repackages the verified upstream Composa 1.4.0 Windows x64 portable release.
.DESCRIPTION
Creates a self-signed MSIX for local testing/personal use. No existing signing
credentials are needed. This script neither installs the app nor changes trust
stores, Developer Mode, execution policy, or other machine settings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PortableDirectory,

    [string] $OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\msix'),
    [string] $WorkDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\msix'),
    [string] $SourceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'source\Composa'),
    [string] $UpstreamArchivePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'downloads\composa-1.4.0-win-x64.zip'),

    [ValidatePattern('^1\.4\.0\.\d+$')]
    [string] $PackageVersion = '1.4.0.0',

    [string] $MakeAppxPath,
    [string] $SignToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$upstreamVersion = '1.4.0'
$expectedArchiveHash = '1d3d8d5f1af258d2d82541b62a3b5a14cacb638f74bb4ccf2049e874833eb162'
$upstreamUrl = 'https://github.com/dvdstelt/Composa/releases/tag/v1.4.0'
$packageName = 'Local.Composa.Windows'
$publisher = 'CN=Composa Local Build'
$displayName = 'Composa (local MSIX)'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-FullDirectoryPath([string] $Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Write-Utf8([string] $Path, [string] $Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Find-MakeAppx {
    $onPath = Get-Command 'makeappx.exe' -ErrorAction SilentlyContinue
    if ($null -ne $onPath) { return $onPath.Source }
    $sdkBase = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $sdkBase -PathType Container) {
        $versions = @(Get-ChildItem -LiteralPath $sdkBase -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending)
        foreach ($version in $versions) {
            $candidate = Join-Path $version.FullName 'x64\makeappx.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
        $candidate = Join-Path $sdkBase 'x64\makeappx.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'MakeAppx.exe was not found. Install the Windows SDK or supply -MakeAppxPath.'
}

function New-PackageLogo([System.Drawing.Image] $Image, [int] $Size, [string] $Path) {
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $scale = [Math]::Min($Size / [double]$Image.Width, $Size / [double]$Image.Height)
        $width = [Math]::Max(1, [int][Math]::Round($Image.Width * $scale))
        $height = [Math]::Max(1, [int][Math]::Round($Image.Height * $scale))
        $left = [int][Math]::Floor(($Size - $width) / 2)
        $top = [int][Math]::Floor(($Size - $height) / 2)
        $graphics.DrawImage($Image, $left, $top, $width, $height)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'This packaging script requires Windows.' }
if (-not [Environment]::Is64BitProcess) { throw 'Run this script in 64-bit PowerShell.' }
if (([version]$PackageVersion).Revision -gt 65535) { throw 'The package revision must be between 0 and 65535.' }

$portable = (Resolve-Path -LiteralPath $PortableDirectory).ProviderPath
if (-not (Test-Path -LiteralPath $portable -PathType Container)) { throw 'PortableDirectory must be a directory.' }
$portable = Get-FullDirectoryPath $portable
$source = Get-FullDirectoryPath ((Resolve-Path -LiteralPath $SourceDirectory).ProviderPath)
$output = Get-FullDirectoryPath $OutputDirectory
$work = Get-FullDirectoryPath $WorkDirectory
if ($output.Equals($portable, [StringComparison]::OrdinalIgnoreCase) -or
    $output.StartsWith($portable + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must not be inside PortableDirectory.'
}
if ($work.Equals($portable, [StringComparison]::OrdinalIgnoreCase) -or
    $work.StartsWith($portable + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'WorkDirectory must not be inside PortableDirectory.'
}
if ($work.Equals($output, [StringComparison]::OrdinalIgnoreCase) -or
    $work.StartsWith($output + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'WorkDirectory must be separate from OutputDirectory so temporary build files are not distributed.'
}

$executable = Join-Path $portable 'composa.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw 'PortableDirectory must contain composa.exe directly, not its parent directory.'
}
$links = @(Get-ChildItem -LiteralPath $portable -Recurse -Force |
    Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
if ($links.Count -ne 0) { throw 'The portable input contains reparse points. Use a fresh extraction of the verified upstream ZIP.' }

$archive = (Resolve-Path -LiteralPath $UpstreamArchivePath).ProviderPath
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($archiveHash -ne $expectedArchiveHash) {
    throw "Upstream ZIP checksum mismatch. Expected $expectedArchiveHash; received $archiveHash."
}

# Match every ZIP file to the extracted input; do not label unrelated binaries as
# the verified upstream release merely because the upstream archive is present.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $entries = @($zip.Entries | Where-Object { $_.Name.Length -gt 0 })
    $exeEntries = @($entries | Where-Object { $_.FullName -match '(^|/)composa\.exe$' })
    if ($exeEntries.Count -ne 1) { throw 'The upstream ZIP must contain exactly one composa.exe.' }
    $zipPrefix = $exeEntries[0].FullName.Substring(0, $exeEntries[0].FullName.Length - $exeEntries[0].Name.Length)
    $knownFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        if (-not $entry.FullName.StartsWith($zipPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "ZIP content falls outside the application folder: $($entry.FullName)"
        }
        $relative = $entry.FullName.Substring($zipPrefix.Length).Replace('/', '\')
        $filePath = [IO.Path]::GetFullPath((Join-Path $portable $relative))
        if (-not $filePath.StartsWith($portable + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe ZIP entry: $($entry.FullName)"
        }
        if (-not $knownFiles.Add($filePath)) { throw "Duplicate ZIP entry: $($entry.FullName)" }
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "Missing portable file: $relative" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $expected = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $stream.Dispose(); $sha.Dispose() }
        $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "Portable file differs from upstream ZIP: $relative" }
    }
    foreach ($file in Get-ChildItem -LiteralPath $portable -Recurse -File -Force) {
        if (-not $knownFiles.Contains($file.FullName)) { throw "Unexpected portable file: $($file.FullName). Use a fresh ZIP extraction." }
    }
}
finally { $zip.Dispose() }

if ([string]::IsNullOrWhiteSpace($MakeAppxPath)) { $MakeAppxPath = Find-MakeAppx }
$MakeAppxPath = (Resolve-Path -LiteralPath $MakeAppxPath).ProviderPath
if ([string]::IsNullOrWhiteSpace($SignToolPath)) {
    $SignToolPath = Join-Path (Split-Path $MakeAppxPath -Parent) 'signtool.exe'
}
$SignToolPath = (Resolve-Path -LiteralPath $SignToolPath).ProviderPath
$licensePath = Join-Path $source 'LICENSE'
$noticesPath = Join-Path $source 'packaging\THIRD-PARTY-NOTICES.txt'
foreach ($required in @($licensePath, $noticesPath, (Join-Path $PSScriptRoot 'Install-Msix.ps1'), (Join-Path $PSScriptRoot 'README.md'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required packaging input is missing: $required" }
}
$iconCandidates = @(
    (Join-Path $source 'packaging\icons\composa-1024.png'),
    (Join-Path $source 'packaging\icons\composa-512.png'),
    (Join-Path $source 'src\Composa.App\Assets\icon.png')
)
$iconPath = $iconCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($null -eq $iconPath) { throw 'No upstream Composa PNG icon was found.' }

$null = New-Item -ItemType Directory -Path $output -Force
$stage = Join-Path $work ('staging\' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
Get-ChildItem -LiteralPath $portable -Force | Copy-Item -Destination $stage -Recurse -Force

# Names are reserved for the packaging additions. Refuse to overwrite payload.
$assets = Join-Path $stage 'LocalMsixAssets'
$docs = Join-Path $stage 'LocalMsixDocumentation'
foreach ($addition in @($assets, $docs, (Join-Path $stage 'AppxManifest.xml'))) {
    if (Test-Path -LiteralPath $addition) { throw "Portable payload conflicts with a package addition: $addition" }
}
$null = New-Item -ItemType Directory -Path $assets
$null = New-Item -ItemType Directory -Path $docs
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $docs 'LICENSE.txt')
Copy-Item -LiteralPath $noticesPath -Destination (Join-Path $docs 'THIRD-PARTY-NOTICES.txt')
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Image]::FromFile($iconPath)
try {
    New-PackageLogo $icon 44 (Join-Path $assets 'Square44x44Logo.png')
    New-PackageLogo $icon 150 (Join-Path $assets 'Square150x150Logo.png')
    New-PackageLogo $icon 50 (Join-Path $assets 'StoreLogo.png')
}
finally { $icon.Dispose() }

$provenance = @"
Composa $upstreamVersion - local Windows MSIX repack

This MSIX is a local repack of the unmodified upstream portable Windows x64
release. It is not an official MSIX released or signed by the Composa authors.
The Composa executable, its bundled runtime, dependencies, and original notices
are retained. Added files are the MSIX manifest, package logos, and local package
documentation. No application source changes are included.

Upstream project: https://github.com/dvdstelt/Composa
Upstream release: $upstreamUrl
Upstream archive: composa-1.4.0-win-x64.zip
Upstream archive SHA-256: $archiveHash
Original inspiration: https://github.com/robbietilton/Compositor

Application version: $upstreamVersion
Local package version: $PackageVersion
Package identity: $packageName
Display name: $displayName
Publisher: $publisher
Architecture: x64
Minimum operating system: Windows 10 version 2004 (build 19041)
Package signature: locally generated self-signed development certificate
Built at (UTC): $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))

The app remains licensed by its upstream authors under the included LICENSE.
Bundled third-party software retains its licenses and notices.
This package is intended for local use/testing, not general public distribution
or Microsoft Store submission. The public certificate must be explicitly trusted
in LocalMachine\TrustedPeople before installation. The installer requests clear
confirmation. No certificate stores or system settings are changed during build.
The private signing key is used only in memory and a temporary PFX, which the
build removes after signing. The private key is never part of the bundle.
The app's upstream built-in updater does not produce this local MSIX; update the
local MSIX manually by rebuilding and installing a newer package revision.
"@
Write-Utf8 (Join-Path $docs 'PROVENANCE.txt') $provenance

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="$packageName" Publisher="$publisher" Version="$PackageVersion" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$displayName</DisplayName>
    <PublisherDisplayName>Local repack of Composa</PublisherDisplayName>
    <Description>Local self-signed MSIX repack of Composa $upstreamVersion.</Description>
    <Logo>LocalMsixAssets\StoreLogo.png</Logo>
  </Properties>
  <Resources><Resource Language="en-us" /></Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26200.0" />
  </Dependencies>
  <Applications>
    <Application Id="Composa" Executable="composa.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$displayName" Description="Composa image editor - local MSIX repack"
                          BackgroundColor="transparent"
                          Square150x150Logo="LocalMsixAssets\Square150x150Logo.png"
                          Square44x44Logo="LocalMsixAssets\Square44x44Logo.png" />
    </Application>
  </Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
"@
Write-Utf8 (Join-Path $stage 'AppxManifest.xml') $manifest

$packageFile = 'Composa-1.4.0-x64.msix'
$packagePath = Join-Path $output $packageFile
Write-Host 'Packing and validating the MSIX with the Windows SDK...'
# No /nv: MakeAppx must validate the manifest and package semantics.
& $MakeAppxPath pack /d $stage /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed with exit code $LASTEXITCODE. Staging retained at $stage" }
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'MakeAppx did not produce the expected package.' }

$certificateFile = 'Composa-Local-Build.cer'
$certificatePath = Join-Path $output $certificateFile
$signingDirectory = Join-Path $work ('signing\' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $signingDirectory
$privateKeyPath = [IO.Path]::GetFullPath((Join-Path $signingDirectory 'local-signing-key.pfx'))
$rsa = [Security.Cryptography.RSA]::Create(3072)
$certificate = $null
$password = $null
try {
    # CertificateRequest creates a certificate in memory only. Do not use
    # New-SelfSignedCertificate here: that would modify a certificate store.
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($publisher),
        $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
    $eku = [Security.Cryptography.OidCollection]::new()
    $null = $eku.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3', 'Code Signing'))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($eku, $false))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($request.PublicKey, $false))
    $now = [DateTimeOffset]::UtcNow
    $certificate = $request.CreateSelfSigned($now.AddMinutes(-5), $now.AddYears(3))
    $passwordBytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(48)
    $password = [Convert]::ToBase64String($passwordBytes)
    [Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
    # Only the public CER is distributed. The random PFX password is never
    # written to a file or logged; the temporary PFX is deleted in finally.
    [IO.File]::WriteAllBytes($certificatePath, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    $pfxBytes = $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password)
    try { [IO.File]::WriteAllBytes($privateKeyPath, $pfxBytes) }
    finally { [Array]::Clear($pfxBytes, 0, $pfxBytes.Length) }
    Write-Host 'Signing with the local development certificate (no trust-store changes)...'
    & $SignToolPath sign /fd SHA256 /f $privateKeyPath /p $password $packagePath
    if ($LASTEXITCODE -ne 0) { throw "SignTool failed with exit code $LASTEXITCODE." }
    $provenance += "`nCertificate SHA-1 thumbprint: $($certificate.Thumbprint)`nCertificate valid until (UTC): $($certificate.NotAfter.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))`n"
}
finally {
    # Delete this one known file only, after checking containment. Never pass
    # calculated paths to a recursive deletion and never distribute a PFX.
    $signingRoot = [IO.Path]::GetFullPath($signingDirectory).TrimEnd('\', '/')
    if (-not $privateKeyPath.StartsWith($signingRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($privateKeyPath) -ne 'local-signing-key.pfx') {
        throw 'Refusing private-key cleanup because the path is outside the signing directory.'
    }
    if (Test-Path -LiteralPath $privateKeyPath -PathType Leaf) { Remove-Item -LiteralPath $privateKeyPath -Force }
    $password = $null
    if ($null -ne $certificate) { $certificate.Dispose() }
    $rsa.Dispose()
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-Msix.ps1') -Destination (Join-Path $output 'Install-Msix.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $output 'README-Msix.md') -Force
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $output 'LICENSE.txt') -Force
Copy-Item -LiteralPath $noticesPath -Destination (Join-Path $output 'THIRD-PARTY-NOTICES.txt') -Force
Write-Utf8 (Join-Path $output 'PROVENANCE.txt') $provenance
$filesToHash = @($packageFile, $certificateFile, 'Install-Msix.ps1', 'README-Msix.md', 'LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', 'PROVENANCE.txt')
$checksumLines = foreach ($fileName in $filesToHash) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $output $fileName) -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $fileName"
}
Write-Utf8 (Join-Path $output 'sha256sums.txt') (($checksumLines -join "`n") + "`n")
Write-Host "Created: $packagePath"
Write-Host "SHA-256 manifest: $(Join-Path $output 'sha256sums.txt')"
Write-Host "Staging retained for inspection: $stage"
Write-Host 'No installation, certificate, or system-setting changes were performed.'
[pscustomobject]@{ Package = $packagePath; Checksums = (Join-Path $output 'sha256sums.txt'); Staging = $stage }
