// Helpers shared by the app's tests.
//
// The same rule as in the app: a file name is compared by its scalars or bytes, never with `==` on Strings (which
// calls an NFC and an NFD spelling equal). Test files are created and listed with POSIX calls, so the spelling on
// disk is exactly the one the test asked for.
import AppKit
import Darwin
import Foundation
import SwiftUI
import Testing
import HangeulFilenameFixerCore
@testable import HangeulFilenameFixer

/// A text compared scalar by scalar. `#expect(Exact(a) == Exact(b))` fails when `a` is NFD and `b` is NFC, and the
/// failure message shows the code points.
struct Exact: Equatable, CustomStringConvertible, Sendable {
	let text: String

	init(_ text: String) {
		self.text = text
	}

	init?(_ text: String?) {
		guard let text else {
			return nil
		}

		self.text = text
	}

	static func == (first: Exact, second: Exact) -> Bool {
		first.text.unicodeScalars.elementsEqual(second.text.unicodeScalars)
	}

	var description: String {
		"\"\(text)\" [\(text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " "))]"
	}
}

/// Decomposes modern Hangul syllables into conjoining jamo (what NFD does to Korean text), by the arithmetic of the
/// Unicode standard, so the tests do not depend on a normalizer for their inputs.
func decomposed(_ text: String) -> String {
	var scalars = String.UnicodeScalarView()
	for scalar in text.unicodeScalars {
		guard (0xAC00...0xD7A3).contains(scalar.value) else {
			scalars.append(scalar)
			continue
		}

		let index = scalar.value - 0xAC00
		let (choseong, jungseong, jongseong) = (index / 588, (index % 588) / 28, index % 28)
		for value in [0x1100 + choseong, 0x1161 + jungseong] + (jongseong == 0 ? [] : [0x11A7 + jongseong]) {
			if let jamo = Unicode.Scalar(value) {
				scalars.append(jamo)
			}
		}
	}

	return String(scalars)
}

struct TestError: Error, CustomStringConvertible {
	let description: String
}

/// The one folder everything of this test run is created in (the Core's tests have the same, with the same watcher).
///
/// The tests tidy up after themselves, but a test process that crashes or is killed cannot. So a small watcher
/// process waits for this process to end, in whatever way, and then removes the folder.
enum TestRun {
	/// `<temporary directory>/hangeul-filename-fixer-app-XXXXXX`, made on first use.
	static var root: String { started.root }

	/// The folder, and the write end of the pipe that is the watcher's standard input (-1 without a watcher). The
	/// pipe is never written to and never closed: it closes when this process ends, and that is what wakes the watcher.
	private static let started: (root: String, watcherInput: Int32) = start()

	private static func start() -> (root: String, watcherInput: Int32) {
		// The real path: the temporary folder is reached through a symlink (/var → /private/var).
		let temporary = realpath(NSTemporaryDirectory(), nil).map { pointer -> String in
			defer { free(pointer) }
			return String(cString: pointer)
		} ?? NSTemporaryDirectory()
		var template = Array((temporary + "/hangeul-filename-fixer-app-XXXXXX").utf8CString)
		guard mkdtemp(&template) != nil else {
			fatalError("mkdtemp failed: \(String(cString: strerror(errno)))")
		}

		let root = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
		let watcherInput = startWatcher(root: root)
		// The normal end of a run.
		atexit { removeTree(TestRun.root) }
		return (root, watcherInput)
	}

