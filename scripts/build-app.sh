#!/bin/zsh
# Builds 한글 파일명 정리기.app with SwiftPM only (no Xcode project needed) and signs it.
#
#   ./scripts/build-app.sh [debug|release]      → build/한글 파일명 정리기.app (ad-hoc signed, hardened runtime)
#
# debug (the default) is built for this Mac's architecture only and also contains the development hooks (`#if DEBUG`);
# release is universal (arm64 + x86_64) and leaves them out. A release build needs Xcode: the Command Line Tools
# alone cannot link the x86_64 half (their Swift compatibility libraries are Apple Silicon only).
#
# Optional environment:
#   APP_VERSION        CFBundleShortVersionString of the bundle (default: the value in Resources/Info.plist)
#   APP_BUILD          CFBundleVersion of the bundle, an integer, e.g. 42 (default: the value in Resources/Info.plist)
#   OUTPUT_DIR         folder that receives the .app (default: build; relative to the repository root)
#   CODESIGN_IDENTITY  "-" (default) signs ad-hoc; a certificate name signs with that certificate. Either way with the
#                      hardened runtime and without entitlements (the app needs none).
# Only the Info.plist copy inside the bundle is edited; Resources/Info.plist is never changed.
set -e
P="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${1:-debug}"
case "$CONF" in
	debug|release) ;;
	*) print -u2 "사용법: $0 [debug|release]"; exit 2 ;;
