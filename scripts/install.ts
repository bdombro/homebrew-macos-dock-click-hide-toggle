#!/usr/bin/env bun
/** Install or remove the logged-in user's local LaunchAgent. */
import { accessSync, constants, copyFileSync, chmodSync, mkdirSync, mkdtempSync, readdirSync, renameSync, rmSync, rmdirSync, statSync, unlinkSync, utimesSync } from "node:fs";
import { homedir, userInfo } from "node:os";
import { dirname, join, resolve } from "node:path";
import { cli, command, fail, NAME, ROOT, writePlist } from "./common.ts";
import type { CommandResult } from "./common.ts";

const LABEL = `local.${NAME}`;

interface Installation {
  directory: string;
  executable: string;
  plist: string;
  log: string;
  domain: string;
  service: string;
}

/** Print the local install and uninstall command forms. */
function usage(stderr = false): void {
  (stderr ? console.error : console.log)("Usage: scripts/install.ts [prebuilt-executable]\n       scripts/install.ts --uninstall");
}

/** Run launchctl; captured results leave status interpretation to the caller. */
function launchctl(args: string[], capture = false): CommandResult {
  const result = command(["launchctl", ...args], { capture });
  if (!capture && result.status) fail(`launchctl ${args[0]} failed.`, result.status);
  return result;
}

/** Unload a service, accepting only status 113 as an absent service. */
function unload(service: string): void {
  const result = launchctl(["print", service], true);
  if (result.status === 0) launchctl(["bootout", service]);
  else if (result.status !== 113) {
    fail(`Cannot inspect ${service} (status ${result.status}):\n${result.stdout}${result.stderr}`, result.status);
  }
}

/** Remove a file if present without suppressing other filesystem errors. */
function unlinkIfPresent(path: string): void {
  try { unlinkSync(path); } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
}

/** Remove the local service and executable while preserving existing logs. */
function uninstall(paths: Installation): void {
  unload(paths.service);
  unlinkIfPresent(paths.plist);
  unlinkIfPresent(paths.executable);
  try {
    if (statSync(paths.directory).isDirectory() && readdirSync(paths.directory).length === 0) rmdirSync(paths.directory);
  } catch (error) {
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  console.log(`Uninstalled ${LABEL}. Existing logs are kept at ${paths.log}.`);
}

/** Stage a prebuilt executable and Aqua plist before unloading and replacing files. */
function install(binary: string, paths: Installation): void {
  let executable = false;
  try {
    executable = statSync(binary).isFile();
    accessSync(binary, constants.X_OK);
  } catch { executable = false; }
  if (!executable) fail(`Missing executable: ${binary}. Run 'just build' first or provide a prebuilt executable.`);
  mkdirSync(paths.directory, { recursive: true });
  mkdirSync(dirname(paths.plist), { recursive: true });
  const binaryStage = mkdtempSync(join(paths.directory, ".install."));
  try {
    const plistStage = mkdtempSync(join(dirname(paths.plist), `.${LABEL}.`));
    try {
      const temporary = join(binaryStage, NAME);
      const temporaryPlist = join(plistStage, "agent.plist");
      copyFileSync(binary, temporary);
      const metadata = statSync(binary);
      chmodSync(temporary, metadata.mode);
      utimesSync(temporary, metadata.atime, metadata.mtime);
      writePlist(temporaryPlist, {
        Label: LABEL, ProgramArguments: [paths.executable, "start"],
        LimitLoadToSessionType: "Aqua", RunAtLoad: true,
        KeepAlive: { SuccessfulExit: false }, ThrottleInterval: 30,
        StandardOutPath: paths.log, StandardErrorPath: paths.log,
      });
      unload(paths.service);
      renameSync(temporary, paths.executable);
      renameSync(temporaryPlist, paths.plist);
    } finally { rmSync(plistStage, { recursive: true, force: true }); }
  } finally { rmSync(binaryStage, { recursive: true, force: true }); }
  launchctl(["enable", paths.service]);
  launchctl(["bootstrap", paths.domain, paths.plist]);
  console.log(`Installed and loaded ${LABEL}. Starts now and at login.\nExecutable: ${paths.executable}\nPlist: ${paths.plist}\nLog: ${paths.log}`);
  console.log("Allow the installed executable in System Settings > Privacy & Security > Accessibility.\nThe service waits for approval without prompting repeatedly.");
}

/** Dispatch installation or removal using the logged-in user's paths and UID. */
function main(): void {
  const args = process.argv.slice(2);
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) { usage(); return; }
  if (args.length > 1 || (args[0]?.startsWith("--") && args[0] !== "--uninstall")) {
    usage(true); fail("");
  }
  const uid = process.getuid?.() ?? userInfo().uid;
  if (uid === 0) fail("Run this command as your logged-in user, without sudo.");
  const directory = join(homedir(), ".local", "share", NAME);
  const domain = `gui/${uid}`;
  const paths: Installation = {
    directory, executable: join(directory, NAME),
    plist: join(homedir(), "Library", "LaunchAgents", `${LABEL}.plist`),
    log: join(directory, "daemon.log"), domain, service: `${domain}/${LABEL}`,
  };
  if (args[0] === "--uninstall") uninstall(paths);
  else install(args[0] ? resolve(args[0]) : join(ROOT, "build", "bin", NAME), paths);
}

if (import.meta.main) cli("Install", main);
