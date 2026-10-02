// The copy engine against real HFS+ and exFAT volumes.
//
// macOS reports names on these volumes decomposed, so a copy with a Korean name cannot be kept there (see "Intended
// behavior (not bugs)" in AGENTS.md): the engine must refuse it in Korean and leave nothing behind, not even the "._" AppleDouble
// file exFAT uses for extended attributes. A name without composed characters must work as on APFS.
//
// Two 4 MB disk images are made with hdiutil once per run (about 3 seconds) and detached when the suite ends, or by
// the watcher process of `TestRun` when the test process dies before that. When hdiutil cannot create or attach them
// (a sandbox), the whole suite is skipped with a message. Where the volumes are expected (CI), that skip is a
// failure: see `realVolumesAreThereWhereRequired`.
import Darwin
import Foundation
import Testing
@testable import HangeulFilenameFixerCore

final class TestVolumes: Sendable {
	enum Kind: String, CaseIterable, Sendable, CustomTestStringConvertible {
		case hfs = "HFS+"
		case exfat = "ExFAT"

		var testDescription: String { rawValue }
		var folderName: String { self == .hfs ? "hfs" : "exfat" }
	}

	/// The volumes, or nil when they could not be made. Attached on first use.
	static let shared: TestVolumes? = attach()

	/// True where a run without the real volumes must not pass: on CI (GitHub Actions sets `CI`), or when
	/// `HANGEUL_REQUIRE_VOLUMES=1` asks for it. `HANGEUL_REQUIRE_VOLUMES=0` allows the skip on CI as well.
	static var areRequired: Bool {
		func value(_ name: String) -> String {
			getenv(name).map { String(cString: $0) } ?? ""
		}

		switch value("HANGEUL_REQUIRE_VOLUMES") {
		case "1":
			return true
		case "0":
			return false
		default:
			return !["", "0", "false"].contains(value("CI"))
		}
	}

	let root: String

	private init(root: String) {
		self.root = root
	}

	func mountPoint(_ kind: Kind) -> String {
		root + "/" + kind.folderName
	}

	/// A new empty folder on the volume.
	func makeFolder(on kind: Kind) throws -> String {
		let folder = mountPoint(kind) + "/case-\(UUID().uuidString)"
		guard mkdir(folder, 0o755) == 0 else {
			throw TestError(description: "mkdir(\(folder)) failed: \(String(cString: strerror(errno)))")
		}

		return folder
	}

	private static func attach() -> TestVolumes? {
		// Inside the run's folder, where the watcher process detaches the images should this process be killed
		// while they are attached (see TestRun).
		let volumes = TestVolumes(root: TestRun.volumesRoot)
		guard mkdir(volumes.root, 0o755) == 0 else {
			return nil
		}
		// Also detach when the process ends without the suite having run to its end.
		atexit { TestVolumes.shared?.detach() }

		for kind in Kind.allCases {
			let image = volumes.root + "/" + kind.folderName + ".dmg"
			let mountPoint = volumes.mountPoint(kind)
			mkdir(mountPoint, 0o755)

			// -quiet also silences the deprecation notice newer macOS versions print for hdiutil.
			let created = try? run("/usr/bin/hdiutil", ["create", "-quiet", "-size", "4m", "-fs", kind.rawValue, "-layout", "NONE", "-volname", "HFFTEST", image])
			var attached: (status: Int32, output: String)?
			if created?.status == 0 {
				attached = try? run("/usr/bin/hdiutil", ["attach", "-quiet", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint, image])
			}
			guard attached?.status == 0, volumes.isMounted(kind) else {
				print("skipping the real-volume tests: hdiutil could not create or attach a \(kind.rawValue) image")
				volumes.detach()
				return nil
			}
		}

		return volumes
	}

	private func isMounted(_ kind: Kind) -> Bool {
		var rootStatus = stat()
		var mountStatus = stat()
		guard stat(root, &rootStatus) == 0, stat(mountPoint(kind), &mountStatus) == 0 else {
			return false
		}

		return rootStatus.st_dev != mountStatus.st_dev
	}

	/// Detaches both images (by our own mount points only) and removes the temporary folder. Safe to call twice.
	func detach() {
		for kind in Kind.allCases where isMounted(kind) {
			for _ in 0..<5 where isMounted(kind) {
				if (try? run("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint(kind)]))?.status != 0 {
					usleep(500_000)
				}
			}
			// Still mounted after five tries: force, so no image stays attached.
			if isMounted(kind) {
				_ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mountPoint(kind)])
			}
		}

		// Only delete the folder when nothing is mounted inside it any more.
		if !Kind.allCases.contains(where: isMounted) {
			removeTree(root)
		}
	}
}

/// Detaches the test volumes when the suite it is attached to has finished.
struct DetachingTestVolumes: SuiteTrait, TestScoping {
	func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
		defer { TestVolumes.shared?.detach() }
		try await function()
	}
}

