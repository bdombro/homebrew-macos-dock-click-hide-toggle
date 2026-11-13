#!/usr/bin/env bash
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$app_dir"
name=macos-dock-click-hide-toggle
repo="bdombro/$name"
usage() {
  echo "Usage: scripts/release.sh <patch|minor|major|X.Y.Z> [--dry-run] [--prepare] [--yes]"
  echo "--prepare builds and updates local release files only; permits the current version."
}
fail() { echo "$*" >&2; exit 1; }
target=""
dry_run=false
prepare=false
yes=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --prepare) prepare=true ;;
    --yes) yes=true ;;
    --help|-h) usage; exit 0 ;;
    --*) usage >&2; exit 1 ;;
    *) [[ -z "$target" ]] || fail "Specify exactly one version or bump."; target="$arg" ;;
  esac
done
[[ -n "$target" ]] || { usage >&2; exit 1; }
valid_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$ ]]
}
current="$(< VERSION)"
valid_version "$current" || fail "VERSION must contain a numeric X.Y.Z version (components <= 999999)."
IFS=. read -r major minor patch <<< "$current"
case "$target" in
  major) target="$((major + 1)).0.0" ;;
  minor) target="$major.$((minor + 1)).0" ;;
  patch) target="$major.$minor.$((patch + 1))" ;;
esac
valid_version "$target" || fail "Invalid release version."
if [[ "$target" == "$current" ]]; then
  $prepare || fail "Publishing requires a version newer than VERSION; use --prepare for initial artifacts."
else
  awk -v old="$current" -v new="$target" 'BEGIN {
    split(old,a,"."); split(new,b,".");
    for(i=1;i<=3;i++) { if(b[i]>a[i]) exit 0; if(b[i]<a[i]) exit 1 }
    exit 1
  }' || fail "Release version must increase."
  if grep -Fq "## [$target]" CHANGELOG.md; then
    fail "Target version already exists in CHANGELOG.md."
  fi
fi
[[ "$(grep -c '^## \[Unreleased\]$' CHANGELOG.md)" == 1 ]] || fail "Expected one Unreleased heading."
if [[ "$target" == "$current" ]]; then
  grep -Fq "## [$target] - " CHANGELOG.md || fail "Current release needs dated changelog notes."
fi
asset="$name-$target-macos-arm64.tar.gz"
if $dry_run; then
  printf '[dry-run] %s -> %s; validate tests, build/sign arm64 macOS 13, archive %s, hash and update formula/changelog/VERSION.\n' "$current" "$target" "$asset"
  if $prepare; then
    echo "[dry-run] Prepare only: no Git or network operations."
  else
    echo "[dry-run] Publishing would require a clean Git tree, origin and unused tag; commit only release metadata, tag, atomic push, gh release create."
  fi
  echo "[dry-run] Nothing changed; build, signing and publication preflights were not executed."
  exit 0
fi
if ! $prepare; then
  [[ "$(git rev-parse --show-toplevel)" == "$app_dir" ]] || fail "Run from the project Git repository."
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "Working tree must be clean, including untracked files."
  branch="$(git symbolic-ref --quiet --short HEAD)" || fail "Detached HEAD is not supported."
  origin="$(git remote get-url origin)"
  case "$origin" in
    "https://github.com/$repo"|"https://github.com/$repo.git"|"git@github.com:$repo.git") ;;
    *) fail "origin must point to the public project repository." ;;
  esac
  if git show-ref --verify --quiet "refs/tags/v$target"; then fail "Tag already exists locally."; fi
  remote_tag="$(git ls-remote --tags origin "refs/tags/v$target")"
  [[ -z "$remote_tag" ]] || fail "Tag already exists remotely."
  gh auth status --hostname github.com >/dev/null 2>&1 || fail "Authenticate gh before publishing."
fi
if ! $yes; then
  [[ -t 0 ]] || fail "Not a TTY; pass --yes to confirm."
  if $prepare; then action="prepare local artifacts"; else action="commit, tag, push and publish"; fi
  read -r -p "Release v$target ($action)? [y/N] " answer
  [[ "$answer" == y || "$answer" == Y ]] || { echo "Aborted."; exit 0; }
fi
./scripts/test.sh
./scripts/build.sh
mkdir -p build/release Formula
temporary="$(mktemp -d "$app_dir/build/release/.prepare.XXXXXX")"
stage=preparation
cleanup() {
  status=$?
  rm -rf -- "$temporary"
  if [[ "$status" -ne 0 ]]; then
    echo "Release stopped during $stage. Inspect local files and remote state before retrying; no rollback or forced overwrite is attempted." >&2
  fi
}
trap cleanup EXIT
printf '%s\n' "$target" > "$temporary/VERSION"
if [[ "$target" == "$current" ]]; then
  cp CHANGELOG.md "$temporary/CHANGELOG.md"
else
  awk -v version="$target" -v date="$(date -u +%F)" '
    {print}
    /^## \[Unreleased\]$/ {printf "\n## [%s] - %s\n",version,date}
  ' CHANGELOG.md > "$temporary/CHANGELOG.md"
fi
awk -v version="$target" '
  /^## / {
    if(found) exit
    if(index($0,"## [" version "] - ")==1) found=1
    next
  }
  found {print}
' "$temporary/CHANGELOG.md" > "$temporary/notes.md"
grep -q '[^[:space:]]' "$temporary/notes.md" || fail "Add release notes under Unreleased before bumping."
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$temporary/$asset" \
  -C "$app_dir/build/bin" "$name" -C "$app_dir" LICENSE
sha="$(shasum -a 256 "$temporary/$asset" | awk '{print $1}')"
cat > "$temporary/formula.rb" <<EOF
class MacosDockClickHideToggle < Formula
  desc "Click a frontmost application's Dock icon to hide it"
  homepage "https://github.com/$repo"
  url "https://github.com/$repo/releases/download/v$target/$asset"
  sha256 "$sha"
  license "ISC"

  depends_on arch: :arm64
  depends_on :macos
  on_macos do
    depends_on macos: :ventura
  end

  def install
    bin.install "$name"
  end

  service do
    run [opt_bin/"$name", "start"]
    keep_alive successful_exit: false
    # Homebrew includes Aqua in its generated session types; use without sudo.
    working_dir var
    log_path var/"log/$name.log"
    error_log_path var/"log/$name.log"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/$name --help")
  end
end
EOF
ruby -c "$temporary/formula.rb"
mv -f "$temporary/$asset" "build/release/$asset"
mv -f "$temporary/notes.md" "build/release/$name-$target-notes.md"
mv -f "$temporary/VERSION" VERSION
mv -f "$temporary/CHANGELOG.md" CHANGELOG.md
mv -f "$temporary/formula.rb" "Formula/$name.rb"
printf 'Prepared build/release/%s\nSHA-256: %s\n' "$asset" "$sha"
if $prepare; then
  echo "Prepare only: no commit, tag, push or publication. Parent may review and publish the initial release."
  exit 0
fi
stage="release metadata commit"
git add -- VERSION CHANGELOG.md "Formula/$name.rb"
git commit -m "chore: release v$target"
stage=tagging
git tag -a "v$target" -m "Release v$target"
stage="atomic branch/tag push"
git push --atomic origin "HEAD:refs/heads/$branch" "refs/tags/v$target"
stage="GitHub release publication"
gh release create "v$target" "build/release/$asset" --repo "$repo" \
  --verify-tag --title "v$target" --notes-file "build/release/$name-$target-notes.md"
echo "Published v$target."
