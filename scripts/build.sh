#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
  cat <<'EOF'
Usage: scripts/build.sh

Build macos-dock-click-hide-toggle.swift and sign macos-dock-click-hide-toggle
in build/bin (Apple Silicon, macOS 13+). Does not install or restart the app.
Requires Xcode command-line tools and a configured code-signing identity.
Set CODE_SIGN_IDENTITY to select an identity; otherwise exactly one valid
Apple Development, Mac Developer, or Developer ID Application identity is required.
EOF
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: scripts/build.sh" >&2
  exit 1
fi

app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source="$app_dir/macos-dock-click-hide-toggle.swift"
mkdir -p "$app_dir/build/bin"
output="$app_dir/build/bin/macos-dock-click-hide-toggle"

identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities="$(/usr/bin/security find-identity -v -p codesigning)"
  identity="$(printf '%s\n' "$identities" | awk '/^[[:space:]]*[0-9]+\)/ && /"(Apple Development|Mac Developer|Developer ID Application):/ {print $2}')"
  count="$(printf '%s\n' "$identity" | awk 'NF {count++} END {print count+0}')"
  if [[ "$count" -ne 1 ]]; then
    echo "Found $count valid Apple code-signing identities. Set CODE_SIGN_IDENTITY to select one." >&2
    exit 1
  fi
fi
if [[ "$identity" == "-" ]]; then
  echo "Ad-hoc signing is not supported because it cannot preserve approval across builds." >&2
  exit 1
fi

temporary="$(mktemp "$app_dir/build/bin/.macos-dock-click-hide-toggle.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
/usr/bin/xcrun swiftc -O \
  -target arm64-apple-macosx13.0 \
  -module-name MacOSDockClickHideToggle -o "$temporary" - < "$source"
chmod 755 "$temporary"
if ! signing_output="$(/usr/bin/codesign --force --sign "$identity" \
  --identifier local.macos-dock-click-hide-toggle "$temporary" 2>&1)"; then
  echo "Code signing failed. Check the selected identity and key access locally." >&2
  exit 1
fi
/usr/bin/codesign --verify --strict "$temporary"
mv -f -- "$temporary" "$output"
printf 'Built and signed: %s\nInstall with: just --justfile %q install\n' "$output" "$app_dir/justfile"
