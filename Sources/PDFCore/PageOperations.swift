import Foundation
import PDFKit

public enum PDFCoreError: LocalizedError {
    case unreadable(URL)
    case locked(URL)
    case cannotRemoveAllPages
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Não foi possível ler \(url.lastPathComponent)."
        case .locked(let url): "\(url.lastPathComponent) está protegido por senha. Abra e desbloqueie antes."
        case .cannotRemoveAllPages: "O documento precisa ficar com pelo menos uma página."
        case .writeFailed(let url): "Não foi possível salvar \(url.lastPathComponent)."
        }
    }
}

/// Operações de página. Todas alteram o documento no lugar.
public enum PageOperations {
    public static func rotate(_ doc: PDFDocument, pages indexes: IndexSet, by degrees: Int) {
        for i in indexes {
            guard let page = doc.page(at: i) else { continue }
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        }
    }

    public static func delete(_ doc: PDFDocument, pages indexes: IndexSet) throws {
        let valid = indexes.filter { $0 < doc.pageCount }
        guard valid.count < doc.pageCount else { throw PDFCoreError.cannotRemoveAllPages }
        for i in valid.sorted(by: >) { doc.removePage(at: i) }
    }

    /// Mesma semântica de `Array.move(fromOffsets:toOffset:)`.
    public static func move(_ doc: PDFDocument, from source: IndexSet, to destination: Int) {
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0) }
        let moving = source.filter { $0 < pages.count }.map { pages[$0] }
        guard !moving.isEmpty else { return }
        var rest = pages.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = min(destination - source.filter { $0 < destination }.count, rest.count)
        rest.insert(contentsOf: moving, at: max(insertAt, 0))
        for i in stride(from: doc.pageCount - 1, through: 0, by: -1) { doc.removePage(at: i) }
        for (i, page) in rest.enumerated() { doc.insert(page, at: i) }
    }

    public static func insertBlank(_ doc: PDFDocument, at index: Int, size: CGSize? = nil) {
        let reference = doc.page(at: max(min(index, doc.pageCount) - 1, 0))?.bounds(for: .mediaBox).size
        guard let page = blankPage(size: size ?? reference ?? CGSize(width: 595, height: 842)) else { return }
        doc.insert(page, at: min(index, doc.pageCount))
    }

    public static func insertPages(from url: URL, into doc: PDFDocument, at index: Int) throws {
        let source = try open(url)
        var at = min(index, doc.pageCount)
        for i in 0..<source.pageCount {
            guard let page = source.page(at: i)?.copy() as? PDFPage else { continue }
            doc.insert(page, at: at)
            at += 1
        }
    }

    /// Novo documento só com as páginas pedidas (cópias).
    public static func extract(_ doc: PDFDocument, pages indexes: IndexSet) -> PDFDocument {
        let out = PDFDocument()
        for i in indexes where i < doc.pageCount {
            if let page = doc.page(at: i)?.copy() as? PDFPage { out.insert(page, at: out.pageCount) }
        }
        return out
    }

    /// Divide em partes de `pagesPerPart` páginas.
    public static func split(_ doc: PDFDocument, pagesPerPart: Int) -> [PDFDocument] {
        let size = max(pagesPerPart, 1)
        return stride(from: 0, to: doc.pageCount, by: size).map { start in
            extract(doc, pages: IndexSet(start..<min(start + size, doc.pageCount)))
        }
    }

    public static func merge(_ urls: [URL]) throws -> PDFDocument {
        let out = PDFDocument()
        for url in urls { try insertPages(from: url, into: out, at: out.pageCount) }
        return out
    }

    public static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw PDFCoreError.unreadable(url) }
        guard !doc.isLocked else { throw PDFCoreError.locked(url) }
        return doc
    }

    public static func blankPage(size: CGSize) -> PDFPage? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }
}
