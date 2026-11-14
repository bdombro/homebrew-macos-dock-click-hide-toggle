/** Shared formula fragments and archive helpers, adapted from argsbarg/examples/homebrew. */
import { createHash } from "node:crypto";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { $ } from "bun";
import { NAME, ROOT, VERSION_PATTERN } from "./common.ts";

export const releaseRepoSlug = `bdombro/homebrew-${NAME}`;
export const className = NAME.split("-").map(s => s[0]!.toUpperCase() + s.slice(1)).join("");
export const formulaInstallRuby = `def install
    bin.install "${NAME}"
  end`;
export const formulaServiceRuby = `service do
    run [opt_bin/"${NAME}", "start"]
    keep_alive successful_exit: false
    # Homebrew includes Aqua in its generated session types; use without sudo.
    working_dir var
    log_path var/"log/${NAME}.log"
    error_log_path var/"log/${NAME}.log"
  end`;
export const formulaTestRuby = `test do
    assert_match "Usage:", shell_output("#{bin}/${NAME} --help")
    assert_equal version.to_s, shell_output("#{bin}/${NAME} --version").strip
  end`;

export interface FormulaCoords {
  url: string;
  version: string;
  sha256: string;
}

export function releaseArchiveName(): string {
  return `${NAME}.zip`;
}

/** Recreate the binary + ISC notice zip so stale members cannot survive. */
export async function buildReleaseArchive(binaryPath: string): Promise<{ archivePath: string; sha256: string }> {
  const archivePath = `${binaryPath}.zip`;
  rmSync(archivePath, { force: true });
  await $`zip -j -9 ${archivePath} ${binaryPath} ${join(ROOT, "LICENSE")}`.quiet();
  return { archivePath, sha256: createHash("sha256").update(readFileSync(archivePath)).digest("hex") };
}

export function releaseFormulaUrl(version: string): string {
  return `https://github.com/${releaseRepoSlug}/releases/download/v${version}/${releaseArchiveName()}`;
}

export function renderFormula(coords: FormulaCoords): string {
  if (!VERSION_PATTERN.test(coords.version)) throw new Error("Formula version must be numeric X.Y.Z.");
  if (!/^[a-f0-9]{64}$/.test(coords.sha256)) throw new Error("Invalid formula SHA-256.");
  if (!/^(https:\/\/github\.com\/|file:\/\/)/.test(coords.url) || /["\\\r\n#]/.test(coords.url)) {
    throw new Error("Invalid formula URL.");
  }
  return `class ${className} < Formula
  desc "Click a frontmost application's Dock icon to hide it"
  homepage "https://github.com/${releaseRepoSlug}"
  url "${coords.url}"
  version "${coords.version}"
  sha256 "${coords.sha256}"
  license "ISC"

  depends_on arch: :arm64
  depends_on :macos
  on_macos do
    depends_on macos: :ventura
  end

  ${formulaInstallRuby}

  ${formulaServiceRuby}

  ${formulaTestRuby}
end
`;
}

export function renderReleaseFormula(version: string, sha256: string): string {
  return renderFormula({ url: releaseFormulaUrl(version), version, sha256 });
}

export function renderDevFormula(stagingPath: string, version: string, sha256: string): string {
  return renderFormula({ url: pathToFileURL(stagingPath).href, version, sha256 });
}
