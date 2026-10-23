#requires -Version 5.1
<#
.SYNOPSIS
Verifies this Kazuha bundle, then installs it for the current non-elevated user.
.DESCRIPTION
Run normally to install for the intended user. A separate administrator run with
-TrustCertificate verifies the bundle and asks permission to import only its
public certificate into LocalMachine\TrustedPeople, then exits without installing.
This script never self-elevates, changes execution policy, or enables Developer Mode.
#>
[CmdletBinding()]
param([string] $PackagePath, [switch] $TrustCertificate)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'This installer requires Windows 10 or 11.' }
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell (powershell.exe), not PowerShell 7 (pwsh.exe), for Add-AppxPackage.'
}
$windows = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = [int]$windows.CurrentBuildNumber
if ($build -lt 19041) {
    throw 'This package requires Windows 10 version 2004 (build 19041) or newer, or Windows 11.'
}
if (-not [Environment]::Is64BitOperatingSystem) { throw 'This package requires a 64-bit Windows installation.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
finally { $identity.Dispose() }
if ($TrustCertificate -and -not $isAdministrator) {
    throw 'Certificate trust requires an administrator Windows PowerShell window. Run .\Install-Kazuha.ps1 -TrustCertificate there, then close it and run .\Install-Kazuha.ps1 in the intended user''s normal Windows PowerShell window. This script does not elevate itself.'
}
if (-not $TrustCertificate -and $isAdministrator) {
    throw 'Install from the intended user''s normal Windows PowerShell window, without Run as administrator. Use -TrustCertificate in this elevated window only for certificate trust; that mode never installs the app.'
}
if ($TrustCertificate) { $null = Get-Command Import-Certificate -ErrorAction Stop }
else { $null = Get-Command Add-AppxPackage -ErrorAction Stop }

$bundleDirectory = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$checksumPath = Join-Path $bundleDirectory 'sha256sums.txt'
if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) { throw 'sha256sums.txt is missing. Keep the full MSIX bundle together.' }
$verifiedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$packageCandidates = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in Get-Content -LiteralPath $checksumPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([A-Fa-f0-9]{64}) [ *](.+)$') { throw "Malformed checksum manifest line: $line" }
    $expected = $matches[1]
    $relative = $matches[2]
    if ([IO.Path]::IsPathRooted($relative)) { throw "Absolute paths are not allowed in sha256sums.txt: $relative" }
    $filePath = [IO.Path]::GetFullPath((Join-Path $bundleDirectory $relative))
    if (-not $filePath.StartsWith($bundleDirectory + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Checksum manifest path leaves the bundle: $relative"
    }
    if (-not $verifiedFiles.Add($filePath)) { throw "Duplicate checksum entry: $relative" }
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "A bundle file is missing: $relative" }
    $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "Checksum mismatch for $relative. Stop and obtain a fresh bundle." }
    if ([IO.Path]::GetExtension($filePath) -ieq '.msix') { $packageCandidates.Add($filePath) }
}
if ($verifiedFiles.Count -eq 0) { throw 'The checksum manifest is empty.' }
if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    if ($packageCandidates.Count -ne 1) { throw 'The checksum manifest must list exactly one MSIX, or supply -PackagePath explicitly.' }
    $PackagePath = $packageCandidates[0]
}
else {
    $PackagePath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackagePath).ProviderPath)
}
if (-not $verifiedFiles.Contains($PackagePath) -or [IO.Path]::GetExtension($PackagePath) -ine '.msix') {
    throw 'The chosen package must be an MSIX verified against this bundle''s sha256sums.txt.'
}

