# Kazuha

<img src="packaging/assets/kazuha-icon.png" alt="Kazuha maple-leaf logo" width="120">

**Original reference: [Compositor by Robbie Tilton](https://github.com/robbietilton/Compositor).** Kazuha is an independent Windows image editor based on **[Composa by Dennis van der Stelt](https://github.com/dvdstelt/Composa)**.

Kazuha adds its own name and minimal autumn maple-leaf logo, Windows packaging, installation helpers, and verification. The editor is built from Composa 1.4.0 with a recorded branding change and the upstream managed update setting. It is independently maintained and does not claim endorsement or authorship of either upstream project.

## Download and install

**[Download Kazuha 1.4.0 for Windows x64 (MSIX ZIP)](https://github.com/FupaulHuang/kazuha/releases/download/v1.4.0-kazuha.1/Kazuha-1.4.0-Windows-x64-MSIX.zip)**

Requires Windows 10 version 2004 (build 19041) or later, or Windows 11. The complete ZIP includes the application, public signing certificate, installer, checksums, and license notices. No developer/signing account or separate .NET installation is needed.

1. Verify the download against the [release checksums](https://github.com/FupaulHuang/kazuha/releases/tag/v1.4.0-kazuha.1), then extract the ZIP.
2. Inspect `Kazuha-Local-Build.cer`. Install it into **Local Machine > Trusted People** and approve the administrator prompt.
3. In your ordinary desktop session, double-click `Kazuha-1.4.0-x64.msix`, choose **Install**, then open **Kazuha** from Start.

This GitHub download is signed with a self-signed development certificate that requires manual trust. It identifies this community build, not the upstream authors' identity. See the [installation guide](packaging/README-Kazuha.md) for certificate details and the optional verified PowerShell installer.

The separate Microsoft Store package has been built, uploaded, and saved after portal package validation. Store availability and certification are pending. The GitHub package uses `Local.Kazuha.Windows`; the Store package uses `Fuh.Kazuha`.

## Features

- Layers, groups, masks, blend modes, effects, and adjustment layers.
- Painting, selections, transformations, cropping, editable text, and shapes.
- Filters, color adjustments, and bundled local subject-detection and enhancement models.
- Editable `.cmps` projects and PNG, JPEG, and WebP export.
- Optional local MCP automation, disabled by default.

Kazuha retains Composa's `.cmps` format; it does not open Compositor's macOS `.comp` projects. Core editing and bundled model inference run locally. The managed update setting disables the application's upstream GitHub update checks and downloads. Install GitHub sideload updates manually; a future Store installation receives its updates through Microsoft Store. See the [privacy policy](docs/store/PRIVACY.md).

## Build from source

```powershell
git clone --recurse-submodules https://github.com/FupaulHuang/kazuha.git
```

The upstream `source/Composa` submodule is pinned to [`86529d3b5355d28ddc28ec3db2e4de1d4d00f63b`](https://github.com/dvdstelt/Composa/commit/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b). Run `git submodule update --init --recursive` if it was omitted during cloning.

Use Windows x64, PowerShell 7.2 or later, .NET SDK **10.0.402**, and the Windows SDK packaging tools. The [build guide](packaging/README.md) prepares an isolated branded source copy, runs selected tests, publishes the application, and creates either a signed sideload package or an unsigned Store upload package. The upstream checkout remains unchanged. Downloaded dependencies, binaries, private signing material, and local test records are excluded from Git.

## Verification

**216 selected tests passed**, and both Kazuha packages passed their build and payload-integrity checks. The signed sideload package also passed signature and content-block verification. Native payload checks confirmed the title, icon, sample rendering, and managed-update message. Installed Kazuha workflow testing, Windows App Certification Kit testing, and Store certification are not claimed. Read the [verification summary](docs/VERIFICATION.md) for the exact scope and the separate historical Composa installation results.

## Attribution and earlier release

The [upstream Composa license](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/LICENSE), Compositor attribution to Wonder Assembly LLC, and third-party/model notices are preserved. See [NOTICE.md](NOTICE.md) for credits; the root MIT license covers this repository's additions.

The [earlier Composa-branded release](https://github.com/FupaulHuang/kazuha/releases/tag/v1.4.0-msix.1) remains available as a historical package. Its filenames, certificate, installed label, and original upstream updater remain unchanged. New users should use the Kazuha release above.
