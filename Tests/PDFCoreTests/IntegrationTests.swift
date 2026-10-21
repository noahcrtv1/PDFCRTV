import AppKit
import PDFKit
import XCTest
@testable import PDFCore

final class IntegrationTests: XCTestCase {
    func testVisionProducesSearchableCopy() async throws {
        guard ProcessInfo.processInfo.environment["PDFCRTV_INTEGRATION_TESTS"] == "1" else { throw XCTSkip("Requer o serviço Vision do macOS fora do isolamento.") }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 350, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1600, height: 350).fill()
        ("Culto domingo 19 horas" as NSString).draw(at: NSPoint(x: 80, y: 140), withAttributes: [.font: NSFont.systemFont(ofSize: 105), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: CGSize(width: 1600, height: 350)); image.addRepresentation(rep)
        let doc = try DocumentCreator.image(image, settings: PageSettings())
        XCTAssertTrue((doc.string ?? "").isEmpty)
        let result = try await SearchablePDF.create(from: XCTUnwrap(doc.dataRepresentation()))
        let reopened = try XCTUnwrap(PDFDocument(data: result.data))
        XCTAssertEqual(result.recognizedPages, 1)
        XCTAssertEqual(reopened.findString("domingo", withOptions: [.caseInsensitive]).count, 1)
        XCTAssertEqual(reopened.pageCount, 1)
        let again = try await SearchablePDF.create(from: result.data)
        XCTAssertEqual(again.recognizedPages, 0)
        XCTAssertEqual(again.existingTextPages, 1)
        let twice = try XCTUnwrap(PDFDocument(data: again.data))
        XCTAssertEqual(twice.findString("domingo", withOptions: [.caseInsensitive]).count, 1)
    }

    func testOfficeConversionWithConfiguredExecutable() async throws {
        guard let path = ProcessInfo.processInfo.environment["PDFCRTV_TEST_OFFICE"] else { throw XCTSkip("Requer um conversor LibreOffice informado explicitamente.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("teste com espaços.docx")
        let text = NSAttributedString(string: "Relatório CRTV — reunião de domingo", attributes: [.font: NSFont.systemFont(ofSize: 18)])
        let docx = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try docx.write(to: source)
        let pdf = try await OfficeConverter.convert(source, executable: URL(fileURLWithPath: path))
        let doc = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(doc.pageCount, 1)
        XCTAssertTrue(doc.string?.contains("domingo") == true)
    }

    func testSpaceCopiesFilesAndRejectsEscapingPaths() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = base.appendingPathComponent("Reunião")
        var space = try LocalSpaceFiles.create(at: folder, name: "Reunião")
        let file = base.appendingPathComponent("Notas.txt")
        try "Decisões".write(to: file, atomically: true, encoding: .utf8)
        space.items.append(try LocalSpaceFiles.importFile(file, into: folder))
        space.notes = "Próxima reunião"
        try LocalSpaceFiles.save(space, in: folder)
        try FileManager.default.removeItem(at: file)
        let reopened = try LocalSpaceFiles.read(from: folder)
        XCTAssertEqual(reopened.notes, "Próxima reunião")
        XCTAssertEqual(try String(contentsOf: LocalSpaceFiles.destination(for: reopened.items[0], in: folder), encoding: .utf8), "Decisões")
        let invalid = LocalSpace.Item(id: UUID(), title: "Escape", file: "Arquivos/../../fora", link: nil)
        XCTAssertThrowsError(try LocalSpaceFiles.destination(for: invalid, in: folder))
        XCTAssertThrowsError(try LocalSpaceFiles.webLink(URL(string: "file:///etc/passwd")!))
    }
}
