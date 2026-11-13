#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$app_dir/scripts/service-common.sh"
if [[ $# -ne 0 ]]; then
  echo "Usage: scripts/uninstall.sh" >&2
  exit 1
fi
require_user
unload
rm -f -- "$plist" "$executable"
if [[ -d "$installation" && -z "$(ls -A "$installation")" ]]; then
  rmdir "$installation"
fi
printf 'Uninstalled %s. Existing logs are kept at %s.\n' "$label" "$log"
