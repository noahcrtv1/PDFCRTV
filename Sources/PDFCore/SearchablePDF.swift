import AppKit
import CoreText
import PDFKit
import Vision

public struct RecognizedLine {
    public let text: String
    /// Coordenadas normalizadas da imagem, com origem embaixo à esquerda (Vision).
    public let bounds: CGRect
    public init(text: String, bounds: CGRect) { self.text = text; self.bounds = bounds }
}

public struct SearchablePDFResult: Sendable {
    public let data: Data
    public let recognizedPages: Int
    public let existingTextPages: Int
}

public enum SearchablePDF {
    /// Trabalha numa cópia privada e conserva as anotações das páginas reconhecidas.
    public static func create(from data: Data, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> SearchablePDFResult {
        let worker = Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(data: data), !doc.isLocked else { throw CreationError.conversion("Desbloqueie o PDF antes de reconhecer o texto.") }
            var recognized = 0, existing = 0
            for index in 0..<doc.pageCount {
                try Task.checkCancellation()
                progress(index, doc.pageCount)
                guard let page = doc.page(at: index) else { continue }
                if !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing += 1; continue
                }
                let image = Exporter.render(page, scale: 3)
                guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CreationError.conversion("Não foi possível ler a página \(index + 1).") }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["pt-BR", "en-US", "es-ES"]
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: cg).perform([request])
                let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                    guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
                    return RecognizedLine(text: candidate.string, bounds: observation.boundingBox)
                }
                if !lines.isEmpty {
                    let replacement = try pageWithText(lines, original: page)
                    doc.removePage(at: index)
                    doc.insert(replacement, at: index)
                    remapDestinations(in: doc, from: page, to: replacement)
                    recognized += 1
                }
            }
            try Task.checkCancellation()
            guard recognized + existing > 0 else { throw CreationError.noRecognizedText }
            guard let result = doc.dataRepresentation(),
                  let reopened = PDFDocument(data: result), reopened.pageCount == doc.pageCount,
                  !(reopened.string ?? "").isEmpty else { throw CreationError.conversion("O texto foi reconhecido, mas não foi possível gravá-lo no PDF.") }
            progress(doc.pageCount, doc.pageCount)
            return SearchablePDFResult(data: result, recognizedPages: recognized, existingTextPages: existing)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    public static func pageWithText(_ lines: [RecognizedLine], original page: PDFPage) throws -> PDFPage {
        guard let ref = page.pageRef else { throw CreationError.conversion("Página sem conteúdo legível.") }
        var box = page.bounds(for: .mediaBox)
        let displaySize = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let transform = ref.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: displaySize), rotate: 0, preserveAspectRatio: true).inverted()
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CreationError.invalidPage }
        context.beginPDFPage(nil)
        context.drawPDFPage(ref)
        context.saveGState()
        context.concatenate(transform)
        for item in lines {
            let rect = CGRect(x: item.bounds.minX * displaySize.width, y: item.bounds.minY * displaySize.height,
                              width: item.bounds.width * displaySize.width, height: item.bounds.height * displaySize.height)
            let text = NSAttributedString(string: item.text, attributes: [.font: NSFont.systemFont(ofSize: 12), NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])
            let line = CTLineCreateWithAttributedString(text)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            guard width > 0, ascent + descent > 0 else { continue }
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / width, y: rect.height / (ascent + descent))
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 0, y: descent)
            context.setTextDrawingMode(.invisible)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        context.restoreGState()
        context.endPDFPage(); context.closePDF()
        guard let newPage = PDFDocument(data: data as Data)?.page(at: 0) else { throw CreationError.invalidPage }
        for displayBox in [PDFDisplayBox.mediaBox, .cropBox, .bleedBox, .trimBox, .artBox] {
            newPage.setBounds(page.bounds(for: displayBox), for: displayBox)
        }
        newPage.rotation = page.rotation
        for annotation in page.annotations {
            if let copy = annotation.copy() as? PDFAnnotation { newPage.addAnnotation(copy) }
        }
        return newPage
    }

    private static func remapDestinations(in doc: PDFDocument, from old: PDFPage, to new: PDFPage) {
        func mapped(_ destination: PDFDestination?) -> PDFDestination? {
            guard let destination, destination.page === old else { return destination }
            let copy = PDFDestination(page: new, at: destination.point); copy.zoom = destination.zoom
            return copy
        }
        func walk(_ outline: PDFOutline) {
            if let destination = outline.destination { outline.destination = mapped(destination) }
            for i in 0..<outline.numberOfChildren { if let child = outline.child(at: i) { walk(child) } }
        }
        if let root = doc.outlineRoot { walk(root) }
        for i in 0..<doc.pageCount {
            for annotation in doc.page(at: i)?.annotations ?? [] {
                if let destination = annotation.destination { annotation.destination = mapped(destination) }
                if let action = annotation.action as? PDFActionGoTo, let destination = mapped(action.destination) { action.destination = destination }
            }
        }
    }
}
