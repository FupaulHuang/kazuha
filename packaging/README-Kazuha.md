# Install Kazuha

Kazuha is an independent Windows image editor based on
[Composa](https://github.com/dvdstelt/Composa) by Dennis van der Stelt. The original
reference is [Compositor](https://github.com/robbietilton/Compositor) by Robbie
Tilton / Wonder Assembly LLC. The upstream MIT license and dependency notices
are included. This community build does not claim upstream endorsement.

This download includes Kazuha branding, the maple-leaf icon, the .NET runtime,
image codecs and the three bundled on-device models. It uses Composa 1.4.0 source
with recorded branding changes and its managed update mode. Automatic upstream
GitHub update downloads are disabled; install Kazuha updates manually from
[Kazuha releases](https://github.com/FupaulHuang/kazuha/releases).

## Requirements

- A 64-bit Windows 10 installation, version 2004 (build 19041) or later, or Windows 11.
- Administrator access to trust this download's public development certificate.
- No developer account or separate .NET installation is required.

The app appears as **Kazuha** in Windows. This sideload build uses the technical
identity `Local.Kazuha.Windows` and package version **1.4.0.0**. It is separate
from the Microsoft Store package and the earlier Composa package. The underlying
executable remains named `composa.exe` for compatibility with the upstream build.

## Install with the included helper

1. Download and extract the complete release bundle. Keep these files together:
   `Kazuha-1.4.0-x64.msix`, `Kazuha-Local-Build.cer`, `Install-Kazuha.ps1`,
   `README-Kazuha.md`, `LICENSE.txt`, `THIRD-PARTY-NOTICES.txt`, `PROVENANCE.txt`
   and `sha256sums.txt`.
2. Compare the package and certificate SHA-256 checksums with the published
   release checksums using `Get-FileHash`. If Windows blocks the downloaded
   script, right-click `Install-Kazuha.ps1`, choose **Properties**, select
   **Unblock**, and choose **Apply** after verifying the download.
3. For the certificate-trust step, open **Windows PowerShell** using **Run as administrator**. Use
   `powershell.exe`, rather than PowerShell 7 (`pwsh.exe`). Change to the
   extracted folder and run:

   ```powershell
   .\Install-Kazuha.ps1 -TrustCertificate
   ```

4. This trust-only mode verifies all listed file checksums, the package identity, the
   embedded signature and its matching public certificate. Read the displayed
   certificate fingerprint and trust explanation, then enter `TRUST` to continue.
   Any other response cancels before certificate changes. This step never installs
   Kazuha for the administrator.
5. Close the administrator window. Sign in as the person who will use Kazuha,
   open a **normal Windows PowerShell** window without **Run as administrator**,
   change to the extracted folder and run:

   ```powershell
   .\Install-Kazuha.ps1
   ```

   This step checks the bundle again and installs Kazuha only for that user.
6. Open **Kazuha** from Start in that user's session.

The certificate is imported only into **Local Computer > Trusted People**.
It is not added to Trusted Root. Trusting it allows packages signed with this
certificate to be installed on this computer; it is not independent verification
of the publisher's identity. Checksums detect changed or damaged files but do
not independently authenticate their source. The helper does not elevate itself,
change execution policy, or enable Developer Mode. Trust-only mode skips the trust
prompt when this exact certificate is already present in Trusted People. Normal
installation never changes certificate trust and refuses an elevated session so
the app cannot accidentally be registered for an administrator's separate account.

## Install through Windows dialogs

If script execution is restricted, use these dialogs when your device policy
permits sideloading. You do not need to change execution policy.

1. Verify the package and certificate against the release's `sha256sums.txt`:

   ```powershell
   Get-FileHash .\Kazuha-1.4.0-x64.msix -Algorithm SHA256
   Get-FileHash .\Kazuha-Local-Build.cer -Algorithm SHA256
   ```

2. Double-click `Kazuha-Local-Build.cer`, then **Install Certificate**.
3. Select **Local Machine** and approve the administrator prompt.
4. Select **Place all certificates in the following store**, then **Browse**.
5. Select **Trusted People** (not **Trusted Root Certification Authorities**),
   then **OK > Next > Finish**.
6. Back in the intended user's ordinary desktop session, double-click
   `Kazuha-1.4.0-x64.msix` and choose **Install**. Do not open App Installer as a
   different administrator: MSIX registration is per user.

## Updates and removal

Install later sideload versions manually. A new build creates a new development
certificate, which may require another explicit trust step. Package updates must
use an increased four-part version. The private signing key is not retained or
distributed. No timestamp service is used; obtain a fresh bundle if the
certificate expires. The certificate thumbprint and validity date are recorded
in `PROVENANCE.txt`.

Uninstall through **Settings > Apps > Installed apps > Kazuha > Uninstall**.
If you no longer need this certificate, open **Manage computer certificates >
Trusted People > Certificates** and remove only the certificate with the exact
thumbprint recorded in this bundle's `PROVENANCE.txt`.

## Rebuild

Clone [Kazuha](https://github.com/FupaulHuang/kazuha) with its submodule. Use
64-bit PowerShell 7.2 or later, .NET SDK 10 and the Windows SDK packaging tools.
After preparing and building the branded managed application with the repository's
`Prepare-KazuhaSource.ps1` and `Build-ManagedApp.ps1` instructions, run from the
repository root:

```powershell
.\packaging\Build-KazuhaMsix.ps1 -PortableDirectory .\dist\store-managed\kazuha-1.4.0-win-x64
.\tests\verify-kazuha-package.ps1 -PackagePath .\dist\kazuha-msix\Kazuha-1.4.0-x64.msix
```

The builder validates the pinned source, branded source delta, current logo,
build provenance, assembly metadata and every application file. It packs with
Windows SDK validation enabled and signs using an in-memory non-CA certificate
with DigitalSignature usage and Code Signing EKU. It removes its temporary,
random-password PFX after signing and distributes only the public CER.
Distributable files go to `dist\kazuha-msix`; intermediate staging stays in
`build\kazuha-msix`. Neither building nor read-only verification installs the
package, changes certificate trust, or changes system settings.

For source and redistribution details, see `LICENSE.txt`,
`THIRD-PARTY-NOTICES.txt` and `PROVENANCE.txt` in the bundle.
