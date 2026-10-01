// Helpers shared by the Core tests.
//
// The tests follow the same rule as the Core: a file name is compared by its scalars or bytes, never with `==` on
// Strings (which calls an NFC and an NFD spelling equal), and test files are created and listed with POSIX calls so
// that the spelling on disk is exactly the one the test asked for.
import Darwin
import Foundation
import Testing
@testable import HangeulFilenameFixerCore

/// A text compared scalar by scalar. `#expect(Exact(a) == Exact(b))` fails when `a` is NFD and `b` is NFC, and the
/// failure message shows the code points.
struct Exact: Equatable, CustomStringConvertible, Sendable {
	let text: String

	init(_ text: String) {
		self.text = text
	}

	static func == (first: Exact, second: Exact) -> Bool {
		first.text.unicodeScalars.elementsEqual(second.text.unicodeScalars)
	}

	var description: String {
		"\"\(text)\" [\(hexScalars(text))]"
	}
}

func hexScalars(_ text: String) -> String {
	text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " ")
}

/// Builds a String from space-separated hexadecimal code points ("D55C AE00"); "-" is the empty string.
func text(fromHex hex: String) -> String {
	if hex == "-" {
		return ""
	}

	var scalars = String.UnicodeScalarView()
	for part in hex.split(separator: " ") {
		if let value = UInt32(part, radix: 16), let scalar = Unicode.Scalar(value) {
			scalars.append(scalar)
		}
	}

	return String(scalars)
}

/// Decomposes modern Hangul syllables into conjoining jamo (what NFD does to Korean text), by the arithmetic of the
/// Unicode standard. Written out here so the tests do not depend on Foundation's or ICU's normalizer for their inputs.
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

/// True when the text contains a conjoining jamo (U+1100–U+11FF), i.e. it is not fully composed Korean.
func containsConjoiningJamo(_ text: String) -> Bool {
	text.unicodeScalars.contains { (0x1100...0x11FF).contains($0.value) }
}

struct TestError: Error, CustomStringConvertible {
	let description: String
}

/// The one folder everything of this test run is created in: the work folders, and the disk images and mount points
/// of the real-volume suite.
///
/// The tests tidy up after themselves, but a test process that crashes or is killed cannot. So a small watcher
/// process waits for this process to end, in whatever way, and then detaches the test volumes and removes the folder.
enum TestRun {
	/// `<temporary directory>/hangeul-filename-fixer-XXXXXX`, made on first use.
	static var root: String { started.root }

	/// Where the real-volume suite keeps its images and mount points (`hfs`, `exfat`). The watcher knows these names.
	static var volumesRoot: String { root + "/volumes" }

	/// The folder, and the write end of the pipe that is the watcher's standard input (-1 without a watcher). The
	/// pipe is never written to and never closed: it closes when this process ends, and that is what wakes the watcher.
	private static let started: (root: String, watcherInput: Int32) = start()

	private static func start() -> (root: String, watcherInput: Int32) {
		var template = Array((NSTemporaryDirectory() + "hangeul-filename-fixer-XXXXXX").utf8CString)
		guard mkdtemp(&template) != nil else {
			fatalError("mkdtemp failed: \(String(cString: strerror(errno)))")
		}

		let root = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
		let watcherInput = startWatcher(root: root)
		// The normal end of a run. Registered before the volumes' own handler, so it runs after it.
		atexit { TestRun.removeRoot() }
		return (root, watcherInput)
	}

	/// Removes the run's folder, unless a test volume is still mounted in it (the watcher detaches that one by force).
	private static func removeRoot() {
		var rootStatus = stat()
		guard lstat(root, &rootStatus) == 0 else {
			return
		}
		for name in ["hfs", "exfat"] {
			var mountStatus = stat()
			if stat(volumesRoot + "/" + name, &mountStatus) == 0, mountStatus.st_dev != rootStatus.st_dev {
				return
			}
		}

		removeTree(root)
	}

