#!/usr/bin/env bun
/** Prepare local release artifacts or publish a versioned GitHub release. */
import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readSync, renameSync, rmSync, writeFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { cli, command, fail, NAME, ROOT, run, VERSION_PATTERN } from "./common.ts";

const REPO = `bdombro/${NAME}`;
interface Arguments { requested: string; options: Set<string> }
interface Release { current: string; target: string; changelog: string }

/** Print release modes and their command-line options. */
function usage(stderr = false): void {
  (stderr ? console.error : console.log)("Usage: scripts/release.ts <patch|minor|major|X.Y.Z> [--dry-run] [--prepare] [--yes]\n--prepare builds and updates local release files only; permits the current version.");
}

/** Return the requested version/bump and flags, rejecting unknown arguments. */
function parseArguments(args: string[]): Arguments | undefined {
  let requested: string | undefined;
  const options = new Set<string>();
  for (const arg of args) {
    if (arg === "--help" || arg === "-h") { usage(); return; }
    if (["--dry-run", "--prepare", "--yes"].includes(arg)) options.add(arg);
    else if (arg.startsWith("--")) { usage(true); fail(""); }
    else if (requested === undefined) requested = arg;
    else fail("Specify exactly one version or bump.");
  }
  if (requested === undefined) { usage(true); fail(""); }
  return { requested, options };
}

/** Validate bounded numeric versions, monotonic bumps, and changelog headings. */
function validateVersion(requested: string, prepare: boolean): Release {
  const current = readFileSync(join(ROOT, "VERSION"), "utf8").replace(/\r\n?/g, "\n").replace(/\n+$/, "");
  if (!VERSION_PATTERN.test(current)) fail("VERSION must contain a numeric X.Y.Z version (components <= 999999).");
  const components = current.split(".").map(Number);
  const index = ["major", "minor", "patch"].indexOf(requested);
  let target = requested;
  if (index >= 0) {
    components[index] = (components[index] ?? 0) + 1;
    for (let i = index + 1; i < 3; i++) components[i] = 0;
    target = components.join(".");
  }
  if (!VERSION_PATTERN.test(target)) fail("Invalid release version.");
  if (target === current) {
    if (!prepare) fail("Publishing requires a version newer than VERSION; use --prepare for initial artifacts.");
  } else {
    const old = current.split(".").map(Number);
    const next = target.split(".").map(Number);
    const different = next.findIndex((value, i) => value !== old[i]);
    if (different < 0 || (next[different] ?? 0) < (old[different] ?? 0)) fail("Release version must increase.");
  }
  const changelog = readFileSync(join(ROOT, "CHANGELOG.md"), "utf8").replace(/\r\n?/g, "\n");
  if (changelog.split(/\r?\n/).filter(line => line === "## [Unreleased]").length !== 1) fail("Expected one Unreleased heading.");
  if (target !== current && changelog.includes(`## [${target}]`)) fail("Target version already exists in CHANGELOG.md.");
  if (target === current && !changelog.includes(`## [${target}] - `)) fail("Current release needs dated changelog notes.");
  return { current, target, changelog };
}

/** Check clean Git state, public origin, unused local/remote tag and gh auth. */
function preflight(target: string): string {
  const top = run(["git", "rev-parse", "--show-toplevel"], { capture: true }).stdout.trim();
  if (realpathSync(top) !== realpathSync(ROOT)) fail("Run from the project Git repository.");
  if (run(["git", "status", "--porcelain", "--untracked-files=all"], { capture: true }).stdout) fail("Working tree must be clean, including untracked files.");
  const branch = run(["git", "symbolic-ref", "--quiet", "--short", "HEAD"], { capture: true }).stdout.trim();
  const origin = run(["git", "remote", "get-url", "origin"], { capture: true }).stdout.trim();
  if (![ `https://github.com/${REPO}`, `https://github.com/${REPO}.git`, `git@github.com:${REPO}.git` ].includes(origin)) fail("origin must point to the public project repository.");
  const tag = command(["git", "show-ref", "--verify", "--quiet", `refs/tags/v${target}`], { capture: true });
  if (tag.status === 0) fail("Tag already exists locally.");
  if (tag.status !== 1) fail("Cannot inspect local tag.", tag.status);
  if (run(["git", "ls-remote", "--tags", "origin", `refs/tags/v${target}`], { capture: true }).stdout) fail("Tag already exists remotely.");
  const auth = command(["gh", "auth", "status", "--hostname", "github.com"], { capture: true });
  if (auth.status) fail("Authenticate gh before publishing.", auth.status);
  return branch;
}

