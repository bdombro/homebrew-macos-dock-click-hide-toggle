#!/usr/bin/env bun
/** Stage/reset the local formula; never overwrite an unresolved release backup. */
import { createHash } from "node:crypto";
import { chmodSync, constants, copyFileSync, existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { NAME, ROOT } from "./common.ts";
import { renderDevFormula } from "./formula-shared.ts";

const stagingDir = join(ROOT, "Formula", ".staging");
const stagingPath = join(stagingDir, NAME);
const formulaPath = join(ROOT, "Formula", `${NAME}.rb`);
const backupPath = join(stagingDir, `${NAME}.rb.bak`);

function backupReleaseFormula(): void {
  mkdirSync(stagingDir, { recursive: true });
  if (existsSync(backupPath)) throw new Error("Unresolved dev formula backup; run bun scripts/dev-formula.ts reset first.");
  copyFileSync(formulaPath, backupPath, constants.COPYFILE_EXCL);
}

function restoreReleaseFormula(): void {
  if (!existsSync(backupPath)) return;
  copyFileSync(backupPath, formulaPath);
  unlinkSync(backupPath);
}

function stageDevFormula(): void {
  copyFileSync(join(ROOT, "build", "bin", NAME), stagingPath);
  chmodSync(stagingPath, 0o755);
  const version = readFileSync(join(ROOT, "VERSION"), "utf8").trim();
  const sha256 = createHash("sha256").update(readFileSync(stagingPath)).digest("hex");
  writeFileSync(formulaPath, renderDevFormula(stagingPath, version, sha256));
}

function install(): void {
  backupReleaseFormula();
  let staged = false;
  try {
    stageDevFormula();
    staged = true;
  } finally {
    if (!staged) restoreReleaseFormula();
  }
  console.log("Staged local formula; reset after Homebrew finishes.");
}

function reset(): void {
  restoreReleaseFormula();
  console.log("Release formula restored (or no backup present).");
}

const args = process.argv.slice(2);
if (args.length !== 1 || !["install", "reset"].includes(args[0]!)) {
  throw new Error("Usage: bun scripts/dev-formula.ts <install|reset>");
}
if (args[0] === "install") install();
else reset();
