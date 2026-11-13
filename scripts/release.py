#!/usr/bin/env python3
"""Prepare local release artifacts or publish a versioned GitHub release."""

import datetime
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parent.parent
NAME = "macos-dock-click-hide-toggle"
REPO = "bdombro/" + NAME
VERSION_PATTERN = r"(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})"


def fail(message, status=1):
    print(message, file=sys.stderr)
    raise SystemExit(status)


def run(arguments, **kwargs):
    result = subprocess.run(arguments, cwd=ROOT, **kwargs)
    if result.returncode:
        fail("{} failed (status {}).".format(Path(arguments[0]).name, result.returncode),
             result.returncode)
    return result


def usage(stream=sys.stdout):
    print("Usage: scripts/release.py <patch|minor|major|X.Y.Z> [--dry-run] [--prepare] [--yes]\n"
          "--prepare builds and updates local release files only; permits the current version.",
          file=stream)


def parse_arguments(arguments):
    target = None
    options = set()
    for argument in arguments:
        if argument in ("--help", "-h"):
            usage()
            raise SystemExit(0)
        if argument in ("--dry-run", "--prepare", "--yes"):
            options.add(argument)
        elif argument.startswith("--"):
            usage(sys.stderr)
            raise SystemExit(1)
        elif target is None:
            target = argument
        else:
            fail("Specify exactly one version or bump.")
    if target is None:
        usage(sys.stderr)
        raise SystemExit(1)
    return target, options


def validate_version(requested, prepare):
    current = (ROOT / "VERSION").read_text().rstrip("\n")
    if not re.fullmatch(VERSION_PATTERN, current):
        fail("VERSION must contain a numeric X.Y.Z version (components <= 999999).")
    components = list(map(int, current.split(".")))
    if requested in ("major", "minor", "patch"):
        index = ("major", "minor", "patch").index(requested)
        components[index] += 1
        components[index + 1:] = [0] * (2 - index)
        target = ".".join(map(str, components))
    else:
        target = requested
    if not re.fullmatch(VERSION_PATTERN, target):
        fail("Invalid release version.")
    if target == current:
        if not prepare:
            fail("Publishing requires a version newer than VERSION; use --prepare for initial artifacts.")
    elif tuple(map(int, target.split("."))) <= tuple(map(int, current.split("."))):
        fail("Release version must increase.")
    changelog = (ROOT / "CHANGELOG.md").read_text()
    if changelog.splitlines().count("## [Unreleased]") != 1:
        fail("Expected one Unreleased heading.")
    if target != current and "## [{}]".format(target) in changelog:
        fail("Target version already exists in CHANGELOG.md.")
    if target == current and "## [{}] - ".format(target) not in changelog:
        fail("Current release needs dated changelog notes.")
    return current, target, changelog


def preflight(target):
    top = run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
    if Path(top).resolve() != ROOT:
        fail("Run from the project Git repository.")
    if run(["git", "status", "--porcelain", "--untracked-files=all"],
           capture_output=True, text=True).stdout:
        fail("Working tree must be clean, including untracked files.")
    branch = run(["git", "symbolic-ref", "--quiet", "--short", "HEAD"],
                 capture_output=True, text=True).stdout.strip()
    origin = run(["git", "remote", "get-url", "origin"],
                 capture_output=True, text=True).stdout.strip()
    if origin not in ("https://github.com/" + REPO, "https://github.com/" + REPO + ".git",
                      "git@github.com:" + REPO + ".git"):
        fail("origin must point to the public project repository.")
    tag = subprocess.run(["git", "show-ref", "--verify", "--quiet", "refs/tags/v" + target],
                         cwd=ROOT, capture_output=True)
    if tag.returncode == 0:
        fail("Tag already exists locally.")
    if tag.returncode != 1:
        fail("Cannot inspect local tag.", tag.returncode)
    if run(["git", "ls-remote", "--tags", "origin", "refs/tags/v" + target],
           capture_output=True, text=True).stdout:
        fail("Tag already exists remotely.")
    auth = subprocess.run(["gh", "auth", "status", "--hostname", "github.com"],
                          cwd=ROOT, capture_output=True)
    if auth.returncode:
        fail("Authenticate gh before publishing.", auth.returncode)
    return branch


def confirm(target, prepare, yes):
    if yes:
        return True
    if not sys.stdin.isatty():
        fail("Not a TTY; pass --yes to confirm.")
    action = "prepare local artifacts" if prepare else "commit, tag, push and publish"
    try:
        answer = input("Release v{} ({})? [y/N] ".format(target, action))
    except EOFError:
        answer = ""
    if answer not in ("y", "Y"):
        print("Aborted.")
        return False
    return True


def build(target):
    environment = dict(os.environ, APP_VERSION=target)
    run([sys.executable, str(ROOT / "scripts" / "build.py")], env=environment)
    version = run([str(ROOT / "build" / "bin" / NAME), "--version"],
                  capture_output=True, text=True).stdout.rstrip("\n")
    if version != target:
        fail("Built executable version does not match release target.")


def release_notes(changelog, current, target):
    if target != current:
        date = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        changelog = changelog.replace(
            "## [Unreleased]\n",
            "## [Unreleased]\n\n## [{}] - {}\n".format(target, date), 1)
    notes = []
    found = False
    for line in changelog.splitlines(keepends=True):
        if line.startswith("## "):
            if found:
                break
            found = line.startswith("## [{}] - ".format(target))
            continue
        if found:
            notes.append(line)
    notes = "".join(notes)
    if not notes.strip():
        fail("Add release notes under Unreleased before bumping.")
    return changelog, notes