	private static func startWatcher(root: String) -> Int32 {
		// `read` returns when the pipe's last write end is closed, which the kernel does when this process ends, also
		// on a crash or SIGKILL. The signals a terminal sends to the whole process group (Ctrl-C) are ignored, so the
		// watcher outlives the test process it is cleaning up after. After a normal run there is nothing left to do.
		let script = """
			trap '' HUP INT QUIT TERM
			read -r _
			case "$1" in */hangeul-filename-fixer-app-??????) ;; *) exit 0 ;; esac
			/bin/chmod -R u+rwx "$1"
			/bin/rm -rf "$1"
			"""

		var ends: [Int32] = [-1, -1]
		guard pipe(&ends) == 0 else {
			return -1
		}
		// The write end must stay in this process alone: a child that inherited it would keep the pipe open.
		_ = fcntl(ends[1], F_SETFD, FD_CLOEXEC)

		let watcher = Process()
		watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
		watcher.arguments = ["-c", script, "sh", root]
		watcher.standardInput = FileHandle(fileDescriptor: ends[0], closeOnDealloc: true)
		// Not this process's output: `swift test` would wait for the watcher to close it.
		watcher.standardOutput = FileHandle.nullDevice
		watcher.standardError = FileHandle.nullDevice
		// Without the watcher (a sandbox that forbids /bin/sh) the tests still run; only the crash cleanup is missing.
		guard (try? watcher.run()) != nil else {
			close(ends[1])
			return -1
		}

		return ends[1]
	}
}

/// A work folder with "source" and "output" inside, removed again when the owning suite instance goes away.
final class TestFolders: Sendable {
	let work: String
	let source: String
	let output: String

	init() {
		var template = Array((TestRun.root + "/case-XXXXXX").utf8CString)
		guard mkdtemp(&template) != nil else {
			fatalError("mkdtemp failed: \(String(cString: strerror(errno)))")
		}

		work = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
		source = work + "/source"
		output = work + "/output"
		mkdir(source, 0o755)
		mkdir(output, 0o755)
	}

	deinit {
		removeTree(work)
	}

	/// Creates `source/<name>` with exactly this spelling and returns its path.
	func writeSource(_ name: String, _ content: String = "content") throws -> String {
		try writeFile(source + "/" + name, content)
	}
}

/// Removes a folder and everything in it, also when a test left something read-only.
func removeTree(_ path: String) {
	var status = stat()
	guard lstat(path, &status) == 0 else {
		return
	}
	guard (status.st_mode & S_IFMT) == S_IFDIR else {
		unlink(path)
		return
	}

	chmod(path, 0o700)
	for name in (try? storedNames(in: path)) ?? [] {
		removeTree(path + "/" + name)
	}
	rmdir(path)
}

/// Creates a file with open(2), so it is stored under exactly the given spelling. Fails if the name exists.
@discardableResult
func writeFile(_ path: String, _ content: String = "content", mode: mode_t = 0o644) throws -> String {
	let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, mode)
	guard descriptor >= 0 else {
		throw TestError(description: "open(\(path)) failed: \(String(cString: strerror(errno)))")
	}
	defer { close(descriptor) }

	let bytes = Array(content.utf8)
	let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
	guard written == bytes.count else {
		throw TestError(description: "write(\(path)) failed: \(String(cString: strerror(errno)))")
	}

	return path
}

func readFile(_ path: String) throws -> String {
	let descriptor = open(path, O_RDONLY)
	guard descriptor >= 0 else {
		throw TestError(description: "open(\(path)) failed: \(String(cString: strerror(errno)))")
	}
	defer { close(descriptor) }

	var content: [UInt8] = []
	var buffer = [UInt8](repeating: 0, count: 65536)
	while true {
		let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
		guard count >= 0 else {
			throw TestError(description: "read(\(path)) failed: \(String(cString: strerror(errno)))")
		}
		if count == 0 {
			break
		}
		content.append(contentsOf: buffer[..<count])
	}

	return String(decoding: content, as: UTF8.self)
}

/// The names in a folder as raw bytes straight from readdir, sorted. Independent of the Core's own listing code.
func storedNameBytes(in directory: String) throws -> [[UInt8]] {
	guard let stream = opendir(directory) else {
		throw TestError(description: "opendir(\(directory)) failed: \(String(cString: strerror(errno)))")
	}
	defer { closedir(stream) }

	var names: [[UInt8]] = []
	while let entry = readdir(stream) {
		let length = Int(entry.pointee.d_namlen)
		let bytes = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
			Array(UnsafeRawBufferPointer(start: pointer, count: length))
		}
		if bytes != Array(".".utf8), bytes != Array("..".utf8) {
			names.append(bytes)
		}
	}

	return names.sorted { $0.lexicographicallyPrecedes($1) }
}