// Serialized: the volumes are tiny, and the full-volume test must not starve the others.
@Suite(
	"Real HFS+ and exFAT volumes",
	.serialized,
	.enabled(if: TestVolumes.shared != nil, "hdiutil could not create or attach the HFS+ and exFAT test images"),
	DetachingTestVolumes()
)
struct VolumeTests {
	let folders = TestFolders()
	static let nfcMessage = "이 저장 위치는 파일명을 NFC로 유지하지 못합니다(외장 드라이브 등). 내장 디스크의 다른 폴더를 선택하세요."
	static let quarantineMessage = "다운로드 보안 표시(quarantine)를 사본에 옮기지 못했습니다. 다른 저장 위치를 선택하세요."

	@Test("the test volumes are real HFS+ and exFAT mounts", arguments: TestVolumes.Kind.allCases)
	func volumesAreReal(kind: TestVolumes.Kind) throws {
		let volumes = try #require(TestVolumes.shared)
		var information = statfs()
		try #require(statfs(volumes.mountPoint(kind), &information) == 0)
		let typeName = withUnsafeBytes(of: &information.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }

		#expect(typeName == (kind == .hfs ? "hfs" : "exfat"))
	}

	/// True when the volume lists a name written in NFC as NFD, which is what HFS+ and exFAT do on macOS.
	private func listsNamesDecomposed(_ folder: String) throws -> Bool {
		let probe = folder + "/" + "확인.tmp"
		try writeFile(probe, "")
		defer { unlink(probe) }
		return try storedNameBytes(in: folder).contains(Array(decomposed("확인.tmp").utf8))
	}

	private func quarantinedReadOnlySource(_ name: String, _ content: String) throws -> String {
		let sourcePath = try folders.writeSource(name, content)
		try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
		guard chmod(sourcePath, 0o444) == 0 else {
			throw TestError(description: "chmod failed")
		}

		return sourcePath
	}

	@Test("a Korean name is refused in Korean and nothing is left in the folder", arguments: TestVolumes.Kind.allCases)
	func hangulNameIsRefused(kind: TestVolumes.Kind) throws {
		let volumes = try #require(TestVolumes.shared)
		let sources = [
			try quarantinedReadOnlySource(decomposed("한글 사본.txt"), "payload"),
			try folders.writeSource(decomposed("일반 파일.txt"), "plain"),
			// An empty file: on exFAT its inode number is made up and changes between listings.
			try folders.writeSource(decomposed("빈 파일.txt"), "")
		]

		for sourcePath in sources {
			let folder = try volumes.makeFolder(on: kind)
			guard try listsNamesDecomposed(folder) else {
				// Not what macOS does today. Then the copy must simply succeed with an NFC name.
				print("note: this macOS lists NFC names unchanged on \(kind.rawValue); checking a successful copy instead")
				let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: ""))
				#expect(isNFCName(created.destinationName))
				continue
			}

