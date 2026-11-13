# Changelog

All notable changes are documented here, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