/// The names in a folder with the spelling the volume reports, sorted by their bytes.
func storedNames(in directory: String) throws -> [String] {
	try storedNameBytes(in: directory).map { String(decoding: $0, as: UTF8.self) }
}

func exactNames(in directory: String) throws -> [Exact] {
	try storedNames(in: directory).map { Exact($0) }
}

func fileStatus(_ path: String) throws -> stat {
	var status = stat()
	guard stat(path, &status) == 0 else {
		throw TestError(description: "stat(\(path)) failed: \(String(cString: strerror(errno)))")
	}

	return status
}

/// True when the folder's volume finds a file under either normalization of its name (APFS does). The original then
/// takes the copy's name when both are in one folder, and the copy gets " (1)".
func isNormalizationInsensitive(_ directory: String) throws -> Bool {
	let probe = directory + "/" + "정규화 확인.tmp"
	try writeFile(probe, "")
	defer { unlink(probe) }
	var status = stat()
	return lstat(directory + "/" + decomposed("정규화 확인.tmp"), &status) == 0
}

/// Holds a piece of work back until the test lets it go.
final class Gate: @unchecked Sendable {
	private let condition = NSCondition()
	private var isOpen = false
	private var waiting = 0

	func open() {
		condition.lock()
		isOpen = true
		condition.broadcast()
		condition.unlock()
	}

	func wait() {
		condition.lock()
		waiting += 1
		while !isOpen {
			condition.wait()
		}
		condition.unlock()
	}
}

/// Counts calls from any thread.
final class Counter: @unchecked Sendable {
	private let lock = NSLock()
	private var value = 0

	func increment() {
		lock.lock()
		value += 1
		lock.unlock()
	}

	var count: Int {
		lock.lock()
		defer { lock.unlock() }
		return value
	}
}

/// Stands in for the window: answers the two panels with what the test prepared and records what was asked.
@MainActor
final class FakeShell: AppShell {
	var fileAnswer: String?
	var directoryAnswer: String?
	private(set) var fileRequests = 0
	private(set) var directoryRequests: [String?] = []
	private(set) var revealedPaths: [String] = []

	func chooseFile(completion: @escaping @MainActor (String?) -> Void) {
		fileRequests += 1
		completion(fileAnswer)
	}

	func chooseOutputDirectory(startingAt directory: String?, completion: @escaping @MainActor (String?) -> Void) {
		directoryRequests.append(directory)
		completion(directoryAnswer)
	}

	func revealInFinder(path: String) {
		revealedPaths.append(path)
	}
}

extension AppModel {
	/// Waits until the preview that was asked for last has arrived.
	func previewSettled() async {
		await pendingPreview?.value
	}

	/// Waits until the running copy has finished and the preview after it has arrived.
	func conversionSettled() async {
		await pendingConversion?.value
		await pendingPreview?.value
	}
}

// MARK: - Screens that are never shown

/// Lets SwiftUI bring its AppKit views up to date with the model.
@MainActor
func settleScreen(_ view: NSView?) {
	view?.layoutSubtreeIfNeeded()
	RunLoop.current.run(until: Date().addingTimeInterval(0.1))
	view?.layoutSubtreeIfNeeded()
}

/// The same for the app's window, which fits itself to the content after the layout has finished. That is work
/// waiting for the main actor, and it only gets its turn when the test lets go of it.
@MainActor
func settleWindow(_ window: NSWindow) async {
	for _ in 0..<2 {
		settleScreen(window.contentView)
		for _ in 0..<5 {
			await Task.yield()
		}
	}
}

@MainActor
func findViews<V: NSView>(_ type: V.Type, in view: NSView?) -> [V] {
	guard let view else {
		return []
	}

	let own = (view as? V).map { [$0] } ?? []
	return own + view.subviews.flatMap { findViews(type, in: $0) }
}

@MainActor
func findView<V: NSView>(_ type: V.Type, in view: NSView?) -> V? {
	findViews(type, in: view).first
}

/// A screen that SwiftUI built, read the way an assistive app reads it: the buttons and texts with their identifiers,
/// what they say, whether they can be pressed, and a press. This is how the unit tests see what is really on the
/// screen (a SwiftUI button has no AppKit view of its own to look at).
///
/// SwiftUI only describes its views this way once an assistive app has announced itself. `isAvailable` does that for
/// this process and reports whether a description then exists; the tests that need it are skipped where it does not.
@MainActor
struct ScreenReader {
	struct Element {
		let object: NSObject

