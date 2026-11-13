#!/usr/bin/env bun
/** Build and sign the Apple Silicon executable without installing it. */
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { cli, command, fail, NAME, ROOT, VERSION_PATTERN, writePlist } from "./common.ts";

/** Compile arm64/macOS 13 Swift from stdin with embedded version plist metadata. */
function build(source: string, output: string, metadata: string, version: string): void {
  writePlist(metadata, { CFBundleShortVersionString: version });
  const result = command([
    "/usr/bin/xcrun", "swiftc", "-O", "-target", "arm64-apple-macosx13.0",
    "-module-name", "MacOSDockClickHideToggle", "-o", output,
    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
    "-Xlinker", "__info_plist", "-Xlinker", metadata, "-",
  ], { input: readFileSync(source) });
  if (result.status) fail("Swift compilation failed.", result.status);
  chmodSync(output, 0o755);
}

/** Select exactly one identity unless explicit; sign and verify without exposing it. */
function sign(output: string): void {
  let identity = process.env.CODE_SIGN_IDENTITY ?? "";
  if (!identity) {
    const result = command(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"], { capture: true });
    if (result.status) fail("Cannot inspect code-signing identities; check the local keychain.", result.status);
    const identities = [...result.stdout.matchAll(/^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(?:Apple Development|Mac Developer|Developer ID Application):/gm)];
    if (identities.length !== 1) {
      fail(`Found ${identities.length} valid Apple code-signing identities. Set CODE_SIGN_IDENTITY to select one.`);
    }
    identity = identities[0]?.[1] ?? "";
  }
  if (identity === "-") fail("Ad-hoc signing is not supported because it cannot preserve approval across builds.");
  const result = command(["/usr/bin/codesign", "--force", "--sign", identity, "--identifier", `local.${NAME}`, output], { capture: true });
  if (result.status) fail("Code signing failed. Check the selected identity and key access locally.", result.status);
  const verification = command(["/usr/bin/codesign", "--verify", "--strict", output], { capture: true });
  if (verification.status) fail("Code signature verification failed.", verification.status);
}

/** Build and sign in same-filesystem staging, replacing output only after success. */
function main(): void {
  const args = process.argv.slice(2);
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
    console.log(`Usage: scripts/build.ts

Build and sign build/bin/${NAME} (arm64, macOS 13+).
Does not install or restart the app. Requires Xcode command-line tools.
Set CODE_SIGN_IDENTITY to select an identity; otherwise exactly one valid
Apple Development, Mac Developer, or Developer ID Application identity is required.
The version comes from VERSION; APP_VERSION overrides it for release builds.`);
    return;
  }
  if (args.length) fail("Usage: scripts/build.ts");
  const version = process.env.APP_VERSION ?? readFileSync(join(ROOT, "VERSION"), "utf8").replace(/\r\n?/g, "\n").replace(/\n+$/, "");
  if (!VERSION_PATTERN.test(version)) fail("Build version must be numeric X.Y.Z (components <= 999999).");
  const directory = join(ROOT, "build", "bin");
  mkdirSync(directory, { recursive: true });
  const staging = mkdtempSync(join(directory, ".build."));
  try {
    const output = join(staging, NAME);
    build(join(ROOT, `${NAME}.swift`), output, join(staging, "Info.plist"), version);
    sign(output); // Comment out this call only for a local unsigned build.
    renameSync(output, join(directory, NAME));
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
  const justfile = join(ROOT, "justfile");
  const quoted = /^[a-zA-Z0-9_/@%+=:,.-]+$/.test(justfile) ? justfile : `'${justfile.replaceAll("'", "'\"'\"'")}'`;
  console.log(`Built: ${join(directory, NAME)}\nInstall with: just --justfile ${quoted} install`);
}

if (import.meta.main) cli("Build", main);
