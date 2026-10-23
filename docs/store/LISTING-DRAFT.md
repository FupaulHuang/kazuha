# Kazuha — Microsoft Store listing draft

Prepared 23 October 2026. This is draft content for a free English listing. **Kazuha** is the reserved Store name for product **9N327XKWB7L5**. The Store package was built from pinned Composa source with Kazuha UI branding, a minimal maple-leaf logo with an autumn gradient and one wind curve, and the existing `UpdateChannel=managed` setting. The source build passed 216 selected tests; the unsigned package passed payload checks and Partner Center upload validation and was saved in the draft. Native payload checks confirmed the title, icon, sample rendering, and managed-update message. Installed-package testing, Windows App Certification Kit results, Store certification, and publication remain unestablished.

## Proposed listing fields

| Field | Draft value |
| --- | --- |
| Product name | Kazuha |
| Store product ID | 9N327XKWB7L5 |
| Package identity name | Fuh.Kazuha |
| Package publisher | CN=06B7220A-0F66-4D34-82F8-853BDEDBC011 |
| Publisher display name | Fuh |
| Package version and architecture | 1.4.0.0, x64 |
| Minimum Windows version | Windows 10 build 19041 |
| Language | English (United States) |
| Price | Free |
| Category | Photo & video; use Multimedia design if that better matches the available category choices |
| Support URL | https://github.com/FupaulHuang/kazuha/issues |
| Website | https://github.com/FupaulHuang/kazuha |
| Privacy policy URL | https://github.com/FupaulHuang/kazuha/blob/main/docs/store/PRIVACY.md |
| Search keywords | photo editor; image editor; layers; compositing; retouching; background removal; image filters |

### Short description

Layer-based photo editing, compositing, and retouching with local subject detection.

### Full description

Kazuha is an independently maintained Windows image editor based on the open-source Composa application. Combine images with layers and masks, retouch photos, paint, add editable text and shapes, and refine the result with color adjustments and filters.

Keep your work editable in the layered .cmps project format, then export finished images as PNG, JPEG, or WebP. Bundled subject detection runs on your PC. Core editing works without an internet connection or an application account.

For optional automation, Help > Allow AI Control enables a local Model Context Protocol (MCP) connection for a compatible client. This feature is off by default. A connected client can inspect and edit documents; how it handles document content depends on that client's provider and settings.

The original reference is Compositor by Robbie Tilton. Kazuha is based on Composa by Dennis van der Stelt, with independent branding and packaging. It is not an official release from either upstream project. Its .cmps files are not compatible with Compositor's macOS .comp projects.

Updates for this Store version are managed through Microsoft Store. The application does not automatically check GitHub for upstream updates or offer GitHub release downloads; its update menu directs you to the package manager. See the privacy policy for local storage and optional AI-client access.

### Features

- Arrange images with layers, groups, masks, blend modes, and layer effects.
- Paint, erase, select, crop, and transform image content.
- Add editable text and vector shapes.
- Adjust color and apply filters, including Camera Raw controls.
- Use bundled subject detection locally on your PC.
- Save layered .cmps projects and export PNG, JPEG, and WebP images.
- Undo and redo edits; recover available autosaved work after an unexpected exit.
- Optionally connect a compatible MCP client through a local, same-user connection.

### Copyright and attribution