esac
OUT="${OUTPUT_DIR:-build}"
[[ "$OUT" == /* ]] || OUT="$P/$OUT"
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ -n "${APP_VERSION:-}" && ! "$APP_VERSION" =~ '^[0-9A-Za-z._+-]+$' ]]; then
	print -u2 "APP_VERSION 형식이 잘못되었습니다: '$APP_VERSION' (예: 1.2.0, 1.2.0-beta.1)"; exit 2
fi
if [[ -n "${APP_BUILD:-}" && ! "$APP_BUILD" =~ '^[0-9]+$' ]]; then
	print -u2 "APP_BUILD 형식이 잘못되었습니다: '$APP_BUILD' (정수, 예: 42)"; exit 2
fi
cd "$P"
source "$P/scripts/toolchain.sh"
echo "toolchain: $DEVELOPER_DIR"
# The bundle's name, written precomposed (NFC), and the executable inside it (the SwiftPM product).
APP_NAME="한글 파일명 정리기"
PRODUCT="HangeulFilenameFixer"
# The oldest macOS the app runs on: Package.swift (platforms) makes the compiler target it, Info.plist tells
# LaunchServices. Every slice is checked against this value below, so the two cannot drift apart unnoticed.
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# 12.0 and 12 are the same version; tools print either.
normalized_version() {
	local v="$1"
	while [[ "$v" == *.0 ]]; do v="${v%.0}"; done
	print -r -- "$v"
}
# Prints "<minos> <sdk>" of a single-architecture binary (LC_BUILD_VERSION).
build_version() {
	vtool -show-build "$1" | awk '$1 == "minos" { minos = $2 } $1 == "sdk" { sdk = $2 } END { print minos, sdk }'
}
SLICES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hangeul-filename-fixer-build.XXXXXX")"
trap 'rm -rf "$SLICES_DIR"' EXIT
# Builds the product for one architecture ("" = this Mac's) and leaves a checked copy in $SLICES_DIR.
build_slice() {
	local arch="$1" triple=() bin_dir slice versions minos sdk
	if [[ -n "$arch" ]]; then triple=(--triple "$arch-apple-macosx"); fi
	swift build -c "$CONF" --product "$PRODUCT" "${triple[@]}" "${SWIFT_EXTRA[@]}"
	# The build system decides where products go (.build/<conf> is not always a symlink to them), so ask it.
	bin_dir="$(swift build -c "$CONF" "${triple[@]}" --show-bin-path "${SWIFT_EXTRA[@]}")"
	[[ -n "$arch" ]] || arch="$(lipo -archs "$bin_dir/$PRODUCT")"
	slice="$SLICES_DIR/$PRODUCT-$arch"
	cp "$bin_dir/$PRODUCT" "$slice"
	[[ "$(lipo -archs "$slice")" == "$arch" ]] || { print -u2 "$arch 용으로 빌드했는데 결과가 '$(lipo -archs "$slice")' 입니다."; exit 1; }
	versions=($(build_version "$slice"))
	minos="${versions[1]}" sdk="${versions[2]}"
	[[ "$(normalized_version "$minos")" == "$(normalized_version "$MIN_MACOS")" ]] \
		|| { print -u2 "$arch 빌드의 최소 macOS가 $minos 입니다 (Info.plist의 LSMinimumSystemVersion은 $MIN_MACOS)."; exit 1; }
	# The SDK version recorded in the binary decides which behaviors and looks AppKit gives the app ("linked on or
	# after" checks): built with the macOS 26 SDK or later, a window gets the current title bar; an older SDK gets the
	# old one. SwiftPM's native build system (the default of Xcode 26, which CI uses) records the SDK it built with.
	# The Swift Build engine (the default of Xcode 27 / Swift 6.4) links without telling the linker the SDK version,
	# and the binary then claims the SDK of its deployment target (12.0), so macOS would treat the app as one built
	# in 2021. Record the real SDK in that case, so both build systems produce the same kind of app.
	if [[ "$(normalized_version "$sdk")" != "$(normalized_version "$SDK_VERSION")" ]]; then
		# (vtool warns that the linker's ad-hoc signature is now invalid; the bundle is signed below. A failure shows in
		# the check that follows.)
		vtool -set-build-version macos "$minos" "$SDK_VERSION" -replace -output "$slice" "$slice" 2>/dev/null || true
		versions=($(build_version "$slice"))
		[[ "$(normalized_version "${versions[1]}")" == "$(normalized_version "$MIN_MACOS")" \
			&& "$(normalized_version "${versions[2]}")" == "$(normalized_version "$SDK_VERSION")" ]] \
			|| { print -u2 "$arch 빌드에 SDK 버전($SDK_VERSION)을 기록하지 못했습니다."; exit 1; }
		echo "slice: $arch (macOS $minos+, SDK $SDK_VERSION; the build system had recorded SDK $sdk)"
	else
		echo "slice: $arch (macOS $minos+, SDK $sdk)"
	fi
}
# Universal release: one `swift build` per architecture, joined with lipo. `swift build --arch arm64 --arch x86_64`
# would do it in one step, but it is not the same build everywhere: with Xcode 26 two --arch options switch SwiftPM
# from its own build system to Xcode's (other flags, products in .build/apple/Products), with Xcode 27 it is the
# Swift Build engine (which builds both, .build/out/Products). A --triple build is the ordinary single-architecture
# build of whichever toolchain is selected, the path every `swift build` and `swift test` takes, and lipo is the
# same everywhere. Tried on Xcode 27 with both of its build systems (Swift Build and the native one of Xcode 26).
# Each slice is copied out before the next build: the Swift Build engine puts every architecture's product at the same
# path (.build/out/Products/Release), so the second build replaces the first.
if [[ "$CONF" == release ]]; then
	build_slice arm64
	build_slice x86_64
else
	build_slice ""
fi
ICNS="$P/Resources/AppIcon.icns"
[[ -f "$ICNS" ]] || { print -u2 "Resources/AppIcon.icns 가 없습니다."; exit 1; }
APP="$OUT/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/$PRODUCT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SLICES=("$SLICES_DIR"/$PRODUCT-*)
if (( ${#SLICES} > 1 )); then lipo -create -output "$BIN" "${SLICES[@]}"; else cp "${SLICES[1]}" "$BIN"; fi
echo "architectures: $(lipo -archs "$BIN")"
# The bundle ships no libraries of its own, so everything the executable loads must be part of macOS. A library found
# through @rpath (for example Swift's back-deployment libraries, which exist only inside Xcode) would be missing on a
# user's Mac.
if otool -L "$BIN" | /usr/bin/grep -q '@rpath/'; then
	print -u2 "실행 파일이 macOS에 없는 라이브러리를 필요로 합니다:"; otool -L "$BIN" | /usr/bin/grep '@rpath/' >&2; exit 1
fi
cp Resources/Info.plist "$PLIST"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
# The app's only language (Info.plist CFBundleLocalizations: ko), from Resources/ko.lproj, used as it is (plain-text
# property lists, nothing to compile):
#   Localizable.strings  the app's texts, keyed by the Korean text
#   InfoPlist.strings    the app's name
# Only these files are copied (never a .DS_Store). The unit tests check the texts; here only what a broken copy would
# ship is checked: every file parses, both tables are there, and the name in InfoPlist.strings is Info.plist's.
mkdir -p "$APP/Contents/Resources/ko.lproj"
for f in Resources/ko.lproj/*.strings(N); do
	plutil -lint -s "$f" || { print -u2 "$f 을(를) 읽을 수 없습니다."; exit 1; }
	cp "$f" "$APP/Contents/Resources/ko.lproj/"
done
for table in Localizable InfoPlist; do
	[[ -f "$APP/Contents/Resources/ko.lproj/$table.strings" ]] || { print -u2 "Resources/ko.lproj/$table.strings 가 없습니다."; exit 1; }
done
for key in CFBundleName CFBundleDisplayName; do
	[[ "$(plutil -extract "$key" raw -o - "$APP/Contents/Resources/ko.lproj/InfoPlist.strings" 2>/dev/null)" == "$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")" ]] \
		|| { print -u2 "ko.lproj/InfoPlist.strings 의 $key 가 Info.plist 와 다릅니다."; exit 1; }
done
# File-type icons: vector PDFs made from Resources/FileIcons/source/*.svg by scripts/make-file-icons.swift (macOS 12
# cannot draw SVG files itself). Only the PDFs go into the bundle; every SVG must have its PDF.
mkdir -p "$APP/Contents/Resources/FileIcons"
for svg in Resources/FileIcons/source/*.svg(N); do
	pdf="Resources/FileIcons/${${svg:t}:r}.pdf"
	[[ -f "$pdf" ]] || { print -u2 "$pdf 가 없습니다. swift scripts/make-file-icons.swift 로 다시 만드세요."; exit 1; }
done
ICONS=(Resources/FileIcons/*.pdf(N))
(( ${#ICONS} > 0 )) || { print -u2 "Resources/FileIcons 에 아이콘(PDF)이 없습니다."; exit 1; }
cp "${ICONS[@]}" "$APP/Contents/Resources/FileIcons/"
if [[ -n "${APP_VERSION:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$PLIST"; fi
if [[ -n "${APP_BUILD:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$PLIST"; fi
echo "version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST"))"
# Hardened runtime also for the ad-hoc signature, and no entitlements: the app is plain compiled Swift (no JIT, no
# libraries of its own), so nothing the hardened runtime forbids is needed.
if [[ "$IDENTITY" == "-" ]]; then
	echo "signing: ad-hoc (hardened runtime)"
else
	echo "signing: certificate (hardened runtime)"
fi
codesign --force --sign "$IDENTITY" --options runtime "$APP" >/dev/null
codesign --verify --strict "$APP"
echo "built: $APP"
