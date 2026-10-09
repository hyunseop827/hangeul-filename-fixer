// 앱 메뉴 > "업데이트 확인…" and the "업데이트 확인" link under the card (RootView): Sparkle 2's standard updater. The only
// code of the app that uses the network, and the only file that imports Sparkle.
//
// What goes over the network, and when:
// - The feed. Once a day at most, and only while the app is running (Sparkle's default interval; Info.plist sets
//   `SUEnableAutomaticChecks`, so there is no "check automatically?" question), and when the user chooses
//   "업데이트 확인…", Sparkle reads `SUFeedURL`: the appcast.xml of the latest GitHub release. "Once a day" counts
//   from the last check, which Sparkle remembers in the app's preferences: when the app is opened and no check was
//   made in the last day (always so the first time it is opened), the feed is read right after the launch. The
//   request says which app and version is asking (the User-Agent, "…/2.0.0 Sparkle/2.10.0") and nothing about the
//   Mac or the user (no system profile: `SUEnableSystemProfiling` is not set). Nothing about the files the app works
//   on is ever sent.
// - The update itself, only after the user agreed. When the feed lists a newer build, Sparkle's window shows the
//   release notes (they are part of the feed) and asks. `SUAllowsAutomaticUpdates` is false, so there is no "install
//   automatically" option: without a click on "업데이트 설치" nothing is downloaded. Then Sparkle downloads the disk
//   image the feed names, checks it against the EdDSA key in `SUPublicEDKey` before opening it
//   (`SUVerifyUpdateBeforeExtraction`), replaces this app and opens it again.
//
// Quitting for an update: Sparkle asks the app to quit the ordinary way (a quit event, as from the Dock), so it goes
// through `AppDelegate.applicationShouldTerminate`: a copy that is being written is finished first, and the update is
// installed right after.
//
// Sparkle's windows are Korean: they are shown by Sparkle.framework inside this app, a framework takes the language
// of the app that loads it, the app's only language is Korean (Info.plist, CFBundleLocalizations), and the framework
// has a ko.lproj (scripts/build-app.sh and scripts/verify-dmg.sh check that it is in the bundle). Two things are not
// the app's to decide: Sparkle 2.10.0 has no Korean wording for a few rare error messages, which then appear in
// English; and the small progress window of the helper that installs an update, a program of its own, follows the
// system language.
import AppKit
import Combine
import Sparkle

/// What Info.plist says about updates, and the decision whether that is enough to start the updater. Values only, so
/// the decision is tested without a bundle and without Sparkle.
struct UpdaterConfiguration {
	/// `SUFeedURL` and `SUPublicEDKey`; nil when the key is missing or not a string.
	var feedURL: String?
	var publicKey: String?

	init(feedURL: String?, publicKey: String?) {
		self.feedURL = feedURL
		self.publicKey = publicKey
	}

	/// Outside an app bundle (`swift run`, the unit tests) there is no Info.plist of the app, and both are nil.
	init(bundle: Bundle) {
		self.init(
			feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
			publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
		)
	}

	/// The updater is started only with a feed to read and a key to check updates with. Sparkle refuses to start
	/// with a key it cannot decode and then puts an alert on the screen; a build that still has the placeholder for
	/// the key must open like any other, so the same question is asked here first.
	var canStart: Bool {
		Self.isFeed(feedURL) && Self.isPublicKey(publicKey)
	}

	/// A feed is named: `SUFeedURL` is there and not empty. Whether the address can be read is Sparkle's to say
	/// when it starts (a refusal is logged, see `startSparkle`). Which address a shipped app has is not decided
	/// here: the unit tests and scripts/verify-dmg.sh accept only the https address of the latest GitHub release.
	static func isFeed(_ text: String?) -> Bool {
		guard let text else {
			return false
		}

		return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	/// An Ed25519 public key as Sparkle's `generate_keys` prints it: 32 bytes in base64 (44 characters). Sparkle
	/// itself ignores white space around the key, so this does too.
	static func isPublicKey(_ text: String?) -> Bool {
		guard let text else {
			return false
		}

		return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))?.count == 32
	}
}

