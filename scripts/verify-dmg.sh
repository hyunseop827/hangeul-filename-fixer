#!/bin/bash
# Checks a built DMG: the image verifies and holds the app next to an Applications link; the app has the expected
# version, an integer build number and the right bundle identifier; its executable is universal (exactly arm64 and
# x86_64), each half built for the macOS in LSMinimumSystemVersion; the signature verifies and has the hardened
# runtime; the Korean texts and the icon are inside.
# CI runs it on every push to main and every pull request, and release.yml before publishing.
# The image is mounted read-only in a temporary folder and always detached again (if that fails, so does the script).
# An image that is open already (in Finder, for example) cannot be checked: eject it first.
# Usage: scripts/verify-dmg.sh <dmg> <version> [build]
#   build: when given, CFBundleVersion must be exactly this number (release.yml passes the CI run number)
set -euo pipefail

usage="usage: scripts/verify-dmg.sh <dmg> <version> [build]"
dmg="${1:?$usage}"
version="${2:?$usage}"
build="${3:-}"
app_name="한글 파일명 정리기.app"
executable="HangeulFilenameFixer"
bundle_id="app.hangeul-filename-fixer.desktop"

fail() {
  echo "::error::$*"
  exit 1
}

# 12.0 and 12 are the same version; tools print either.
normalized_version() {
  local v="$1"
  while [[ "$v" == *.0 ]]; do v="${v%.0}"; done
  printf '%s' "$v"
}

[[ -f "$dmg" ]] || fail "$dmg 가 없습니다."
hdiutil verify -quiet "$dmg" || fail "$dmg 이미지 검사(hdiutil verify)에 실패했습니다."

mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/hangeul-filename-fixer-dmg.XXXXXX")"
# Physical path (/var → /private/var), so it matches what `mount` reports.
mount_dir="$(cd "$mount_dir" && pwd -P)"
is_mounted() { [[ "$(mount)" == *" on $mount_dir ("* ]]; }
# The image must never stay attached after this script: an attached image cannot be attached a second time, so the
# next user of the file (ci.yml starts the app from it right after this check) would fail. hdiutil sometimes answers
# "Resource busy" for a moment, so: try, wait, try again, then force. The mount is read-only, so forcing loses nothing.
cleanup() {
  local rc=$?
  if is_mounted; then
    hdiutil detach -quiet "$mount_dir" 2> /dev/null \
      || { sleep 2; hdiutil detach -quiet "$mount_dir" 2> /dev/null; } \
      || hdiutil detach -quiet -force "$mount_dir" \
      || true
  fi
  if is_mounted; then
    echo "::error::검사에 쓴 마운트 $mount_dir 를 분리하지 못했습니다. hdiutil detach -force 로 분리한 뒤 다시 실행하세요."
    if [[ $rc -eq 0 ]]; then rc=1; fi
  else
    rmdir "$mount_dir" 2> /dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT

# Where the image is attached already, if it is: its first mount point, else its device (hdiutil info lists every
# attached image as a block that starts with "image-path", followed by one line per device).
attached_at() {
  local image
  image="$(cd "$(dirname "$dmg")" && pwd -P)/${dmg##*/}"
  { hdiutil info 2> /dev/null || true; } | awk -F '\t' -v image="$image" '
    /^=+$/ { current = 0 }
    index($0, "image-path") == 1 { path = $0; sub(/^image-path[ ]*:[ ]*/, "", path); current = (path == image) }
    current && /^\/dev\// {
      if (device == "") device = $1
      if (mount_point == "" && NF >= 3 && $3 != "") mount_point = $3
    }
    END { if (mount_point != "") print mount_point; else if (device != "") print device }
  '
}

if ! hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mount_dir" "$dmg"; then
  where="$(attached_at || true)"
  if [[ -n "$where" ]]; then
    fail "$dmg 가 이미 열려 있어서($where) 검사할 수 없습니다. 꺼낸 뒤(Finder의 꺼내기 또는 hdiutil detach) 다시 실행하세요."
  fi
  fail "$dmg 를 열지 못했습니다(hdiutil attach). 이미 열려 있다면 꺼낸 뒤 다시 실행하세요."
fi

