import { spawnSync } from "node:child_process";
import { constants as osConstants } from "node:os";
import { basename, resolve } from "node:path";

export const ROOT = resolve(import.meta.dir, "..");
export const NAME = "macos-dock-click-hide-toggle";
export const VERSION_PATTERN = /^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})(?![\s\S])/;

/** Carry a CLI status through finally blocks without terminating cleanup. */
export class CommandError extends Error {
  constructor(message: string, readonly status = 1) {
    super(message);
  }
}

/** Stop the current operation while allowing all staged resources to be cleaned. */
export function fail(message: string, status = 1): never {
  throw new CommandError(message, status);
}

export interface CommandOptions {
  capture?: boolean;
  input?: Buffer;
  env?: NodeJS.ProcessEnv;
}

export interface CommandResult {
  status: number;
  stdout: string;
  stderr: string;
}

/** Execute argv directly, optionally capturing diagnostics; never invoke a shell. */
export function command(arguments_: string[], options: CommandOptions = {}): CommandResult {
  const [executable, ...args] = arguments_;
  if (!executable) fail("Missing command.");
  const result = spawnSync(executable, args, {
    cwd: ROOT,
    env: options.env ?? process.env,
    input: options.input,
    stdio: [options.input ? "pipe" : options.capture ? "pipe" : "inherit",
      options.capture ? "pipe" : "inherit", options.capture ? "pipe" : "inherit"],
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  return {
    status: result.status ?? (result.signal ? -osConstants.signals[result.signal] : 1),
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

/** Execute a checked command and preserve its failure status. */
export function run(arguments_: string[], options: CommandOptions = {}): CommandResult {
  const result = command(arguments_, options);
  if (result.status) fail(`${basename(arguments_[0] ?? "")} failed (status ${result.status}).`, result.status);
  return result;
}

/** Serialize plist values through Apple's XML encoder, passing JSON as stdin. */
export function writePlist(destination: string, value: object): void {
  run(["/usr/bin/plutil", "-convert", "xml1", "-o", destination, "-"], {
    input: Buffer.from(JSON.stringify(value)),
  });
}

/** Map filesystem/tool errors to concise CLI diagnostics after cleanup completes. */
export function cli(label: string, main: () => void): void {
  try {
    main();
  } catch (error) {
    if (error instanceof CommandError) {
      if (error.message) console.error(error.message);
      process.exitCode = ((error.status % 256) + 256) % 256;
    } else if (error instanceof Error) {
      const errno = "errno" in error && typeof error.errno === "number" ? Math.abs(error.errno) : 1;
      const code = "code" in error && typeof error.code === "string" ? error.code : "operation failed";
      console.error(`${label} filesystem/tool error: ${code}.`);
      process.exitCode = errno || 1;
    } else {
      throw error;
    }
  }
}
