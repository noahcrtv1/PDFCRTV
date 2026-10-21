import AppKit
import PDFKit
import XCTest
@testable import PDFCore

final class PageOperationsTests: XCTestCase {
    /// Páginas com larguras 100, 200, 300… para identificar a ordem.
    private func makeDoc(_ count: Int) -> PDFDocument {
        let doc = PDFDocument()
        for i in 0..<count {
            doc.insert(PageOperations.blankPage(size: CGSize(width: 100 * (i + 1), height: 500))!, at: i)
        }
        return doc
    }

    private func widths(_ doc: PDFDocument) -> [Int] {
        (0..<doc.pageCount).map { Int(doc.page(at: $0)!.bounds(for: .mediaBox).width) }
    }

    func testMoveMatchesArraySemantics() {
        let doc = makeDoc(4)
        PageOperations.move(doc, from: [0], to: 3)
        XCTAssertEqual(widths(doc), [200, 300, 100, 400])
        PageOperations.move(doc, from: [3], to: 0)
        XCTAssertEqual(widths(doc), [400, 200, 300, 100])
    }

    func testDeleteKeepsAtLeastOnePage() throws {
        let doc = makeDoc(3)
        try PageOperations.delete(doc, pages: [0, 2])
        XCTAssertEqual(widths(doc), [200])
        XCTAssertThrowsError(try PageOperations.delete(doc, pages: [0]))
    }

    func testRotateWraps() {
        let doc = makeDoc(1)
        PageOperations.rotate(doc, pages: [0], by: -90)
        XCTAssertEqual(doc.page(at: 0)!.rotation, 270)
        PageOperations.rotate(doc, pages: [0], by: 90)
        XCTAssertEqual(doc.page(at: 0)!.rotation, 0)
    }

    func testSplitAndMergeRoundTrip() throws {
        let doc = makeDoc(5)
        let parts = PageOperations.split(doc, pagesPerPart: 2)
        XCTAssertEqual(parts.map(\.pageCount), [2, 2, 1])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = try parts.enumerated().map { i, part in
            let url = dir.appendingPathComponent("\(i).pdf")
            try Exporter.write(part, to: url)
            return url
        }
        XCTAssertEqual(widths(try PageOperations.merge(urls)), [100, 200, 300, 400, 500])
    }

    func testEncryptedCopyNeedsPassword() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try Exporter.writeEncrypted(makeDoc(1), to: url, password: "1234")
        let reopened = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(reopened.isLocked)
        XCTAssertTrue(reopened.unlock(withPassword: "1234"))
    }

    /// A assinatura precisa continuar visível depois de salvar e reabrir.
    func testSignatureSurvivesSave() throws {
        let doc = makeDoc(1)
        let image = NSImage(size: CGSize(width: 50, height: 50), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        doc.page(at: 0)!.addAnnotation(ImageStampAnnotation(image: image, bounds: CGRect(x: 0, y: 0, width: 50, height: 50)))
        let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(doc.dataRepresentation())))
        let png = try XCTUnwrap(Exporter.pngData(reopened.page(at: 0)!, scale: 1))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        let pixel = try XCTUnwrap(rep.colorAt(x: 10, y: rep.pixelsHigh - 10))
        XCTAssertLessThan(pixel.usingColorSpace(.deviceRGB)!.brightnessComponent, 0.2)
    }
}
