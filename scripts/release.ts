#!/usr/bin/env bun
/** Example-derived bump/build/archive/formula/commit/tag/publish pipeline. No asset deletion. */
import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { stdin as input, stdout as output } from "node:process";
import * as readline from "node:readline/promises";
import { $ } from "bun";
import { NAME, ROOT, VERSION_PATTERN } from "./common.ts";
import { buildReleaseArchive, releaseRepoSlug, renderReleaseFormula } from "./formula-shared.ts";

$.cwd(ROOT);
const formulaPath = `Formula/${NAME}.rb`;
const binaryPath = join(ROOT, "build", "bin", NAME);
type Bump = "major" | "minor" | "patch";
interface ReleaseOptions {
  bump: Bump;
  yes: boolean;
  dryRun: boolean;
  prepare: boolean;
}

function usage(): string {
  return "Usage: bun scripts/release.ts <major|minor|patch> [--yes] [--dry-run] [--prepare]";
}

function parseOptions(argv: string[]): ReleaseOptions {
  const bumps = argv.filter((a): a is Bump => ["major", "minor", "patch"].includes(a));
  if (bumps.length !== 1 || argv.some(a => !["major", "minor", "patch", "--yes", "--dry-run", "--prepare"].includes(a))) {
    throw new Error(usage());
  }
  return { bump: bumps[0]!, yes: argv.includes("--yes"), dryRun: argv.includes("--dry-run"), prepare: argv.includes("--prepare") };
}

function readCurrentVersion(): string {
  const version = readFileSync(join(ROOT, "VERSION"), "utf8").trim();
  if (!VERSION_PATTERN.test(version)) throw new Error("Invalid numeric X.Y.Z in VERSION.");
  return version;
}

function applyBump(current: string, bump: Bump): string {
  const [major, minor, patch] = current.split(".").map(Number) as [number, number, number];
  const next = bump === "major" ? `${major + 1}.0.0` : bump === "minor" ? `${major}.${minor + 1}.0` : `${major}.${minor}.${patch + 1}`;
  if (!VERSION_PATTERN.test(next)) throw new Error("Version components must be <= 999999.");
  return next;
}

function updateChangelog(newVersion: string): string {
  const content = readFileSync(join(ROOT, "CHANGELOG.md"), "utf8");
  if (content.split(/\r?\n/).filter(line => line === "## [Unreleased]").length !== 1) {
    throw new Error("Expected exactly one Unreleased changelog heading.");
  }
  if (content.includes(`## [${newVersion}]`)) throw new Error("Release already appears in changelog.");
  const notes = content.split(/^## \[Unreleased\]\r?$/m)[1]!.split(/^## /m)[0]!.trim();
  if (!notes) throw new Error("Add release notes under Unreleased.");
  return content.replace(/^## \[Unreleased\]\r?$/m, `## [Unreleased]\n\n## [${newVersion}] - ${new Date().toISOString().slice(0, 10)}`);
}

/** Validate repository, branch, tag and authentication without discarding changes. */
async function preflight(newVersion: string): Promise<string> {
  const top = (await $`git rev-parse --show-toplevel`.quiet()).text().trim();
  if (realpathSync(top) !== realpathSync(ROOT)) throw new Error("Wrong Git repository.");
  const branch = (await $`git symbolic-ref --quiet --short HEAD`.quiet()).text().trim();
  const origin = (await $`git remote get-url origin`.quiet()).text().trim();
  if (![ `https://github.com/${releaseRepoSlug}`, `https://github.com/${releaseRepoSlug}.git`, `git@github.com:${releaseRepoSlug}.git` ].includes(origin)) {
    throw new Error("origin must point to the public project repository.");
  }
  const tags = (await $`git tag --list ${`v${newVersion}`}`.quiet()).text().trim();
  if (tags) throw new Error("Release tag already exists locally.");
  if ((await $`git ls-remote --tags origin ${`refs/tags/v${newVersion}`}`.quiet()).text()) throw new Error("Release tag already exists remotely.");
  const auth = await $`gh auth status --hostname github.com`.quiet().nothrow();
  if (auth.exitCode !== 0) throw new Error("Authenticate gh before publishing.");
  return branch;
}

async function updateReleaseFormula(version: string): Promise<string> {
  const { archivePath, sha256 } = await buildReleaseArchive(binaryPath);
  const formula = renderReleaseFormula(version, sha256);
  // Validate generated Ruby before changing any release metadata.
  await $`ruby -c < ${Buffer.from(formula)}`.quiet();
  writeFileSync(join(ROOT, formulaPath), formula);
  return archivePath;
}

async function commitAndTag(newVersion: string, branch: string): Promise<void> {
  await $`git add -A`;
  await $`git commit -m ${`chore: release v${newVersion}`} -m ${"Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"}`;
  await $`git tag -a ${`v${newVersion}`} -m ${`Release v${newVersion}`}`;
  await $`git push --atomic origin ${`HEAD:refs/heads/${branch}`} ${`refs/tags/v${newVersion}`}`;
}

async function createGithubRelease(tag: string, archivePath: string): Promise<void> {
  await $`gh release create ${tag} ${archivePath} --repo ${releaseRepoSlug} --verify-tag --title ${tag} --generate-notes`;
}

async function runRelease(bump: Bump, options: ReleaseOptions): Promise<void> {
  if (existsSync(join(ROOT, "Formula", ".staging", `${NAME}.rb.bak`))) throw new Error("Reset the staged dev formula before preparing a release.");
  const currentVersion = readCurrentVersion();
  const newVersion = applyBump(currentVersion, bump);
  const changelog = updateChangelog(newVersion);
  if (options.dryRun) {
    console.log(`[dry-run] ${currentVersion} → ${newVersion}: typecheck, build/sign, zip, update formula/VERSION/changelog${options.prepare ? " (prepare only)" : ", git add -A, commit all changes, tag, atomic push, public GitHub release"}. Nothing changed.`);
    return;
  }
  const branch = options.prepare ? undefined : await preflight(newVersion);
  if (!options.yes) {
    if (!input.isTTY) throw new Error("Not a TTY; pass --yes to confirm.");
    const rl = readline.createInterface({ input, output });
    let answer: string;
    try {
      answer = await rl.question(`Release v${newVersion} (${options.prepare ? "prepare local files" : "stage and commit all changes, tag, push, publish"})? [y/N] `);
    } finally { rl.close(); }
    if (answer.trim().toLowerCase() !== "y") { console.log("Aborted."); return; }
  }
  await $`just build`.env({ ...process.env, APP_VERSION: newVersion });
  if ((await $`${binaryPath} --version`.quiet()).text().trim() !== newVersion) throw new Error("Built executable version does not match release target.");
  const archivePath = await updateReleaseFormula(newVersion);
  writeFileSync(join(ROOT, "VERSION"), `${newVersion}\n`);
  writeFileSync(join(ROOT, "CHANGELOG.md"), changelog);
  if (branch !== undefined) {
    await commitAndTag(newVersion, branch);
    await createGithubRelease(`v${newVersion}`, archivePath);
  }
  console.log(options.prepare ? "Prepared local release files; no commit, push or publication." : `Released v${newVersion}`);
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  if (argv.length === 1 && ["--help", "-h"].includes(argv[0]!)) { console.log(usage()); return; }
  const options = parseOptions(argv);
  await runRelease(options.bump, options);
}

await main();
