#!/bin/zsh
# Builds 한글 파일명 정리기.app with SwiftPM only (no Xcode project needed) and signs it.
#
#   ./scripts/build-app.sh [debug|release]      → build/한글 파일명 정리기.app (ad-hoc signed, hardened runtime)
#
# debug (the default) is built for this Mac's architecture only and without optimization; release is universal
# (arm64 + x86_64) and optimized. The sources are the same for both: there is no debug-only code. A release build
# needs Xcode: the Command Line Tools alone cannot link the x86_64 half (their Swift compatibility libraries are
# Apple Silicon only).
#
# The bundle carries one library, Sparkle.framework (the updater, Sources/HangeulFilenameFixer/AppUpdater.swift), in
# Contents/Frameworks, the same way in debug and release: without its XPC services, signed again from the inside out.
#
# Optional environment:
#   APP_VERSION        CFBundleShortVersionString of the bundle (default: the value in Resources/Info.plist)
#   APP_BUILD          CFBundleVersion of the bundle, an integer from 1 up without leading zeros, e.g. 42 (default:
#                      the value in Resources/Info.plist); Sparkle compares it, so a release must always have a higher
#                      one (CI uses the run number)
#   OUTPUT_DIR         folder that receives the .app (default: build; relative to the repository root)
#   CODESIGN_IDENTITY  "-" (default) signs ad-hoc; a certificate name signs with that certificate. Either way with the
#                      hardened runtime and with the app's one entitlement (Resources/HangeulFilenameFixer.entitlements).
# Only the Info.plist copy inside the bundle is edited; Resources/Info.plist is never changed.
# A bundle that is already at the output path is replaced only once everything that goes into the new one has been
# built and checked; if a later step fails, the unfinished bundle is removed instead of being left there unsigned.
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
# The same form scripts/make-appcast.sh and the release's build-number check accept (sparkle:version).
if [[ -n "${APP_BUILD:-}" && ! "$APP_BUILD" =~ '^[1-9][0-9]*$' ]]; then
	print -u2 "APP_BUILD 형식이 잘못되었습니다: '$APP_BUILD' (1 이상의 정수, 예: 42)"; exit 2
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
# Sparkle.framework, the only library the bundle ships: the name the executable asks for (the framework's install
# name), and the one folder it is looked up in (the rpath Package.swift adds; Contents/Frameworks of the bundle).
SPARKLE_INSTALL_NAME="@rpath/Sparkle.framework/Versions/B/Sparkle"
FRAMEWORKS_RPATH="@executable_path/../Frameworks"
# Prints every library a single-architecture binary loads (its load commands), one per line.
loaded_libraries() {
	otool -L "$1" | awk 'NR > 1 { print $1 }'
}
# Prints the folders a binary searches for them (LC_RPATH), one per line.
rpaths() {
	otool -l "$1" | sed -n '/LC_RPATH/,/path /s/^ *path \(.*\) (offset [0-9]*)$/\1/p'
}
# The slices are collected in a temporary folder that is removed however the script ends: at the end, on a failed step,
# and on Ctrl-C or a kill (INT and TERM become an ordinary exit, so the EXIT trap runs).
SLICES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hangeul-filename-fixer-build.XXXXXX")"
# UNFINISHED is the bundle while it is being put together (see below): a run that stops half way removes it.
UNFINISHED=""
trap 'rm -rf "$SLICES_DIR"; if [[ -n "$UNFINISHED" ]]; then rm -rf "$UNFINISHED"; fi' EXIT
trap 'exit 130' INT TERM
# Builds the product for one architecture ("" = this Mac's) and leaves a checked copy in $SLICES_DIR.
# Always called in a subshell, `(build_slice …)`: when a command fails inside a function (set -e), or a signal arrives
# while one runs, zsh leaves without running the EXIT trap, and the temporary folder would stay behind. A failing
# subshell is an ordinary failed command of the script itself, which does run the trap. The function only writes files
# into $SLICES_DIR, so nothing is lost by the subshell.
build_slice() {
	local arch="$1" triple=() bin_dir slice versions minos sdk rpath library sparkle_loads=0 foreign=()
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
	# What the executable loads: Sparkle.framework, by the one name that is looked up in the bundle, and otherwise only
	# libraries that are part of macOS (/System/Library, /usr/lib; nobody can write there). Every load command is
	# looked at, not only the @rpath ones. Any other library found through @rpath (for example Swift's back-deployment
	# libraries, which exist only inside Xcode) would be missing on a user's Mac; and one named by a path outside
	# macOS (/usr/local/lib, @executable_path/…, @loader_path/…) would be loaded from wherever somebody put it,
	# because the app is signed to load libraries that Apple's rules would refuse (the entitlement below).
	for library in ${(f)"$(loaded_libraries "$slice")"}; do
		case "$library" in
			*/../*|*/..) foreign+=("$library") ;;   # a path that climbs out of the folder it starts in
			"$SPARKLE_INSTALL_NAME") sparkle_loads=$((sparkle_loads + 1)) ;;
			/System/Library/*|/usr/lib/*) ;;
			*) foreign+=("$library") ;;
		esac
	done
	if (( sparkle_loads != 1 || ${#foreign} > 0 )); then
		print -u2 "$arch 실행 파일은 Sparkle.framework 하나($SPARKLE_INSTALL_NAME)와 macOS에 들어 있는 라이브러리(/System/Library, /usr/lib)만 불러와야 합니다."
		print -u2 "  $SPARKLE_INSTALL_NAME: ${sparkle_loads}번"
		if (( ${#foreign} > 0 )); then print -u2 -l -- "  그 밖의 라이브러리:" "${(@)foreign/#/    }"; fi
		exit 1
	fi
	# And it must be looked for in the bundle only. SwiftPM also records folders of this build (its products folder, the
	# toolchain inside Xcode, the executable's own folder) as places to search, in front of the bundle's Frameworks.
	# The app is signed to load a library that Apple's rules would refuse (the entitlement below), so a
	# Sparkle.framework that somebody put at one of those paths on a user's Mac would be loaded instead of the one in
	# the bundle. Those entries are removed; /usr/lib/swift, which is part of macOS and cannot be written to, may stay.
	# (install_name_tool warns that the linker's ad-hoc signature is now invalid; the bundle is signed below. A failure
	# shows in the check that follows.)
	for rpath in ${(f)"$(rpaths "$slice")"}; do
		if [[ "$rpath" != "$FRAMEWORKS_RPATH" && "$rpath" != /usr/lib/swift ]]; then
			install_name_tool -delete_rpath "$rpath" "$slice" 2>/dev/null || true
		fi
	done
	[[ "$(rpaths "$slice" | /usr/bin/grep -vx '/usr/lib/swift')" == "$FRAMEWORKS_RPATH" ]] || {
		print -u2 "$arch 실행 파일의 라이브러리 검색 경로(LC_RPATH)가 $FRAMEWORKS_RPATH 하나가 아닙니다:"
		rpaths "$slice" >&2; exit 1
	}
	# Sparkle.framework itself: SwiftPM leaves the package's framework (universal as it is distributed) next to the
	# product. Every slice is linked against the same one; the first copy is kept (ditto keeps its symlinks).
	[[ -d "$bin_dir/Sparkle.framework" ]] || { print -u2 "$bin_dir/Sparkle.framework 가 없습니다."; exit 1; }
	if [[ ! -d "$SLICES_DIR/Sparkle.framework" ]]; then
		ditto "$bin_dir/Sparkle.framework" "$SLICES_DIR/Sparkle.framework"
	elif ! cmp -s "$bin_dir/Sparkle.framework/Versions/B/Sparkle" "$SLICES_DIR/Sparkle.framework/Versions/B/Sparkle"; then
		print -u2 "$arch 빌드의 Sparkle.framework 가 다른 아키텍처 빌드의 것과 다릅니다."; exit 1
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
	(build_slice arm64)
	(build_slice x86_64)
else
	(build_slice "")
fi
ICNS="$P/Resources/AppIcon.icns"
[[ -f "$ICNS" ]] || { print -u2 "Resources/AppIcon.icns 가 없습니다."; exit 1; }
# The executable, still in the temporary folder (its name does not match the slices' pattern).
SLICES=("$SLICES_DIR"/$PRODUCT-*)
JOINED="$SLICES_DIR/joined"
if (( ${#SLICES} > 1 )); then lipo -create -output "$JOINED" "${SLICES[@]}"; else cp "${SLICES[1]}" "$JOINED"; fi
ARCHS=($(lipo -archs "$JOINED"))
echo "architectures: ${ARCHS[*]}"
# Sparkle.framework, before anything at the output path is touched: what is embedded must be what the executable asks
# for, for every architecture of the app, and must run on the oldest macOS the app runs on: the framework and the two
# helpers Sparkle starts to install an update.
FW_SOURCE="$SLICES_DIR/Sparkle.framework"
SPARKLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FW_SOURCE/Versions/B/Resources/Info.plist")"
[[ "$(otool -D "$FW_SOURCE/Versions/B/Sparkle" | /usr/bin/grep -v ':$' | sort -u)" == "$SPARKLE_INSTALL_NAME" ]] \
	|| { print -u2 "Sparkle.framework 의 설치 이름이 $SPARKLE_INSTALL_NAME 이 아닙니다."; exit 1; }
for code in "$FW_SOURCE/Versions/B/Sparkle" "$FW_SOURCE/Versions/B/Autoupdate" "$FW_SOURCE/Versions/B/Updater.app/Contents/MacOS/Updater"; do
	[[ -f "$code" ]] || { print -u2 "Sparkle.framework 에 ${code#$FW_SOURCE/} 가 없습니다."; exit 1; }
	for arch in "${ARCHS[@]}"; do
		lipo "$code" -verify_arch "$arch" || { print -u2 "Sparkle.framework 의 ${code:t} 에 $arch 가 없습니다."; exit 1; }
		minos="$(vtool -arch "$arch" -show-build "$code" | awk '$1 == "minos" { print $2 }')"
		# Not newer than the app's: the higher of the two versions is the app's own.
		[[ -n "$minos" && "$(normalized_version "$(print -l -- "$minos" "$MIN_MACOS" | sort -V | tail -1)")" == "$(normalized_version "$MIN_MACOS")" ]] \
			|| { print -u2 "Sparkle.framework 의 ${code:t} ($arch) 는 macOS $minos 이상이 필요합니다 (앱은 $MIN_MACOS 부터 실행됩니다)."; exit 1; }
	done
done
# Sparkle's windows are Korean because the framework has a ko.lproj: a framework shows its texts in the language of
# the app that loads it, and this app's only language is Korean (CFBundleLocalizations in Info.plist), whatever the
# system language is. Without the folder they would be English.
[[ -s "$FW_SOURCE/Versions/B/Resources/ko.lproj/Sparkle.strings" ]] \
	|| { print -u2 "Sparkle.framework 에 한국어 문구(Resources/ko.lproj/Sparkle.strings)가 없습니다."; exit 1; }
# License texts of the bundled third-party code (Sparkle, MIT, and what Sparkle itself includes): their copyright
# notices must ship with the app. The file names the Sparkle version it was taken from.
/usr/bin/grep -qx "Sparkle $SPARKLE_VERSION" Resources/ThirdPartyNotices.txt \
	|| { print -u2 "Resources/ThirdPartyNotices.txt 가 Sparkle $SPARKLE_VERSION 의 고지가 아닙니다."; exit 1; }
# From here on the bundle at the output path is replaced. Until it is signed and verified it counts as unfinished: the
# EXIT trap removes it when a step below fails, so a broken, unsigned bundle is never left where a good one is expected.
APP="$OUT/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/$PRODUCT"
UNFINISHED="$APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$JOINED" "$BIN"
# Sparkle.framework (AppUpdater, "업데이트 확인…") goes where the executable looks for it: Contents/Frameworks. Its XPC
# services serve sandboxed apps only; this app has no sandbox and Info.plist enables none of them, so they are left
# out, the folder and the link to it
# (https://sparkle-project.org/documentation/sandboxing/#removing-xpc-services). All of it is signed again below.
FW="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SLICES_DIR/Sparkle.framework" "$FW"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
echo "sparkle: $SPARKLE_VERSION ($(lipo -archs "$FW/Versions/B/Sparkle" | tr ' ' '\n' | sort | xargs), XPC services removed)"
cp Resources/Info.plist "$PLIST"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"
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
# Hardened runtime also for the ad-hoc signature, and one entitlement: without it the hardened runtime's library
# validation would refuse Sparkle.framework, which is ad-hoc signed like the app (no Team ID in common). Nothing else
# the hardened runtime forbids is needed: the app is plain compiled Swift (no JIT).
SIGN=(--force --sign "$IDENTITY" --options runtime --entitlements Resources/HangeulFilenameFixer.entitlements)
if [[ "$IDENTITY" == "-" ]]; then
	echo "signing: ad-hoc (hardened runtime)"
else
	echo "signing: certificate (hardened runtime)"
fi
# Inside out and never --deep: Sparkle's helpers, the framework, then the app with its entitlement
# (https://sparkle-project.org/documentation/sandboxing/#code-signing). The helpers and the framework keep the hardened
# runtime Sparkle ships them with, and get no entitlements.
FW_SIGN=(--force --sign "$IDENTITY" --options runtime)
for code in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do
	codesign "${FW_SIGN[@]}" "$code"
done
codesign "${SIGN[@]}" "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
UNFINISHED=""
echo "built: $APP"
