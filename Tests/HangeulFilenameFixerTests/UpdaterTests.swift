// The updater (Sparkle): what Info.plist tells it, when the app starts it, and what goes into the bundle with it.
//
// Nothing here starts Sparkle, asks the network for anything or makes a key. The settings are read from
// Resources/Info.plist, the decision to start is asked of `UpdaterConfiguration` and `AppUpdater` with values, and
// the bundle is read from what makes it: Package.swift, scripts/build-app.sh, the entitlements, the license texts.
// (The built bundle itself is checked by scripts/verify-dmg.sh.)
//
// ONE TEST HERE FAILS ON PURPOSE whenever Resources/Info.plist does not hold a real public key for updates (as it
// did, with a placeholder, until the owner put the key in): `thePublicKeyIsARealKey`. Do not weaken it and do not "fix" it with a made-up key.
import AppKit
import Foundation
import Testing
@testable import HangeulFilenameFixer

private enum Repository {
	static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

	static func text(_ path: String) throws -> String {
		try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
	}

	static func propertyList(_ path: String) throws -> [String: Any] {
		let data = try Data(contentsOf: root.appendingPathComponent(path))
		return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], "\(path) is not a dictionary")
	}

	static func swiftSources(_ folder: String) throws -> [(name: String, text: String)] {
		let items = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
		return try items.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
			.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
	}

	/// The lines of a script, and where a line with `text` stands (the first one).
	static func lines(_ path: String) throws -> [String] {
		try text(path).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
	}
}

/// The feed every installed copy asks for updates. Once a release has shipped it can never change (AGENTS.md,
/// "Changes and releases", step 9).
private let feedURL = "https://github.com/hyunseop827/hangeul-filename-fixer/releases/latest/download/appcast.xml"
/// What stood in Resources/Info.plist until the owner put the public key in; no build with it may be released.
private let placeholderKey = "PASTE_PUBLIC_KEY_FROM_generate_keys"
/// A public key of the right shape that is nobody's secret: the public key of RFC 8032's first Ed25519 test vector
/// (section 7.1, TEST 1), 32 bytes, as base64.
private let publishedTestKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

/// Resources/Info.plist, as Sparkle reads it.
@Suite struct UpdaterSettingsTests {
	/// Updates are looked for once a day at Sparkle's default interval and when the user asks, and never installed
	/// without the user (there is no "install automatically" option). The feed is the latest GitHub release's
	/// appcast, over HTTPS. An update is verified before it is opened. Nothing about the Mac is sent, no XPC service
	/// is asked for (they are not in the bundle), and no exception to App Transport Security is made.
	@Test func updatesAreCheckedDailyAndInstalledOnlyByTheUser() throws {
		let plist = try Repository.propertyList("Resources/Info.plist")
		#expect(plist["SUFeedURL"] as? String == feedURL)
		// Booleans, not strings: `<true/>` and `<false/>`.
		#expect(plist["SUEnableAutomaticChecks"] as? NSNumber === kCFBooleanTrue, "SUEnableAutomaticChecks must be <true/>: a check once a day, without asking first")
		#expect(plist["SUAllowsAutomaticUpdates"] as? NSNumber === kCFBooleanFalse, "SUAllowsAutomaticUpdates must be <false/>: the user chooses to install")
		#expect(plist["SUVerifyUpdateBeforeExtraction"] as? NSNumber === kCFBooleanTrue, "SUVerifyUpdateBeforeExtraction must be <true/>")
		#expect(plist["SUPublicEDKey"] is String, "without a key Sparkle cannot verify an update")
		for key in [
			"SUScheduledCheckInterval", "SUAutomaticallyUpdate", "SUEnableSystemProfiling", "SUPublicDSAKeyFile",
			"SUEnableInstallerLauncherService", "SUEnableDownloaderService", "SUEnableInstallerConnectionService", "SUEnableInstallerStatusService",
			"NSAppTransportSecurity"
		] {
			#expect(plist[key] == nil, "\(key) must not be set")
		}

		// Sparkle compares CFBundleVersion: an integer (the released app gets the CI run number).
		let build = try #require(plist["CFBundleVersion"] as? String)
		#expect(Int(build).map { $0 >= 1 } == true && String(Int(build) ?? 0) == build, "CFBundleVersion must be an integer: \(build)")
		// The scripts that check a built app look for the same feed.
		#expect(try Repository.text("scripts/verify-dmg.sh").contains("feed_url=\"\(feedURL)\""))
	}

