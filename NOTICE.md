# Kazuha attribution

The original reference for this project is **[Compositor by Robbie Tilton](https://github.com/robbietilton/Compositor)**.

Kazuha is based on **[Composa by Dennis van der Stelt](https://github.com/dvdstelt/Composa)**. This repository adds Kazuha branding, Windows packaging, installation, and verification work. The historical MSIX release packages the unmodified Composa 1.4.0 portable application and retains its Composa names. The current Kazuha sideload and Store packages are built from the pinned upstream source with recorded Kazuha branding and the existing managed update channel. Kazuha is independently maintained and does not claim authorship of the upstream editor.

The root MIT license covers this repository's additions. The upstream source submodule and downloaded application retain their own licenses and notices, including:

- Composa: Copyright (c) 2026 Dennis van der Stelt, MIT License.
- Portions derived from Compositor's image-processing math: Copyright (c) 2026 Wonder Assembly LLC, MIT License, as acknowledged in Composa's license.
- Dependencies and bundled model: see the upstream third-party and model notices preserved in the application package.

The upstream source is pinned to commit `86529d3b5355d28ddc28ec3db2e4de1d4d00f63b`. Packaging retains the upstream license and third-party notices; this repository's license does not replace them.