/** Confirm side effects interactively unless --yes was supplied. */
function confirm(target: string, prepare: boolean, yes: boolean): boolean {
  if (yes) return true;
  if (!process.stdin.isTTY) fail("Not a TTY; pass --yes to confirm.");
  const action = prepare ? "prepare local artifacts" : "commit, tag, push and publish";
  process.stdout.write(`Release v${target} (${action})? [y/N] `);
  const bytes: number[] = [];
  const byte = Buffer.alloc(1);
  while (readSync(0, byte, 0, 1, null) !== 0) {
    if (byte[0] === 10) break;
    bytes.push(byte[0] ?? 0);
  }
  const answer = Buffer.from(bytes).toString("utf8").replace(/\r$/, "");
  if (answer !== "y" && answer !== "Y") { console.log("Aborted."); return false; }
  return true;
}

/** Build a signed executable with APP_VERSION and check its public --version. */
function build(target: string): void {
  run([process.execPath, join(ROOT, "scripts", "build.ts")], { env: { ...process.env, APP_VERSION: target } });
  const version = run([join(ROOT, "build", "bin", NAME), "--version"], { capture: true }).stdout.replace(/\n+$/, "");
  if (version !== target) fail("Built executable version does not match release target.");
}

/** Promote Unreleased using a UTC date and return the exact target notes. */
function releaseNotes(changelog: string, current: string, target: string): { changelog: string; notes: string } {
  if (target !== current) {
    changelog = changelog.replace("## [Unreleased]\n", `## [Unreleased]\n\n## [${target}] - ${new Date().toISOString().slice(0, 10)}\n`);
  }
  let found = false;
  let notes = "";
  for (const line of changelog.match(/[^\n]*\n|[^\n]+$/g) ?? []) {
    if (line.startsWith("## ")) {
      if (found) break;
      found = line.startsWith(`## [${target}] - `);
      continue;
    }
    if (found) notes += line;
  }
  if (!notes.trim()) fail("Add release notes under Unreleased before bumping.");
  return { changelog, notes };
}

/** Archive only executable and license, excluding macOS metadata; return SHA-256. */
function archive(destination: string): string {
  run(["/usr/bin/tar", "--format", "ustar", "--no-xattrs", "-czf", destination,
    "-C", join(ROOT, "build", "bin"), NAME, "-C", ROOT, "LICENSE"],
  { env: { ...process.env, COPYFILE_DISABLE: "1" } });
  return createHash("sha256").update(readFileSync(destination)).digest("hex");
}

/** Render the public Homebrew formula for the exact release asset and hash. */
function formula(target: string, asset: string, digest: string): string {
  return `class MacosDockClickHideToggle < Formula
  desc "Click a frontmost application's Dock icon to hide it"
  homepage "https://github.com/${REPO}"
  url "https://github.com/${REPO}/releases/download/v${target}/${asset}"
  sha256 "${digest}"
  license "ISC"

  depends_on arch: :arm64
  depends_on :macos
  on_macos do
    depends_on macos: :ventura
  end

  def install
    bin.install "${NAME}"
  end

  service do
    run [opt_bin/"${NAME}", "start"]
    keep_alive successful_exit: false
    # Homebrew includes Aqua in its generated session types; use without sudo.
    working_dir var
    log_path var/"log/${NAME}.log"
    error_log_path var/"log/${NAME}.log"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/${NAME} --help")
    assert_equal version.to_s, shell_output("#{bin}/${NAME} --version").strip
  end
end
`;
}