	/// THIS TEST FAILS WHEN A PLACEHOLDER IS IN Resources/Info.plist INSTEAD OF A REAL KEY. That is intended: an app released with it
	/// could never update itself, so nothing may be merged or released before the owner's key is in.
	@Test func thePublicKeyIsARealKey() throws {
		let plist = try Repository.propertyList("Resources/Info.plist")
		let key = try #require(plist["SUPublicEDKey"] as? String, "Resources/Info.plist has no SUPublicEDKey")
		#expect(
			Data(base64Encoded: key)?.count == 32,
			"""
			Resources/Info.plist: SUPublicEDKey is "\(key)", which is not an Ed25519 public key (base64 of 32 bytes, 44 characters).
			This failure is intended until the repository owner has set the key; it must not be worked around.
			Only the owner creates and stores the key (AGENTS.md, "Changes and releases", step 8). What the owner does, once:
			  1. swift package resolve
			     .build/artifacts/sparkle/Sparkle/bin/generate_keys --account hangeul-filename-fixer
			     (makes the key pair, keeps the private key in the login keychain and prints the public key; run again, it prints the same public key)
			  2. Put the printed public key into Resources/Info.plist, in place of \(placeholderKey):
			     <key>SUPublicEDKey</key><string>THE PRINTED KEY</string>
			  3. KEY_FILE="$HOME/hangeul-filename-fixer-update-key.txt"
			     (umask 077; .build/artifacts/sparkle/Sparkle/bin/generate_keys --account hangeul-filename-fixer -x "$KEY_FILE")
			     gh secret set SPARKLE_PRIVATE_KEY -R hyunseop827/hangeul-filename-fixer < "$KEY_FILE"
			     (a file outside the repository, readable by the owner only; the release workflow signs every update with it; back the file up somewhere safe, then delete it: a lost key means no installed copy can ever be updated again)
			After the first release with this key, neither the key nor SUFeedURL may change.
			"""
		)
	}

	/// Sparkle is the app's only code that uses the network: one file imports it, and no source of the app or the
	/// Core opens a connection of its own.
	@Test func onlyTheUpdaterUsesTheNetwork() throws {
		let app = try Repository.swiftSources("Sources/HangeulFilenameFixer")
		let core = try Repository.swiftSources("Sources/HangeulFilenameFixerCore")
		#expect(app.count >= 15 && core.count >= 6)
		#expect(app.filter { $0.text.contains("import Sparkle") }.map(\.name) == ["AppUpdater.swift"])
		#expect(core.filter { $0.text.contains("Sparkle") }.map(\.name).isEmpty, "the Core knows nothing about updates")
		let network = ["URLSession", "URLRequest", "NSURLConnection", "NWConnection", "import Network", "CFNetwork", "CFStream", "WebKit"]
		for source in app + core {
			for word in network {
				#expect(!source.text.contains(word), "\(source.name) uses \(word)")
			}
		}
	}
}

/// When the app starts the updater: `UpdaterConfiguration`, a pure function of two Info.plist values, and `AppUpdater`
/// with a counted stand-in for "start Sparkle".
@MainActor
@Suite struct AppUpdaterTests {
	@Test func aFeedAndARealKeyAreBothNeeded() throws {
		#expect(Data(base64Encoded: publishedTestKey)?.count == 32)
		#expect(UpdaterConfiguration(feedURL: feedURL, publicKey: publishedTestKey).canStart)

		// The key: missing, empty, the placeholder, not base64, base64 of another length.
		let short = Data(repeating: 7, count: 31).base64EncodedString(), long = Data(repeating: 7, count: 33).base64EncodedString()
		let signature = Data(repeating: 7, count: 64).base64EncodedString()
		for key in [nil, "", " ", placeholderKey, "not a key", String(publishedTestKey.dropLast()), publishedTestKey + "A", short, long, signature] {
			#expect(!UpdaterConfiguration(feedURL: feedURL, publicKey: key).canStart, "\(key ?? "nil")")
			#expect(!UpdaterConfiguration.isPublicKey(key), "\(key ?? "nil")")
		}
		// Sparkle ignores white space around the key (a line break after pasting it); so does the app.
		#expect(UpdaterConfiguration(feedURL: feedURL, publicKey: " \(publishedTestKey)\n").canStart)

		// The feed: missing or empty. Any other value is handed to Sparkle, which decides when it starts whether it
		// can be read; a feed on this Mac (an update tried out by hand, over http) is one of them.
		for feed in [nil, "", " ", "\n"] {
			#expect(!UpdaterConfiguration(feedURL: feed, publicKey: publishedTestKey).canStart, "\(feed ?? "nil")")
			#expect(!UpdaterConfiguration.isFeed(feed), "\(feed ?? "nil")")
		}
		#expect(UpdaterConfiguration(feedURL: "http://127.0.0.1:8000/appcast.xml", publicKey: publishedTestKey).canStart)
		#expect(!UpdaterConfiguration(feedURL: "http://127.0.0.1:8000/appcast.xml", publicKey: placeholderKey).canStart)
		#expect(!UpdaterConfiguration(feedURL: nil, publicKey: nil).canStart)
	}

