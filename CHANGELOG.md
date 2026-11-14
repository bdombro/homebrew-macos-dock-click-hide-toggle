# Changelog

All notable changes are documented here, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-11-14

### Changed

- Rename the repository to `bdombro/homebrew-macos-dock-click-hide-toggle` so
  Homebrew installs work without an explicit repository URL.

## [0.1.3] - 2026-11-13

### Changed

- Replace private-copy installation with Homebrew-only local and production
  workflows; installs and rebuilds leave the service stopped.
- Share local/release formula rendering and simplify release tooling using the
  argsbarg Homebrew example.

## [0.1.2] - 2026-11-13

### Changed

## [0.1.1] - 2026-11-13

### Added

- `--version` prints the version embedded in the executable at build time.
- Help lists the version and help flags, including `-h`.
- Build, local install/uninstall and release scripts use Python 3.9+ with no
  third-party Python dependencies.

## [0.1.0] - 2026-11-13

### Added

- Initial public Apple Silicon build targeting macOS 13 and later.
- Hide the frontmost app by clicking its Dock icon; preserve normal activation,
  modified clicks and drags.
- Per-Mac Accessibility consent with a background wait for approval.
- Same-repository Homebrew formula and opt-in login service.
- Signed local builds, standalone local install/uninstall scripts and release tooling.

### Security

- Initial binaries use Apple Development signing and are **not notarized**.
  Gatekeeper or managed security policy may block downloaded binaries.