def archive(destination):
    # Explicit names only: no source tree, metadata sidecars or signing material.
    with tarfile.open(destination, "w:gz", format=tarfile.USTAR_FORMAT) as bundle:
        bundle.add(ROOT / "build" / "bin" / NAME, arcname=NAME, recursive=False)
        bundle.add(ROOT / "LICENSE", arcname="LICENSE", recursive=False)
    digest = hashlib.sha256()
    with destination.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def formula(target, asset, digest):
    return '''class MacosDockClickHideToggle < Formula
  desc "Click a frontmost application's Dock icon to hide it"
  homepage "https://github.com/REPO"
  url "https://github.com/REPO/releases/download/vTARGET/ASSET"
  sha256 "DIGEST"
  license "ISC"

  depends_on arch: :arm64
  depends_on :macos
  on_macos do
    depends_on macos: :ventura
  end

  def install
    bin.install "NAME"
  end

  service do
    run [opt_bin/"NAME", "start"]
    keep_alive successful_exit: false
    # Homebrew includes Aqua in its generated session types; use without sudo.
    working_dir var
    log_path var/"log/NAME.log"
    error_log_path var/"log/NAME.log"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/NAME --help")
    assert_equal version.to_s, shell_output("#{bin}/NAME --version").strip
  end
end
'''.replace("REPO", REPO).replace("TARGET", target).replace("ASSET", asset).replace(
        "DIGEST", digest).replace("NAME", NAME)


def prepare(current, target, changelog, asset):
    build(target)
    changelog, notes = release_notes(changelog, current, target)
    directory = ROOT / "build" / "release"
    directory.mkdir(parents=True, exist_ok=True)
    (ROOT / "Formula").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".prepare.", dir=directory) as staging:
        staging = Path(staging)
        (staging / "VERSION").write_text(target + "\n")
        (staging / "CHANGELOG.md").write_text(changelog)
        (staging / "notes.md").write_text(notes)
        digest = archive(staging / asset)
        (staging / "formula.rb").write_text(formula(target, asset, digest))
        run(["ruby", "-c", str(staging / "formula.rb")])
        replacements = [
            (staging / asset, directory / asset),
            (staging / "notes.md", directory / (NAME + "-" + target + "-notes.md")),
            (staging / "VERSION", ROOT / "VERSION"),
            (staging / "CHANGELOG.md", ROOT / "CHANGELOG.md"),
            (staging / "formula.rb", ROOT / "Formula" / (NAME + ".rb")),
        ]
        # Stage beside each destination so every individual replacement is atomic.
        for source, destination in replacements:
            with tempfile.NamedTemporaryFile(prefix=".release.", dir=destination.parent,
                                             delete=False) as stream:
                temporary = Path(stream.name)
            try:
                temporary.write_bytes(source.read_bytes())
                temporary.chmod(0o644)
                os.replace(temporary, destination)
            finally:
                temporary.unlink(missing_ok=True)
    print("Prepared build/release/{}\nSHA-256: {}".format(asset, digest))


def publish(target, branch, asset):
    print("Committing release metadata.", flush=True)
    run(["git", "add", "--", "VERSION", "CHANGELOG.md", "Formula/" + NAME + ".rb"])
    run(["git", "commit", "-m", "chore: release v" + target, "-m",
         "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"])
    print("Tagging release.", flush=True)
    run(["git", "tag", "-a", "v" + target, "-m", "Release v" + target])
    print("Atomically pushing branch and tag.", flush=True)
    run(["git", "push", "--atomic", "origin", "HEAD:refs/heads/" + branch,
         "refs/tags/v" + target])
    print("Publishing GitHub release.", flush=True)
    run(["gh", "release", "create", "v" + target, "build/release/" + asset,
         "--repo", REPO, "--verify-tag", "--title", "v" + target,
         "--notes-file", "build/release/" + NAME + "-" + target + "-notes.md"])
    print("Published v{}.".format(target))


def main():
    requested, options = parse_arguments(sys.argv[1:])
    local_only = "--prepare" in options
    current, target, changelog = validate_version(requested, local_only)
    asset = "{}-{}-macos-arm64.tar.gz".format(NAME, target)
    if "--dry-run" in options:
        print("[dry-run] {} -> {}; build/sign arm64 macOS 13, archive {}, "
              "hash and update formula/changelog/VERSION.".format(current, target, asset))
        print("[dry-run] Prepare only: no Git or network operations." if local_only else
              "[dry-run] Publishing would require a clean Git tree, origin and unused tag; "
              "commit only release metadata, tag, atomic push, gh release create.")
        print("[dry-run] Nothing changed; build, signing and publication preflights were not executed.")
        return
    branch = None if local_only else preflight(target)
    if not confirm(target, local_only, "--yes" in options):
        return
    try:
        prepare(current, target, changelog, asset)
        if local_only:
            print("Prepare only: no commit, tag, push or publication. Parent may review and publish.")
        else:
            publish(target, branch, asset)
    finally:
        if sys.exc_info()[0] is not None:
            print("Release stopped. Inspect the reported operation, local files and remote state "
                  "before retrying; no rollback or forced overwrite is attempted.", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail("Release filesystem/tool error: {}.".format(error.strerror), error.errno or 1)