	/// With the placeholder for the key, without a feed or without both, Sparkle is never asked to start: no check,
	/// no alert, nothing on the network. The menu item then has nothing to send, and the link cannot be used.
	@Test func nothingIsStartedWithoutAFeedAndARealKey() {
		var started = 0
		let target = NSObject()
		let start: @MainActor () -> UpdateCheck? = {
			started += 1
			return UpdateCheck(target: target, action: NSSelectorFromString("checkForUpdates:"))
		}

		for configuration in [
			UpdaterConfiguration(feedURL: feedURL, publicKey: placeholderKey),
			UpdaterConfiguration(feedURL: feedURL, publicKey: nil),
			UpdaterConfiguration(feedURL: nil, publicKey: publishedTestKey),
			UpdaterConfiguration(feedURL: nil, publicKey: nil)
		] {
			let updater = AppUpdater(configuration: configuration, start: start)
			#expect(updater.check == nil && !updater.isAvailable && !updater.canCheck)
		}
		#expect(started == 0)

		// With both: started once, and what the start gives is what the menu item gets; the link can be used.
		let updater = AppUpdater(configuration: UpdaterConfiguration(feedURL: feedURL, publicKey: publishedTestKey), start: start)
		#expect(started == 1)
		#expect(updater.isAvailable && updater.check?.target === target && updater.canCheck)

		// Sparkle did not start (it reported an error): no updater, and the app goes on without one.
		let refused = AppUpdater(configuration: UpdaterConfiguration(feedURL: feedURL, publicKey: publishedTestKey), start: { nil })
		#expect(refused.check == nil && !refused.isAvailable && !refused.canCheck)
	}

	/// Under `swift test`, as under `swift run`, there is no app bundle: no feed, no key, and the app's own updater
	/// has started nothing.
	@Test func outsideTheAppBundleNothingIsStarted() {
		let configuration = UpdaterConfiguration(bundle: .main)
		#expect(configuration.feedURL == nil && configuration.publicKey == nil && !configuration.canStart)
		#expect(AppUpdater.shared.check == nil && !AppUpdater.shared.isAvailable && !AppUpdater.shared.canCheck)
	}

	/// Stands in for Sparkle's controller as the target of the check.
	private final class CheckTarget: NSObject {
		var checks = 0

		@objc func checkForUpdates(_ sender: Any?) {
			checks += 1
		}
	}

