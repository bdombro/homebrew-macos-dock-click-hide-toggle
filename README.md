# Dock Click-to-Hide for macOS

**Click to show. Click again to hide.**

Clear an app out of the way with the same Dock icon you used to open it.
No need to reach for **Cmd+H** or minimize its windows one by one.

- **Click the frontmost app's icon:** hide the app and its windows without quitting.
- **Click another app's icon:** open or switch to it as usual, including bringing
  a hidden app back.
- **Keep your usual gestures:** modified clicks and drags retain their normal behavior.

A small native Swift utility runs in the background. Once set up, you can leave
the terminal behind.

![Dock click-to-hide in action](macos-dock-click-hide-toggle.gif)

## Quick setup

You need an **Apple Silicon Mac**, **macOS 13 (Ventura) or later**, and
[Homebrew](https://brew.sh). No source checkout, Bun, or build tools are needed
to install the release. Native Dock/permission behavior has not been
runtime-tested on macOS 13.

> **Before installing:** releases are Apple Development-signed, but **not
> notarized**. macOS or your organization's security policy may block them.
> Install only if you trust the software; Homebrew does not bypass those controls.

### 1. Install

Run this command in Terminal:

```sh
brew install bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
```

Installation alone does **not** start the utility. No GitHub sign-in is needed.

### 2. Start the background service

When you are ready to enable click-to-hide, run the following as your signed-in
macOS user, **never with `sudo`**. This starts the utility now and at login:

```sh
brew services start bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
```

### 3. Allow Accessibility access

The utility needs Accessibility access to recognize Dock clicks and hide apps.
Approval is manual on each Mac; installing or signing the executable cannot
grant it.

1. Open **System Settings > Privacy & Security > Accessibility** (called
   **Device Control and Data Access** on some versions).
2. Enable `macos-dock-click-hide-toggle` if it is listed. Otherwise, click **+** and add:

   ```sh
   /opt/homebrew/opt/macos-dock-click-hide-toggle/bin/macos-dock-click-hide-toggle
   ```

3. Add the executable and turn its permission on. Allow the **installed
   executable**, not just Terminal.

The service waits for approval without repeated prompts and continues once
access is granted.

**Try it:** bring an app to the front, then click its Dock icon. Its windows
should hide. Click the icon again to bring it back.

## Pause, update, or uninstall

### Pause click-to-hide

Restore normal Dock behavior and disable startup at login:

```sh
brew services stop bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
```

Use the [start command](#2-start-the-background-service) whenever you want to enable it again.

### Update

Stop the service before upgrading:

```sh
brew services stop bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
brew update
brew upgrade bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
```

The service remains stopped. When ready, [start it again](#2-start-the-background-service)
and check Accessibility access; updates or path changes may require renewed approval.

### Uninstall

No source checkout is required:

```sh
brew services stop bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
brew uninstall bdombro/macos-dock-click-hide-toggle/macos-dock-click-hide-toggle
brew untap bdombro/macos-dock-click-hide-toggle
```

Logs are preserved.

## Troubleshooting

- **Clicking does nothing:** check `brew services list`, then verify
  [Accessibility access](#3-allow-accessibility-access) for the installed executable.
  Test with an ordinary click on the **frontmost** app's icon, not a modified
  click or a drag.
- **macOS blocks the executable:** a valid signature does not guarantee
  Gatekeeper acceptance. Releases use Apple Development signing, not Developer
  ID Application signing, and are not notarized. Use normal macOS approval
  controls only for software you trust; managed policy may prevent execution.
- **It stopped working after an update:** recheck the Accessibility entry.
  The same signing identity helps preserve approval but does not guarantee it.
- **Input behaves unexpectedly:** [stop the service](#pause-click-to-hide)
  before investigating. Accessibility approval alone does not resolve every
  event-tap or security-policy issue.

To inspect recent startup and permission messages:

```sh
tail -n 50 "$(brew --prefix)/var/log/macos-dock-click-hide-toggle.log"
```

## Development and releases

<details>
<summary>Build from source, work on the utility, or publish a release</summary>

### Local development: Homebrew, not a second installer

Requires Bun, just, Homebrew, Xcode command-line tools and a valid code-signing
identity. The Swift runtime has no third-party dependencies.

```sh
bun install
just build                          # build/sign only; never installs or starts
build/bin/macos-dock-click-hide-toggle --help
build/bin/macos-dock-click-hide-toggle --version
just install-local                  # also: just install
just reinstall-local                # also: just reinstall
just test-release                   # install/test checked-in public release formula
just install-production             # switch back to the public remote tap
just uninstall                      # stop/remove Homebrew keg and this tap
```

`just install-production` first stops/removes the existing Homebrew installation
and tap (including a local symlink tap), then installs the public formula from
the explicit repository URL. No GitHub authentication is needed.

`install-local` stops/removes the old keg and untaps before creating a source
symlink in Homebrew's standard tap directory. It builds the native binary,
backs up the release formula, stages a `file://` development formula and installs
with Homebrew. An EXIT trap restores the exact original formula even if brew
fails. An unresolved backup is never overwritten: inspect it and run
`bun scripts/dev-formula.ts reset` before trying again. Staging is ignored by Git.
Tap removal delegates to `brew untap` without custom origin or working-tree
checks. Source symlink creation refuses any existing path, including a
dangling symlink.

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

The service runs `macos-dock-click-hide-toggle start`. Homebrew's generated
session types include Aqua but are not Aqua-only.

### Releases (maintainers)

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
origin, a branch and an unused local/remote tag. It builds/signs and checks the
embedded version, creates
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

#### Adaptations from the argsbarg Homebrew example

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

</details>

## License

[ISC](LICENSE).
