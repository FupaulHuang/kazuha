#requires -Version 7.2
<#
.SYNOPSIS
Builds an unsigned Kazuha MSIX for Microsoft Store upload.
.DESCRIPTION
Requires the exact product identity and reserved display name from Partner Center.
Verifies a managed-channel source build and every payload file before packaging.
Does not sign, create private keys, install software, or change certificate trust.
The Microsoft Store signs the package during submission:
https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide
.EXAMPLE
./Build-StoreMsix.ps1 -PortableDirectory ../dist/store-managed/kazuha-1.4.0-win-x64 `
    -IdentityName 'COPY_FROM_PARTNER_CENTER' -Publisher 'CN=COPY_FROM_PARTNER_CENTER' `
    -PublisherDisplayName 'COPY_FROM_PARTNER_CENTER' -DisplayName 'RESERVED_PRODUCT_NAME'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PortableDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9.-]{3,50}$')]
    [string] $IdentityName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $Publisher,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $PublisherDisplayName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $DisplayName,

    [string] $OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\store'),
    [string] $WorkDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\store'),
    [string] $SourceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'source\Composa'),
    [string] $BuildProvenancePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\store-managed\build-provenance.json'),
    [string] $LogoPath = (Join-Path $PSScriptRoot 'assets\kazuha-icon.png'),
    [string] $MakeAppxPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageVersion = '1.4.0.0' # Fourth component is reserved for the Store and remains zero.
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
    if (-not ('ComposaStoreMetadata' -as [type])) {
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
public static class ComposaStoreMetadata {
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
    return [ComposaStoreMetadata]::Read($Path)
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
foreach ($value in @($IdentityName, $Publisher, $PublisherDisplayName, $DisplayName)) {
    if ([string]::IsNullOrWhiteSpace($value) -or $value -ne $value.Trim() -or $value -match '[\r\n]') {
        throw 'Portal identity values must be nonblank, single-line values without surrounding whitespace.'
    }
    if ($value -match 'COPY_FROM_PARTNER_CENTER|RESERVED_PRODUCT_NAME|YOUR_(PACKAGE|PUBLISHER)|(Composa|Kazuha) Local Build') {
        throw 'Replace the example/local identity with the exact reserved Partner Center product identity.'
    }
    $null = ConvertTo-XmlValue $value
}
if ($IdentityName -eq 'Local.Composa.Windows') { throw 'The local testing identity cannot be used for this Store build.' }
if ($IdentityName -eq 'Local.Kazuha.Windows') { throw 'The local testing identity cannot be used for this Store build.' }
if ($DisplayName -cne 'Kazuha') { throw 'Use the reserved display name Kazuha for this branded build.' }
if ($Publisher.Length -gt 8192 -or $PublisherDisplayName.Length -gt 256 -or $DisplayName.Length -gt 256) {
    throw 'An identity/display value exceeds the manifest schema limit.'
}
$null = [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Publisher)

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

$null = New-Item -ItemType Directory -Path $output -Force
$stage = Join-Path $work ('staging\' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
Get-ChildItem -LiteralPath $portable -Force | Copy-Item -Destination $stage -Recurse -Force
$assets = Join-Path $stage 'StoreAssets'
$docs = Join-Path $stage 'StoreDocumentation'
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
UpdateChannel=managed setting. Updates are managed by Microsoft Store.
The build includes the .NET runtime, image codecs, all three original on-device
models, and license notices. Added files are the Store manifest, package image
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
Reserved product display name: $DisplayName
Package version: $packageVersion
Architecture: x64
Minimum OS: Windows 10 version 2004 (10.0.19041.0)
Built at UTC: $builtAt

This upload artifact is intentionally unsigned. Microsoft Store signs the
package during its submission process. No signing certificate, private key,
certificate-trust instructions, or local installation helper is included.
Signing reference:
https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide

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
    <Logo>StoreAssets\StoreLogo.png</Logo>
  </Properties>
  <Resources><Resource Language="en-us" /></Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26200.0" />
  </Dependencies>
  <Applications>
    <Application Id="Kazuha" Executable="composa.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="$xmlDisplay" Description="Layer-based image editor"
                          BackgroundColor="transparent"
                          Square150x150Logo="StoreAssets\Square150x150Logo.png"
                          Square44x44Logo="StoreAssets\Square44x44Logo.png" />
    </Application>
  </Applications>
  <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
"@
$manifestPath = Join-Path $stage 'AppxManifest.xml'
Write-Utf8 $manifestPath $manifest
$packageBase = "${IdentityName}_${packageVersion}_x64_Store"
$packagePath = Join-Path $output ($packageBase + '.msix')
Write-Host "Verified $verifiedFileCount managed source-build files. Packing Store MSIX..."
# Validation stays enabled: do not add /nv. No SignTool call follows this command.
& $MakeAppxPath pack /d $stage /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed ($LASTEXITCODE). Stage retained: $stage" }
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'MakeAppx did not produce a package.' }

# Verify the actual archive, not only the manifest written before packaging.
$packed = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    if ($null -ne $packed.GetEntry('AppxSignature.p7x')) { throw 'Store upload unexpectedly contains a signature.' }
    foreach ($entry in $packed.Entries) {
        if ($entry.FullName -match '(^|/)(LocalMsixDocumentation|LocalMsixAssets)(/|$)|\.(pfx|p12|cer)$|(^|/)(Install-Msix|Trust-LocalCertificate)\.ps1$') {
            throw "Local signing/install artifact found in Store payload: $($entry.FullName)"
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
        throw 'Packaged identity does not exactly match the supplied Partner Center values.'
    }
}
finally { $packed.Dispose() }

$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$metadata = [ordered]@{
    package = $packagePath; sha256 = $packageHash; unsigned = $true; builtAtUtc = $builtAt
    identityName = $IdentityName; publisher = $Publisher; publisherDisplayName = $PublisherDisplayName
    displayName = $DisplayName; packageVersion = $packageVersion; architecture = 'x64'
    minVersion = '10.0.19041.0'; capability = 'runFullTrust'; verifiedApplicationFileCount = $verifiedFileCount
    sourceCommit = $expectedSourceCommit; updateChannel = 'managed'; sdkVersion = $buildRecord.sdkVersion
    sourceDirty = $true; upstreamSourceDirty = $false; brandingDeltaSha256 = $sourceDiffHash
    sourceBuildProvenance = $buildRecordPath; sourceBuildProvenanceSha256 = $buildRecordHash
    iconSourceSha256 = (Get-FileHash -LiteralPath $iconPath -Algorithm SHA256).Hash.ToLowerInvariant()
    staging = $stage; makeAppx = $MakeAppxPath
}
$metadataPath = Join-Path $output ($packageBase + '.build.json')
Write-Utf8 $metadataPath ($metadata | ConvertTo-Json -Depth 4)
Write-Utf8 (Join-Path $output ($packageBase + '.sha256.txt')) ("$packageHash  $([IO.Path]::GetFileName($packagePath))`n")
Write-Host "Created unsigned Store package: $packagePath"
Write-Host "Retained stage: $stage"
Write-Host 'No signing, private keys, installation, or certificate-store changes.'
[pscustomobject]@{ Package = $packagePath; Sha256 = $packageHash; Metadata = $metadataPath; Staging = $stage; Manifest = $manifestPath }
