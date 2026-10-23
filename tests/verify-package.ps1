#requires -Version 5.1
<#
.SYNOPSIS
Read-only verification of the local Composa MSIX bundle and its portable payload.
.DESCRIPTION
Does not install software, import certificates, or require a trusted signing
certificate. Verifies the CMS signature mathematically, the signed block-map
and content-type digests, all package content blocks, and the portable files.
Windows deployment policy and actual packaged app launch require a separate,
explicit installation test; this script does not claim to perform that test.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $PackagePath,
    [string] $PortableDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\portable\composa-1.4.0-win-x64'),
    [string] $CertificatePath,
    [string] $ChecksumPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($PSVersionTable.PSEdition -eq 'Desktop') { Add-Type -AssemblyName System.Security }
else { Add-Type -AssemblyName System.Security.Cryptography.Pkcs }

function Assert-That([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Hex([byte[]] $Bytes) {
    return [BitConverter]::ToString($Bytes).Replace('-', '').ToLowerInvariant()
}

function Get-Sha256([byte[]] $Bytes) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ,$hasher.ComputeHash($Bytes) }
    finally { $hasher.Dispose() }
}

function Read-EntryBytes($Entry) {
    $inputStream = $Entry.Open()
    $memory = New-Object IO.MemoryStream
    try {
        $inputStream.CopyTo($memory)
        return ,$memory.ToArray()
    }
    finally { $inputStream.Dispose(); $memory.Dispose() }
}

