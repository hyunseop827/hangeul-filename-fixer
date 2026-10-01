// STUB — replaced by the Core/app implementation
import Foundation
import Testing
@testable import HangeulFilenameFixer

// The app's name is written precomposed (NFC) in the source. Compared by Unicode scalars: `String ==` treats NFC and
// NFD as equal, so it cannot tell.
@Test func appNameIsWrittenInNFC() {
	let title = StubApp.windowTitle
	#expect(Array(title.unicodeScalars) == Array(title.precomposedStringWithCanonicalMapping.unicodeScalars))
	#expect(title.unicodeScalars.count == 10)
}
