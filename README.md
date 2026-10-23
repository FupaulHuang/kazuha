# Composa for Windows — local MSIX packaging

**Original reference: [Compositor by Robbie Tilton](https://github.com/robbietilton/Compositor).** Compositor is the macOS image editor that inspired this project.

The Windows application packaged here is **[Composa by Dennis van der Stelt](https://github.com/dvdstelt/Composa)**, an existing open-source implementation inspired by Compositor. This repository adds local MSIX packaging, installation helpers, and verification scripts around the unmodified **Composa 1.4.0** Windows x64 release. It is an independent packaging project, not an official release from either upstream project.

## Get the application

Clone this repository with its pinned upstream source submodule:

```powershell
git clone --recurse-submodules https://github.com/FupaulHuang/compositor-windows-msix.git
```

From the cloned repository's root, download and extract the portable release:

```powershell
.\packaging\Get-Portable.ps1
.\Launch-Composa.cmd
```

The downloader verifies the pinned SHA-256 before extraction. Keep the entire portable application folder together. The portable release includes its runtime and does not require a developer account, signing account, or administrator access to launch.

Downloaded application binaries, generated MSIX packages, local certificates, build output, and machine-specific verification records are not tracked in Git.

## Build and install the MSIX

Packaging requires Windows x64, **PowerShell 7.2 or later**, and the Windows SDK's `MakeAppx.exe` and `SignTool.exe`. The build wraps the published application; it does not require the .NET SDK.

After running `Get-Portable.ps1`, run from PowerShell 7:

```powershell
.\packaging\Build-Msix.ps1 -PortableDirectory .\dist\portable\composa-1.4.0-win-x64
```

The generated bundle is in `dist\msix`. The builder validates the application payload, creates a local development certificate, signs the MSIX, and removes the temporary private-key file. Building does not install the app or change certificate trust.

Installation requires **Windows 10 version 2004 (build 19041) or later, or Windows 11**, and administrator access for the certificate trust step. No developer or signing account is required. Open **Windows PowerShell** (`powershell.exe`) as administrator, change to the repository root, and run:

```powershell
.\dist\msix\Install-Msix.ps1
```

The installer verifies the bundle, displays the local certificate fingerprint, and asks for `TRUST` before adding that certificate to **Local Computer > Trusted People**. It then installs **Composa (local MSIX)**, available from Start. The certificate identifies this local build; it does not verify the upstream authors' identity. A fresh build generates a new certificate that may need to be trusted again.

See the [packaging guide](packaging/README.md) for build options, installation details, updates, and removal. The upstream app's update checker downloads upstream releases; it does not update this local MSIX.

## Application features

- Layers, groups, masks, blend modes, layer effects, and adjustment layers.
- Painting, selections, transformations, cropping, editable text, and shapes.
- Filters, color adjustments, and bundled offline subject detection.
- Layered `.cmps` projects and common image import/export.

Composa's `.cmps` files are not compatible with Compositor's macOS `.comp` projects. See the [upstream README](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/README.md) for supported features and differences.

## Source and attribution

| Role | Project |
| --- | --- |
| Original reference and inspiration | [Robbie Tilton's Compositor](https://github.com/robbietilton/Compositor) |
| Windows application implementation | [Dennis van der Stelt's Composa](https://github.com/dvdstelt/Composa) |
| Packaged upstream release | [Composa v1.4.0](https://github.com/dvdstelt/Composa/releases/tag/v1.4.0) |
| Additions in this repository | MSIX packaging, installation helpers, and verification scripts |

The `source/Composa` Git submodule is pinned to commit [`86529d3b5355d28ddc28ec3db2e4de1d4d00f63b`](https://github.com/dvdstelt/Composa/commit/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b). If the repository was cloned without submodules, run `git submodule update --init --recursive`.

The input archive is `composa-1.4.0-win-x64.zip`, with the pinned upstream SHA-256:

```text
1d3d8d5f1af258d2d82541b62a3b5a14cacb638f74bb4ccf2049e874833eb162
```

Composa retains its upstream MIT license, original Compositor attribution to Wonder Assembly LLC, and dependency/model notices. The packaging preserves those notices in the distributed application. See the [upstream license](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/LICENSE) and the notices included with the downloaded release.

To build or develop the application itself, install the **.NET 10 SDK** and follow the [upstream build instructions](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/README.md#build-from-source). That source-build workflow is separate from wrapping the verified published release into an MSIX.

## Verification

The portable application, package integrity, installed MSIX, and selected native UI workflows were checked on Windows 11. Read the [sanitized verification summary](docs/VERIFICATION.md) for the tested workflows and scope. Verification scripts are in `tests/`; generated local evidence is excluded from Git. The full upstream test suite was not run as part of this packaging work.