			let message = failureMessage { try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: "")) }

			#expect(message == Exact(Self.nfcMessage))
			#expect(try storedNames(in: folder) == [], "no copy and no ._ file may be left on \(kind.rawValue)")
		}

		// The original was only read.
		#expect(try permissionBits(sources[0]) == 0o444)
		#expect(extendedAttribute(quarantineAttributeName, atPath: sources[0]) == Array(sampleQuarantine.utf8))
		#expect(try exactNames(in: folders.source).count == 3)
	}

	@Test("a typed Korean name is refused as well, next to copies that were kept", arguments: TestVolumes.Kind.allCases)
	func typedHangulNameIsRefused(kind: TestVolumes.Kind) throws {
		let volumes = try #require(TestVolumes.shared)
		let folder = try volumes.makeFolder(on: kind)
		guard try listsNamesDecomposed(folder) else {
			print("note: this macOS lists NFC names unchanged on \(kind.rawValue)")
			return
		}
		let sourcePath = try folders.writeSource("report.txt", "payload")

		let kept = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: ""))
		let before = try storedNameBytes(in: folder)
		let message = failureMessage { try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: "보고서")) }

		#expect(message == Exact(Self.nfcMessage))
		#expect(try storedNameBytes(in: folder) == before, "only the refused copy is removed")
		#expect(try readFile(kept.destinationPath) == "payload")
	}

	@Test("a name without composed characters is copied, with its quarantine flag", arguments: TestVolumes.Kind.allCases)
	func asciiNameIsCopied(kind: TestVolumes.Kind) throws {
		let volumes = try #require(TestVolumes.shared)
		let folder = try volumes.makeFolder(on: kind)
		let name = "Report Final (v2).txt"
		let sourcePath = try quarantinedReadOnlySource(name, "payload")

		let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: ""))

		#expect(Exact(created.destinationName) == Exact(name))
		#expect(Exact(created.destinationPath) == Exact(folder + "/" + name))
		#expect(created.hasNumberSuffix == false)
		#expect(try readFile(created.destinationPath) == "payload")
		// exFAT keeps extended attributes in a "._" file beside the copy; that one may be there, nothing else.
		let appleDoublePrefix = Array("._".utf8)
		#expect(try storedNameBytes(in: folder).filter { !$0.starts(with: appleDoublePrefix) } == [Array(name.utf8)])

		// Both file systems take extended attributes on macOS; if this volume does not, there is nothing to compare.
		let probe = try writeFile(folder + "/probe.tmp")
		let supportsExtendedAttributes = (try? setExtendedAttribute("user.test", [1], atPath: probe)) != nil
		unlink(probe)
		if supportsExtendedAttributes {
			#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == Array(sampleQuarantine.utf8))
		} else {
			print("note: \(kind.rawValue) took no extended attribute here; the quarantine comparison was skipped")
		}
		if kind == .hfs {
			// exFAT has no permission bits to keep.
			#expect(try permissionBits(created.destinationPath) == 0o444)
		}

		// Never overwrite, here too.
		let second = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: ""))
		#expect(Exact(second.destinationName) == Exact("Report Final (v2) (1).txt"))
		#expect(second.hasNumberSuffix)
		#expect(try readFile(created.destinationPath) == "payload")
	}

	@Test("no room for the quarantine flag: the copy is refused and removed", arguments: TestVolumes.Kind.allCases)
	func quarantineCannotBeWritten(kind: TestVolumes.Kind) throws {
		let volumes = try #require(TestVolumes.shared)
		let folder = try volumes.makeFolder(on: kind)
		var information = statfs()
		try #require(statfs(folder, &information) == 0)
		let freeBytes = Int(information.f_bavail) * Int(information.f_bsize)
		try #require(freeBytes > 1024 * 1024)

		// The data fits and leaves about 300 kB. The 1 MB quarantine value, which both volumes take while they have
		// room, does not fit any more, so fsetxattr fails. (Sparse on APFS, so making the source costs nothing.)
		let sourcePath = folders.source + "/big-flag.command"
		let descriptor = open(sourcePath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
		try #require(descriptor >= 0)
		#expect(ftruncate(descriptor, off_t(freeBytes - 300 * 1024)) == 0)
		close(descriptor)
		try setExtendedAttribute(quarantineAttributeName, [UInt8](repeating: UInt8(ascii: "q"), count: 1024 * 1024), atPath: sourcePath)

		let message = failureMessage { try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: "")) }

		// A copy that lost the flag would slip past Gatekeeper: it must not be kept, and neither may a "._" file.
		#expect(message == Exact(Self.quarantineMessage))
		#expect(try storedNames(in: folder) == [], "no copy without its quarantine flag may be left on \(kind.rawValue)")

		// Without the flag the same data is copied: it was the flag that did not fit.
		#expect(removexattr(sourcePath, quarantineAttributeName, 0) == 0)
		let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: ""))
		#expect(try fileStatus(created.destinationPath).st_size == off_t(freeBytes - 300 * 1024))
		#expect(unlink(created.destinationPath) == 0)
	}

	@Test("a full volume: the Korean message, and no partial copy stays", arguments: TestVolumes.Kind.allCases)
	func fullVolume(kind: TestVolumes.Kind) throws {
		let volumes = try #require(TestVolumes.shared)
		let folder = try volumes.makeFolder(on: kind)
		// 8 MiB for a 4 MB volume. Sparse on APFS, so making it costs nothing; the copy writes every byte.
		let sourcePath = folders.source + "/too-big.bin"
		let descriptor = open(sourcePath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
		try #require(descriptor >= 0)
		#expect(ftruncate(descriptor, 8 * 1024 * 1024) == 0)
		close(descriptor)

		let message = failureMessage { try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folder, baseName: "")) }

		#expect(message == Exact("저장 공간이 부족합니다."))
		#expect(try storedNames(in: folder) == [], "the partial copy is removed")

		// The space is free again: a small copy works right after.
		let small = try folders.writeSource("small.txt", "payload")
		let created = try copyNormalizedFile(PlanInput(sourcePath: small, outputDirectory: folder, baseName: ""))
		#expect(try readFile(created.destinationPath) == "payload")
	}
}

// Three behaviors have their only test on the real volumes: the refused copy is removed through the NFC path that was
// written (on exFAT the name readdir reports does not unlink), a failed fcopyfile is reported, and the copy is
// identified after its data is written (an empty exFAT file changes its inode number). A run that skipped the suite
// would still pass, so where the volumes are expected the skip itself fails.
@Test("the real volumes are there where they are required (CI)")
func realVolumesAreThereWhereRequired() {
	guard TestVolumes.areRequired else {
		return
	}

	#expect(
		TestVolumes.shared != nil,
		"hdiutil could not create or attach the HFS+ and exFAT test images, and this run requires them (CI or HANGEUL_REQUIRE_VOLUMES=1 is set). HANGEUL_REQUIRE_VOLUMES=0 allows the skip."
	)
}