$certificatePath = Join-Path $bundleDirectory 'Kazuha-Local-Build.cer'
if (-not $verifiedFiles.Contains($certificatePath)) { throw 'The public signing certificate is not covered by sha256sums.txt.' }
$certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2($certificatePath)
try {
    if ($certificate.HasPrivateKey) { throw 'The distributed certificate must not include a private key.' }
    if ($certificate.Subject -cne 'CN=Kazuha Local Build') { throw 'Unexpected certificate subject.' }
    if ((Get-Date) -lt $certificate.NotBefore -or (Get-Date) -gt $certificate.NotAfter) { throw 'The local signing certificate is outside its validity dates. Obtain a newly built bundle.' }
    $basicConstraints = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
    if ($basicConstraints.Count -ne 1 -or $basicConstraints[0].CertificateAuthority) { throw 'The local signing certificate must be a non-CA end-entity certificate.' }
    $keyUsage = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.15' })
    if ($keyUsage.Count -ne 1 -or ($keyUsage[0].KeyUsages -band [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature) -eq 0) { throw 'The certificate is missing DigitalSignature usage.' }
    $eku = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' })
    if ($eku.Count -ne 1 -or @($eku[0].EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.3' }).Count -ne 1) { throw 'The certificate is missing the Code Signing extended usage.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.Security
    $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $manifestEntry = $archive.GetEntry('AppxManifest.xml')
        $signatureEntry = $archive.GetEntry('AppxSignature.p7x')
        if ($null -eq $manifestEntry -or $null -eq $signatureEntry) { throw 'The MSIX is missing its manifest or signature.' }
        $reader = New-Object IO.StreamReader($manifestEntry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
        if ($manifest.Package.Identity.Name -cne 'Local.Kazuha.Windows') { throw 'Unexpected local package identity.' }
        if ($manifest.Package.Identity.Publisher -cne $certificate.Subject) { throw 'The package publisher does not match the supplied certificate.' }
        $signatureStream = $signatureEntry.Open()
        $memory = New-Object IO.MemoryStream
        try { $signatureStream.CopyTo($memory); $signatureBytes = $memory.ToArray() }
        finally { $signatureStream.Dispose(); $memory.Dispose() }
    }
    finally { $archive.Dispose() }

    # The MSIX signature is a PKCX header followed by CMS. Validate the embedded
    # CMS signature and match its actual signer to the supplied public CER before
    # requesting trust. Windows validates all package content during install.
    if ($signatureBytes.Length -lt 5 -or [Text.Encoding]::ASCII.GetString($signatureBytes, 0, 4) -cne 'PKCX') { throw 'Invalid MSIX signature header.' }
    $cmsBytes = New-Object byte[] ($signatureBytes.Length - 4)
    [Array]::Copy($signatureBytes, 4, $cmsBytes, 0, $cmsBytes.Length)
    $cms = New-Object Security.Cryptography.Pkcs.SignedCms
    $cms.Decode($cmsBytes)
    $cms.CheckSignature($true)
    if ($cms.SignerInfos.Count -ne 1 -or $null -eq $cms.SignerInfos[0].Certificate -or
        $cms.SignerInfos[0].Certificate.GetRawCertDataString() -cne $certificate.GetRawCertDataString()) {
        throw 'The actual MSIX signer does not match the supplied public certificate.'
    }

    $certificateSha256 = (Get-FileHash -LiteralPath $certificatePath -Algorithm SHA256).Hash
    Write-Host "Verified $($verifiedFiles.Count) bundle files and the package signer."
    Write-Host "Certificate subject: $($certificate.Subject)"
    Write-Host "Certificate SHA-256 fingerprint: $certificateSha256"
    Write-Host "Windows certificate thumbprint (SHA-1): $($certificate.Thumbprint)"
    Write-Host "Valid until: $($certificate.NotAfter.ToString('yyyy-MM-dd'))"
    $trustPath = 'Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint
    $alreadyTrusted = Test-Path -LiteralPath $trustPath
    if ($TrustCertificate) {
      if (-not $alreadyTrusted) {
        Write-Host ''
        Write-Host 'This is a local development certificate, not a publicly verified publisher.'
        Write-Host 'Trusting it lets Windows install packages signed with this certificate for users of this computer.'
        Write-Host 'It will be added to LocalMachine\TrustedPeople, not the Trusted Root store.'
        Write-Host 'This step only trusts the certificate. It does not install Kazuha for the administrator.'
        $answer = Read-Host 'Type TRUST to trust this certificate (anything else cancels)'
        if ($answer -cne 'TRUST') { throw 'Cancelled. No certificate or package was installed.' }
        $null = Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction Stop
      }
      else { Write-Host 'This exact certificate is already trusted in LocalMachine\TrustedPeople.' }
      Write-Host 'Certificate trust is ready. No app was installed.'
      Write-Host 'Close this administrator window. In the intended user''s normal Windows PowerShell window, run .\Install-Kazuha.ps1 without -TrustCertificate.'
      return
    }
    if (-not $alreadyTrusted) {
        throw 'This bundle''s certificate is not yet trusted. Have an administrator run .\Install-Kazuha.ps1 -TrustCertificate, close that elevated window, then rerun this command in the intended user''s normal Windows PowerShell window.'
    }

    Write-Host 'Installing Kazuha, the independent Windows edition based on Composa 1.4.0...'
    try { Add-AppxPackage -Path $PackagePath -ErrorAction Stop }
    catch {
        throw "Package installation failed: $($_.Exception.Message) This installation step did not change certificate trust."
    }
    Write-Host 'Installed. Open Kazuha from the Start menu.'
    Write-Host 'To remove the app later, use Settings > Apps > Installed apps > Kazuha > Uninstall.'
    Write-Host "If the local certificate is no longer needed, its TrustedPeople thumbprint is $($certificate.Thumbprint)."
}
finally { $certificate.Dispose() }