		private func text(_ key: String) -> String? {
			guard object.responds(to: NSSelectorFromString(key)) else {
				return nil
			}

			return object.value(forKey: key).map { "\($0)" }
		}

		var identifier: String { text("accessibilityIdentifier") ?? "" }
		var role: String { text("accessibilityRole") ?? "" }
		var label: String? { text("accessibilityLabel") }
		var value: String? { text("accessibilityValue") }
		var isEnabled: Bool { text("isAccessibilityEnabled") == "1" }

		var frame: NSRect {
			guard object.responds(to: NSSelectorFromString("accessibilityFrame")) else {
				return .zero
			}

			return (object.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
		}

		/// Presses the element as VoiceOver does. A button that is switched off does nothing.
		func press() {
			let selector = NSSelectorFromString("accessibilityPerformPress")
			guard object.responds(to: selector), let method = object.method(for: selector) else {
				return
			}

			typealias Press = @convention(c) (NSObject, Selector) -> Bool
			_ = unsafeBitCast(method, to: Press.self)(object, selector)
		}
	}

	let elements: [Element]

	init(_ root: NSView?) {
		var found: [Element] = []
		func collect(_ object: NSObject, depth: Int) {
			found.append(Element(object: object))
			guard depth < 40, object.responds(to: NSSelectorFromString("accessibilityChildren")) else {
				return
			}

			for child in object.value(forKey: "accessibilityChildren") as? [Any] ?? [] {
				if let child = child as? NSObject {
					collect(child, depth: depth + 1)
				}
			}
		}
		if let root {
			collect(root, depth: 0)
		}
		elements = found
	}

	subscript(identifier: String) -> Element? {
		elements.first { $0.identifier == identifier }
	}

	/// The identifiers of the screen's elements, in their order on the screen.
	var identifiers: [String] {
		elements.map(\.identifier).filter { !$0.isEmpty && !$0.hasPrefix("_") }
	}

	/// The texts that have no identifier (headings, labels, notes), in their order on the screen.
	var plainTexts: [String] {
		elements.filter { $0.identifier.isEmpty && $0.role == NSAccessibility.Role.staticText.rawValue }.compactMap(\.value)
	}

	/// True where a run that cannot read the screen must not pass: on CI (GitHub Actions sets `CI`), or when
	/// `HANGEUL_REQUIRE_SCREEN_READER=1` asks for it. `HANGEUL_REQUIRE_SCREEN_READER=0` allows the skip on CI as well.
	/// (The same rule as the Core tests' real volumes, `HANGEUL_REQUIRE_VOLUMES`.)
	nonisolated static var isRequired: Bool {
		func value(_ name: String) -> String {
			getenv(name).map { String(cString: $0) } ?? ""
		}

		switch value("HANGEUL_REQUIRE_SCREEN_READER") {
		case "1":
			return true
		case "0":
			return false
		default:
			return !["", "0", "false"].contains(value("CI"))
		}
	}

	/// Tells AppKit and SwiftUI that an assistive app is listening (what VoiceOver does when it starts), then looks
	/// whether a SwiftUI text can be found by its identifier.
	static let isAvailable: Bool = {
		let application = NSApplication.shared
		let announce = NSSelectorFromString("accessibilitySetValue:forAttribute:")
		guard application.responds(to: announce) else {
			return false
		}

		application.perform(announce, with: true as NSNumber, with: "AXEnhancedUserInterface" as NSString)
		let probe = NSHostingView(rootView: Text(verbatim: "probe").accessibilityIdentifier("screenReaderProbe"))
		probe.frame = NSRect(x: 0, y: 0, width: 200, height: 50)
		let window = NSWindow(contentRect: probe.frame, styleMask: [.titled], backing: .buffered, defer: true)
		window.isReleasedWhenClosed = false
		window.contentView = probe
		settleScreen(probe)
		return ScreenReader(probe)["screenReaderProbe"]?.value == "probe"
	}()
}
