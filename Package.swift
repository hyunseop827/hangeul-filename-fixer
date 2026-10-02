// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "HangeulFilenameFixer",
	platforms: [.macOS(.v12)],
	products: [
		.executable(name: "HangeulFilenameFixer", targets: ["HangeulFilenameFixer"])
	],
	targets: [
		// Filename rules and the copy engine. Foundation + Darwin only (no AppKit, no SwiftUI).
		.target(
			name: "HangeulFilenameFixerCore"
		),
		// The app (AppKit lifecycle + SwiftUI views). scripts/build-app.sh wraps the executable into
		// build/한글 파일명 정리기.app together with Resources/ (Info.plist, icon, ko.lproj, FileIcons).
		.executableTarget(
			name: "HangeulFilenameFixer",
			dependencies: ["HangeulFilenameFixerCore"]
		),
		.testTarget(
			name: "HangeulFilenameFixerCoreTests",
			dependencies: ["HangeulFilenameFixerCore"]
		),
		// The app's model, views and window (created, never put on the screen), localization table.
		.testTarget(
			name: "HangeulFilenameFixerTests",
			dependencies: ["HangeulFilenameFixer", "HangeulFilenameFixerCore"]
		)
	]
)