	/// The link under the card sends the check the menu item sends, to the same target, as often as it is pressed
	/// while a check can start. Without an updater it sends nothing.
	@Test func theLinkSendsTheSameCheckAsTheMenuItem() {
		_ = NSApplication.shared
		let target = CheckTarget()
		let check = UpdateCheck(target: target, action: #selector(CheckTarget.checkForUpdates(_:)))
		let updater = AppUpdater(configuration: UpdaterConfiguration(feedURL: feedURL, publicKey: publishedTestKey), start: { check })
		#expect(updater.canCheck)
		updater.checkForUpdates()
		updater.checkForUpdates()
		#expect(target.checks == 2)

		for none in [
			AppUpdater(configuration: UpdaterConfiguration(feedURL: feedURL, publicKey: placeholderKey), start: { check }),
			AppUpdater(configuration: UpdaterConfiguration(feedURL: feedURL, publicKey: publishedTestKey), start: { nil })
		] {
			#expect(!none.canCheck)
			none.checkForUpdates()
		}
		#expect(target.checks == 2)
	}

	/// The link's text is the menu item's without the ellipsis, and its tooltip names this build's version (with the
	/// build number, as the About panel shows them) and, while the link can be used, what a click does.
	@Test func theLinkIsNamedLikeTheMenuItemAndItsTooltipNamesThisBuild() throws {
		#expect(Exact(AppUpdater.linkName) == Exact("업데이트 확인"))
		#expect(Exact(AppUpdater.help(version: "2.0.2 (16)")) == Exact("현재 버전 2.0.2 (16). 눌러서 업데이트를 확인합니다."))
		#expect(Exact(AppUpdater.help(version: "2.0.2 (16)", enabled: false)) == Exact("현재 버전 2.0.2 (16)."))
		#expect(Exact(AppUpdater.help(version: nil)) == Exact("눌러서 업데이트를 확인합니다."))
		#expect(AppUpdater.help(version: nil, enabled: false).isEmpty)

		// The version comes from the bundle's Info.plist: a small bundle made here with the repository's own values
		// (2.0.2 and build 1), one without a build number, and one without a version. None under `swift test` itself.
		let folders = TestFolders()
		func bundle(_ values: [String: String]) throws -> Bundle {
			let app = folders.work + "/\(UUID().uuidString).app"
			mkdir(app, 0o755)
			mkdir(app + "/Contents", 0o755)
			let plist = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
			try plist.write(to: URL(fileURLWithPath: app + "/Contents/Info.plist"))
			return try #require(Bundle(path: app))
		}
		let repository = try Repository.propertyList("Resources/Info.plist")
		let version = try #require(repository["CFBundleShortVersionString"] as? String)
		let build = try #require(repository["CFBundleVersion"] as? String)
		#expect(try AppUpdater.version(of: bundle(["CFBundleShortVersionString": version, "CFBundleVersion": build])) == "\(version) (\(build))")
		#expect(try AppUpdater.version(of: bundle(["CFBundleShortVersionString": "2.0.2"])) == "2.0.2")
		#expect(try AppUpdater.version(of: bundle(["CFBundleVersion": "16"])) == nil)
		#expect(AppUpdater.version(of: .main) == nil)
	}

	/// The app built from this repository starts its updater exactly when Resources/Info.plist holds a real key: not
	/// with the placeholder (such a build must open without an alert), and at once when the key is in.
	@Test func theAppStartsItsUpdaterOnceTheKeyIsIn() throws {
		let plist = try Repository.propertyList("Resources/Info.plist")
		let key = try #require(plist["SUPublicEDKey"] as? String)
		let configuration = UpdaterConfiguration(feedURL: plist["SUFeedURL"] as? String, publicKey: key)
		#expect(UpdaterConfiguration.isFeed(configuration.feedURL) && configuration.feedURL == feedURL)
		#expect(configuration.canStart == (Data(base64Encoded: key)?.count == 32))
		#expect(!UpdaterConfiguration(feedURL: configuration.feedURL, publicKey: placeholderKey).canStart)
	}

	/// The menu item goes straight to Sparkle's controller, so the controller must be what answers for it: it has the
	/// action, and it validates menu items (that is what disables the item while a check is running). The link asks the
	/// updater the same question (`canCheckForUpdates`, observed) and sends the same check. And the app starts the
	/// updater itself instead of letting the controller do it, whose failure would be an alert at every launch.
	@Test func sparklesControllerAnswersForTheMenuItem() throws {
		let controller = try #require(NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type, "Sparkle.framework is not loaded")
		let answersTheAction = controller.instancesRespond(to: NSSelectorFromString("checkForUpdates:"))
		let validatesTheItem = controller.instancesRespond(to: #selector(NSMenuItemValidation.validateMenuItem(_:)))
		#expect(answersTheAction && validatesTheItem)
		let updater = try #require(NSClassFromString("SPUUpdater") as? NSObject.Type)
		#expect(updater.instancesRespond(to: NSSelectorFromString("canCheckForUpdates")), "the link follows SPUUpdater.canCheckForUpdates")

		let source = try Repository.text("Sources/HangeulFilenameFixer/AppUpdater.swift")
		#expect(source.contains("SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)"))
		#expect(source.contains("try controller.updater.start()"))
		#expect(source.contains("UpdateCheck(target: controller, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))"))
		#expect(source.contains(#"updater.observe(\.canCheckForUpdates, options: [.initial, .new])"#))
		#expect(source.contains("_ = NSApp.sendAction(check.action, to: check.target, from: nil)"))
		#expect(!source.contains("startingUpdater: true") && !source.contains("controller.startUpdater()"))
		// Checks in the background and automatic downloads are Info.plist's to decide, not the code's.
		for word in ["automaticallyChecksForUpdates", "automaticallyDownloadsUpdates", "updateCheckInterval", "checkForUpdatesInBackground", "setFeedURL", "sendsSystemProfile"] {
			#expect(!source.contains(word), "AppUpdater.swift sets \(word)")
		}
	}
}

/// What the bundle is made of, read from what makes it.
@Suite struct UpdaterBundleTests {
	/// The Sparkle version, from Package.swift's `exact:`.
	private static func sparkleVersion() throws -> String {
		let package = try Repository.text("Package.swift")
		let prefix = #".package(url: "https://github.com/sparkle-project/Sparkle", exact: ""#
		let start = try #require(package.range(of: prefix), "Package.swift does not name Sparkle with an exact version")
		return String(package[start.upperBound...].prefix { $0 != "\"" })
	}

	/// Sparkle 2.10.0 exactly (the release workflow signs with the same version's tools), the package's only
	/// dependency, linked by the app and by nothing else; the executable looks for it in the bundle's Frameworks.
	@Test func sparkleIsPinnedAndOnlyTheAppLinksIt() throws {
		#expect(try Self.sparkleVersion() == "2.10.0")
		let package = try Repository.text("Package.swift")
		#expect(package.components(separatedBy: ".package(").count == 2, "Sparkle is the only dependency")
		#expect(package.components(separatedBy: #".product(name: "Sparkle", package: "Sparkle")"#).count == 2, "only the app links Sparkle")
		#expect(package.contains(#"dependencies: ["HangeulFilenameFixerCore", .product(name: "Sparkle", package: "Sparkle")],"#))
		#expect(package.contains(#"linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]"#))
		// The Core's target has no dependencies at all.
		let core = try #require(package.range(of: #"name: "HangeulFilenameFixerCore""#))
		let afterCore = package[core.upperBound...]
		let coreTarget = afterCore[..<(try #require(afterCore.range(of: ".executableTarget(")).lowerBound)]
		#expect(!coreTarget.contains("dependencies"))

		// What SwiftPM resolved is that version and nothing else.
		let resolved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: Repository.root.appendingPathComponent("Package.resolved"))) as? [String: Any])
		let pins = try #require(resolved["pins"] as? [[String: Any]])
		#expect(pins.map { $0["identity"] as? String } == ["sparkle"])
		#expect(pins.first?["location"] as? String == "https://github.com/sparkle-project/Sparkle")
		#expect((pins.first?["state"] as? [String: Any])?["version"] as? String == "2.10.0")
	}

	/// The app's entitlements: exactly one. The hardened runtime may load Sparkle.framework, which is ad-hoc signed
	/// like the app; everything else the hardened runtime forbids stays forbidden, and there is no sandbox.
	@Test func theAppHasExactlyOneEntitlement() throws {
		let entitlements = try Repository.propertyList("Resources/HangeulFilenameFixer.entitlements")
		#expect(Array(entitlements.keys) == ["com.apple.security.cs.disable-library-validation"])
		#expect(entitlements["com.apple.security.cs.disable-library-validation"] as? NSNumber === kCFBooleanTrue)
		// The check of a built app expects the same.
		#expect(try Repository.text("scripts/verify-dmg.sh").contains(#"entitlements='{"com.apple.security.cs.disable-library-validation":true}'"#))
	}

	/// scripts/build-app.sh: the framework is copied with its symlinks, without the XPC services a non-sandboxed app
	/// does not use (the folder and the link to it); its two helpers, then the framework, then the app are signed with
	/// the hardened runtime, the app alone with the entitlement, never with `--deep`; the result is verified
	/// strictly and deeply. The executable loads Sparkle through @rpath and otherwise only libraries of macOS (every
	/// load command is looked at), and looks for Sparkle in the bundle only: the other search folders SwiftPM
	/// records are removed. A bundle that is already there is replaced only after the checks that need no bundle,
	/// and a bundle that was not finished is removed.
	@Test func sparkleIsEmbeddedWithoutXPCServicesAndSignedInsideOut() throws {
		let lines = try Repository.lines("scripts/build-app.sh")
		let script = lines.joined(separator: "\n")
		func line(_ text: String) throws -> Int {
			try #require(lines.firstIndex { $0.contains(text) }, "build-app.sh: no \(text)")
		}

		let framework = try line(#"FW="$APP/Contents/Frameworks/Sparkle.framework""#)
		let copy = try line(#"ditto "$SLICES_DIR/Sparkle.framework" "$FW""#)
		let xpc = try line(#"rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices""#)
		let notices = try line(#"cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt""#)
		let helpers = try line(#"for code in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW"; do"#)
		let sign = try line(#"codesign "${FW_SIGN[@]}" "$code""#)
		let app = try line(#"codesign "${SIGN[@]}" "$APP""#)
		let verify = try line(#"codesign --verify --deep --strict "$APP""#)
		#expect(framework < copy && copy < xpc && xpc < notices && notices < helpers && helpers < sign && sign < app && app < verify)
		#expect(script.contains(#"FW_SIGN=(--force --sign "$IDENTITY" --options runtime)"#))
		#expect(script.contains(#"SIGN=(--force --sign "$IDENTITY" --options runtime --entitlements Resources/HangeulFilenameFixer.entitlements)"#))
		let signing = lines.filter { $0.contains("codesign ") && !$0.hasPrefix("#") && !$0.contains("--verify") }
		#expect(signing.count == 2 && !signing.contains { $0.contains("--deep") }, "\(signing)")
		#expect(lines.filter { $0.contains("--entitlements") && !$0.hasPrefix("#") }.count == 1, "only the app gets the entitlement")

		// The framework the slices were linked against is the one that is embedded.
		#expect(script.contains(#"ditto "$bin_dir/Sparkle.framework" "$SLICES_DIR/Sparkle.framework""#))
		// The one library found through @rpath, and the one folder it is looked for in (Package.swift's rpath).
		#expect(script.contains(#"SPARKLE_INSTALL_NAME="@rpath/Sparkle.framework/Versions/B/Sparkle""#))
		#expect(script.contains(#"FRAMEWORKS_RPATH="@executable_path/../Frameworks""#))
		// Every load command: Sparkle by that name, exactly once, and otherwise only what is part of macOS.
		#expect(script.contains(#"otool -L "$1" | awk 'NR > 1 { print $1 }'"#))
		#expect(script.contains(#"for library in ${(f)"$(loaded_libraries "$slice")"}; do"#))
		#expect(script.contains(#""$SPARKLE_INSTALL_NAME") sparkle_loads=$((sparkle_loads + 1)) ;;"#))
		#expect(script.contains("/System/Library/*|/usr/lib/*) ;;") && script.contains(#"*/../*|*/..) foreign+=("$library") ;;"#))
		#expect(script.contains(#"if (( sparkle_loads != 1 || ${#foreign} > 0 )); then"#))
		#expect(script.contains(#"install_name_tool -delete_rpath "$rpath" "$slice""#))
		#expect(script.contains(#"[[ "$(rpaths "$slice" | /usr/bin/grep -vx '/usr/lib/swift')" == "$FRAMEWORKS_RPATH" ]] || {"#))
		// Both architectures, the app's oldest macOS, and Sparkle's Korean texts.
		#expect(script.contains(#"lipo "$code" -verify_arch "$arch""#))
		#expect(script.contains(#"[[ -s "$FW_SOURCE/Versions/B/Resources/ko.lproj/Sparkle.strings" ]]"#))
		// The bundle at the output path is replaced only after the checks of what goes into it, counts as unfinished
		// until it is signed and verified, and the EXIT trap removes an unfinished one.
		let noticesCheck = try line(#"/usr/bin/grep -qx "Sparkle $SPARKLE_VERSION" Resources/ThirdPartyNotices.txt"#)
		let koreanCheck = try line(#"[[ -s "$FW_SOURCE/Versions/B/Resources/ko.lproj/Sparkle.strings" ]]"#)
		let unfinished = try line(#"UNFINISHED="$APP""#)
		let replace = try line(#"rm -rf "$APP""#)
		let finished = try #require(lines.lastIndex { $0 == #"UNFINISHED="""# })
		#expect(noticesCheck < unfinished && koreanCheck < unfinished && unfinished < replace && replace < framework && verify < finished)
		#expect(script.contains(#"trap 'rm -rf "$SLICES_DIR"; if [[ -n "$UNFINISHED" ]]; then rm -rf "$UNFINISHED"; fi' EXIT"#))
		// The build number: what Sparkle compares, in the one form the release accepts.
		#expect(script.contains(#"! "$APP_BUILD" =~ '^[1-9][0-9]*$'"#))

		// The check of a built app looks at the same things, and the image carries the framework.
		let check = try Repository.text("scripts/verify-dmg.sh")
		for text in [
			#"sparkle_install_name="@rpath/Sparkle.framework/Versions/B/Sparkle""#, #"frameworks_rpath="@executable_path/../Frameworks""#,
			#"-name XPCServices -o -name '*.xpc'"#, #"for code in "$framework" "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app"; do"#,
			#"check_loaded_libraries "$sparkle_install_name" "$arch" "$binary" "실행 파일""#,
			#"check_loaded_libraries "$sparkle_install_name" "$arch" "$framework/Versions/B/Sparkle" "Sparkle.framework""#,
			"/System/Library/* | /usr/lib/*) ;;", #"lipo "$framework/Versions/B/Sparkle" -verify_arch "$arch""#, "^[1-9][0-9]*$",
			"SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUVerifyUpdateBeforeExtraction", "SUScheduledCheckInterval", "SUPublicEDKey",
			"ko.lproj/Sparkle.strings", "ThirdPartyNotices.txt"
		] {
			#expect(check.contains(text), "verify-dmg.sh: no \(text)")
		}
		// A key that is still the placeholder is reported there, not failed (this suite and the release fail on it).
		let keyCheck = try #require(check.range(of: #"if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then"#))
		#expect(check[keyCheck.upperBound...].prefix(40).contains("::notice::"))
		let image = try Repository.text("scripts/make-dmg.sh")
		#expect(image.contains(#"print -r -- "app=$APP""#) && image.contains(#"MOUNTED_FW="$MNT/$NAME.app/Contents/Frameworks/Sparkle.framework""#))
	}

	/// Sparkle's license (MIT) and the notices its LICENSE carries for the code it includes ship with the app, for the
	/// version that is built in; where SwiftPM has downloaded Sparkle, the text is its LICENSE byte for byte.
	@Test func theLicenseTextsShipWithTheApp() throws {
		let version = try Self.sparkleVersion()
		let notices = try Repository.text("Resources/ThirdPartyNotices.txt")
		let lines = notices.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		#expect(lines.first == "한글 파일명 정리기 includes the following third-party software:")
		#expect(lines.contains("Sparkle \(version)") && lines.contains("https://github.com/sparkle-project/Sparkle"))
		for text in [
			"Copyright (c) 2006-2013 Andy Matuschak.", "Permission is hereby granted, free of charge, to any person obtaining a copy of",
			"EXTERNAL LICENSES", "bspatch.c and bsdiff.c, from bsdiff 4.3", "Copyright 2003-2005 Colin Percival",
			"sais.c and sais.h, from sais-lite", "Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.",
			"Portable C implementation of Ed25519", "Copyright (c) 2015 Orson Peters", "SUSignatureVerifier.m:", "Copyright (c) 2011 Mark Hamlin."
		] {
			#expect(notices.contains(text), "ThirdPartyNotices.txt: no \(text)")
		}

		// build-app.sh refuses to build when the file is not for the framework's version, and copies it.
		let script = try Repository.text("scripts/build-app.sh")
		#expect(script.contains(#"/usr/bin/grep -qx "Sparkle $SPARKLE_VERSION" Resources/ThirdPartyNotices.txt"#))

		// SwiftPM's download (in the default build folder; elsewhere this part is not checked).
		let license = Repository.root.appendingPathComponent(".build/artifacts/sparkle/Sparkle/LICENSE")
		if let licenseData = try? Data(contentsOf: license) {
			let noticesData = try Data(contentsOf: Repository.root.appendingPathComponent("Resources/ThirdPartyNotices.txt"))
			#expect(licenseData.count > 4000 && noticesData.suffix(licenseData.count) == licenseData, "ThirdPartyNotices.txt does not end with Sparkle \(version)'s LICENSE")
		}
	}
}

/// The release: what the workflows and the release scripts do with the update key, read from their text. (How they
/// behave is checked by running them: scripts/check-release-tools.sh runs make-appcast.sh and ed25519-verify.swift
/// without a key.)
@Suite struct UpdaterReleaseTests {
	/// The private key's value reaches one step of one job: the step that signs. ci.yml hands it to release.yml by
	/// name; the key check only learns whether it is set; and make-appcast.sh takes it out of the environment before
	/// it starts any other program.
	@Test func thePrivateKeyReachesOnlyTheSigningStep() throws {
		let value = "SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}"
		let release = try Repository.lines(".github/workflows/release.yml")
		let holders = release.indices.filter { release[$0].contains(value) }
		#expect(holders.count == 1)
		let signing = try #require(release.firstIndex { $0.contains("- name: 업데이트 피드 만들기 (appcast.xml)") })
		let next = try #require(release[(signing + 1)...].firstIndex { $0.contains("- name: ") })
		#expect(holders.first.map { signing < $0 && $0 < next } == true, "the secret belongs to the signing step")
		#expect(release.contains { $0.contains("HAS_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY != '' }}") })

		let ci = try Repository.text(".github/workflows/ci.yml")
		#expect(ci.components(separatedBy: "${{ secrets.").count == 2 && ci.contains("      \(value)"), "ci.yml names the secret once, for release.yml")
		#expect(!ci.contains("\n    secrets: inherit"), "release.yml gets this one secret, not every secret of the repository")

		// make-appcast.sh: nothing is started before the key has left the environment, and it goes to sign_update
		// on standard input.
		let script = try Repository.lines("scripts/make-appcast.sh").filter { !$0.hasPrefix("#") && !$0.isEmpty }
		#expect(Array(script.prefix(4)) == ["set -e", "setopt pipefail", #"typeset +x PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}""#, "unset SPARKLE_PRIVATE_KEY"])
		#expect(script.contains { $0.contains(#"print -r -- "$PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" -p --ed-key-file - "$DMG""#) })
		let valueUsed = script.filter { $0.contains("$PRIVATE_KEY") || $0.contains("${SPARKLE_PRIVATE_KEY") }
		#expect(valueUsed.count == 3, "the key's value is read where it is taken, checked and handed to sign_update: \(valueUsed)")
	}

	/// Pull requests run the release tools without a key, and while the key-format test fails (the placeholder),
	/// the app is still built, inspected and started: the steps after the tests do not depend on their result.
	@Test func pullRequestsCheckTheReleaseToolsAndStillBuildWhenTheTestsFail() throws {
		let ci = try Repository.lines(".github/workflows/ci.yml")
		func step(_ name: String) throws -> [String] {
			let start = try #require(ci.firstIndex { $0.hasSuffix("- name: \(name)") }, "ci.yml: no step \(name)")
			let end = ci[(start + 1)...].firstIndex { $0.contains("- name: ") || $0.hasPrefix("  release:") } ?? ci.endIndex
			return ci[start..<end].map { $0.trimmingCharacters(in: .whitespaces) }
		}

		#expect(try step("릴리스 도구 확인 (키 없이)").contains("run: ./scripts/check-release-tools.sh"))
		let tests = try step("테스트")
		#expect(tests.contains("id: test") && tests.contains("run: ./scripts/test.sh") && !tests.contains { $0.hasPrefix("if:") })
		let afterTheTests = "if: ${{ !cancelled() && steps.test.outcome != 'skipped' }}"
		let withADiskImage = "if: ${{ !cancelled() && steps.dmg.outcome == 'success' }}"
		#expect(try step("테스트 (x86_64, Rosetta)").contains(afterTheTests))
		let image = try step("DMG 만들기 (release 빌드 포함)")
		#expect(image.contains(afterTheTests) && image.contains("id: dmg"))
		#expect(try step("DMG 확인").contains(withADiskImage))
		#expect(try step("실행 확인 (arm64, x86_64)").contains(withADiskImage))
		// A failed check never releases: the release job needs the check job and has no status function of its own.
		let release = ci[(try #require(ci.firstIndex { $0.hasPrefix("  release:") }))...]
		#expect(release.contains("    needs: check") && release.contains("    if: github.event_name == 'push' && github.ref == 'refs/heads/main'"))
		#expect(!ci.contains { $0.contains("continue-on-error") || $0.contains("always()") })
	}

	/// The update key can never change between releases: the plan, which pull requests run too, compares this
	/// commit's SUPublicEDKey with the key of every published release, and tells the build-number check whether a
	/// release with Sparkle is out (a missing feed is then an error, not "the first release").
	@Test func thePlanKeepsTheKeyOfTheReleasesSoFar() throws {
		let plan = try Repository.text("scripts/release-plan.mjs")
		for text in [
			#"updateKeyOf(git("show", `refs/tags/${release.name}:${infoPlistPath}`))"#, "if (releasedKey !== currentUpdateKey) {",
			"if (release.draft || release.name === tag) {", "sparkle_release: sparkleRelease"
		] {
			#expect(plan.contains(text), "release-plan.mjs: no \(text)")
		}
		let release = try Repository.text(".github/workflows/release.yml")
		#expect(release.contains("SPARKLE_RELEASE: ${{ steps.plan.outputs.sparkle_release }}"))
		let notFound = try #require(release.range(of: #"if [[ "$status" == 404 ]]; then"#))
		#expect(release[notFound.upperBound...].prefix(80).contains(#"if [[ -n "$SPARKLE_RELEASE" ]]; then"#))
	}
}
