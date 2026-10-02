// Port of tests/naming.test.ts (the Electron app; the file is in the tag v1.1.0): one test per TypeScript test, same
// inputs and same expected names.
// The Korean literals in this file are NFC (see `literalsInTheTestSourcesAreNFC`), so no nfc() wrapper is needed.
import Testing
@testable import HangeulFilenameFixerCore

@Suite("naming.test.ts")
struct NamingTests {
	@Test("NFD names become NFC, including the extension")
	func nfdNamesBecomeNFC() {
		let name = windowsSafeFileName(stem: decomposed("홍길동_레포트_진짜최종"), extension: ".hwp")

		#expect(Exact(name) == Exact("홍길동_레포트_진짜최종.hwp"))
		#expect(isNFCName(name))
		#expect(Exact(windowsSafeFileName(stem: "자료", extension: decomposed(".한글"))) == Exact("자료.한글"))
	}

	@Test("forbidden and control characters become underscores, in the stem and the extension")
	func forbiddenCharactersBecomeUnderscores() {
		#expect(Exact(windowsSafeFileName(stem: "a<b>c:d\"e/f\\g|h?i*j", extension: ".txt")) == Exact("a_b_c_d_e_f_g_h_i_j.txt"))
		#expect(Exact(windowsSafeFileName(stem: "Q&A 2024", extension: ".1분기?")) == Exact("Q&A 2024.1분기_"))
		#expect(Exact(windowsSafeFileName(stem: "bell\u{07}", extension: ".TX\u{01}T")) == Exact("bell_.TX_T"))
	}

	@Test("trailing dots and spaces are removed from the stem and the whole name")
	func trailingDotsAndSpacesAreRemoved() {
		#expect(Exact(windowsSafeFileName(stem: "보고서. ", extension: ".hwp")) == Exact("보고서.hwp"))
		#expect(Exact(windowsSafeFileName(stem: "file", extension: ".")) == Exact("file"))
		#expect(Exact(windowsSafeFileName(stem: "a", extension: ".txt ")) == Exact("a.txt"))
		#expect(Exact(windowsSafeFileName(stem: "  앞뒤 공백  ", extension: ".pdf")) == Exact("앞뒤 공백.pdf"))
	}

	@Test("an empty stem falls back to 파일")
	func emptyStemFallsBack() {
		#expect(Exact(windowsSafeFileName(stem: "...", extension: ".txt")) == Exact("파일.txt"))
		#expect(Exact(windowsSafeFileName(stem: "   ", extension: "")) == Exact("파일"))
	}

	@Test("reserved Windows device names get a leading underscore")
	func reservedDeviceNamesGetAnUnderscore() {
		#expect(Exact(windowsSafeFileName(stem: "CON", extension: ".txt")) == Exact("_CON.txt"))
		#expect(Exact(windowsSafeFileName(stem: "nul ", extension: ".txt")) == Exact("_nul.txt"))
		#expect(Exact(windowsSafeFileName(stem: "con.tar", extension: ".gz")) == Exact("_con.tar.gz"))
		#expect(Exact(windowsSafeFileName(stem: "nul .tar", extension: ".gz")) == Exact("_nul .tar.gz"))
		#expect(Exact(windowsSafeFileName(stem: "COM¹", extension: ".txt")) == Exact("_COM¹.txt"))
		#expect(Exact(windowsSafeFileName(stem: "LPT9", extension: "")) == Exact("_LPT9"))
		#expect(Exact(windowsSafeFileName(stem: "CONSOLE", extension: ".txt")) == Exact("CONSOLE.txt"))
		#expect(Exact(windowsSafeFileName(stem: "COM10", extension: ".txt")) == Exact("COM10.txt"))
	}

	@Test("splitFileName splits at the last dot and keeps dotfiles whole")
	func splitFileNameSplitsAtTheLastDot() {
		expectSplit("a.tar.gz", stem: "a.tar", extension: ".gz")
		expectSplit(".bashrc", stem: ".bashrc", extension: "")
		expectSplit("README", stem: "README", extension: "")
		expectSplit("file.", stem: "file", extension: ".")
	}

