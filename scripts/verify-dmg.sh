#!/bin/bash
# Checks a built DMG: the image verifies, it holds the app at the expected version, signed and Apple Silicon only,
# next to an Applications link. CI runs it on every push and pull request, and release.yml before publishing.
# Usage: scripts/verify-dmg.sh <dmg> <version>
set -euo pipefail

dmg="${1:?usage: scripts/verify-dmg.sh <dmg> <version>}"
version="${2:?usage: scripts/verify-dmg.sh <dmg> <version>}"
app_name="한글 파일명 정리기.app"
executable="Hangeul Filename Fixer"

fail() {
  echo "::error::$*"
  exit 1
}

[[ -f "$dmg" ]] || fail "$dmg 가 없습니다."
hdiutil verify -quiet "$dmg" || fail "$dmg 이미지 검사(hdiutil verify)에 실패했습니다."

mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/hangeul-filename-fixer-dmg.XXXXXX")"
trap 'hdiutil detach -quiet "$mount_dir" 2>/dev/null || true; rmdir "$mount_dir" 2>/dev/null || true' EXIT
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mount_dir" "$dmg"

app="$mount_dir/$app_name"
[[ -d "$app" ]] || fail "DMG 안에 $app_name 이 없습니다."
[[ "$(readlink "$mount_dir/Applications" || true)" == /Applications ]] || fail "DMG 안에 Applications 바로가기가 없습니다."

actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$actual" == "$version" ]] || fail "DMG 안 앱 버전이 $actual 입니다 ($version 이어야 합니다)."

codesign --verify --deep --strict "$app" || fail "DMG 안 앱의 서명 확인(codesign --verify)에 실패했습니다."

archs="$(lipo -archs "$app/Contents/MacOS/$executable")"
[[ "$archs" == arm64 ]] || fail "앱 아키텍처가 '$archs' 입니다 (arm64 이어야 합니다)."

echo "OK  ${dmg##*/}: $app_name $actual, $archs, 서명 확인됨"