/// What the two update controls (the menu item and the link) send, and to whom: Sparkle's controller and its
/// `checkForUpdates(_:)` in the app (the value also keeps the controller alive), any object in the tests.
struct UpdateCheck {
	let target: AnyObject
	let action: Selector
}

@MainActor
final class AppUpdater: ObservableObject {
	static let shared = AppUpdater()

	/// Nil when no updater was started: outside an app bundle, without a feed, with the placeholder for the key, or
	/// when Sparkle could not start. Both controls are then disabled, and nothing is ever asked of the network.
	let check: UpdateCheck?
	/// Whether a check can start now: false without an updater, and while Sparkle's window shows a check or an update
	/// (`SPUUpdater.canCheckForUpdates`, the same answer the controller gives for the menu item). The link follows it.
	@Published private(set) var canCheck: Bool
	private var observation: NSKeyValueObservation?

	/// `start` is only called when the configuration allows it. (A value, so the unit tests can ask without Sparkle.)
	init(
		configuration: UpdaterConfiguration = UpdaterConfiguration(bundle: .main),
		start: @MainActor () -> UpdateCheck? = AppUpdater.startSparkle
	) {
		check = configuration.canStart ? start() : nil
		canCheck = check != nil
		guard let updater = (check?.target as? SPUStandardUpdaterController)?.updater else {
			return
		}

		observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
			// Sparkle changes it on the main thread.
			MainActor.assumeIsolated {
				self?.canCheck = updater.canCheckForUpdates
			}
		}
	}

	var isAvailable: Bool {
		check != nil
	}

	/// The link's press: the check the menu item sends, to the same target (a check the user asked for, whose window
	/// says what it found or that this is the latest version). Nothing without an updater, and nothing while a check
	/// cannot start: the link is disabled then, and a press that arrives all the same (by automation) does as little as
	/// the disabled menu item.
	func checkForUpdates() {
		guard let check, canCheck else {
			return
		}

		_ = NSApp.sendAction(check.action, to: check.target, from: nil)
	}

	/// Starts Sparkle's updater for the main bundle. Starting reads the settings and schedules the daily check: when
	/// no check was made in the last day (always so on the first launch) Sparkle reads the feed right away;
	/// otherwise it waits until a day has passed since the last one. Starting also lets an update the user already
	/// agreed to, and which waited for the app to quit, finish.
	///
	/// The controller is made without starting it, and the updater is started here: started by the controller, a
	/// failure would put Sparkle's "업데이트를 확인할 수 없습니다." alert on the screen at every launch, about
	/// something the user cannot change. A failure is logged instead, and both controls stay disabled.
	///
	/// The menu item goes straight to the controller's `checkForUpdates(_:)`: a check the user asked for, whose
	/// window says what it found (or that this is the latest version). The controller validates the item itself and
	/// disables it while a check is running.
	static func startSparkle() -> UpdateCheck? {
		let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
		do {
			try controller.updater.start()
		} catch {
			NSLog("The updater did not start: %@", error.localizedDescription)
			return nil
		}

		return UpdateCheck(target: controller, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
	}

	// MARK: The link's texts

	/// The link's text: the menu item's words without the ellipsis (the version is in its tooltip).
	static var linkName: String {
		String(localized: "업데이트 확인")
	}

	/// This build's version with its build number, as the About panel shows them ("2.0.2 (16)"); nil outside an app
	/// bundle (`swift run`, the unit tests), where the bundle has no Info.plist of the app.
	static func version(of bundle: Bundle) -> String? {
		guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
			return nil
		}

		let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		return build.map { "\(version) (\($0))" } ?? version
	}

	/// The link's tooltip: which version this is and, while the link can be used, what a click does. A disabled link
	/// (no updater, or Sparkle's window is already checking) names only the version.
	static func help(version: String? = version(of: .main), enabled: Bool = true) -> String {
		let about = version.map { String(localized: "현재 버전") + " " + $0 + "." }
		let action = enabled ? String(localized: "눌러서 업데이트를 확인합니다.") : nil
		return [about, action].compactMap { $0 }.joined(separator: " ")
	}
}
