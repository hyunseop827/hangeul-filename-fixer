// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "HangeulFilenameFixer",
	platforms: [.macOS(.v12)],
	products: [
		.executable(name: "HangeulFilenameFixer", targets: ["HangeulFilenameFixer"])
	],
	// The only dependency, and only the app uses it (the Core has none).
	dependencies: [
		// "업데이트 확인…" (Sources/HangeulFilenameFixer/AppUpdater.swift). Exact: the release workflow signs updates with the
		// sign_update of this same Sparkle version, and scripts/build-app.sh embeds and re-signs this framework.
		.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
	],
	targets: [
		// Filename rules and the copy engine. Foundation + Darwin only (no AppKit, no SwiftUI, no Sparkle, no network).
		.target(
			name: "HangeulFilenameFixerCore"
		),
		// The app (AppKit lifecycle + SwiftUI views). scripts/build-app.sh wraps the executable into
		// build/한글 파일명 정리기.app together with Resources/ (Info.plist, icon, ko.lproj, FileIcons) and
		// Sparkle.framework.
		.executableTarget(
			name: "HangeulFilenameFixer",
			dependencies: ["HangeulFilenameFixerCore", .product(name: "Sparkle", package: "Sparkle")],
			// The app bundle carries Sparkle.framework in Contents/Frameworks (scripts/build-app.sh).
			linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
		),
		.testTarget(
			name: "HangeulFilenameFixerCoreTests",
			dependencies: ["HangeulFilenameFixerCore"]
		),
		// The app's model, views and window (created, never put on the screen), localization table, and what the
		// updater and the bundle are made of (Info.plist, entitlements, build-app.sh).
		.testTarget(
			name: "HangeulFilenameFixerTests",
			dependencies: ["HangeulFilenameFixer", "HangeulFilenameFixerCore"]
		)
	]
)
