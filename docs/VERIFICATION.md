# Verification summary

Composa 1.4.0 and its local MSIX package were checked on **23 October 2026**, on **Windows 11 25H2, build 26200, x64**. This is a summary of that local verification run, not a guarantee for every Windows configuration.

## Package and installation

- The downloaded archive matched the pinned upstream SHA-256; extracted application files matched the archive.
- Windows SDK MakeAppx completed its normal package validation, and SignTool signed the package with the generated local development certificate.
- Independent checks passed for bundle checksums, package content blocks, signature mathematics, signed metadata hashes, certificate/publisher matching, manifest entry point, and icon sizes.
- No private-key files remained in the build or distribution trees.
- Windows reported the installed `Local.Composa.Windows` package as **Ok**, with its Start menu entry registered.
- The running application's MSIX identity and ownership of the local test connection were verified before installed workflow testing.

## Installed application workflows

All eight automated workflow groups passed against the installed application:

1. Application startup and test connection.
2. Layer compositing checked against exact colors.
3. Layer opacity and undo.
4. Transform, duplication, painting, and editable text.
5. Project save/reopen and pixel-identical PNG export.
6. PNG import, blur, exposure, and pixel-identical undo.
7. Bundled subject detection: model hash verification, ONNX runtime loaded from the installed package, and model output distinguished from the plain-background fallback.
8. Creation and PNG export of an editable 1400 × 900 demonstration project.

Native Windows interface checks also passed: opening a saved project with **Ctrl+O** and the file picker, duplicating a layer with **Ctrl+J**, undoing with **Ctrl+Z**, and redoing with **Ctrl+Shift+Z**. A final undo returned the document to its saved state.

The automated run temporarily enabled the application's local AI-control interface. The prior settings were restored byte-for-byte afterward, and the application was relaunched with AI control off. Test documents were generated separately from user projects.

## Scope

These checks cover the listed workflows, package structure, signature integrity, and a local Windows installation. The upstream application binaries were unmodified. The full upstream unit-test suite was not rebuilt or run, and Microsoft Store certification is not claimed.

The `tests/` directory contains the verification scripts. Raw local logs, screenshots, test documents, certificate identifiers, and machine-specific installation records are excluded from Git. New builds use fresh local certificates and should be verified and installed on their intended target systems.
