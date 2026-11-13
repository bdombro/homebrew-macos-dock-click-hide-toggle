#!/usr/bin/env python3
"""Build and sign the Apple Silicon executable without installing it."""

import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
NAME = "macos-dock-click-hide-toggle"
VERSION_PATTERN = r"(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})"


def fail(message, status=1):
    print(message, file=sys.stderr)
    raise SystemExit(status)


def build(source, output, metadata, version):
    with metadata.open("wb") as stream:
        plistlib.dump({"CFBundleShortVersionString": version}, stream)
    with source.open("rb") as stream:
        result = subprocess.run([
            "/usr/bin/xcrun", "swiftc", "-O",
            "-target", "arm64-apple-macosx13.0",
            "-module-name", "MacOSDockClickHideToggle", "-o", str(output),
            "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
            "-Xlinker", "__info_plist", "-Xlinker", str(metadata), "-",
        ], stdin=stream)
    if result.returncode:
        fail("Swift compilation failed.", result.returncode)
    output.chmod(0o755)


def sign(output):
    identity = os.environ.get("CODE_SIGN_IDENTITY", "")
    if not identity:
        result = subprocess.run(
            ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
            capture_output=True, text=True,
        )
        if result.returncode:
            fail("Cannot inspect code-signing identities; check the local keychain.",
                 result.returncode)
        identities = re.findall(
            r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"(?:Apple Development|Mac Developer|Developer ID Application):',
            result.stdout, re.MULTILINE,
        )
        if len(identities) != 1:
            fail("Found {} valid Apple code-signing identities. "
                 "Set CODE_SIGN_IDENTITY to select one.".format(len(identities)))
        identity = identities[0]
    if identity == "-":
        fail("Ad-hoc signing is not supported because it cannot preserve approval across builds.")
    # Never echo the signing command, certificate subjects or keychain diagnostics.
    result = subprocess.run([
        "/usr/bin/codesign", "--force", "--sign", identity,
        "--identifier", "local." + NAME, str(output),
    ], capture_output=True)
    if result.returncode:
        fail("Code signing failed. Check the selected identity and key access locally.",
             result.returncode)
    result = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", str(output)],
        capture_output=True,
    )
    if result.returncode:
        fail("Code signature verification failed.", result.returncode)


def main():
    if sys.argv[1:] in (["--help"], ["-h"]):
        print("""Usage: scripts/build.py

Build and sign build/bin/macos-dock-click-hide-toggle (arm64, macOS 13+).
Does not install or restart the app. Requires Xcode command-line tools.
Set CODE_SIGN_IDENTITY to select an identity; otherwise exactly one valid
Apple Development, Mac Developer, or Developer ID Application identity is required.
The version comes from VERSION; APP_VERSION overrides it for release builds.""")
        return
    if sys.argv[1:]:
        fail("Usage: scripts/build.py")
    version = (os.environ["APP_VERSION"] if "APP_VERSION" in os.environ
               else (ROOT / "VERSION").read_text().rstrip("\n"))
    if not re.fullmatch(VERSION_PATTERN, version):
        fail("Build version must be numeric X.Y.Z (components <= 999999).")
    directory = ROOT / "build" / "bin"
    directory.mkdir(parents=True, exist_ok=True)
    # Same-filesystem staging keeps the installed build intact on failure.
    with tempfile.TemporaryDirectory(prefix=".build.", dir=directory) as staging:
        output = Path(staging) / NAME
        metadata = Path(staging) / "Info.plist"
        build(ROOT / (NAME + ".swift"), output, metadata, version)
        sign(output)  # Comment out this call only for a local unsigned build.
        os.replace(output, directory / NAME)
    print("Built: {}\nInstall with: just --justfile {} install".format(
        directory / NAME, shlex.quote(str(ROOT / "justfile"))))


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail("Build filesystem/tool error: {}.".format(error.strerror), error.errno or 1)
