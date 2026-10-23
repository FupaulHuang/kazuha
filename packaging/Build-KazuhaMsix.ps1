#requires -Version 7.2
<#
.SYNOPSIS
Builds a self-signed Kazuha MSIX from the verified branded managed source build.
.DESCRIPTION
Validates pinned source, branding provenance, every payload file and assembly
metadata. Creates a non-CA development signing certificate in memory, distributes
only its public CER, and removes the temporary PFX after signing. Never installs
software, imports certificates, or changes machine settings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PortableDirectory,
    [string] $OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\kazuha-msix'),
    [string] $WorkDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\kazuha-msix'),
    [string] $SourceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'source\Composa'),
    [string] $BuildProvenancePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\store-managed\build-provenance.json'),
    [string] $LogoPath = (Join-Path $PSScriptRoot 'assets\kazuha-icon.png'),
    [ValidatePattern('^1\.4\.0\.\d+$')]
    [string] $PackageVersion = '1.4.0.0',
    [string] $MakeAppxPath,
    [string] $SignToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$IdentityName = 'Local.Kazuha.Windows'
$Publisher = 'CN=Kazuha Local Build'
$PublisherDisplayName = 'Kazuha community build'
$DisplayName = 'Kazuha'
if (([version]$PackageVersion).Revision -gt 65535) { throw 'The package revision must be between 0 and 65535.' }
$expectedSourceCommit = '86529d3b5355d28ddc28ec3db2e4de1d4d00f63b'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-FullDirectoryPath([string] $Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}
function Write-Utf8([string] $Path, [string] $Text) {
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Test-Within([string] $Candidate, [string] $Parent) {
    return $Candidate.Equals($Parent, [StringComparison]::OrdinalIgnoreCase) -or
        $Candidate.StartsWith($Parent + '\', [StringComparison]::OrdinalIgnoreCase)
}
function ConvertTo-XmlValue([string] $Value) {
    # Reject XML control characters; escape data rather than evaluating it as XML/code.
    $null = [Xml.XmlConvert]::VerifyXmlChars($Value)
    return [Security.SecurityElement]::Escape($Value)
}
function Read-AssemblyBuildMetadata([string] $Path) {
    # PE metadata inspection only: do not load or execute application code.
    if (-not ('KazuhaSideloadMetadata' -as [type])) {
        Add-Type -ReferencedAssemblies @(
            [Reflection.Metadata.MetadataReader].Assembly.Location,
            [Collections.Immutable.ImmutableArray].Assembly.Location,
            (Join-Path $PSHOME 'ref\System.Collections.dll')
        ) -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
public static class KazuhaSideloadMetadata {
    public static Dictionary<string, string> Read(string path) {
        using (var stream = File.OpenRead(path))
        using (var pe = new PEReader(stream)) {
            var reader = pe.GetMetadataReader();
            var assembly = reader.GetAssemblyDefinition();
            var values = new Dictionary<string, string>(StringComparer.Ordinal);
            values.Add("AssemblyName", reader.GetString(assembly.Name));
            values.Add("AssemblyVersion", assembly.Version.ToString());
            foreach (var handle in assembly.GetCustomAttributes()) {
                var attribute = reader.GetCustomAttribute(handle);
                if (attribute.Constructor.Kind != HandleKind.MemberReference) continue;
                var ctor = reader.GetMemberReference((MemberReferenceHandle)attribute.Constructor);
                if (ctor.Parent.Kind != HandleKind.TypeReference) continue;
                var type = reader.GetTypeReference((TypeReferenceHandle)ctor.Parent);
                var name = reader.GetString(type.Namespace) + "." + reader.GetString(type.Name);
                var blob = reader.GetBlobReader(attribute.Value);
                if (name == "System.Reflection.AssemblyMetadataAttribute") {
                    if (blob.ReadUInt16() != 1) throw new InvalidDataException("Invalid metadata prolog.");
                    values.Add(blob.ReadSerializedString(), blob.ReadSerializedString());
                } else if (name == "System.Reflection.AssemblyInformationalVersionAttribute") {
                    if (blob.ReadUInt16() != 1) throw new InvalidDataException("Invalid version prolog.");
                    values.Add("InformationalVersion", blob.ReadSerializedString());
                } else if (name == "System.Runtime.Versioning.TargetFrameworkAttribute") {
                    if (blob.ReadUInt16() != 1) throw new InvalidDataException("Invalid target framework prolog.");
                    values.Add("TargetFramework", blob.ReadSerializedString());
                } else if (name == "System.Reflection.AssemblyProductAttribute") {
                    if (blob.ReadUInt16() != 1) throw new InvalidDataException("Invalid product prolog.");
                    values.Add("Product", blob.ReadSerializedString());
                } else if (name == "System.Reflection.AssemblyTitleAttribute") {
                    if (blob.ReadUInt16() != 1) throw new InvalidDataException("Invalid title prolog.");
                    values.Add("Title", blob.ReadSerializedString());
                }
            }
            foreach (var handle in reader.TypeDefinitions) {
                var type = reader.GetTypeDefinition(handle);
                if (reader.GetString(type.Namespace) != "Composa.App" || reader.GetString(type.Name) != "AppInfo") continue;
                foreach (var fieldHandle in type.GetFields()) {
                    var field = reader.GetFieldDefinition(fieldHandle);
                    if (reader.GetString(field.Name) != "Name") continue;
                    var constant = reader.GetConstant(field.GetDefaultValue());
                    if (constant.TypeCode != ConstantTypeCode.String) throw new InvalidDataException("Invalid display name constant.");
                    var blob = reader.GetBlobReader(constant.Value);
                    values.Add("AppDisplayName", blob.ReadUTF16(blob.Length));
                }
            }
            return values;
        }
    }
}
'@
    }
    return [KazuhaSideloadMetadata]::Read($Path)
}
function Find-MakeAppx {
    $command = Get-Command 'makeappx.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $sdkRoot -PathType Container) {
        $versions = @(Get-ChildItem -LiteralPath $sdkRoot -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending)
        foreach ($version in $versions) {
            $candidate = Join-Path $version.FullName 'x64\makeappx.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
        $candidate = Join-Path $sdkRoot 'x64\makeappx.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'MakeAppx.exe was not found. Supply -MakeAppxPath or install the Windows SDK.'
}
function New-PackageLogo([Drawing.Image] $Image, [int] $Size, [string] $Path) {
    $bitmap = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $scale = [Math]::Min($Size / [double]$Image.Width, $Size / [double]$Image.Height)
        $width = [Math]::Max(1, [int][Math]::Round($Image.Width * $scale))
        $height = [Math]::Max(1, [int][Math]::Round($Image.Height * $scale))
        $graphics.DrawImage($Image, [int][Math]::Floor(($Size - $width) / 2), [int][Math]::Floor(($Size - $height) / 2), $width, $height)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}

if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
    throw 'Use 64-bit PowerShell on Windows.'
}
$portable = Get-FullDirectoryPath ((Resolve-Path -LiteralPath $PortableDirectory).ProviderPath)
$source = Get-FullDirectoryPath ((Resolve-Path -LiteralPath $SourceDirectory).ProviderPath)
$buildRecordPath = (Resolve-Path -LiteralPath $BuildProvenancePath).ProviderPath
$output = Get-FullDirectoryPath $OutputDirectory
$work = Get-FullDirectoryPath $WorkDirectory
foreach ($root in @($portable, $source)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Not an input directory: $root" }
    if ((Test-Within $output $root) -or (Test-Within $work $root)) {
        throw 'OutputDirectory and WorkDirectory must be outside the portable and source input directories.'
    }
}
if ((Test-Within $work $output) -or (Test-Within $output $work)) {
    throw 'WorkDirectory and OutputDirectory must not overlap.'
}
if (-not (Test-Path -LiteralPath (Join-Path $portable 'composa.exe') -PathType Leaf)) {
    throw 'PortableDirectory must directly contain composa.exe.'
}
$links = @(Get-Item -LiteralPath $portable; Get-ChildItem -LiteralPath $portable -Recurse -Force) |
    Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }
if (@($links).Count -ne 0) { throw 'Application input contains a reparse point; use a fresh managed source build.' }

# These records describe our build, not upstream release binary equivalence.
# Bind both the source revision and every published byte to the build record.
$buildRecordHash = (Get-FileHash -LiteralPath $buildRecordPath -Algorithm SHA256).Hash.ToLowerInvariant()
$buildRecord = Get-Content -LiteralPath $buildRecordPath -Raw | ConvertFrom-Json
if ($buildRecord.schemaVersion -ne 1 -or
    $buildRecord.sourceRepository -cne 'https://github.com/dvdstelt/Composa' -or
    $buildRecord.sourceCommit -cne $expectedSourceCommit -or
    $buildRecord.sourceDirty -isnot [bool] -or -not $buildRecord.sourceDirty -or
    $buildRecord.upstreamSourceDirty -isnot [bool] -or $buildRecord.upstreamSourceDirty -or
    $buildRecord.sourceTag -cne 'v1.4.0' -or
    $buildRecord.configuration -cne 'Release' -or
    $buildRecord.runtimeIdentifier -cne 'win-x64' -or
    $buildRecord.selfContained -isnot [bool] -or -not $buildRecord.selfContained -or
    $buildRecord.updateChannel -cne 'managed' -or $buildRecord.debugType -cne 'none' -or
    $buildRecord.sdkVersion -notmatch '^10\.\d+\.\d+$') {
    throw 'Build provenance must describe the pinned v1.4.0 managed build with recorded Kazuha branding and a clean upstream checkout.'
}
$sourceHead = & git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $sourceHead -cne $expectedSourceCommit) { throw 'Source checkout is not the pinned Composa revision.' }
$sourceTag = & git -C $source rev-parse 'v1.4.0^{commit}'
if ($LASTEXITCODE -ne 0 -or $sourceTag -cne $expectedSourceCommit) { throw 'The source v1.4.0 tag does not resolve to the pinned revision.' }
$sourceChanges = & git -C $source status --porcelain --untracked-files=no
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace(($sourceChanges -join "`n"))) {
    throw 'Source has tracked modifications; rebuild from the clean pinned checkout.'
}
$iconPath = (Resolve-Path -LiteralPath $LogoPath).ProviderPath
$iconHash = (Get-FileHash -LiteralPath $iconPath -Algorithm SHA256).Hash.ToLowerInvariant()
$branding = $buildRecord.brandingRecord
$brandingSource = (Resolve-Path -LiteralPath $buildRecord.buildSourceDirectory).ProviderPath
if ($branding.name -cne 'Kazuha' -or $branding.schemaVersion -ne 1 -or
    $branding.sourceCommit -cne $expectedSourceCommit -or
    $branding.logoSha256 -cne $iconHash -or $branding.sourceDirectory -cne $brandingSource -or
    $branding.preparationScriptSha256 -cne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Prepare-KazuhaSource.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()) {
    throw 'Kazuha branding record does not match the preparation script, final logo or pinned source.'
}
if ((Get-FileHash -LiteralPath ($brandingSource + '.branding.json') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $buildRecord.brandingRecordSha256) {
    throw 'Branding provenance changed since the source build.'
}
if ((& git -C $brandingSource rev-parse HEAD) -cne $expectedSourceCommit -or $LASTEXITCODE -ne 0) { throw 'Branded copy has the wrong base revision.' }
$allowedBrandingFiles = @(
    'Directory.Build.props', 'packaging/icons/composa-1024.png', 'packaging/icons/composa-512.png',
    'packaging/icons/composa.ico', 'src/Composa.App/AppInfo.cs', 'src/Composa.App/Assets/icon.png',
    'src/Composa.App/MainWindow.Commands.cs', 'src/Composa.App/MainWindow.cs',
    'src/Composa.App/MainWindow.Updates.cs', 'src/Composa.App/UpdateNotice.cs',
    'tests/Composa.App.Tests/AppPathsTests.cs', 'tests/Composa.App.Tests/UpdateNoticeTests.cs'
) | Sort-Object
$actualBrandingFiles = @(& git -C $brandingSource diff --name-only --no-ext-diff HEAD) | Sort-Object
if ($LASTEXITCODE -ne 0 -or ($actualBrandingFiles -join "`n") -cne ($allowedBrandingFiles -join "`n") -or
    (@($branding.changedFiles.path | Sort-Object) -join "`n") -cne ($allowedBrandingFiles -join "`n")) {
    throw 'The branded source differs outside the expected display strings, metadata, icons or associated test expectations.'
}
foreach ($file in $branding.changedFiles) {
    if ((Get-FileHash -LiteralPath (Join-Path $brandingSource $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256 -or
        (Get-FileHash -LiteralPath (Join-Path $source $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.baseSha256) {
        throw "Branded source/base file changed: $($file.path)"
    }
}
$sourceDiff = ((@(& git -C $brandingSource diff --binary --no-ext-diff HEAD) -join "`n") + "`n")
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the source branding delta.' }
$sourceDiffHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($sourceDiff))).ToLowerInvariant()
if ($sourceDiffHash -cne $branding.sourceDiffSha256 -or $sourceDiffHash -cne $buildRecord.sourceDiffSha256) {
    throw 'Source branding delta changed after preparation/build.'
}
$knownFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $buildRecord.files) {
    $relative = [string]$entry.path
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^[\\/]|:|\\|(^|/)\.\.?(\/|$))' -or
        $entry.sha256 -notmatch '^[a-f0-9]{64}$' -or $entry.bytes -lt 0) {
        throw "Invalid file record in build provenance: $relative"
    }
    $filePath = [IO.Path]::GetFullPath((Join-Path $portable $relative.Replace('/', '\')))
    if (-not $filePath.StartsWith($portable + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe payload path: $relative" }
    if (-not $knownFiles.Add($filePath)) { throw "Duplicate payload path: $relative" }
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "Missing application file: $relative" }
    if ((Get-Item -LiteralPath $filePath).Length -ne $entry.bytes -or
        (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
        throw "Application file differs from source build record: $relative"
    }
}
if ($knownFiles.Count -eq 0) { throw 'Build provenance contains no files.' }
foreach ($file in Get-ChildItem -LiteralPath $portable -Recurse -File -Force) {
    if (-not $knownFiles.Contains($file.FullName)) { throw "Unexpected application file: $($file.FullName)" }
}
$verifiedFileCount = $knownFiles.Count
$assemblyMetadata = Read-AssemblyBuildMetadata (Join-Path $portable 'composa.dll')
if ($assemblyMetadata['AssemblyName'] -cne 'composa' -or
    $assemblyMetadata['InformationalVersion'] -cne "1.4.0+$expectedSourceCommit" -or
    $assemblyMetadata['TargetFramework'] -cne '.NETCoreApp,Version=v10.0' -or
    $assemblyMetadata['UpdateChannel'] -cne 'managed' -or
    $assemblyMetadata['RuntimeIdentifier'] -cne 'win-x64' -or
    $assemblyMetadata['Product'] -cne 'Kazuha' -or $assemblyMetadata['Title'] -cne 'Kazuha' -or
    $assemblyMetadata['AppDisplayName'] -cne 'Kazuha') {
    throw 'Application assembly must report Kazuha, pinned Composa 1.4.0, .NET 10, UpdateChannel=managed and RuntimeIdentifier=win-x64.'
}
$runtimeConfig = Get-Content -LiteralPath (Join-Path $portable 'composa.runtimeconfig.json') -Raw | ConvertFrom-Json
if ($null -eq $runtimeConfig.runtimeOptions.PSObject.Properties['includedFrameworks'] -or
    @($runtimeConfig.runtimeOptions.includedFrameworks | Where-Object { $_.name -eq 'Microsoft.NETCore.App' -and $_.version -match '^10\.' }).Count -ne 1) {
    throw 'The application must include a self-contained .NET 10 runtime.'
}
foreach ($required in @('hostfxr.dll', 'hostpolicy.dll', 'coreclr.dll', 'ImageMagick-NOTICE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $portable $required) -PathType Leaf)) { throw "Required runtime/notice file missing: $required" }
}
$models = @{
    'u2netp.onnx' = '309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8'
    'modnet.onnx' = '07c308cf0fc7e6e8b2065a12ed7fc07e1de8febb7dc7839d7b7f15dd66584df9'
    'realesr-general-x4v3.onnx' = '09b757accd747d7e423c1d352b3e8f23e77cc5742d04bae958d4eb8082b76fa4'
}
foreach ($model in $models.GetEnumerator()) {
    $modelPath = Join-Path $portable ('models\' + $model.Key)
    if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $model.Value) {
        throw "Required bundled model is missing or changed: $($model.Key)"
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem

$licensePath = Join-Path $source 'LICENSE'
$noticesPath = Join-Path $source 'packaging\THIRD-PARTY-NOTICES.txt'
foreach ($pair in @(@($licensePath, (Join-Path $portable 'LICENSE')), @($noticesPath, (Join-Path $portable 'THIRD-PARTY-NOTICES.txt')))) {
    foreach ($file in $pair) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required notice missing: $file" }
    }
    # Source checkouts may use CRLF. Compare notice text with newline normalization.
    if ([IO.File]::ReadAllText($pair[0]).Replace("`r`n", "`n") -cne [IO.File]::ReadAllText($pair[1]).Replace("`r`n", "`n")) {
        throw "Application notice differs from the pinned source: $($pair[0])"
    }
}
if ([string]::IsNullOrWhiteSpace($MakeAppxPath)) { $MakeAppxPath = Find-MakeAppx }
$MakeAppxPath = (Resolve-Path -LiteralPath $MakeAppxPath).ProviderPath
if ([string]::IsNullOrWhiteSpace($SignToolPath)) { $SignToolPath = Join-Path (Split-Path $MakeAppxPath -Parent) 'signtool.exe' }
$SignToolPath = (Resolve-Path -LiteralPath $SignToolPath).ProviderPath
foreach ($required in @('Install-Kazuha.ps1', 'README-Kazuha.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $required) -PathType Leaf)) { throw "Required bundle input missing: $required" }
}

$null = New-Item -ItemType Directory -Path $output -Force
$stage = Join-Path $work ('staging\' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
Get-ChildItem -LiteralPath $portable -Force | Copy-Item -Destination $stage -Recurse -Force
$assets = Join-Path $stage 'KazuhaAssets'
$docs = Join-Path $stage 'KazuhaDocumentation'
foreach ($addition in @($assets, $docs, (Join-Path $stage 'AppxManifest.xml'), (Join-Path $stage 'AppxSignature.p7x'))) {
    if (Test-Path -LiteralPath $addition) { throw "Unexpected preexisting packaging content: $addition" }
}
$null = New-Item -ItemType Directory -Path $assets
$null = New-Item -ItemType Directory -Path $docs
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $docs 'LICENSE.txt')
Copy-Item -LiteralPath $noticesPath -Destination (Join-Path $docs 'THIRD-PARTY-NOTICES.txt')
Add-Type -AssemblyName System.Drawing
$icon = [Drawing.Image]::FromFile($iconPath)
try {
    New-PackageLogo $icon 44 (Join-Path $assets 'Square44x44Logo.png')
    New-PackageLogo $icon 150 (Join-Path $assets 'Square150x150Logo.png')
    New-PackageLogo $icon 50 (Join-Path $assets 'StoreLogo.png')
    New-PackageLogo $icon 300 (Join-Path $assets 'AppTile300.png')
}
finally { $icon.Dispose() }

$builtAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$provenance = @"
Kazuha 1.4.0 - independent Windows edition of Composa

Kazuha is based on Composa by Dennis van der Stelt, Copyright (c) 2026.
Composa reimplements the macOS Compositor editor by Robbie Tilton / Wonder
Assembly LLC. Portions of image-processing math follow that MIT-licensed work.
Original Compositor: https://github.com/robbietilton/Compositor
Composa source: https://github.com/dvdstelt/Composa
Composa release: https://github.com/dvdstelt/Composa/releases/tag/v1.4.0
Kazuha source and build helpers: https://github.com/FupaulHuang/kazuha
This package is independently prepared; it does not claim upstream endorsement.

The application is built from pinned Composa source with recorded Kazuha
display-name, product-metadata and icon changes, plus its existing
UpdateChannel=managed setting. Install updates manually from the Kazuha GitHub releases; automatic upstream GitHub update downloads are disabled.
The build includes the .NET runtime, image codecs, all three original on-device
models, and license notices. Added files are the sideload manifest, package image
assets, attribution documentation and source-build provenance.
Application license: MIT. Third-party components retain their respective terms.

Source commit: $expectedSourceCommit
Source tag: v1.4.0
Upstream checkout tracked modifications: none
Build-copy modifications: recorded Kazuha branding delta
Branding delta SHA-256: $sourceDiffHash
Branding preparation script SHA-256: $($branding.preparationScriptSha256)
Kazuha logo SHA-256: $iconHash
Build configuration: Release; win-x64; self-contained; DebugType=none
Update channel: managed
.NET SDK: $($buildRecord.sdkVersion)
Build provenance record SHA-256: $buildRecordHash
Verified application file count: $verifiedFileCount
Package identity: $IdentityName
Publisher identity: $Publisher
Publisher display name: $PublisherDisplayName
Product display name: $DisplayName
Package version: $packageVersion
Architecture: x64
Minimum OS: Windows 10 version 2004 (10.0.19041.0)
Built at UTC: $builtAt

This community download is signed with a self-signed development certificate.
It is not a Microsoft Store package or a publicly verified publisher identity.
The public certificate must be explicitly trusted in LocalMachine\TrustedPeople
before installation. The bundled installer asks for explicit confirmation.
Building never installs the app or changes any certificate store or system setting.
The private key exists only in memory and a temporary random-password PFX that
is deleted after signing. No private key is included in this bundle or retained.
No timestamp service is used. A rebuild generates a new certificate that may
need to be trusted; package updates must use a higher four-part version.

The existing managed build option disables automatic GitHub update checks and
release downloads; manual checks explain that the package manager owns updates.
No claim is made that this source build is byte-identical to the GitHub binary.
"@
Write-Utf8 (Join-Path $docs 'PROVENANCE.txt') $provenance
$packageBuildRecord = [ordered]@{
    schemaVersion = 1; sourceRepository = $buildRecord.sourceRepository
    sourceCommit = $expectedSourceCommit; sourceTag = 'v1.4.0'; sourceDirty = $true; upstreamSourceDirty = $false
    sdkVersion = $buildRecord.sdkVersion; configuration = 'Release'; runtimeIdentifier = 'win-x64'
    selfContained = $true; updateChannel = 'managed'; debugType = 'none'
    builtAtUtc = $buildRecord.builtAtUtc; files = $buildRecord.files
    branding = [ordered]@{
        name = 'Kazuha'; preparationScriptSha256 = $branding.preparationScriptSha256
        logoSha256 = $iconHash; sourceDiffSha256 = $sourceDiffHash; changedFiles = $branding.changedFiles
    }
}
Write-Utf8 (Join-Path $docs 'SOURCE-BUILD.json') ($packageBuildRecord | ConvertTo-Json -Depth 6)

$xmlIdentity = ConvertTo-XmlValue $IdentityName
$xmlPublisher = ConvertTo-XmlValue $Publisher
$xmlPublisherDisplay = ConvertTo-XmlValue $PublisherDisplayName
$xmlDisplay = ConvertTo-XmlValue $DisplayName
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="$xmlIdentity" Publisher="$xmlPublisher" Version="$packageVersion" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>$xmlDisplay</DisplayName>
    <PublisherDisplayName>$xmlPublisherDisplay</PublisherDisplayName>
    <Description>Layer-based image editing and compositing with Kazuha.</Description>
    <Logo>KazuhaAssets\StoreLogo.png</Logo>
  </Properties>
  <Resources><Resource Language="en-us" /></Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26200.0" />
  </Dependencies>
  <Applications>
    <Application Id="Kazuha" Executable="composa.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$xmlDisplay" Description="Layer-based image editor"
                          BackgroundColor="transparent"
                          Square150x150Logo="KazuhaAssets\Square150x150Logo.png"
                          Square44x44Logo="KazuhaAssets\Square44x44Logo.png" />
    </Application>
  </Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
"@
$manifestPath = Join-Path $stage 'AppxManifest.xml'
Write-Utf8 $manifestPath $manifest
$packageBase = 'Kazuha-1.4.0-x64'
$packageFile = $packageBase + '.msix'
$packagePath = Join-Path $output ($packageBase + '.msix')
Write-Host "Verified $verifiedFileCount managed source-build files. Packing Kazuha sideload MSIX..."
# MakeAppx manifest and semantic validation stays enabled; signing follows byte verification.
& $MakeAppxPath pack /d $stage /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed ($LASTEXITCODE). Stage retained: $stage" }
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'MakeAppx did not produce a package.' }

# Verify the actual archive, not only the manifest written before packaging.
$packed = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    if ($null -ne $packed.GetEntry('AppxSignature.p7x')) { throw 'The fresh package unexpectedly already contains a signature.' }
    foreach ($entry in $packed.Entries) {
        if ($entry.FullName -match '(^|/)(LocalMsixDocumentation|LocalMsixAssets)(/|$)|\.(pfx|p12|cer)$|(^|/)(Install-Msix|Trust-LocalCertificate)\.ps1$') {
            throw "Unexpected signing/install artifact inside the application payload: $($entry.FullName)"
        }
    }
    foreach ($file in $buildRecord.files) {
        $payloadEntry = $packed.GetEntry($file.path)
        if ($null -eq $payloadEntry) { throw "Application file missing from package: $($file.path)" }
        $stream = $payloadEntry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $packedHash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
        finally { $stream.Dispose(); $sha.Dispose() }
        if ($packedHash -cne $file.sha256 -or $payloadEntry.Length -ne $file.bytes) {
            throw "Packaged application file differs from the verified build: $($file.path)"
        }
    }
    $entry = $packed.GetEntry('AppxManifest.xml')
    if ($null -eq $entry) { throw 'Packaged manifest is missing.' }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { [xml]$actualManifest = $reader.ReadToEnd() }
    finally { $reader.Dispose() }
    if ($actualManifest.Package.Identity.Name -cne $IdentityName -or
        $actualManifest.Package.Identity.Publisher -cne $Publisher -or
        $actualManifest.Package.Properties.PublisherDisplayName -cne $PublisherDisplayName -or
        $actualManifest.Package.Properties.DisplayName -cne $DisplayName -or
        $actualManifest.Package.Identity.Version -cne $packageVersion) {
        throw 'Packaged identity does not exactly match the Kazuha sideload identity.'
    }
}
finally { $packed.Dispose() }

$certificateFile = 'Kazuha-Local-Build.cer'
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

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-Kazuha.ps1') -Destination (Join-Path $output 'Install-Kazuha.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README-Kazuha.md') -Destination (Join-Path $output 'README-Kazuha.md') -Force
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $output 'LICENSE.txt') -Force
Copy-Item -LiteralPath $noticesPath -Destination (Join-Path $output 'THIRD-PARTY-NOTICES.txt') -Force
Write-Utf8 (Join-Path $output 'PROVENANCE.txt') $provenance
$filesToHash = @($packageFile, $certificateFile, 'Install-Kazuha.ps1', 'README-Kazuha.md', 'LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', 'PROVENANCE.txt')
$checksumLines = foreach ($fileName in $filesToHash) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $output $fileName) -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $fileName"
}
Write-Utf8 (Join-Path $output 'sha256sums.txt') (($checksumLines -join "`n") + "`n")
Write-Host "Created: $packagePath"
Write-Host "SHA-256 manifest: $(Join-Path $output 'sha256sums.txt')"
Write-Host "Staging retained for inspection: $stage"
Write-Host 'No installation, certificate-store, or system-setting changes were performed.'
[pscustomobject]@{ Package = $packagePath; Checksums = (Join-Path $output 'sha256sums.txt'); Staging = $stage }
