#!/usr/bin/env python3
"""Install or remove the logged-in user's local LaunchAgent."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
NAME = "macos-dock-click-hide-toggle"
LABEL = "local." + NAME


def fail(message, status=1):
    print(message, file=sys.stderr)
    raise SystemExit(status)


def usage(stream=sys.stdout):
    print("Usage: scripts/install.py [prebuilt-executable]\n"
          "       scripts/install.py --uninstall", file=stream)


def launchctl(*arguments, capture=False):
    result = subprocess.run(["launchctl", *map(str, arguments)],
                            capture_output=capture, text=True)
    if not capture and result.returncode:
        fail("launchctl {} failed.".format(arguments[0]), result.returncode)
    return result


def unload(service):
    result = launchctl("print", service, capture=True)
    if result.returncode == 0:
        launchctl("bootout", service)
    elif result.returncode != 113:
        fail("Cannot inspect {} (status {}):\n{}{}".format(
            service, result.returncode, result.stdout, result.stderr),
            result.returncode)


def uninstall(installation, executable, plist, log, service):
    unload(service)
    plist.unlink(missing_ok=True)
    executable.unlink(missing_ok=True)
    if installation.is_dir() and not any(installation.iterdir()):
        installation.rmdir()
    print("Uninstalled {}. Existing logs are kept at {}.".format(LABEL, log))


def install(binary, installation, executable, plist, log, domain, service):
    if not binary.is_file() or not os.access(binary, os.X_OK):
        fail("Missing executable: {}. Run 'just build' first or provide a prebuilt executable."
             .format(binary))
    installation.mkdir(parents=True, exist_ok=True)
    plist.parent.mkdir(parents=True, exist_ok=True)
    # Stage each file on its destination filesystem, before unloading anything.
    with tempfile.TemporaryDirectory(prefix=".install.", dir=installation) as binary_stage:
        with tempfile.TemporaryDirectory(prefix="." + LABEL + ".", dir=plist.parent) as plist_stage:
            temporary = Path(binary_stage) / NAME
            temporary_plist = Path(plist_stage) / "agent.plist"
            shutil.copy2(binary, temporary)
            with temporary_plist.open("wb") as stream:
                plistlib.dump({
                    "Label": LABEL,
                    "ProgramArguments": [str(executable), "start"],
                    "LimitLoadToSessionType": "Aqua",
                    "RunAtLoad": True,
                    "KeepAlive": {"SuccessfulExit": False},
                    "ThrottleInterval": 30,
                    "StandardOutPath": str(log),
                    "StandardErrorPath": str(log),
                }, stream)
            unload(service)
            os.replace(temporary, executable)
            os.replace(temporary_plist, plist)
    launchctl("enable", service)
    launchctl("bootstrap", domain, plist)
    print("Installed and loaded {}. Starts now and at login.\n"
          "Executable: {}\nPlist: {}\nLog: {}".format(LABEL, executable, plist, log))
    print("Allow the installed executable in System Settings > Privacy & Security > Accessibility.\n"
          "The service waits for approval without prompting repeatedly.")


def main():
    args = sys.argv[1:]
    if args in (["--help"], ["-h"]):
        usage()
        return
    if len(args) > 1 or (args and args[0].startswith("--") and args[0] != "--uninstall"):
        usage(sys.stderr)
        raise SystemExit(1)
    if os.getuid() == 0:
        fail("Run this command as your logged-in user, without sudo.")
    installation = Path.home() / ".local" / "share" / NAME
    executable = installation / NAME
    plist = Path.home() / "Library" / "LaunchAgents" / (LABEL + ".plist")
    log = installation / "daemon.log"
    domain = "gui/{}".format(os.getuid())
    service = domain + "/" + LABEL
    if args == ["--uninstall"]:
        uninstall(installation, executable, plist, log, service)
    else:
        binary = Path(args[0]) if args else ROOT / "build" / "bin" / NAME
        install(binary, installation, executable, plist, log, domain, service)


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        fail("Install filesystem/tool error: {}.".format(error.strerror), error.errno or 1)
