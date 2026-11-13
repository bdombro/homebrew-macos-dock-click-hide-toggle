#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$app_dir/scripts/service-common.sh"
if [[ $# -gt 1 ]]; then
  echo "Usage: scripts/install.sh [prebuilt-executable]" >&2
  exit 1
fi
require_user
binary="${1:-$app_dir/build/bin/$name}"
if [[ ! -f "$binary" || ! -x "$binary" ]]; then
  echo "Missing executable: $binary. Run 'just build' first or provide a prebuilt executable." >&2
  exit 1
fi
mkdir -p "$installation" "$agents"
temporary="$(mktemp "$installation/.install.XXXXXX")"
temporary_plist=""
trap 'rm -f -- "$temporary"; if [[ -n "$temporary_plist" ]]; then rm -f -- "$temporary_plist"; fi' EXIT
temporary_plist="$(mktemp "$agents/.$label.XXXXXX")"
cp -p "$binary" "$temporary"
/usr/bin/plutil -create xml1 "$temporary_plist"
/usr/bin/plutil -insert Label -string "$label" "$temporary_plist"
/usr/bin/plutil -insert ProgramArguments -array "$temporary_plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$executable" "$temporary_plist"
/usr/bin/plutil -insert ProgramArguments.1 -string start "$temporary_plist"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$temporary_plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$temporary_plist"
/usr/bin/plutil -insert KeepAlive -dictionary "$temporary_plist"
/usr/bin/plutil -insert KeepAlive.SuccessfulExit -bool false "$temporary_plist"
/usr/bin/plutil -insert ThrottleInterval -integer 30 "$temporary_plist"
/usr/bin/plutil -insert StandardOutPath -string "$log" "$temporary_plist"
/usr/bin/plutil -insert StandardErrorPath -string "$log" "$temporary_plist"
unload
mv -f -- "$temporary" "$executable"
mv -f -- "$temporary_plist" "$plist"
launchctl enable "$service"
launchctl bootstrap "$domain" "$plist"
printf 'Installed and loaded %s. Starts now and at login.\nExecutable: %s\nPlist: %s\nLog: %s\n' "$label" "$executable" "$plist" "$log"
printf 'Allow the installed executable in System Settings > Privacy & Security > Accessibility.\nThe service waits for approval without prompting repeatedly.\n'