app="$mount_dir/$app_name"
[[ -d "$app" ]] || fail "DMG 안에 $app_name 이 없습니다."
[[ "$(readlink "$mount_dir/Applications" || true)" == /Applications ]] || fail "DMG 안에 Applications 바로가기가 없습니다."

plist="$app/Contents/Info.plist"
[[ -f "$plist" ]] || fail "DMG 안 앱에 Info.plist 가 없습니다."
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true
}

actual="$(plist_value CFBundleShortVersionString)"
[[ "$actual" == "$version" ]] || fail "DMG 안 앱 버전이 '$actual' 입니다 ($version 이어야 합니다)."

actual_build="$(plist_value CFBundleVersion)"
[[ "$actual_build" =~ ^[0-9]+$ ]] || fail "DMG 안 앱의 빌드 번호(CFBundleVersion)가 '$actual_build' 입니다 (정수여야 합니다)."
if [[ -n "$build" && "$actual_build" != "$build" ]]; then
  fail "DMG 안 앱의 빌드 번호(CFBundleVersion)가 $actual_build 입니다 ($build 이어야 합니다)."
fi

actual_id="$(plist_value CFBundleIdentifier)"
[[ "$actual_id" == "$bundle_id" ]] || fail "DMG 안 앱의 번들 ID가 '$actual_id' 입니다 ($bundle_id 이어야 합니다)."

actual_executable="$(plist_value CFBundleExecutable)"
[[ "$actual_executable" == "$executable" ]] || fail "DMG 안 앱의 실행 파일 이름(CFBundleExecutable)이 '$actual_executable' 입니다 ($executable 이어야 합니다)."
binary="$app/Contents/MacOS/$executable"
[[ -f "$binary" && -x "$binary" ]] || fail "DMG 안 앱에 실행 파일 Contents/MacOS/$executable 이 없습니다."

archs="$(lipo -archs "$binary" | tr ' ' '\n' | sort | xargs)" || fail "실행 파일의 아키텍처를 읽지 못했습니다(lipo)."
[[ "$archs" == "arm64 x86_64" ]] || fail "앱 아키텍처가 '$archs' 입니다 (arm64 와 x86_64 둘 다, 그 둘만 있어야 합니다)."

min_macos="$(plist_value LSMinimumSystemVersion)"
[[ -n "$min_macos" ]] || fail "DMG 안 앱의 Info.plist 에 LSMinimumSystemVersion 이 없습니다."
for arch in $archs; do
  minos="$(vtool -arch "$arch" -show-build "$binary" | awk '$1 == "minos" { print $2 }')" || fail "$arch 실행 파일의 최소 macOS를 읽지 못했습니다(vtool)."
  [[ -n "$minos" && "$(normalized_version "$minos")" == "$(normalized_version "$min_macos")" ]] \
    || fail "$arch 실행 파일의 최소 macOS가 '$minos' 입니다 (LSMinimumSystemVersion 은 $min_macos)."
done

codesign --verify --deep --strict "$app" || fail "DMG 안 앱의 서명 확인(codesign --verify)에 실패했습니다."
for arch in $archs; do
  flags="$(codesign --display --verbose=2 --architecture "$arch" "$app" 2>&1 | sed -n 's/^CodeDirectory .*flags=[^(]*(\(.*\)).*$/\1/p' || true)"
  [[ ",$flags," == *,runtime,* ]] || fail "$arch 실행 파일의 서명에 hardened runtime 이 없습니다 (flags: '${flags:-없음}')."
done

resources="$app/Contents/Resources"
[[ -s "$resources/ko.lproj/Localizable.strings" ]] || fail "DMG 안 앱에 한국어 문구(ko.lproj/Localizable.strings)가 없습니다."
icon="$(plist_value CFBundleIconFile)"
[[ -n "$icon" ]] || fail "DMG 안 앱의 Info.plist 에 CFBundleIconFile 이 없습니다."
[[ -s "$resources/${icon%.icns}.icns" ]] || fail "DMG 안 앱에 아이콘(Contents/Resources/${icon%.icns}.icns)이 없습니다."

echo "OK  ${dmg##*/}: $app_name $actual (빌드 $actual_build), $archs, macOS $min_macos 이상, 서명 확인됨(hardened runtime)"
