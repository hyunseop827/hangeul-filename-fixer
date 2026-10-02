#!/bin/bash
# Checks a built DMG: the image verifies and holds the app next to an Applications link; the app has the expected
# version, an integer build number and the right bundle identifier; its executable is universal (exactly arm64 and
# x86_64), each half built for the macOS in LSMinimumSystemVersion; the signature verifies and has the hardened
# runtime; the Korean texts and the icon are inside.
# The updater: Sparkle.framework is the one library in the bundle and the only one the executable looks for, there and
# nowhere else; everything else the executable and the framework load is part of macOS; its XPC services are gone; the
# framework and its two helpers run on both architectures and on the
# app's oldest macOS, and are signed with the hardened runtime and without entitlements; the app has exactly one
# entitlement; Info.plist has the feed and the update settings; the framework's Korean texts and the license texts
# are inside. A key for updates that is still the placeholder is reported, not failed (see below).
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
# The updater (Sparkle): where installed copies ask for updates, the name the executable asks for the framework by, the
# one folder it is looked up in, and the app's one entitlement (as codesign and plutil print it).
feed_url="https://github.com/hyunseop827/hangeul-filename-fixer/releases/latest/download/appcast.xml"
sparkle_install_name="@rpath/Sparkle.framework/Versions/B/Sparkle"
frameworks_rpath="@executable_path/../Frameworks"
entitlements='{"com.apple.security.cs.disable-library-validation":true}'

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
# An integer from 1 up without leading zeros: what Sparkle compares (sparkle:version), in the one form the release accepts.
[[ "$actual_build" =~ ^[1-9][0-9]*$ ]] || fail "DMG 안 앱의 빌드 번호(CFBundleVersion)가 '$actual_build' 입니다 (1 이상의 정수여야 합니다)."
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

# The signature's flags, for one architecture of a signed bundle or file ("adhoc,runtime").
signature_flags() {
  codesign --display --verbose=2 --architecture "$1" "$2" 2>&1 | sed -n 's/^CodeDirectory .*flags=[^(]*(\(.*\)).*$/\1/p' || true
}
# The entitlements in the signature, for one architecture, as one line of JSON; nothing or {} when there are none.
signature_entitlements() {
  { codesign --display --architecture "$1" --entitlements - --xml "$2" 2> /dev/null || true; } | { plutil -convert json -o - - 2> /dev/null || true; }
}

codesign --verify --deep --strict "$app" || fail "DMG 안 앱의 서명 확인(codesign --verify)에 실패했습니다."
for arch in $archs; do
  flags="$(signature_flags "$arch" "$app")"
  [[ ",$flags," == *,runtime,* ]] || fail "$arch 실행 파일의 서명에 hardened runtime 이 없습니다 (flags: '${flags:-없음}')."
  # Exactly one entitlement: the hardened runtime may load Sparkle.framework, which is ad-hoc signed like the app.
  # Anything more (JIT, unsigned memory, Apple Events, …) would lower what the hardened runtime protects.
  actual_entitlements="$(signature_entitlements "$arch" "$app")"
  [[ "$actual_entitlements" == "$entitlements" ]] \
    || fail "$arch 실행 파일의 권한(entitlements)이 '${actual_entitlements:-없음}' 입니다 (com.apple.security.cs.disable-library-validation 하나만 있어야 합니다)."
done

# Sparkle.framework: the only library in the bundle, complete (the executable loads it through Versions/B), without
# the XPC services (they serve sandboxed apps only; this app has no sandbox).
frameworks="$app/Contents/Frameworks"
framework="$frameworks/Sparkle.framework"
[[ -f "$framework/Versions/B/Sparkle" && "$(readlink "$framework/Versions/Current" || true)" == B ]] \
  || fail "DMG 안 앱에 Sparkle.framework(Contents/Frameworks)가 없거나 온전하지 않습니다."
others="$(cd "$frameworks" && find . -mindepth 1 -maxdepth 1 ! -name Sparkle.framework | tr '\n' ' ')"
[[ -z "$others" ]] || fail "DMG 안 앱의 Contents/Frameworks 에 Sparkle.framework 말고 다른 것이 있습니다: $others"
xpc="$(cd "$app" && find . \( -name XPCServices -o -name '*.xpc' \) | tr '\n' ' ')"
[[ -z "$xpc" ]] || fail "DMG 안 앱에 Sparkle 의 XPC 서비스가 남아 있습니다: $xpc"
sparkle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$framework/Versions/B/Resources/Info.plist" 2> /dev/null || true)"
[[ -n "$sparkle_version" ]] || fail "Sparkle.framework 의 버전을 읽지 못했습니다."

