// Converts the file-type icons from SVG to vector PDF:
//   Resources/FileIcons/source/<name>.svg  →  Resources/FileIcons/<name>.pdf
//
//   swift scripts/make-file-icons.swift        (needs macOS 13 or later, where AppKit reads SVG files)
//
// Why PDF: the app runs on macOS 12, where NSImage cannot read SVG files. Every macOS reads PDF, and the drawing stays
// a vector image, so the icons are sharp at any size. Each page is as large as the SVG's own size (its viewBox).
//
// The PDFs are committed; scripts/build-app.sh copies them (not the SVG sources) into the bundle and fails when an SVG
// has no PDF. Run this again only when an SVG is changed or added, and look at the result: a new run rewrites every
// PDF (the creation date inside changes even when the drawing does not).
import AppKit

let icons = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
	.appendingPathComponent("Resources/FileIcons", isDirectory: true)
let sources = icons.appendingPathComponent("source", isDirectory: true)

func fail(_ message: String) -> Never {
	FileHandle.standardError.write(Data((message + "\n").utf8))
	exit(1)
}

let svgs = ((try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? [])
	.filter { $0.pathExtension == "svg" }
	.sorted { $0.lastPathComponent < $1.lastPathComponent }
if svgs.isEmpty { fail("\(sources.path) 에 SVG 파일이 없습니다.") }

for svg in svgs {
	guard let image = NSImage(contentsOf: svg), image.isValid, image.size.width > 0, image.size.height > 0 else {
		fail("\(svg.lastPathComponent) 을(를) 읽을 수 없습니다.")
	}
	let pdf = icons.appendingPathComponent(svg.deletingPathExtension().lastPathComponent + ".pdf")
	var box = CGRect(origin: .zero, size: image.size)
	guard let consumer = CGDataConsumer(url: pdf as CFURL),
	      let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
		fail("\(pdf.lastPathComponent) 을(를) 만들 수 없습니다.")
	}
	context.beginPDFPage(nil)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
	// Drawn into a PDF context the SVG's paths are recorded as paths, not as a bitmap.
	image.draw(in: box)
	NSGraphicsContext.restoreGraphicsState()
	context.endPDFPage()
	context.closePDF()
	print("\(svg.lastPathComponent) → \(pdf.lastPathComponent) (\(image.size.width) × \(image.size.height))")
}
