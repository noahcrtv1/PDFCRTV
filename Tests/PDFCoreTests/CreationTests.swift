import AppKit
import PDFKit
import XCTest
@testable import PDFCore

final class CreationTests: XCTestCase {
    func testBlankLandscapeAndMargins() throws {
        var settings = PageSettings(); settings.landscape = true
        let doc = try DocumentCreator.blank(pages: 3, settings: settings)
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertGreaterThan(doc.page(at: 0)!.bounds(for: .mediaBox).width, doc.page(at: 0)!.bounds(for: .mediaBox).height)
        settings.margin = 1000
        XCTAssertThrowsError(try DocumentCreator.blank(pages: 1, settings: settings))
    }

    func testLongTextPaginatesAndKeepsLastParagraph() throws {
        let content = Array(repeating: "Reunião e decisões — Português com acentuação.\n", count: 200).joined() + "ÚLTIMA LINHA"
        let doc = try DocumentCreator.plainText(content, settings: PageSettings())
        let reopened = try XCTUnwrap(PDFDocument(data: XCTUnwrap(doc.dataRepresentation())))
        XCTAssertGreaterThan(reopened.pageCount, 1)
        XCTAssertTrue(reopened.string?.contains("ÚLTIMA LINHA") == true)
        XCTAssertTrue(reopened.string?.contains("Reunião") == true)
    }

    func testCombinePreservesRequestedOrderAndAddsBookmarks() throws {
        let a = try DocumentCreator.plainText("PRIMEIRO", settings: PageSettings())
        let b = try DocumentCreator.plainText("SEGUNDO", settings: PageSettings())
        let result = try DocumentCreator.combine([("B", b), ("A", a)])
        XCTAssertTrue(result.page(at: 0)?.string?.contains("SEGUNDO") == true)
        XCTAssertEqual(result.outlineRoot?.numberOfChildren, 2)
        XCTAssertEqual(result.outlineRoot?.child(at: 0)?.label, "B")
    }

    func testAllTemplatesProduceSelectableText() throws {
        for template in DocumentTemplate.allCases {
            let doc = try DocumentCreator.template(template, title: "Equipe CRTV", settings: PageSettings())
            XCTAssertTrue(doc.string?.contains("Equipe CRTV") == true)
        }
    }

    func testOCRLayerSurvivesSaveAndIsInvisible() throws {
        for rotation in [0, 90, 180, 270] {
            let doc = try DocumentCreator.blank(pages: 1, settings: PageSettings())
            let page = try XCTUnwrap(doc.page(at: 0)); page.rotation = rotation
            let reference = try XCTUnwrap(Exporter.pngData(page, scale: 1))
            let replacement = try SearchablePDF.pageWithText([RecognizedLine(text: "Olá domingo", bounds: CGRect(x: 0.15, y: 0.6, width: 0.5, height: 0.06))], original: page)
            doc.removePage(at: 0); doc.insert(replacement, at: 0)
            let data = try XCTUnwrap(doc.dataRepresentation())
            let reopened = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertEqual(reopened.findString("domingo", withOptions: []).count, 1, "rotation=\(rotation)")
            let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
            let selection = try XCTUnwrap(reopened.findString("Olá domingo", withOptions: []).first)
            let bounds = reopenedPage.bounds(for: .mediaBox)
            let display = rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
            let transform = reopenedPage.pageRef!.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: display), rotate: 0, preserveAspectRatio: true)
            let location = selection.bounds(for: reopenedPage).applying(transform)
            XCTAssertEqual(location.minX, display.width * 0.15, accuracy: 3, "Alinhamento OCR, rotação \(rotation)")
            XCTAssertEqual(location.minY, display.height * 0.6, accuracy: 5, "Alinhamento OCR, rotação \(rotation)")
            let actual = try XCTUnwrap(Exporter.pngData(reopened.page(at: 0)!, scale: 1))
            XCTAssertEqual(actual, reference, "A camada OCR deve ser invisível, rotation=\(rotation)")
        }
    }

    func testOCRKeepsAnnotationAndNonzeroPageOrigin() throws {
        let page = try XCTUnwrap(PageOperations.blankPage(size: CGSize(width: 400, height: 600)))
        page.setBounds(CGRect(x: 20, y: 30, width: 400, height: 600), for: .mediaBox)
        let annotation = PDFAnnotation(bounds: CGRect(x: 60, y: 80, width: 100, height: 30), forType: .freeText, withProperties: nil)
        annotation.contents = "Nota importante"; annotation.font = .systemFont(ofSize: 12)
        page.addAnnotation(annotation)
        let result = try SearchablePDF.pageWithText([RecognizedLine(text: "Texto reconhecido", bounds: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.05))], original: page)
        XCTAssertEqual(result.bounds(for: .mediaBox), page.bounds(for: .mediaBox))
        XCTAssertEqual(result.annotations.count, 1)
        XCTAssertEqual(result.annotations.first?.contents, "Nota importante")
    }
}
