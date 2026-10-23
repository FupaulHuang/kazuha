# Kazuha build and packaging guide

Kazuha is an independent Windows edition based on [Composa 1.4.0](https://github.com/dvdstelt/Composa/releases/tag/v1.4.0), with Kazuha branding and the upstream managed update channel. The original reference is [Compositor by Robbie Tilton](https://github.com/robbietilton/Compositor). Upstream licenses and notices remain included.

For installation, use the [Kazuha download guide](README-Kazuha.md). This document describes building the source and packages.

## Requirements

- Windows x64 and 64-bit PowerShell 7.2 or later.
- Git with the `source/Composa` submodule initialized at the pinned release commit.
- .NET SDK **10.0.402**. Extract the official Windows x64 SDK into `build\dotnet`, or pass its installation directory with `-DotnetRoot` to the build script.
- Windows SDK `MakeAppx.exe`; `SignTool.exe` is also required for the sideload package.
- Network access to restore dependencies and obtain the model files used by the source build.

The bundled application includes .NET runtime **10.0.13**; users do not need an SDK. The source-build helper keeps SDK/cache activity within the workspace and does not install the SDK globally.

## Prepare and build Kazuha

From the repository root, use fresh output directories:

```powershell
.\packaging\Prepare-KazuhaSource.ps1 -LogoPath .\packaging\assets\kazuha-icon.png -OutputDirectory .\build\kazuha-source
.\packaging\Build-ManagedApp.ps1 -SourceDirectory .\build\kazuha-source -BrandingRecordPath .\build\kazuha-source.branding.json
```

The preparation step leaves `source\Composa` unchanged. It creates an isolated copy at commit `86529d3b5355d28ddc28ec3db2e4de1d4d00f63b`, applies the Kazuha display-name, product-metadata, and icon changes, and records the complete change and hashes. The current branding record covers 12 files, including matching test expectations.

The build runs selected upstream tests and publishes a self-contained `win-x64` application with `UpdateChannel=managed`. Its default output is `dist\store-managed\kazuha-1.4.0-win-x64`, with file hashes and test results in `dist\store-managed\build-provenance.json`. Existing payload output is refused; use a fresh `-OutputRootPath` for another build and pass the matching provenance path to the package builder.

The user-visible name and logo are Kazuha. Internal assemblies, `composa.exe`, `.cmps` format, and MCP compatibility identifiers retain their upstream names. The managed channel disables automatic upstream GitHub checks and release downloads; the manual update menu refers to the package manager. Sideload users update manually from Kazuha releases.

## Signed GitHub sideload package

```powershell
.\packaging\Build-KazuhaMsix.ps1 -PortableDirectory .\dist\store-managed\kazuha-1.4.0-win-x64
.\tests\verify-kazuha-package.ps1 -PackagePath .\dist\kazuha-msix\Kazuha-1.4.0-x64.msix
```

The bundle is written to `dist\kazuha-msix`. It contains `Kazuha-1.4.0-x64.msix`, `Kazuha-Local-Build.cer`, `Install-Kazuha.ps1`, `README-Kazuha.md`, `LICENSE.txt`, `THIRD-PARTY-NOTICES.txt`, `PROVENANCE.txt`, and `sha256sums.txt`.

The package identity is `Local.Kazuha.Windows`, version `1.4.0.0`, publisher `CN=Kazuha Local Build`, and display name **Kazuha**. Its minimum Windows version is `10.0.19041.0`.

The builder checks source/branding provenance, current logo, assembly metadata, and all application files before MakeAppx validation. It creates a non-CA signing certificate in memory with code-signing usage, exports only a public CER for distribution, and removes its temporary random-password PFX after signing. Each new build has a new certificate and different hashes. Building and read-only verification do not install the app or change certificate trust.

To install, follow [README-Kazuha.md](README-Kazuha.md). The certificate requires explicit trust in **Local Computer > Trusted People**. It is not a publicly trusted publisher identity. The optional helper uses administrator access only with `-TrustCertificate`, then exits. Run it again without that switch in an ordinary Windows PowerShell window to install for the intended user; that step refuses elevation. No developer or signing account is required.

## Unsigned Microsoft Store upload package

Use the identity assigned to the Kazuha product in Partner Center:

```powershell
.\packaging\Build-StoreMsix.ps1 -PortableDirectory .\dist\store-managed\kazuha-1.4.0-win-x64 -IdentityName Fuh.Kazuha -Publisher 'CN=06B7220A-0F66-4D34-82F8-853BDEDBC011' -PublisherDisplayName Fuh -DisplayName Kazuha
```

The output is `dist\store\Fuh.Kazuha_1.4.0.0_x64_Store.msix`, accompanied by a build report and SHA-256 file. This package uses the same audited application payload, the Store-assigned identity, and `runFullTrust`. It is unsigned and contains no local certificate installer or signing key. It is intended for Partner Center upload, not the GitHub sideload installation workflow.

The package has been built, uploaded, and saved after portal package validation. Installation testing, Windows App Certification Kit testing, certification, and Store publication are not implied by that upload. Draft listing and certification instructions are in [docs/store/LISTING-DRAFT.md](../docs/store/LISTING-DRAFT.md).

## Verification and redistribution

The build records selected test results, source revision, branding changes, logo hash, SDK version, and every payload file hash. See the [sanitized verification summary](../docs/VERIFICATION.md). Raw build reports are generated locally and excluded from Git; preserve license and third-party notices when redistributing application files.

The historical `Build-Msix.ps1` and `Install-Msix.ps1` scripts target the earlier Composa-branded package. They do not build or install the Kazuha release. Its [legacy release guide](../docs/releases/v1.4.0-msix.1.md) retains the original filenames, certificate, and installation label.
