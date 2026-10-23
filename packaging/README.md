# Composa 1.4.0 - local Windows MSIX

This is a **local repack of the upstream Composa Windows x64 portable release**,
not an official MSIX from its authors and not a new implementation of Compositor.
Composa is an open-source Windows/Linux image editor inspired by the macOS
[Compositor](https://github.com/robbietilton/Compositor) app. Its executable and
bundled dependencies are unchanged. This package adds Windows installation
metadata, resized upstream icons, and local provenance information.

The package appears as **Composa (local MSIX)** in Windows and has the distinct
identity `Local.Composa.Windows`. It does not register file associations.

## Install

Requirements: 64-bit Windows 10 version 2004 (build 19041) or newer, or Windows 11,
and administrator access for the certificate trust step. No developer account,
paid certificate, or existing signing credentials are needed. This build is
signed with a free, locally generated **development certificate**.

1. Keep the MSIX, `Composa-Local-Build.cer`, `Install-Msix.ps1`, `sha256sums.txt`,
   and accompanying documentation together in one folder. If you received a ZIP,
   extract it first.
2. Open **Windows PowerShell** from Start using **Run as administrator**. Use
   Windows PowerShell (`powershell.exe`), not PowerShell 7 (`pwsh.exe`).
3. Change into the extracted folder and run:

   ```powershell
   .\Install-Msix.ps1
   ```

4. The script verifies every listed checksum, the package identity/publisher,
   and its embedded signer, then shows the public certificate's fingerprint.
   Read the trust prompt and type `TRUST` to trust this certificate and install.
   Any other response cancels before certificate or installation changes.
5. Open **Composa (local MSIX)** from Start.

The certificate is imported only into **Local Computer > Trusted People**, never
Trusted Root. It allows packages signed with this certificate to be installed on
this computer. The script does not self-elevate, change execution policy, or
enable Developer Mode. The exact certificate is trusted once; rerunning the
installer skips the trust prompt if it is already present. After that trust step,
the `.msix` can also be installed through the normal Windows App Installer UI.

Checksums detect damaged or changed files; they are not independent proof of a
publisher's identity. This local certificate is not a public verification of the
Composa authors. Organization policy can still restrict sideloading.

If script execution is restricted, do not change a managed machine's policy.
The portable release can run without an MSIX installation. You can also install
through Windows dialogs without running a PowerShell script:

1. Check the package and certificate SHA-256 values against `sha256sums.txt`
   using `Get-FileHash` in PowerShell.
2. Double-click `Composa-Local-Build.cer` and choose **Install Certificate**.
3. Select **Local Machine**, then approve the administrator prompt.
4. Choose **Place all certificates in the following store**, then **Browse**.
5. Select **Trusted People** (not **Trusted Root Certification Authorities**),
   choose **OK**, **Next**, then **Finish**. This explicitly trusts this local
   certificate on your computer.
6. Double-click `Composa-1.4.0-x64.msix`, then choose **Install**.

The dialog workflow above avoids running a PowerShell script.

## Updates and removal

Update this local MSIX manually. Composa's upstream built-in updater identifies
the app as a portable Windows build and does not create or replace this local
MSIX. A new local build generates a new development certificate, so a later
repack may need its new certificate trusted. Package updates use an increased
four-part version. The original private signing key is not retained.

Remove the app through **Settings > Apps > Installed apps > Composa (local MSIX) >
Uninstall**. When this local certificate is no longer needed, remove only its
matching thumbprint from **Manage computer certificates > Trusted People >
Certificates**. The thumbprint and expiration date are recorded in
`PROVENANCE.txt`. No timestamp service is used; obtain a fresh local build if the
certificate expires. Do not run portable and packaged copies simultaneously
against the same documents.

## Included files

- `Composa-1.4.0-x64.msix`: upstream Composa **1.4.0**, with its .NET runtime and
  bundled components. A separate .NET SDK/runtime is not required.
- `Composa-Local-Build.cer`: public development certificate, without a private key.
- `Install-Msix.ps1`: verification, explicit certificate trust, and installation.
- `sha256sums.txt`: checksums for all bundle files other than this checksum list.
- `LICENSE.txt`, `THIRD-PARTY-NOTICES.txt`, and `PROVENANCE.txt`.
- `README-Msix.md`: these instructions.

The package version is **1.4.0.0** by default. The input portable ZIP SHA-256 is:

```text
1d3d8d5f1af258d2d82541b62a3b5a14cacb638f74bb4ccf2049e874833eb162
```

[Upstream source](https://github.com/dvdstelt/Composa) /
[upstream release](https://github.com/dvdstelt/Composa/releases/tag/v1.4.0).
Preserve the license and dependency notices when redistributing the payload.

## Rebuild from the workspace

Requirements: 64-bit **PowerShell 7.2 or later**, Windows SDK `makeappx.exe` and
`signtool.exe`, the verified upstream ZIP, a fresh extraction with `composa.exe`
at its root, and the upstream source tree for licenses/icons.

From the workspace root:

```powershell
.\packaging\Build-Msix.ps1 -PortableDirectory .\path-to-fresh-extracted-app
```

Default input paths are `downloads\composa-1.4.0-win-x64.zip` and
`source\Composa`; distributable output goes to `dist\msix`, while staging and
temporary signing files stay under `build\msix`. Supply `-UpstreamArchivePath`,
`-SourceDirectory`, `-OutputDirectory`, `-WorkDirectory`, `-MakeAppxPath`, or
`-SignToolPath` to override them. `-PackageVersion` changes the revision component
of `1.4.0.0` while keeping the upstream application version pinned to 1.4.0.

The builder verifies the pinned ZIP hash and every extracted file. It preserves
the complete payload and creates 44, 50, and 150 px icons from the upstream PNG.
MakeAppx runs its normal manifest/semantic validation; validation is not disabled.
Each build uses a unique staging directory retained for inspection.

The signing certificate is created **in memory** with SHA-256, DigitalSignature
usage, Code Signing EKU, and a non-CA constraint. The public `.cer` is distributed.
The private key is exported only to a uniquely located temporary PFX protected by
a random, unlogged password. The PFX is removed in a `finally` block after
signing; the private key is never included in the MSIX or distribution folder.
Building does not install the package or change certificate stores/system settings.

## Microsoft references

- [Create a certificate for package signing](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)
- [Sign an MSIX package](https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide)
- [Create packages with MakeAppx](https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool)

Microsoft describes self-signed packages as suitable for development/testing.
For broad public distribution, use a publicly trusted signing method or the
Microsoft Store. This is a local build for personal use/testing.
