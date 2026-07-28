# Third-Party Notices

## CitroLabs ego-lite / ego-browser

Oriel includes and modifies the open-source `ego-browser` runtime from
CitroLabs' `ego-lite` repository.

- Source: https://github.com/citrolabs/ego-lite
- License: MIT
- Copyright: Copyright (c) 2026 CitroLabs

The full MIT license text is preserved in `LICENSE` and in the macOS
application bundle.

## Node.js

The macOS application bundles an official Node.js binary.

- Source: https://nodejs.org/
- License information: https://github.com/nodejs/node/blob/main/LICENSE

The Node.js distribution license is copied into the application bundle during
the build.

## Playwright and other npm dependencies

Development and testing may use packages declared under
`package/ego-browser/package.json` and their own license terms. These packages
are not copied into the lightweight macOS control-center runtime unless they
are present in the packaged runtime output.

## Space Grotesk

Oriel uses the Space Grotesk typeface for its product wordmark.

- Source: https://github.com/google/fonts/tree/main/ofl/spacegrotesk
- License: SIL Open Font License 1.1
- Copyright: Copyright 2020 The Space Grotesk Project Authors

The full license text is included in the macOS application bundle.
