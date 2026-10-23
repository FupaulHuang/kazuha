# Kazuha verification summary

Checked on **23 October 2026**, on **Windows 11 25H2, build 26200, x64**. Kazuha source-build and package checks are listed first; the earlier Composa installation results are retained separately below.

## Kazuha source build

- Base source: Composa commit `86529d3b5355d28ddc28ec3db2e4de1d4d00f63b`, tag `v1.4.0`. The upstream checkout has no tracked changes.
- An isolated build copy contains a recorded 12-file branding change for Kazuha names, metadata, logo, and matching test expectations.
- Logo SHA-256: `439008c31f463ebc85241bcdcc8d16a77a11fda70e4862a4408b3ce8434f1ca7`.
- Branding change SHA-256: `f3d239f16f0091f19b20e6e52cb56a8fb991da6eaa29ffad936a96c0bdca0735`.
- Release build: .NET SDK **10.0.402**, bundled runtime **10.0.13**, self-contained `win-x64`.
- Production assembly metadata identifies Kazuha and `UpdateChannel=managed`. Internal `composa.exe` and assembly names remain compatible with upstream.
- **216 selected tests passed, zero failed:** 140 updater/application/path tests and 76 rendering, compositing, editing, history, and text tests. Test builds use the upstream GitHub channel to exercise updater code; the production managed-channel metadata was checked separately. This is not the full upstream test suite.
- Native payload checks confirmed the Kazuha title and icon, opened and rendered `Kazuha Make Space.cmps`, and displayed the manual managed-update message with no release download offered. The [editor screenshot](store/assets/kazuha-editor.png) records that native application view. These were payload smoke checks, not an installed Kazuha package test or a complete native editing test.

## Kazuha packages

Both package builds checked all **244 application files** against source-build provenance and used Windows SDK MakeAppx validation.

| Package | Result |
| --- | --- |
| GitHub sideload: `Local.Kazuha.Windows`, version `1.4.0.0`, x64 | Signed with a local development certificate; bundle and signature verification passed |
| Microsoft Store: `Fuh.Kazuha`, version `1.4.0.0`, x64 | Unsigned Store upload package; identity, payload, and absence of local certificate helpers checked |
| Minimum Windows version | `10.0.19041.0` |

Sideload verification checked seven bundle files, 253 package files, 3,179 content blocks, and 244 application files totaling 198,621,616 bytes. CMS signature mathematics, signed block-map/content-type hashes, certificate/publisher matching, and the package identity passed. Verification did not install the package or modify a certificate store.

```text
767bfde58fda349909adf9391b0f304849ffd577236a313fc31a2410881839a3  Kazuha-1.4.0-x64.msix
a231c1e05d685706353e78e3b89b3ccf56a00767739c08f23c8e23bd37471d17  Fuh.Kazuha_1.4.0.0_x64_Store.msix
```

The Store package upload passed portal package validation and was saved in the draft, with Packages marked complete. `runFullTrust` requires Microsoft's approval. This is not Store certification or publication.

**Not yet established:** installed Kazuha workflow results, Windows App Certification Kit results, Microsoft Store certification, or Store availability. Earlier installed-Composa tests below do not establish those results for Kazuha.

## Historical Composa package

The earlier `Local.Composa.Windows` package used the unmodified upstream Composa 1.4.0 binary. Its download/payload hashes, package structure, signature, installation, Start registration, and running MSIX identity were verified. Windows reported that installed package as **Ok**.

Eight automated installed workflow groups passed:

1. Application startup and test connection.
2. Layer compositing checked against exact colors.
3. Layer opacity and undo.
4. Transform, duplication, painting, and editable text.
5. Project save/reopen and pixel-identical PNG export.
6. PNG import, blur, exposure, and pixel-identical undo.
7. Bundled subject detection, including model hash and installed ONNX runtime checks.
8. Creation and export of an editable 1400 × 900 demonstration project.

Native UI checks also covered opening a project, layer duplication, undo, and redo. Temporary AI-control settings were restored byte-for-byte. These results belong to the historical Composa package only.

## Evidence and scope

Verification scripts are in `tests/`. Generated source-build provenance, Store build reports, and sideload integrity reports record the checks above. Raw logs, diagnostic screenshots, paths, settings backups, and local installation records are excluded from Git; the sanitized Store listing screenshot is included. No complete upstream-suite run or Microsoft certification is claimed. Rebuilt signed packages use fresh certificates and hashes and require their own verification.
