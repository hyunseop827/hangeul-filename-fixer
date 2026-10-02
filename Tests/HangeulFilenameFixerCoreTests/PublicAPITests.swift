// The Core as the app sees it. This file imports the module without `@testable`, so it only compiles while everything
// the app needs is public.
import HangeulFilenameFixerCore
import Testing

@Suite("Public API")
struct PublicAPITests {
	// "한글.txt" as one syllable per character (NFC) and as conjoining jamo (NFD).
	static let composedName = "\u{D55C}\u{AE00}.txt"
	static let decomposedName = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}.txt"

	@Test("hasSameScalars is the comparison for \"is this the same spelling?\"; == is not")
	func exactSpellingComparison() {
		// src/App.tsx (v1.1.0) decided its "already fine" hint with `windowsCompatibleName === sourceName`. For a name whose
		// only problem is its normalization, the app's main case, Swift's `==` says "same" and the hint would appear.
		let parts = splitFileName(Self.decomposedName)
		let compatibleName = windowsSafeFileName(stem: parts.stem, extension: parts.extension)

		#expect(compatibleName == Self.decomposedName, "== cannot tell the two spellings apart")
		#expect(!hasSameScalars(compatibleName, Self.decomposedName))
		#expect(hasSameScalars(compatibleName, Self.composedName))

		#expect(hasSameScalars("", ""))
		#expect(hasSameScalars("report (1).txt", "report (1).txt"))
		#expect(!hasSameScalars("report.txt", "Report.txt"))
		#expect(!hasSameScalars("\u{E9}", "e\u{301}"))
		#expect(!hasSameScalars("a", "ab"))
	}

	@Test("the preview and the copy, through public names only")
	func previewAndCopy() throws {
		let folders = TestFolders()
		let sourcePath = try folders.writeSource(Self.decomposedName)

		let input = PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: "")
		let plan = try #require(makePlan(input))
		#expect(hasSameScalars(plan.sourceName, Self.decomposedName))
		#expect(hasSameScalars(plan.destinationName, Self.composedName))
		#expect(!isNFCName(plan.sourceName))
		#expect(plan.hasNumberSuffix == false)
		#expect(hasSameScalars(decomposedDisplayName(plan.sourceName), "ㅎㅏㄴㄱㅡㄹ.txt"))
		#expect(hasSameScalars(windowsSafeStem("CON"), "_CON"))

		let created: FileCopyPlan = try copyNormalizedFile(input)
		#expect(hasSameScalars(created.destinationPath, folders.output + "/" + Self.composedName))
		#expect(hasSameScalars(created.sourcePath, sourcePath))

		// The only error the copy throws, with the Korean text the app shows as it is.
		do {
			_ = try copyNormalizedFile(PlanInput(sourcePath: folders.source, outputDirectory: folders.output, baseName: ""))
			Issue.record("copying a folder must fail")
		} catch {
			let shown: UserFacingError = error
			#expect(hasSameScalars(shown.message, notRegularFileMessage))
		}
	}
}