# What is loaded into the app's process. The app is signed to load a library Apple's rules would refuse (its
# entitlement), so every load command is looked at, for both architectures:
# - the executable loads Sparkle.framework by its one name, and otherwise only libraries that are part of macOS
#   (/System/Library, /usr/lib; nobody can write there). A library named by any other path (/usr/local/lib,
#   @executable_path/…, @loader_path/…, another @rpath name) would be loaded from wherever somebody put it;
# - the framework is looked for in the bundle only (LC_RPATH; /usr/lib/swift is part of macOS);
# - the framework has that name, and itself loads nothing but macOS.
rpaths() {
  otool -arch "$1" -l "$2" | sed -n '/LC_RPATH/,/path /s/^ *path \(.*\) (offset [0-9]*)$/\1/p'
}
# Prints every library one architecture of a binary loads (its load commands; for a library, its own name too).
loaded_libraries() {
  otool -arch "$1" -L "$2" | awk 'NR > 1 { print $1 }'
}
# Fails unless one architecture of a binary ($2 of $3, called $4 in messages) loads $1 exactly once and otherwise only
# libraries of macOS.
check_loaded_libraries() {
  local expected="$1" arch="$2" file="$3" label="$4" libraries library count=0 foreign=""
  libraries="$(loaded_libraries "$arch" "$file")" || fail "$label ($arch) 이 불러오는 라이브러리를 읽지 못했습니다(otool)."
  while IFS= read -r library; do
    case "$library" in
      */../* | */..) foreign+=" '$library'" ;; # a path that climbs out of the folder it starts in
      "$expected") count=$((count + 1)) ;;
      /System/Library/* | /usr/lib/*) ;;
      *) foreign+=" '$library'" ;;
    esac
  done <<< "$libraries"
  [[ -z "$foreign" ]] \
    || fail "$label ($arch) 이 macOS에 들어 있지 않은 라이브러리를 불러옵니다:$foreign ($expected 와 /System/Library, /usr/lib 의 라이브러리만 불러와야 합니다)."
  [[ $count == 1 ]] || fail "$label ($arch) 이 $expected 를 ${count}번 불러옵니다 (한 번이어야 합니다)."
}
for arch in $archs; do
  check_loaded_libraries "$sparkle_install_name" "$arch" "$binary" "실행 파일"
  search="$(rpaths "$arch" "$binary" | { grep -vx '/usr/lib/swift' || true; } | xargs)"
  [[ "$search" == "$frameworks_rpath" ]] \
    || fail "$arch 실행 파일의 라이브러리 검색 경로(LC_RPATH)가 '${search:-없음}' 입니다 ($frameworks_rpath 하나여야 합니다)."
  # The architecture first: without it there is no install name to read, and the message would be about the name.
  lipo "$framework/Versions/B/Sparkle" -verify_arch "$arch" || fail "Sparkle.framework 에 $arch 가 없습니다."
  install_name="$(otool -arch "$arch" -D "$framework/Versions/B/Sparkle" | tail -n 1)"
  [[ "$install_name" == "$sparkle_install_name" ]] \
    || fail "Sparkle.framework ($arch) 의 설치 이름이 '$install_name' 입니다 ($sparkle_install_name 이어야 합니다)."
  # Its own name is the first entry of the list (LC_ID_DYLIB), so it stands exactly once.
  check_loaded_libraries "$sparkle_install_name" "$arch" "$framework/Versions/B/Sparkle" "Sparkle.framework"
done

# The framework and the two helpers Sparkle starts to install an update: every architecture of the app, not a newer
# macOS than the app's, a valid signature with the hardened runtime, and no entitlements (only the app has one).
for code in "$framework" "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app"; do
  name="${code#"$app"/Contents/Frameworks/}"
  case "$code" in
    *.framework) code_binary="$code/Versions/B/Sparkle" ;;
    *.app) code_binary="$code/Contents/MacOS/Updater" ;;
    *) code_binary="$code" ;;
  esac
  [[ -f "$code_binary" ]] || fail "DMG 안 앱에 $name 이 없습니다."
  codesign --verify --strict "$code" || fail "$name 의 서명 확인(codesign --verify)에 실패했습니다."
  for arch in $archs; do
    lipo "$code_binary" -verify_arch "$arch" || fail "$name 에 $arch 가 없습니다."
    minos="$(vtool -arch "$arch" -show-build "$code_binary" | awk '$1 == "minos" { print $2 }')" || fail "$name ($arch) 의 최소 macOS를 읽지 못했습니다(vtool)."
    # Not newer than the app's: the higher of the two versions is the app's own.
    highest="$(printf '%s\n' "$minos" "$min_macos" | sort -V | tail -n 1)"
    [[ -n "$minos" && "$(normalized_version "$highest")" == "$(normalized_version "$min_macos")" ]] \
      || fail "$name ($arch) 는 macOS '$minos' 이상이 필요합니다 (LSMinimumSystemVersion 은 $min_macos)."
    flags="$(signature_flags "$arch" "$code")"
    [[ ",$flags," == *,runtime,* ]] || fail "$name ($arch) 의 서명에 hardened runtime 이 없습니다 (flags: '${flags:-없음}')."
    actual_entitlements="$(signature_entitlements "$arch" "$code")"
    [[ -z "$actual_entitlements" || "$actual_entitlements" == "{}" ]] \
      || fail "$name ($arch) 에 권한(entitlements)이 있습니다: $actual_entitlements (앱에만 하나 있어야 합니다)."
  done
done

# Updates (Info.plist, read by Sparkle): the feed, a check once a day at Sparkle's default interval, never an install
# without the user, and every update verified before it is opened.
plist_typed() {
  plutil -extract "$1" raw -expect "$2" -o - "$plist" 2> /dev/null || true
}
actual_feed="$(plist_typed SUFeedURL string)"
[[ "$actual_feed" == "$feed_url" ]] || fail "DMG 안 앱의 SUFeedURL 이 '$actual_feed' 입니다 ($feed_url 이어야 합니다)."
[[ "$(plist_typed SUEnableAutomaticChecks bool)" == true ]] || fail "DMG 안 앱의 SUEnableAutomaticChecks 가 true 가 아닙니다 (하루에 한 번 업데이트를 확인해야 합니다)."
[[ "$(plist_typed SUAllowsAutomaticUpdates bool)" == false ]] || fail "DMG 안 앱의 SUAllowsAutomaticUpdates 가 false 가 아닙니다 (업데이트는 사용자가 골라서 설치해야 합니다)."
[[ "$(plist_typed SUVerifyUpdateBeforeExtraction bool)" == true ]] || fail "DMG 안 앱의 SUVerifyUpdateBeforeExtraction 이 true 가 아닙니다 (업데이트를 열기 전에 서명을 확인해야 합니다)."
[[ -z "$(plist_value SUScheduledCheckInterval)" ]] || fail "DMG 안 앱에 SUScheduledCheckInterval 이 있습니다 (Sparkle 의 기본 간격, 하루를 써야 합니다)."
public_key="$(plist_typed SUPublicEDKey string)"
[[ -n "$public_key" ]] || fail "DMG 안 앱의 Info.plist 에 SUPublicEDKey 가 없습니다."
# A real key is an Ed25519 public key: 32 bytes in base64, 44 characters. While Resources/Info.plist still has the
# placeholder, this is a notice and not a failure: this script also checks the builds of pull requests, which must keep
# building until the owner has put the key in. Such an app starts no updater (AppUpdater.swift). It can never be
# released: the unit tests fail on the placeholder, and so does the release workflow before it signs anything.
key_note=""
if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "::notice::DMG 안 앱의 SUPublicEDKey 가 아직 실제 키가 아닙니다 ('$public_key'). 이 앱은 업데이트를 확인하지 않습니다. 저장소 소유자가 Resources/Info.plist 에 공개 키를 넣어야 릴리스할 수 있습니다."
  key_note=", 업데이트 키 없음(자리표시자)"
fi

resources="$app/Contents/Resources"
[[ -s "$resources/ko.lproj/Localizable.strings" ]] || fail "DMG 안 앱에 한국어 문구(ko.lproj/Localizable.strings)가 없습니다."
# Sparkle's windows are Korean because the framework has a ko.lproj: a framework shows its texts in the language of
# the app that loads it, and Korean is this app's only language.
[[ -s "$framework/Versions/B/Resources/ko.lproj/Sparkle.strings" ]] || fail "DMG 안 앱의 Sparkle.framework 에 한국어 문구(ko.lproj/Sparkle.strings)가 없습니다."
# The license texts of Sparkle and of the code it includes ship with the app, for the version that is inside.
grep -qx "Sparkle $sparkle_version" "$resources/ThirdPartyNotices.txt" 2> /dev/null \
  || fail "DMG 안 앱에 Sparkle $sparkle_version 의 고지(Contents/Resources/ThirdPartyNotices.txt)가 없습니다."
icon="$(plist_value CFBundleIconFile)"
[[ -n "$icon" ]] || fail "DMG 안 앱의 Info.plist 에 CFBundleIconFile 이 없습니다."
[[ -s "$resources/${icon%.icns}.icns" ]] || fail "DMG 안 앱에 아이콘(Contents/Resources/${icon%.icns}.icns)이 없습니다."

echo "OK  ${dmg##*/}: $app_name $actual (빌드 $actual_build), $archs, macOS $min_macos 이상, 서명 확인됨(hardened runtime), Sparkle $sparkle_version$key_note"