function Get-SafeArchiveName([string] $Name) {
    $normalized = $Name.Replace('\', '/')
    Assert-That (-not [string]::IsNullOrWhiteSpace($normalized)) 'Empty archive path.'
    Assert-That (-not $normalized.StartsWith('/') -and -not $normalized.Contains(':')) "Unsafe archive path: $Name"
    foreach ($part in $normalized.TrimEnd('/').Split('/')) {
        Assert-That ($part -ne '.' -and $part -ne '..' -and $part.Length -gt 0) "Unsafe archive path: $Name"
    }
    return $normalized
}

# A small strict DER reader avoids depending on SDK/ASN.1 packages on PowerShell 5.1.
function Read-DerNode([byte[]] $Data, [int] $Offset, [int] $Limit) {
    Assert-That ($Offset -ge 0 -and $Offset + 2 -le $Limit) 'Truncated DER header.'
    $tag = [int]$Data[$Offset]
    $cursor = $Offset + 1
    $length = [int]$Data[$cursor++]
    if (($length -band 128) -ne 0) {
        $count = $length -band 127
        Assert-That ($count -ge 1 -and $count -le 4 -and $cursor + $count -le $Limit) 'Invalid DER length.'
        $length = [long]0
        for ($i = 0; $i -lt $count; $i++) { $length = ($length * 256) + $Data[$cursor++] }
    }
    Assert-That ($length -ge 0 -and $cursor + $length -le $Limit) 'DER content exceeds bounds.'
    return [pscustomobject]@{ Tag = $tag; Start = $cursor; Length = [int]$length; End = [int]($cursor + $length) }
}

function Read-AppxDigestTable([byte[]] $Content) {
    $root = Read-DerNode $Content 0 $Content.Length
    Assert-That ($root.Tag -eq 48 -and $root.End -eq $Content.Length) 'Expected signed SpcIndirectDataContent sequence.'
    $attribute = Read-DerNode $Content $root.Start $root.End
    $digestInfo = Read-DerNode $Content $attribute.End $root.End
    Assert-That ($attribute.Tag -eq 48 -and $digestInfo.Tag -eq 48 -and $digestInfo.End -eq $root.End) 'Malformed signed digest information.'
    $algorithm = Read-DerNode $Content $digestInfo.Start $digestInfo.End
    $digest = Read-DerNode $Content $algorithm.End $digestInfo.End
    Assert-That ($algorithm.Tag -eq 48 -and $digest.Tag -eq 4 -and $digest.End -eq $digestInfo.End) 'Malformed signed digest table.'
    $oid = Read-DerNode $Content $algorithm.Start $algorithm.End
    $oidHex = Get-Hex ([byte[]]$Content[$oid.Start..($oid.End - 1)])
    Assert-That ($oid.Tag -eq 6 -and $oidHex -eq '608648016503040201') 'The package digest algorithm must be SHA-256.'
    Assert-That ($digest.Length -ge 4 -and (($digest.Length - 4) % 36) -eq 0) 'Unexpected APPX digest table length.'
    Assert-That ([Text.Encoding]::ASCII.GetString($Content, $digest.Start, 4) -eq 'APPX') 'Missing APPX digest table magic.'
    $result = @{}
    for ($offset = $digest.Start + 4; $offset -lt $digest.End; $offset += 36) {
        $label = [Text.Encoding]::ASCII.GetString($Content, $offset, 4)
        Assert-That (-not $result.ContainsKey($label)) "Duplicate signed digest: $label"
        $result[$label] = Get-Hex ([byte[]]$Content[($offset + 4)..($offset + 35)])
    }
    return $result
}

$package = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
$portable = (Resolve-Path -LiteralPath $PortableDirectory).ProviderPath.TrimEnd('\', '/')
$bundle = Split-Path $package -Parent
if ([string]::IsNullOrWhiteSpace($CertificatePath)) { $CertificatePath = Join-Path $bundle 'Composa-Local-Build.cer' }
if ([string]::IsNullOrWhiteSpace($ChecksumPath)) { $ChecksumPath = Join-Path $bundle 'sha256sums.txt' }
Assert-That (Test-Path -LiteralPath $portable -PathType Container) 'PortableDirectory must be a directory.'
Assert-That (Test-Path -LiteralPath $CertificatePath -PathType Leaf) 'Public signing certificate is missing.'
Assert-That (Test-Path -LiteralPath $ChecksumPath -PathType Leaf) 'Bundle checksum manifest is missing.'
$privateFiles = @(Get-ChildItem -LiteralPath $bundle -File -Recurse -Force | Where-Object { $_.Extension -in @('.pfx', '.p12', '.key', '.pem') })
Assert-That ($privateFiles.Count -eq 0) 'Distributable bundle contains potential private-key files.'

$checkedPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($line in Get-Content -LiteralPath $ChecksumPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    Assert-That ($line -match '^([0-9a-fA-F]{64}) [ *](.+)$') 'Malformed checksum line.'
    $expected = $matches[1]
    $relative = Get-SafeArchiveName $matches[2]
    $fullPath = [IO.Path]::GetFullPath((Join-Path $bundle $relative))
    Assert-That ($fullPath.StartsWith($bundle.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)) 'Checksum path escapes bundle.'
    Assert-That ($checkedPaths.Add($fullPath)) "Duplicate checksum path: $relative"
    Assert-That (Test-Path -LiteralPath $fullPath -PathType Leaf) "Missing bundle file: $relative"
    Assert-That ((Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash -eq $expected) "Bundle hash mismatch: $relative"
}
Assert-That ($checkedPaths.Contains($package)) 'MSIX is not covered by the checksum manifest.'
Assert-That ($checkedPaths.Contains((Resolve-Path -LiteralPath $CertificatePath).ProviderPath)) 'Public certificate is not covered by the checksum manifest.'

$archive = [IO.Compression.ZipFile]::OpenRead($package)
try {
    $entries = New-Object 'Collections.Generic.Dictionary[string,System.IO.Compression.ZipArchiveEntry]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $archive.Entries) {
        $name = Get-SafeArchiveName $entry.FullName
        Assert-That (-not $entries.ContainsKey($name)) "Duplicate archive entry: $name"
        $entries.Add($name, $entry)
    }
    foreach ($required in @('AppxManifest.xml', 'AppxBlockMap.xml', '[Content_Types].xml', 'AppxSignature.p7x')) {
        Assert-That ($entries.ContainsKey($required)) "Missing package metadata: $required"
    }

    $manifestBytes = Read-EntryBytes $entries['AppxManifest.xml']
    [xml]$manifest = [Text.Encoding]::UTF8.GetString($manifestBytes)
    $ns = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
    $ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
    $ns.AddNamespace('rescap', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities')
    $identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
    Assert-That ($null -ne $identity) 'Missing manifest identity.'
    Assert-That ($identity.Name -eq 'Local.Composa.Windows' -and $identity.ProcessorArchitecture -eq 'x64') 'Unexpected package name or architecture.'
    Assert-That ($identity.Version -match '^1\.4\.0\.\d+$') 'Unexpected package version.'
    $application = @($manifest.SelectNodes('/m:Package/m:Applications/m:Application', $ns))
    Assert-That ($application.Count -eq 1 -and $application[0].EntryPoint -eq 'Windows.FullTrustApplication') 'Expected one full-trust desktop application.'
    $executableName = Get-SafeArchiveName $application[0].Executable
    Assert-That ($executableName -eq 'composa.exe' -and $entries.ContainsKey($executableName)) 'Missing packaged executable.'
    Assert-That ($null -ne $manifest.SelectSingleNode('/m:Package/m:Capabilities/rescap:Capability[@Name="runFullTrust"]', $ns)) 'Missing runFullTrust capability.'
    $deviceFamily = $manifest.SelectSingleNode('/m:Package/m:Dependencies/m:TargetDeviceFamily[@Name="Windows.Desktop"]', $ns)
    Assert-That ($null -ne $deviceFamily) 'Missing Windows.Desktop dependency.'

    $logoChecks = @(
        @{ Path = $manifest.SelectSingleNode('/m:Package/m:Properties/m:Logo', $ns).InnerText; Size = 50 },
        @{ Path = $application[0].SelectSingleNode('uap:VisualElements', $ns).Square44x44Logo; Size = 44 },
        @{ Path = $application[0].SelectSingleNode('uap:VisualElements', $ns).Square150x150Logo; Size = 150 }
    )
    foreach ($logo in $logoChecks) {
        $name = Get-SafeArchiveName $logo.Path
        Assert-That ($entries.ContainsKey($name)) "Missing logo: $name"
        $png = Read-EntryBytes $entries[$name]
        Assert-That ($png.Length -ge 24 -and (Get-Hex ([byte[]]$png[0..7])) -eq '89504e470d0a1a0a') "Logo is not PNG: $name"
        $width = [long]$png[16] * 16777216 + [long]$png[17] * 65536 + [long]$png[18] * 256 + $png[19]
        $height = [long]$png[20] * 16777216 + [long]$png[21] * 65536 + [long]$png[22] * 256 + $png[23]
        Assert-That ($width -eq $logo.Size -and $height -eq $logo.Size) "Incorrect logo dimensions: $name"
    }

    $signatureBytes = Read-EntryBytes $entries['AppxSignature.p7x']
    Assert-That ($signatureBytes.Length -gt 4 -and [Text.Encoding]::ASCII.GetString($signatureBytes, 0, 4) -eq 'PKCX') 'Invalid P7X signature header.'
    $cms = New-Object Security.Cryptography.Pkcs.SignedCms
    $cms.Decode([byte[]]$signatureBytes[4..($signatureBytes.Length - 1)])
    Assert-That ($cms.SignerInfos.Count -eq 1) 'Expected exactly one package signer.'
    $cms.CheckSignature($true) # Mathematical check only; does not trust/import a certificate.
    $signer = $cms.SignerInfos[0].Certificate
    Assert-That ($null -ne $signer -and $signer.Subject -eq $identity.Publisher) 'Signing certificate subject does not match manifest publisher.'
    $publicCertificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
    try {
        Assert-That (-not $publicCertificate.HasPrivateKey) 'Public certificate unexpectedly contains a private key.'
        Assert-That ((Get-Hex $publicCertificate.RawData) -eq (Get-Hex $signer.RawData)) 'Bundled certificate differs from package signer.'
    }
    finally { $publicCertificate.Dispose() }
    $eku = @($signer.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' })
    Assert-That ($eku.Count -eq 1 -and @($eku[0].EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.3' }).Count -eq 1) 'Signing certificate lacks Code Signing EKU.'
    Assert-That ($signer.NotBefore -le [DateTime]::Now -and $signer.NotAfter -gt [DateTime]::Now) 'Signing certificate is outside its validity period.'
    Assert-That ($cms.ContentInfo.ContentType.Value -eq '1.3.6.1.4.1.311.2.1.4') 'Unexpected signed content type.'
    $signedDigests = Read-AppxDigestTable $cms.ContentInfo.Content
    $blockMapBytes = Read-EntryBytes $entries['AppxBlockMap.xml']
    $contentTypesBytes = Read-EntryBytes $entries['[Content_Types].xml']
    Assert-That ($signedDigests.ContainsKey('AXBM') -and $signedDigests['AXBM'] -eq (Get-Hex (Get-Sha256 $blockMapBytes))) 'Block map does not match its signed digest.'
    Assert-That ($signedDigests.ContainsKey('AXCT') -and $signedDigests['AXCT'] -eq (Get-Hex (Get-Sha256 $contentTypesBytes))) 'Content types do not match their signed digest.'
    $catalogName = 'AppxMetadata/CodeIntegrity.cat'
    if ($entries.ContainsKey($catalogName) -or $signedDigests.ContainsKey('AXCI')) {
        Assert-That ($entries.ContainsKey($catalogName) -and $signedDigests.ContainsKey('AXCI')) 'Code Integrity catalog and signed digest must both be present.'
        $catalogBytes = Read-EntryBytes $entries[$catalogName]
        Assert-That ($signedDigests['AXCI'] -eq (Get-Hex (Get-Sha256 $catalogBytes))) 'Code Integrity catalog does not match its signed digest.'
    }

    [xml]$blockMap = [Text.Encoding]::UTF8.GetString($blockMapBytes)
    Assert-That ($blockMap.DocumentElement.HashMethod -eq 'http://www.w3.org/2001/04/xmlenc#sha256') 'Expected SHA-256 package block hashes.'
    $mappedFiles = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $blockCount = 0
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($file in $blockMap.DocumentElement.ChildNodes) {
            if ($file.NodeType -ne [Xml.XmlNodeType]::Element) { continue }
            $name = Get-SafeArchiveName $file.GetAttribute('Name')
            Assert-That ($mappedFiles.Add($name)) "Duplicate block-map file: $name"
            Assert-That ($entries.ContainsKey($name)) "Block-map file missing: $name"
            $entry = $entries[$name]
            Assert-That ($entry.Length -eq [long]$file.GetAttribute('Size')) "Block-map size mismatch: $name"
            $stream = $entry.Open()
            try {
                $buffer = New-Object byte[] 65536
                $totalRead = [long]0
                foreach ($block in $file.ChildNodes) {
                    if ($block.NodeType -ne [Xml.XmlNodeType]::Element) { continue }
                    if ($block.LocalName -eq 'FileHash') { continue }
                    Assert-That ($block.LocalName -eq 'Block') "Unexpected block-map element: $($block.LocalName)"
                    $read = 0
                    do {
                        $next = $stream.Read($buffer, $read, $buffer.Length - $read)
                        $read += $next
                    } while ($next -gt 0 -and $read -lt $buffer.Length)
                    $actualHash = [Convert]::ToBase64String($hasher.ComputeHash($buffer, 0, $read))
                    Assert-That ($actualHash -ceq $block.GetAttribute('Hash')) "Content block hash mismatch: $name (block $blockCount)"
                    $totalRead += $read
                    $blockCount++
                }
                Assert-That ($totalRead -eq $entry.Length -and $stream.ReadByte() -eq -1) "Block map does not cover the entire file: $name"
            }
            finally { $stream.Dispose() }
            $wholeFileHash = @($file.ChildNodes | Where-Object { $_.LocalName -eq 'FileHash' })
            Assert-That ($wholeFileHash.Count -le 1) "Duplicate whole-file hash: $name"
            if ($wholeFileHash.Count -eq 1) {
                $stream = $entry.Open()
                try { $actualHash = [Convert]::ToBase64String($hasher.ComputeHash($stream)) }
                finally { $stream.Dispose() }
                Assert-That ($actualHash -ceq $wholeFileHash[0].GetAttribute('Hash')) "Whole-file hash mismatch: $name"
            }
        }
    }
    finally { $hasher.Dispose() }
    foreach ($name in $entries.Keys) {
        if ($name.EndsWith('/') -or $name -in @('AppxBlockMap.xml', 'AppxSignature.p7x', '[Content_Types].xml', $catalogName)) { continue }
        Assert-That ($mappedFiles.Contains($name)) "Package file is not covered by the signed block map: $name"
    }

    $portableCount = 0
    $portableBytes = [long]0
    foreach ($file in Get-ChildItem -LiteralPath $portable -File -Recurse -Force) {
        $name = $file.FullName.Substring($portable.Length + 1).Replace('\', '/')
        Assert-That ($entries.ContainsKey($name)) "Portable file missing from package: $name"
        $stream = $entries[$name].Open()
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $actualHash = Get-Hex $hasher.ComputeHash($stream) }
        finally { $stream.Dispose(); $hasher.Dispose() }
        Assert-That ($actualHash -eq (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) "Portable payload changed: $name"
        $portableCount++
        $portableBytes += $file.Length
    }

    [pscustomobject]@{
        Result = 'PASS'
        Package = $package
        Sha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
        Identity = $identity.Name
        Version = $identity.Version
        Publisher = $identity.Publisher
        MinimumWindowsVersion = $deviceFamily.MinVersion
        CertificateThumbprint = $signer.Thumbprint
        CertificateExpires = $signer.NotAfter.ToUniversalTime().ToString('o')
        CheckedBundleFiles = $checkedPaths.Count
        CheckedPackageFiles = $mappedFiles.Count
        CheckedContentBlocks = $blockCount
        CheckedPortableFiles = $portableCount
        CheckedPortableBytes = $portableBytes
        CmsSignatureMathVerified = $true
        SignedBlockMapAndContentTypesVerified = $true
        InstallationTested = $false
        CertificateStoreModified = $false
    }
}
finally { $archive.Dispose() }
