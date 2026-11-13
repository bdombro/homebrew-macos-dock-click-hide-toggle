# Dock Click-to-Hide for macOS

**Click to show. Click again to hide.**

Click an already frontmost application's Dock icon to hide it. Other app
activation, modified clicks and drags retain their normal behavior.

![preview](macos-dock-click-hide-toggle.gif)

## Requirements and distribution limits

- **Apple Silicon; macOS 13 (Ventura) or later.** Native Dock/permission behavior
  has not been runtime-tested on macOS 13.
- Releases use **Apple Development signing**, not Developer ID Application,
  and are **not notarized**. A valid signature does not guarantee Gatekeeper
  acceptance. Quarantine or managed policy may block execution. Homebrew is not
  a security-policy bypass; use normal macOS approval controls for software you trust.
- Each Mac needs manual Accessibility approval. Signing never grants consent.

## Production installation

All installations use the same Homebrew formula and service. Installing does
**not** start the service. This repository contains its own `Formula/`; its name
does not start with `homebrew-`, so the explicit repository URL is necessary:

```sh
brew tap bdombro/macos-dock-click-hide-toggle https://github.com/bdombro/macos-dock-click-hide-toggle.git
brew install bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
```

From a source checkout, `just install-production` first stops/removes the
existing Homebrew installation and tap (including a local symlink tap), then
installs the public formula from that URL. No GitHub authentication is needed.

### Optional service startup and Accessibility

Keep the service stopped while investigating input/event-tap problems. Only
when you choose to run it, use this **manual opt-in**, as your logged-in graphical
user, never with `sudo`:

```sh
brew services start bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
```

The service runs `macos-dock-click-hide-toggle start`. Homebrew's generated
session types include Aqua but are not Aqua-only.

Open **System Settings > Privacy & Security > Accessibility** (called **Device
Control and Data Access** on some versions). Allow the installed executable,
not merely your terminal. Use **+**, then **Cmd+Shift+G**, and enter:

```sh
echo "$(brew --prefix)/opt/macos-dock-click-hide-toggle/bin/macos-dock-click-hide-toggle"
```

The service waits for approval without repeated prompts. Permission is not a
guarantee that every event-tap/security-policy problem is resolved. Updates or
path changes may require renewed approval even with the same signing identity.
Logs are at `$(brew --prefix)/var/log/macos-dock-click-hide-toggle.log`.

### Update and remove

```sh
brew services stop bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
brew update
brew upgrade bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
# Remains stopped; start manually only when desired.

# Or remove the installation and tap, preserving logs:
just uninstall
```

Without a checkout, stop the service as above, then use `brew uninstall
bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle` and
`brew untap bdombro/macos-dock-click-hide-toggle`.

### Legacy private-copy migration

The old installer is removed. `just uninstall` now removes **only Homebrew**.
Before starting Homebrew's service, manually stop/disable any legacy
`local.macos-dock-click-hide-toggle` LaunchAgent and remove its plist at
`~/Library/LaunchAgents/local.macos-dock-click-hide-toggle.plist` and executable at
`~/.local/share/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle`.
Preserve `~/.local/share/macos-dock-click-hide-toggle/daemon.log`.
Do not run two daemons: both would intercept Dock clicks. There is deliberately
no permanent migration tool or automatic service startup.

## Local development: Homebrew, not a second installer

Requires Bun, just, Homebrew, Xcode command-line tools and a valid code-signing
identity. The Swift runtime has no third-party dependencies.

```sh
bun install
just scripts-typecheck
just build                          # build/sign only; never installs or starts
build/bin/macos-dock-click-hide-toggle --help
build/bin/macos-dock-click-hide-toggle --version
just install-local                  # also: just install
just reinstall-local                # also: just reinstall
just test-release                   # install/test checked-in public release formula
just install-production             # switch back to the public remote tap
just uninstall                      # stop/remove Homebrew keg and this tap
```

