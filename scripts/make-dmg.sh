#!/bin/zsh
# Builds a release 한글 파일명 정리기.app (universal: arm64 + x86_64) and packs it into a compressed disk image.
#
#   ./scripts/make-dmg.sh [version]   → build/hangeul-filename-fixer-<version>.dmg and .dmg.sha256
#
# version: the argument, else APP_VERSION, else CFBundleShortVersionString of Resources/Info.plist
# (a leading "v", as in a v1.2.0 tag, is dropped). The app is built into build/release, never into
# build/한글 파일명 정리기.app, which may be running.
#
# Optional environment:
#   APP_BUILD   CFBundleVersion of the bundle, an integer (see build-app.sh); release.yml passes the CI run number
# The app is signed by build-app.sh: ad-hoc with the hardened runtime, unless its CODESIGN_IDENTITY says otherwise.
# The disk image itself is not signed and nothing is notarized.
# Under GitHub Actions the results are also written to $GITHUB_OUTPUT: app (the app that is inside the dmg, in
# build/release), dmg, sha256, version, build.
# The staging folder and the verification mount live in a temporary folder that is removed even on failure.
set -e
setopt pipefail
P="$(cd "$(dirname "$0")/.." && pwd)"
# The bundle's name, written precomposed (NFC), as in build-app.sh.
NAME="한글 파일명 정리기"

fail() { print -u2 "오류: $*"; exit 1 }

VERSION="${1:-${APP_VERSION:-}}"
if [[ -z "$VERSION" ]]; then
	VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$P/Resources/Info.plist")"
fi
VERSION="${VERSION#v}"
[[ "$VERSION" =~ '^[0-9A-Za-z._+-]+$' ]] || fail "버전 형식이 잘못되었습니다: '$VERSION' (예: 1.2.0, 1.2.0-beta.1)"
APP_DIR="$P/build/release"
APP="$APP_DIR/$NAME.app"
DMG="$P/build/hangeul-filename-fixer-$VERSION.dmg"
SHA="$DMG.sha256"

