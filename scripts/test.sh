#!/bin/zsh
# Runs the unit tests (HangeulFilenameFixerCoreTests and HangeulFilenameFixerTests). `swift test` builds the whole package
# (including the SwiftUI app), so the SwiftUI macro plugin from Xcode is needed when building with the Command Line Tools
# toolchain.
# Works from any directory: the repository root is found from the script's own path before changing into it.
#
#   ./scripts/test.sh                       every test, then the umask test in a run of its own (see below)
#   ./scripts/test.sh --filter NamingTests  arguments go to `swift test` as they are; only that run is made
set -e
P="$(cd "$(dirname "$0")/.." && pwd)"
cd "$P"
source "$P/scripts/toolchain.sh"
echo "toolchain: $DEVELOPER_DIR"
swift test "${SWIFT_EXTRA[@]}" "$@"
# UmaskTests changes the umask of its whole process, so it cannot run among the other tests: it is switched off in the
# run above (reported there as skipped) and gets a process to itself here. The test prints a line when it has checked
# its cases; without that line it did not run (a filter that matches nothing still exits with 0), which is a failure.
if (( $# == 0 )); then
	echo "umask test (in a run of its own):"
	UMASK_LOG="$(HANGEUL_TEST_UMASK=1 swift test "${SWIFT_EXTRA[@]}" --filter UmaskTests 2>&1)" || { print -r -- "$UMASK_LOG"; exit 1; }
	print -r -- "$UMASK_LOG"
	[[ "$UMASK_LOG" == *"umask test: "*" cases checked"* ]] || { print -u2 "UmaskTests 가 실행되지 않았습니다."; exit 1; }
fi