`install-local` stops/removes the old keg and untaps before creating a source
symlink in Homebrew's standard tap directory. It builds the native binary,
backs up the release formula, stages a `file://` development formula and installs
with Homebrew. An EXIT trap restores the exact original formula even if brew
fails. An unresolved backup is never overwritten: inspect it and run
`bun scripts/dev-formula.ts reset` before trying again. Staging is ignored by Git.
Unknown existing tap paths are not recursively deleted or replaced.
Before stopping/removing an installation, recipes require any existing tap to
be either a symlink resolving to this checkout or a clean Git checkout rooted
at the physical tap path with this project's authorized public origin.
Unknown, dangling, foreign or modified tap paths are rejected. Source symlink
creation also refuses any existing path, including a dangling symlink.

`reinstall-local` requires this checkout's symlink tap and installed keg. It
stops the service, rebuilds and replaces only the Homebrew executable in the
Cellar. There is no private executable copy or separate local service.
Every install/reinstall leaves the service stopped.

Build output is `build/bin/macos-dock-click-hide-toggle`. `VERSION` is canonical;
release builds use `APP_VERSION` to embed the target version before updating
metadata. Signing chooses automatically only when exactly one valid Apple
Development, Mac Developer or Developer ID Application identity exists.
Otherwise set `CODE_SIGN_IDENTITY` locally; never commit credentials.
Ad-hoc signing is rejected. The stable signing identifier is
`local.macos-dock-click-hide-toggle`; using the same identity helps preserve
approval without guarantees. Signing diagnostics do not disclose the identity.

For intentional foreground troubleshooting, stop all installed services first,
then run `build/bin/macos-dock-click-hide-toggle start`; stop with **Ctrl+C**.
Foreground use may attribute permission to your terminal. Packaging changes do
not change the native runtime.

## Releases (maintainers)

Add notes beneath `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
The pipeline uses Bun, just, Git, Ruby, zip, Apple build/signing tools and
authenticated `gh`:

```sh
just release patch --dry-run         # no file/Git/network mutations
just release patch --prepare --yes   # local preparation only; no commit/push/release
just release minor                   # asks before commit/tag/push/publication
# major and --yes are also supported
```

Publishing accepts a dirty working tree and requires the correct public
origin, a branch and an unused local/remote tag. It typechecks,
builds/signs and checks the embedded version, creates
`build/bin/macos-dock-click-hide-toggle.zip`, syntax-checks the shared public
formula, updates VERSION/changelog/formula, runs `git add -A` and commits all
non-ignored changes across the repository (including existing edits, new files
and deletions, with a coauthor trailer), tags, atomically pushes branch/tag,
then creates a public release. Review all changes before releasing.
`--yes` does not bypass keychain/OS approval.

`--prepare` performs the same local build/metadata work without publication;
it always bumps. Review prepared files; it is not a publish-resume command.
Failures are not force-retried or rolled back: inspect local files, tags and
remote state before recovery. If publication fails after push, publish the
exact existing archive with `gh release create --verify-tag`; do not overwrite
published assets. Older assets are never deleted.

### Adaptations from the argsbarg Homebrew example

- Reuse its `formula-shared.ts` render/archive helpers, `dev-formula.ts`
  backup/stage/reset flow, typed release functions and local/production recipes.
- Keep native Swift arm64/macOS 13 build/signing and canonical VERSION instead
  of Bun compilation and a source version literal; use `build/bin`, ISC and
  the existing daemon service. Formula tests use `--help`/`--version`; there
  are no completions or invented runtime tests.
- Use public HTTPS assets without a private download strategy. New releases
  use the example's zip layout; the checked-in v0.1.2 tar URL/hash remain valid
  until the next real release. No purge option or old-asset deletion.
- Replace permissive example fallbacks with explicit installed/tap queries,
  stopped-service replacement and failure-safe formula restoration. Keep
  `--prepare` for local verification; remove explicit version arguments in
  favor of the example's simpler `major|minor|patch` interface.

## License

[ISC](LICENSE).