# mktemp and the path lookup are separate, checked steps: inside `cd "$(mktemp …)"` a failed mktemp would make zsh run
# `cd ""` (which succeeds), and WORK would silently become the current directory — which the cleanup would then delete.
WORK_NEW="$(mktemp -d "${TMPDIR:-/tmp}/hangeul-filename-fixer-dmg.XXXXXX")" || fail "임시 폴더를 만들지 못했습니다 (TMPDIR=${TMPDIR:-/tmp})."
[[ -n "$WORK_NEW" && -d "$WORK_NEW" && "${WORK_NEW:t}" == hangeul-filename-fixer-dmg.* ]] || fail "임시 폴더 경로가 이상합니다: '$WORK_NEW'"
WORK="$WORK_NEW"
MNT=""
is_mounted() { [[ "$(mount)" == *" on $1 ("* ]] }
# Detaches the verification mount. hdiutil sometimes answers "Resource busy" for a moment (something is still reading
# the new volume), so: try, wait, try again, then force. The mount is read-only, so forcing loses nothing.
detach_image() {
	if hdiutil detach "$1" -quiet; then return 0; fi
	print -u2 "hdiutil detach 실패, 다시 시도"
	sleep 2
	if hdiutil detach "$1" -quiet; then return 0; fi
	print -u2 "hdiutil detach 실패, 강제로 분리"
	hdiutil detach "$1" -force -quiet
}
# Deletes only the folder made above: anything that is not a directory named hangeul-filename-fixer-dmg.* is left alone.
remove_work() { if [[ -n "$WORK" && "${WORK:t}" == hangeul-filename-fixer-dmg.* && -d "$WORK" ]]; then rm -rf -- "$WORK"; fi }
cleanup() {
	local rc=$?
	if [[ -n "$MNT" ]] && is_mounted "$MNT"; then
		detach_image "$MNT" || true
	fi
	if [[ -n "$MNT" ]] && is_mounted "$MNT"; then
		print -u2 "경고: $MNT 를 분리하지 못해 $WORK 를 남겨 둡니다. hdiutil detach -force 후 지우세요."
		rc=1
	else
		remove_work || true
	fi
	# Outputs are only moved into build/ at the very end; never leave a half-finished pair behind.
	if [[ $rc != 0 ]]; then rm -f "$DMG" "$SHA"; fi
	exit $rc
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# Physical path (/var → /private/var), so it matches what `mount` reports for the verification mount.
WORK_REAL="$(cd -- "$WORK" && pwd -P)" || fail "임시 폴더 경로를 확인하지 못했습니다: $WORK"
[[ "$WORK_REAL" == /* && "${WORK_REAL:t}" == hangeul-filename-fixer-dmg.* ]] || fail "임시 폴더 경로가 이상합니다: '$WORK_REAL'"
WORK="$WORK_REAL"
rm -f "$DMG" "$SHA"

echo "## 1. release 빌드 → ${APP#$P/}"
OUTPUT_DIR="$APP_DIR" APP_VERSION="$VERSION" "$P/scripts/build-app.sh" release

echo "## 2. 디스크 이미지 만들기"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
OUT="$WORK/out.dmg"
# HFS+ and zlib (UDZO), as the 1.x images were: every macOS opens it. HFS+ stores names decomposed, so inside the image
# the app's name is NFD whatever is written here; macOS finds it under either spelling.
# hdiutil occasionally reports "Resource busy" on CI machines; a short retry is the usual cure.
for attempt in 1 2 3; do
	if hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT"; then break; fi
	if [[ $attempt == 3 ]]; then fail "hdiutil create 가 실패했습니다."; fi
	print -u2 "hdiutil create 실패, 다시 시도 ($attempt/3)"
	sleep $((attempt * 5))
done

echo "## 3. 검사 (verify, 읽기 전용 마운트)"
hdiutil verify -quiet "$OUT"
MNT="$WORK/mnt"
mkdir -p "$MNT"
hdiutil attach "$OUT" -nobrowse -readonly -noautoopen -noverify -mountpoint "$MNT" -quiet
[[ -d "$MNT/$NAME.app" ]] || fail "디스크 이미지에 앱이 없습니다."
[[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == /Applications ]] || fail "Applications 링크가 없습니다."
MOUNTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MNT/$NAME.app/Contents/Info.plist")"
[[ "$MOUNTED_VERSION" == "$VERSION" ]] || fail "앱 버전이 다릅니다: $MOUNTED_VERSION ≠ $VERSION"
MOUNTED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MNT/$NAME.app/Contents/Info.plist")"
# The updater's framework came along with its symlinks (the executable loads it through Versions/B), and so did the
# license texts that must ship with it.
MOUNTED_FW="$MNT/$NAME.app/Contents/Frameworks/Sparkle.framework"
[[ -f "$MOUNTED_FW/Versions/B/Sparkle" && -L "$MOUNTED_FW/Versions/Current" && -L "$MOUNTED_FW/Sparkle" ]] \
	|| fail "디스크 이미지의 앱에 Sparkle.framework(Contents/Frameworks)가 없거나 온전하지 않습니다."
NOTICES="$MNT/$NAME.app/Contents/Resources/ThirdPartyNotices.txt"
[[ -f "$NOTICES" ]] && cmp -s "$NOTICES" "$P/Resources/ThirdPartyNotices.txt" \
	|| fail "앱의 서드파티 고지(Contents/Resources/ThirdPartyNotices.txt)가 없거나 Resources/ThirdPartyNotices.txt 와 다릅니다."
codesign --verify --deep --strict "$MNT/$NAME.app"
echo "  OK  앱, Applications 링크, 버전 $MOUNTED_VERSION (빌드 $MOUNTED_BUILD), Sparkle.framework, 서드파티 고지, 서명"
# Called in a subshell: a signal that arrives while zsh is inside a function ends the script without running the EXIT
# trap (the cleanup above). The subshell makes the call an ordinary command of the script, where the trap does run.
(detach_image "$MNT") || fail "검사를 마친 디스크 이미지를 분리하지 못했습니다(hdiutil detach)."
MNT=""

mv "$OUT" "$DMG"
(cd "${DMG:h}" && shasum -a 256 "${DMG:t}" >"${SHA:t}")
echo "dmg: $DMG"
echo "sha256: $(cut -d' ' -f1 <"$SHA")"
echo "서명: 앱만 (디스크 이미지는 서명 안 됨), 공증 안 됨"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	{
		print -r -- "app=$APP"
		print -r -- "dmg=$DMG"
		print -r -- "sha256=$SHA"
		print -r -- "version=$VERSION"
		print -r -- "build=$MOUNTED_BUILD"
	} >>"$GITHUB_OUTPUT"
fi