	private static func startWatcher(root: String) -> Int32 {
		// `read` returns when the pipe's last write end is closed, which the kernel does when this process ends, also
		// on a crash or SIGKILL. The signals a terminal sends to the whole process group (Ctrl-C) are ignored, so the
		// watcher outlives the test process it is cleaning up after. After a normal run there is nothing left to do,
		// and every step fails quietly.
		let script = """
			trap '' HUP INT QUIT TERM
			read -r _
			case "$1" in */hangeul-filename-fixer-??????) ;; *) exit 0 ;; esac
			for name in hfs exfat; do
				if [ -d "$1/volumes/$name" ]; then /usr/bin/hdiutil detach -quiet -force "$1/volumes/$name"; fi
			done
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
	try storedNames(in: directory).map(Exact.init)
}

func fileStatus(_ path: String, followingSymlinks: Bool = true) throws -> stat {
	var status = stat()
	guard (followingSymlinks ? stat(path, &status) : lstat(path, &status)) == 0 else {
		throw TestError(description: "stat(\(path)) failed: \(String(cString: strerror(errno)))")
	}

	return status
}

/// lstat: true for any entry with this name, also a symlink without a target.
func nameIsTaken(_ path: String) -> Bool {
	var status = stat()
	return lstat(path, &status) == 0
}

func permissionBits(_ path: String) throws -> mode_t {
	try fileStatus(path).st_mode & 0o7777
}

/// The value of an extended attribute, or nil when the file does not have it.
func extendedAttribute(_ name: String, atPath path: String) -> [UInt8]? {
	let size = getxattr(path, name, nil, 0, 0, 0)
	guard size >= 0 else {
		return nil
	}

	var value = [UInt8](repeating: 0, count: max(size, 1))
	let length = value.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, $0.count, 0, 0) }
	return length >= 0 ? Array(value.prefix(length)) : nil
}

func setExtendedAttribute(_ name: String, _ value: [UInt8], atPath path: String) throws {
	let result = value.withUnsafeBytes { setxattr(path, name, $0.baseAddress, $0.count, 0, 0) }
	guard result == 0 else {
		throw TestError(description: "setxattr(\(name), \(path)) failed: \(String(cString: strerror(errno)))")
	}
}

func extendedAttributeNames(atPath path: String) -> [String] {
	let size = listxattr(path, nil, 0, 0)
	guard size > 0 else {
		return []
	}

	var buffer = [CChar](repeating: 0, count: size)
	let length = listxattr(path, &buffer, size, 0)
	guard length > 0 else {
		return []
	}

	return buffer[..<length].split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }.sorted()
}

let quarantineAttributeName = "com.apple.quarantine"
let sampleQuarantine = "0083;66f00000;Safari;"

/// Runs a command-line tool and returns its exit status and standard output.
@discardableResult
func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
	let process = Process()
	process.executableURL = URL(fileURLWithPath: tool)
	process.arguments = arguments
	let output = Pipe()
	process.standardOutput = output
	process.standardError = Pipe()
	try process.run()
	let data = output.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// The message of the `UserFacingError` the body throws, or nil when it does not throw.
func failureMessage<T>(_ body: () throws -> T) -> Exact? {
	do {
		_ = try body()
		return nil
	} catch let error as UserFacingError {
		return Exact(error.message)
	} catch {
		return Exact("unexpected error type: \(error)")
	}
}

/// True when the folder's volume finds a file under either normalization of its name (APFS, HFS+, exFAT, FAT32).
func isNormalizationInsensitive(_ directory: String) throws -> Bool {
	let probe = directory + "/" + "정규화 확인.tmp"
	try writeFile(probe, "")
	defer { unlink(probe) }
	return nameIsTaken(directory + "/" + decomposed("정규화 확인.tmp"))
}

/// The paths of this process's open descriptors that lie under `directory`. F_GETPATH keeps reporting the path of a
/// file that was deleted while open, so a descriptor leaked for a removed copy shows up too.
func openDescriptorPaths(under directory: String) -> [String] {
	guard let resolved = realpath(directory, nil) else {
		return []
	}
	defer { free(resolved) }

	let prefix = Array(String(cString: resolved).utf8) + [UInt8(ascii: "/")]
	var paths: [String] = []
	for descriptor in 0..<min(getdtablesize(), 10240) {
		var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
		guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else {
			continue
		}

		let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
		if path.utf8.starts(with: prefix) {
			paths.append(path)
		}
	}

	return paths
}