/** Prepare signed artifacts, syntax-check formula and atomically replace each file. */
function prepare(release: Release, asset: string): void {
  const { current, target } = release;
  build(target);
  const { changelog, notes } = releaseNotes(release.changelog, current, target);
  const directory = join(ROOT, "build", "release");
  mkdirSync(directory, { recursive: true });
  mkdirSync(join(ROOT, "Formula"), { recursive: true });
  const staging = mkdtempSync(join(directory, ".prepare."));
  try {
    writeFileSync(join(staging, "VERSION"), `${target}\n`);
    writeFileSync(join(staging, "CHANGELOG.md"), changelog);
    writeFileSync(join(staging, "notes.md"), notes);
    const digest = archive(join(staging, asset));
    writeFileSync(join(staging, "formula.rb"), formula(target, asset, digest));
    run(["ruby", "-c", join(staging, "formula.rb")]);
    const replacements: [string, string][] = [
      [asset, join(directory, asset)],
      ["notes.md", join(directory, `${NAME}-${target}-notes.md`)],
      ["VERSION", join(ROOT, "VERSION")],
      ["CHANGELOG.md", join(ROOT, "CHANGELOG.md")],
      ["formula.rb", join(ROOT, "Formula", `${NAME}.rb`)],
    ];
    for (const [source, destination] of replacements) {
      const local = mkdtempSync(join(dirname(destination), ".release."));
      try {
        const temporary = join(local, "replacement");
        writeFileSync(temporary, readFileSync(join(staging, source)));
        chmodSync(temporary, 0o644);
        renameSync(temporary, destination);
      } finally { rmSync(local, { recursive: true, force: true }); }
    }
    console.log(`Prepared build/release/${asset}\nSHA-256: ${digest}`);
  } finally { rmSync(staging, { recursive: true, force: true }); }
}

/** Commit scoped metadata, tag, atomically push branch/tag, then publish the asset. */
function publish(target: string, branch: string, asset: string): void {
  console.log("Committing release metadata.");
  run(["git", "add", "--", "VERSION", "CHANGELOG.md", `Formula/${NAME}.rb`]);
  run(["git", "commit", "-m", `chore: release v${target}`, "-m", "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"]);
  console.log("Tagging release.");
  run(["git", "tag", "-a", `v${target}`, "-m", `Release v${target}`]);
  console.log("Atomically pushing branch and tag.");
  run(["git", "push", "--atomic", "origin", `HEAD:refs/heads/${branch}`, `refs/tags/v${target}`]);
  console.log("Publishing GitHub release.");
  run(["gh", "release", "create", `v${target}`, `build/release/${asset}`, "--repo", REPO,
    "--verify-tag", "--title", `v${target}`, "--notes-file", `build/release/${NAME}-${target}-notes.md`]);
  console.log(`Published v${target}.`);
}

/** Dispatch nonmutating preview, local preparation, or confirmed publication. */
function main(): void {
  const args = parseArguments(process.argv.slice(2));
  if (!args) return;
  const localOnly = args.options.has("--prepare");
  const release = validateVersion(args.requested, localOnly);
  const { current, target } = release;
  const asset = `${NAME}-${target}-macos-arm64.tar.gz`;
  if (args.options.has("--dry-run")) {
    console.log(`[dry-run] ${current} -> ${target}; build/sign arm64 macOS 13, archive ${asset}, hash and update formula/changelog/VERSION.`);
    console.log(localOnly ? "[dry-run] Prepare only: no Git or network operations." :
      "[dry-run] Publishing would require a clean Git tree, origin and unused tag; commit only release metadata, tag, atomic push, gh release create.");
    console.log("[dry-run] Nothing changed; build, signing and publication preflights were not executed.");
    return;
  }
  const branch = localOnly ? undefined : preflight(target);
  if (!confirm(target, localOnly, args.options.has("--yes"))) return;
  try {
    prepare(release, asset);
    if (localOnly) console.log("Prepare only: no commit, tag, push or publication. Parent may review and publish.");
    else if (branch !== undefined) publish(target, branch, asset);
  } catch (error) {
    console.error("Release stopped. Inspect the reported operation, local files and remote state before retrying; no rollback or forced overwrite is attempted.");
    throw error;
  }
}

if (import.meta.main) cli("Release", main);
