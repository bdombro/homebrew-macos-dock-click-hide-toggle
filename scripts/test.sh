#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/dock-toggle-test.XXXXXX")"
trap 'rm -rf -- "$temporary"' EXIT
export HOME="$temporary/home with spaces"
mkdir -p "$HOME" "$temporary/mocks"
export PATH="$temporary/mocks:$PATH"
export CALLS="$temporary/launchctl.calls"
export INSPECT_STATUS=113 BOOTOUT_STATUS=0
cat > "$temporary/mocks/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
  print) exit "$INSPECT_STATUS" ;;
  bootout) exit "$BOOTOUT_STATUS" ;;
esac
EOF
cat > "$temporary/mocks/id" <<'EOF'
#!/usr/bin/env bash
echo 501
EOF
cat > "$temporary/mocks/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  rev-parse) pwd ;;
  status) echo ' M VERSION' ;;
  *) echo "Unexpected Git operation in isolated test" >&2; exit 99 ;;
esac
EOF
chmod +x "$temporary/mocks/"*
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_status() {
  local expected="$1" actual=0
  shift
  "$@" > "$temporary/output" 2>&1 || actual=$?
  [[ "$actual" -eq "$expected" ]] || fail "expected status $expected, got $actual"
}
name=macos-dock-click-hide-toggle
prebuilt="$temporary/prebuilt"
printf '#!/bin/sh\nprintf "test executable\\n"\n' > "$prebuilt"
chmod +x "$prebuilt"
installation="$HOME/.local/share/$name"
plist="$HOME/Library/LaunchAgents/local.$name.plist"
expect_status 1 "$app_dir/scripts/install.sh" "$temporary/missing"
[[ ! -e "$CALLS" ]] || fail "Missing binary contacted launchctl."
"$app_dir/scripts/install.sh" "$prebuilt" > "$temporary/output"
[[ -x "$installation/$name" ]] || fail "No installed copy."
/usr/bin/plutil -lint "$plist" >/dev/null
[[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw "$plist")" == "$installation/$name" ]] || fail "Unquoted executable path."
[[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw "$plist")" == start ]] || fail "Wrong command."
[[ "$(/usr/bin/plutil -extract LimitLoadToSessionType raw "$plist")" == Aqua ]] || fail "Not Aqua."
grep -q '^enable ' "$CALLS" || fail "Missing enable."
grep -q '^bootstrap ' "$CALLS" || fail "Missing bootstrap."
printf 'retained\n' > "$installation/daemon.log"
before="$(shasum -a 256 "$plist" "$installation/$name")"
export INSPECT_STATUS=1
expect_status 1 "$app_dir/scripts/uninstall.sh"
[[ "$(shasum -a 256 "$plist" "$installation/$name")" == "$before" ]] || fail "Inspection failure removed files."
expect_status 1 "$app_dir/scripts/install.sh" "$prebuilt"
[[ "$(shasum -a 256 "$plist" "$installation/$name")" == "$before" ]] || fail "Inspection failure replaced files."
export INSPECT_STATUS=0 BOOTOUT_STATUS=5
expect_status 5 "$app_dir/scripts/uninstall.sh"
[[ -f "$plist" ]] || fail "Bootout failure removed plist."
export BOOTOUT_STATUS=0
"$app_dir/scripts/uninstall.sh" > "$temporary/output"
[[ ! -e "$plist" && ! -e "$installation/$name" ]] || fail "Uninstall retained executable/plist."
[[ "$(< "$installation/daemon.log")" == retained ]] || fail "Uninstall lost log."
grep -q '^bootout ' "$CALLS" || fail "Loaded service not unloaded."
export INSPECT_STATUS=113
"$app_dir/scripts/uninstall.sh" > "$temporary/output"
echo "PASS: local lifecycle; absent/loaded/error/bootout statuses; spaces; logs."

fixture="$temporary/release fixture"
mkdir -p "$fixture/scripts"
cp "$app_dir/scripts/release.sh" "$fixture/scripts/"
cp "$app_dir/LICENSE" "$fixture/"
printf '0.1.0\n' > "$fixture/VERSION"
printf '# Changelog\n\n## [Unreleased]\n\n### Added\n\n- Next change.\n\n## [0.1.0] - 2026-11-13\n\n- Initial release.\n' > "$fixture/CHANGELOG.md"
cat > "$fixture/scripts/build.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
mkdir -p build/bin
cp /bin/echo build/bin/macos-dock-click-hide-toggle
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/scripts/test.sh"
chmod +x "$fixture/scripts/"*
snapshot() {
  (cd "$fixture"; find . -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
}
before="$(snapshot)"
for pair in 'patch 0.1.1' 'minor 0.2.0' 'major 1.0.0' '2.3.4 2.3.4'; do
  read -r bump expected <<< "$pair"
  "$fixture/scripts/release.sh" "$bump" --dry-run > "$temporary/output"
  grep -q " -> $expected;" "$temporary/output" || fail "Wrong bump."
done
[[ "$(snapshot)" == "$before" ]] || fail "Dry-run mutated files."
expect_status 1 "$fixture/scripts/release.sh" 01.2.3 --dry-run
expect_status 1 "$fixture/scripts/release.sh" 0.0.9 --dry-run
expect_status 1 "$fixture/scripts/release.sh" 0.1.0 --dry-run
expect_status 1 "$fixture/scripts/release.sh" patch --yes
grep -q 'Working tree must be clean' "$temporary/output" || fail "Dirty publish not rejected."
"$fixture/scripts/release.sh" 0.1.0 --prepare --yes > "$temporary/output"
asset="$fixture/build/release/$name-0.1.0-macos-arm64.tar.gz"
sha="$(shasum -a 256 "$asset" | awk '{print $1}')"
grep -q "sha256 \"$sha\"" "$fixture/Formula/$name.rb" || fail "Wrong formula SHA."
[[ "$(tar -tzf "$asset" | LC_ALL=C sort)" == "$(printf 'LICENSE\n%s' "$name")" ]] || fail "Wrong archive layout."
"$fixture/scripts/release.sh" patch --prepare --yes > "$temporary/output"
[[ "$(< "$fixture/VERSION")" == 0.1.1 ]] || fail "Version not updated."
grep -q '^## \[0.1.1\] - ' "$fixture/CHANGELOG.md" || fail "Changelog not promoted."
grep -q 'Next change.' "$fixture/build/release/$name-0.1.1-notes.md" || fail "Missing release notes."
[[ "$(grep -c '^## \[Unreleased\]$' "$fixture/CHANGELOG.md")" -eq 1 ]] || fail "Unreleased heading lost."
echo "PASS: release bumps/validation; nonmutating dry-run; dirty-tree rejection; prepare archive/hash/notes."
