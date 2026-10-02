// The copy's permission bits and quarantine flag do not depend on the umask of the process.
//
// The umask belongs to the whole process: while this test has it at 0777, a file any other test creates would have no
// permission bits at all. So the test is switched off in an ordinary run, and scripts/test.sh gives it a run of its
// own after the others:
//   HANGEUL_TEST_UMASK=1 swift test --filter UmaskTests
// (and checks, by the line printed at the end, that it really ran).
import Darwin
import Testing
@testable import HangeulFilenameFixerCore

@Suite(
	"The umask of the process",
	.serialized,
	.enabled(
		if: getenv("HANGEUL_TEST_UMASK").map { String(cString: $0) } == "1",
		"it changes the umask of the whole test process; scripts/test.sh runs it alone (HANGEUL_TEST_UMASK=1)"
	)
)
struct UmaskTests {
	let folders = TestFolders()

	@Test("the copy gets the source's mode and its quarantine flag, whatever the umask")
	func umaskDoesNotMatter() throws {
		// (umask, the source's mode). 0777 takes every bit away from a file that is created with a mode, and without
		// the owner's write bit the quarantine flag cannot be written; 0 takes nothing away.
		let cases: [(mask: mode_t, sourceMode: mode_t)] = [(0o777, 0o644), (0o277, 0o600), (0o022, 0o444), (0o777, 0o755), (0, 0o600)]
		for (mask, sourceMode) in cases {
			let name = "umask-\(String(mask, radix: 8))-\(String(sourceMode, radix: 8)).command"
			let sourcePath = try folders.writeSource(name, "payload")
			try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
			#expect(chmod(sourcePath, sourceMode) == 0)

			let before = umask(mask)
			let message = failureMessage {
				try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: ""))
			}
			umask(before)

			let label = "umask \(String(mask, radix: 8)), source mode \(String(sourceMode, radix: 8))"
			let copyPath = folders.output + "/" + name
			#expect(message == nil, "\(label)")
			#expect(try permissionBits(copyPath) == sourceMode, "\(label)")
			#expect(extendedAttribute(quarantineAttributeName, atPath: copyPath) == Array(sampleQuarantine.utf8), "\(label)")
			#expect(try readFile(copyPath) == "payload", "\(label)")
			#expect(try permissionBits(sourcePath) == sourceMode, "the original's mode is not touched")
		}

		// scripts/test.sh looks for this line: a filter that matched nothing would pass without it.
		print("umask test: \(cases.count) cases checked")
	}
}
