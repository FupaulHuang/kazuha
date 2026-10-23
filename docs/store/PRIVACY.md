# Privacy policy for Kazuha

Last updated: 23 October 2026.

This policy describes **Kazuha 1.4.0**, built from Composa upstream source commit `86529d3b5355d28ddc28ec3db2e4de1d4d00f63b` with recorded Kazuha branding. Both the current Kazuha GitHub sideload package and the Store upload package use the existing `UpdateChannel=managed` setting. The legacy Composa-branded release has different update behavior, explained below. The Store package has passed draft upload validation; Store availability and certification remain pending.

Kazuha is maintained through the [Kazuha repository](https://github.com/FupaulHuang/kazuha). The original reference is [Compositor by Robbie Tilton](https://github.com/robbietilton/Compositor); the upstream application is [Composa by Dennis van der Stelt](https://github.com/dvdstelt/Composa).

## Images and projects

Image editing and the bundled ONNX subject-detection and enhancement models run on your computer. The model loader reads model files installed with the application and does not download models at runtime. An application account is not required to edit images.

The application reads images and projects you open and writes projects or exports to the paths you choose. Its editing and model-inference functions do not upload those documents to a community-operated service. Files placed in a cloud-synced folder or network location may be transferred by that storage service under its own settings and policies.

## Local settings and recovery copies

The application stores preferences, including window and panel layout, shortcuts, recent file paths, export choices, AI-control permission, and update-check state. The recent-files list can contain up to 12 paths. Kazuha uses `%APPDATA%\Kazuha\settings.json` on Windows; the legacy Composa application uses `%APPDATA%\Composa\settings.json`. Windows may redirect app data into a package-specific location for an MSIX installation.

While a document has unsaved changes, the application periodically writes local recovery copies, normally every two minutes. These can contain the document's image content, layers and text, together with its title, original path, saved time, and process identifier. Kazuha's recovery location is `%LOCALAPPDATA%\Kazuha\recovery`; the legacy Composa location is `%LOCALAPPDATA%\Composa\recovery`, both subject to Windows package redirection. Saving or deliberately closing a document removes its active recovery copy; copies left after an unexpected exit can be offered at the next launch and then recovered or discarded.

Saved projects and exports remain where you put them until you delete them. Preferences remain for reuse. If you use the legacy Composa sideload build's download feature, downloaded upstream releases remain in your Downloads folder. Windows controls how package data is retained or removed during reset and uninstall. To remove remaining local data, close the app first and remove only the settings, recovery copies, or downloaded files you no longer need. Deleting recovery copies removes the ability to recover that work. Files in synced storage and backups are also subject to those services' retention rules.

## Updates in current Kazuha builds

Both current Kazuha builds disable the application's automatic upstream GitHub update checks and release downloads. **Help > Check for Updates** displays a message referring to the package manager without contacting GitHub. Sideload users obtain later Kazuha versions manually from the project releases page. Microsoft Store manages Store-package delivery and updates under Microsoft's own services and policies. Browser downloads and Store services have their own network and privacy behavior.

## Updates in the legacy Composa GitHub sideload release

The legacy GitHub MSIX sideload release wraps the original Composa portable binaries and retains their Composa name. That build has automatic update checks enabled by default. At launch, it can make an HTTPS request to `https://api.github.com/repos/dvdstelt/Composa/releases/latest`, no more than once per 24 hours according to its saved check state. In that build you can turn automatic checks off through **Help > Check for Updates Automatically**. A manual **Help > Check for Updates** request can still contact GitHub.

The check sends the application identifier `Composa` in the HTTP User-Agent header and requests GitHub's release metadata. Its application code does not add your document content, file paths, account identity, installed version, or a persistent device identifier to that request. GitHub and the network services handling it can receive normal connection information such as your IP address, request time, headers, and requested URL.

When you choose **Download**, the application requests the selected upstream release file and its checksum list from GitHub and its download infrastructure, checks the downloaded file, and saves it in your Downloads folder. The requested asset name can identify the release version and platform you are downloading. Opening release notes or other external links uses your browser. These services have their own privacy policies. Upstream release downloads do not update this community MSIX package.

## Optional AI-client access

**Help > Allow AI Control** is off by default and remembers your choice between launches. When enabled, the application accepts Model Context Protocol (MCP) connections through a local Windows named pipe restricted to the current user account.

A connected client can receive document descriptions, layer names, text, rendered previews and tool results, and can issue supported editing, opening, saving, or exporting commands. File paths may be included in commands and responses. This connection is local, but the client you choose may send that information to an external AI provider or another service. Check that client's permissions, settings, and privacy policy before allowing it to access sensitive documents. Disable **Allow AI Control** to stop the application's MCP server.

## Diagnostics and third-party services

The community packaging adds no advertising or analytics collection. The reviewed application source contains HTTP requests for the upstream update functions described above; that update flow is disabled by the managed channel used for both current Kazuha builds and retained only in the legacy Composa sideload build. The application source does not implement a document-upload or automatic crash-report-upload service. Errors can appear in local console or diagnostic trace output, which may contain error details and paths. This statement concerns application-controlled behavior and does not describe every native runtime or Windows diagnostic mechanism.

Windows and Microsoft Store services, GitHub, external websites, storage providers, and any optional AI client have their own data practices. This policy does not govern those services or separate upstream distributions. Open-source licenses and upstream documentation describe software provenance and permissions; they do not replace the privacy policies of services you choose to use.

## Support and privacy contact

For a privacy question about this community package, open an issue at [the project issue tracker](https://github.com/FupaulHuang/kazuha/issues). GitHub issues are public. Do not post private images, project files, access tokens, personal information, or unredacted file paths. If sensitive details are needed, first ask for a private contact route without including those details.

Information you choose to submit in an issue, including your GitHub profile and message, is processed by GitHub and visible to people who can access that issue. The issue tracker is a support channel, not an in-app collection mechanism.

## Changes

This document will be updated when the community package's relevant behavior changes. Check the date above and the repository history for revisions.