Composa: Copyright (c) 2026 Dennis van der Stelt, MIT License. Portions of the image-processing math follow Compositor: Copyright (c) 2026 Wonder Assembly LLC, MIT License. Original reference: [Compositor by Robbie Tilton](https://github.com/robbietilton/Compositor). Windows implementation: [Composa](https://github.com/dvdstelt/Composa). Community packaging additions: Copyright (c) 2026 Kazuha packaging contributors, MIT License. Third-party libraries and models retain their own licenses and included notices.

### Release notes

Initial Kazuha Store package for Windows x64, based on Composa 1.4.0 with Kazuha UI branding, a maple-leaf logo, and the existing upstream managed update channel. Includes the image editor, its runtime, bundled image libraries and local models. Kazuha work adds branding, packaging, installation metadata, and verification. No new editing features or upstream authorship are claimed.

## Restricted capability explanation: runFullTrust

Kazuha runs a Windows desktop executable based on Composa, built with .NET and Avalonia. It needs full-trust desktop execution to run that executable and its native graphics, image-decoding, and ONNX inference libraries, open and save user-selected image/project files with normal desktop file dialogs, and optionally communicate with a user-enabled MCP client over a same-user named pipe. The editor operates with the signed-in user's ordinary permissions; editing does not require administrator elevation. It does not install a background service, driver, or scheduled task. The local certificate trust helper belongs to the separate GitHub sideload bundle and is absent from the Store package.

## Certification test notes

No application account, subscription, or test credentials are required. Test with disposable images and a writable test folder. Confirm the final application identifies itself as **Kazuha** and uses the minimal maple-leaf logo with a natural autumn gradient, three essential vein strokes, and one wind curve.

1. Launch the installed Store-bound package from Start. Confirm the main editor opens without elevation or a sign-in prompt.
2. Create a small document, add a shape and editable text, and paint on a new layer. Confirm layers are visible and changes appear on the canvas.
3. Change layer opacity or position, duplicate a layer, then use Ctrl+Z and Ctrl+Shift+Z to verify undo and redo.
4. Save as a .cmps project in the test folder. Close and reopen it with Ctrl+O; confirm the layers and text remain editable.
5. Export a PNG, reopen it, apply an exposure adjustment or blur, and undo the change. Confirm the export is readable.
6. With a suitable photo, test subject selection or background removal using the bundled model. Repeat with internet disconnected to confirm local inference; model output depends on the image.
7. Inspect Help > Allow AI Control. It is off on a fresh profile. Optional MCP testing requires a separately configured compatible client; after enabling it, connect through the local bridge, inspect or edit only the disposable test document, then disable it.
8. With network access, launch the Store-bound build and inspect Help > Check for Updates. Confirm it displays the managed-update message directing the user to the package manager. Confirm no GitHub release download is offered and no automatic GitHub update request is made by this build.
9. Close and relaunch normally. Confirm the application exits and saved projects reopen. Uninstall through Windows Settings and confirm the app registration is removed; user-saved files are not test cleanup targets.

The [verification summary](../VERIFICATION.md) records Kazuha source tests, package and identity checks, and native payload smoke checks separately from the historical installed-Composa results. The steps above are certification instructions, not a claim that installed-Kazuha workflows have passed. The current native editor screenshot is [kazuha-editor.png](assets/kazuha-editor.png). No Windows App Certification Kit or Microsoft Store certification result is claimed.

## Source evidence for privacy and behavior

Reviewed Composa upstream commit: `86529d3b5355d28ddc28ec3db2e4de1d4d00f63b`. The references below document upstream behavior. The [branding preparation script](../../packaging/Prepare-KazuhaSource.ps1) records Kazuha's name/icon changes; the [managed build script](../../packaging/Build-ManagedApp.ps1) selects the existing managed update channel. The resulting production metadata and Kazuha data-path tests were checked.

| Behavior | Source at the reviewed commit |
| --- | --- |
| Preferences, recent file paths, AI control off; update preference defaults on but is gated by the build's update channel | [Settings.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/Settings.cs) |
| Windows settings/cache/download folders | [AppPaths.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/AppPaths.cs) |
| Recovery copies and associated metadata | [Recovery.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/Recovery.cs) |
| Build metadata and managed-channel gate; GitHub endpoint, headers, and 24-hour interval retained only by the legacy Composa sideload build | [Composa.App.csproj](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/Composa.App.csproj), [UpdateCheck.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/UpdateCheck.cs) |
| Managed build's manual-check message and exclusion of downloadable assets | [MainWindow.Updates.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/MainWindow.Updates.cs), [ReleaseAssets.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/ReleaseAssets.cs) |
| User-triggered release/checksum downloads retained only by the legacy Composa sideload build | [UpdateDownload.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/UpdateDownload.cs) |
| Same-user pipe and optional MCP access | [McpHost.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/Mcp/McpHost.cs), [MCP file tools](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.App/Mcp/ComposaTools.Files.cs) |
| Local model files, no runtime model download, CPU inference | [OnnxModel.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.Core/Vision/OnnxModel.cs), [ModelRunner.cs](https://github.com/dvdstelt/Composa/blob/86529d3b5355d28ddc28ec3db2e4de1d4d00f63b/src/Composa.Core/Vision/ModelRunner.cs) |

A search of `src` for HTTP/network clients and URLs located the update client and model provenance URLs. The managed channel prevents both current Kazuha builds from initiating the upstream update flow; only the legacy Composa-branded release retains that flow. The model URLs are catalog metadata; the model loader reads local files. No application analytics/upload endpoint was identified by that source search. This is not a claim about every native dependency or operating-system diagnostic mechanism.

## Inputs still requiring confirmation

- Installed-Kazuha workflow testing, Windows App Certification Kit results, and Microsoft's certification and restricted-capability approval. Source tests and upload validation do not supply those results.
- Final listing text, category selection, screenshot/logo acceptance, and any additional device-family requirements in the portal.
- Age-rating questionnaire answers, markets, release timing, and any identity, tax, or compliance declarations requested by the account. These must not be inferred from the editor's feature list.
- Confirmation that the repository's issue tracker is the support/privacy contact the maintainer will monitor.

The package identity, x64 architecture, minimum Windows version, Kazuha UI/logo, runtime paths, and production managed-update metadata are now verified. Submission options include the `runFullTrust` explanation and a hold for manual publication. These draft settings do not establish certification or Store availability.