	@Test("decomposedDisplayName shows each conjoining jamo as a separate letter")
	func decomposedDisplayNameShowsEachJamo() {
		#expect(
			Exact(decomposedDisplayName(decomposed("홍길동_레포트_진짜최종_찐최종.hwp")))
				== Exact("ㅎㅗㅇㄱㅣㄹㄷㅗㅇ_ㄹㅔㅍㅗㅌㅡ_ㅈㅣㄴㅉㅏㅊㅚㅈㅗㅇ_ㅉㅣㄴㅊㅚㅈㅗㅇ.hwp")
		)
		#expect(Exact(decomposedDisplayName("이미 NFC.pdf")) == Exact("이미 NFC.pdf"))
	}

	@Test("decomposedDisplayName covers every modern Hangul syllable")
	func decomposedDisplayNameCoversEverySyllable() {
		var leftovers: [String] = []
		var count = 0

		for value in UInt32(0xAC00)...0xD7A3 {
			guard let syllable = Unicode.Scalar(value) else {
				continue
			}

			count += 1
			let shown = decomposedDisplayName(decomposed(String(syllable)))
			if containsConjoiningJamo(shown) {
				leftovers.append("U+\(String(value, radix: 16)) left a conjoining jamo")
			}
		}

		#expect(count == 11172)
		#expect(leftovers.isEmpty, "\(leftovers.prefix(5))")
	}

	@Test("every conjoining jamo is shown as the compatibility letter naming.ts lists for it")
	func decomposedDisplayNameTables() {
		func scalars(_ range: ClosedRange<UInt32>) -> String {
			String(String.UnicodeScalarView(range.compactMap(Unicode.Scalar.init)))
		}

		// The three tables of electron/naming.ts (v1.1.0), in code point order.
		#expect(Exact(decomposedDisplayName(scalars(0x1100...0x1112))) == Exact("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"))
		#expect(Exact(decomposedDisplayName(scalars(0x1161...0x1175))) == Exact("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"))
		#expect(Exact(decomposedDisplayName(scalars(0x11A8...0x11C2))) == Exact("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"))
		// The compatibility letters by code point, in case an editor ever changes the literals above.
		#expect(decomposedDisplayName("\u{11B0}\u{11B1}").unicodeScalars.map(\.value) == [0x313A, 0x313B])

		// Just outside each range (old jamo, the fillers): shown as they are.
		let neighbors = "\u{10FF}\u{1113}\u{115F}\u{1160}\u{1176}\u{11A7}\u{11C3}"
		#expect(Exact(decomposedDisplayName(neighbors)) == Exact(neighbors))
	}

	@Test("all 28 reserved device names get the underscore, and their neighbors do not")
	func everyReservedDeviceName() {
		var names = ["CON", "PRN", "AUX", "NUL"]
		for suffix in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "\u{B9}", "\u{B2}", "\u{B3}"] {
			names += ["COM" + suffix, "LPT" + suffix]
		}
		#expect(names.count == 28)

		for name in names {
			#expect(Exact(windowsSafeStem(name)) == Exact("_" + name))
			#expect(Exact(windowsSafeStem(name.lowercased())) == Exact("_" + name.lowercased()))
			#expect(Exact(windowsSafeFileName(stem: name + ".backup", extension: ".txt")) == Exact("_" + name + ".backup.txt"))
		}
		for name in ["COM0", "LPT0", "COM", "LPT", "COM10", "LPT10", "CONIN$", "CONOUT$", "COM\u{2074}", "NULL", "AUX1", "PRN1"] {
			#expect(Exact(windowsSafeStem(name)) == Exact(name))
		}
	}

	private func expectSplit(_ fileName: String, stem: String, extension fileExtension: String, sourceLocation: SourceLocation = #_sourceLocation) {
		let parts = splitFileName(fileName)
		#expect(Exact(parts.stem) == Exact(stem), sourceLocation: sourceLocation)
		#expect(Exact(parts.extension) == Exact(fileExtension), sourceLocation: sourceLocation)
	}
}
