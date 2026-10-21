import AppKit
import CoreText
import ImageIO
import PDFKit

public enum CreationError: LocalizedError {
    case invalidPage, emptyContent, unsupported(String), conversion(String), noRecognizedText
    public var errorDescription: String? {
        switch self {
        case .invalidPage: "Escolha um tamanho de página e margens válidos."
        case .emptyContent: "Adicione pelo menos um arquivo ou conteúdo para criar o PDF."
        case .unsupported(let name): "O formato de \(name) não é compatível com esta conversão."
        case .conversion(let message): message
        case .noRecognizedText: "Nenhum texto foi reconhecido. Tente uma digitalização mais nítida."
        }
    }
}

public struct PageSettings: Equatable, Sendable {
    public enum Paper: String, CaseIterable, Sendable {
        case a4 = "A4", letter = "Carta", a5 = "A5"
        public var size: CGSize {
            switch self {
            case .a4: CGSize(width: 595.28, height: 841.89)
            case .letter: CGSize(width: 612, height: 792)
            case .a5: CGSize(width: 419.53, height: 595.28)
            }
        }
    }
    public var paper: Paper = .a4
    public var landscape = false
    public var margin: CGFloat = 36
    public init() {}
    public var size: CGSize { landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size }
    public var contentRect: CGRect { CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin) }
    public func validate() throws {
        guard margin.isFinite, margin >= 0, contentRect.width >= 36, contentRect.height >= 36 else { throw CreationError.invalidPage }
    }
}

public enum DocumentTemplate: String, CaseIterable, Sendable {
    case meeting = "Pauta de reunião", report = "Relatório", notes = "Folha de anotações", letterhead = "Papel timbrado"
    public var symbol: String {
        switch self {
        case .meeting: "person.3"
        case .report: "chart.bar.doc.horizontal"
        case .notes: "note.text"
        case .letterhead: "doc.richtext"
        }
    }
}

public enum DocumentCreator {
    public static func blank(pages: Int, settings: PageSettings) throws -> PDFDocument {
        try settings.validate()
        guard (1...500).contains(pages) else { throw CreationError.invalidPage }
        let doc = PDFDocument()
        for _ in 0..<pages {
            guard let page = PageOperations.blankPage(size: settings.size) else { throw CreationError.conversion("Não foi possível criar a página.") }
            doc.insert(page, at: doc.pageCount)
        }
        return doc
    }

    /// Core Text mantém o texto selecionável e pagina sem cortar parágrafos longos.
    public static func text(_ text: NSAttributedString, settings: PageSettings) throws -> PDFDocument {
        try settings.validate()
        guard text.length > 0 else { throw CreationError.emptyContent }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: settings.size)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CreationError.conversion("Não foi possível preparar o documento.") }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var offset = 0
        while offset < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: settings.contentRect, transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw CreationError.invalidPage }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            offset += visible.length
        }
        context.closePDF()
        guard let result = PDFDocument(data: data as Data) else { throw CreationError.conversion("Não foi possível ler o PDF criado.") }
        return result
    }

    public static func plainText(_ text: String, settings: PageSettings) throws -> PDFDocument {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return try self.text(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black, .paragraphStyle: paragraph]), settings: settings)
    }

    public static func image(_ image: NSImage, settings: PageSettings) throws -> PDFDocument {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CreationError.conversion("Não foi possível ler a imagem.") }
        return try imagePages(count: 1, settings: settings) { _ in cg }
    }

    /// ImageIO aplica a orientação EXIF e preserva todas as páginas de um TIFF.
    public static func imageFile(_ url: URL, settings: PageSettings) throws -> PDFDocument {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw CreationError.unsupported(url.lastPathComponent) }
        let count = ["tif", "tiff"].contains(url.pathExtension.lowercased()) ? CGImageSourceGetCount(source) : min(CGImageSourceGetCount(source), 1)
        guard count <= 500 else { throw CreationError.conversion("A imagem contém mais de 500 páginas. Divida o arquivo antes de importar.") }
        return try imagePages(count: count, settings: settings) { index in
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 6000]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { throw CreationError.conversion("Não foi possível ler a imagem \(index + 1).") }
            return image
        }
    }

    private static func imagePages(count: Int, settings: PageSettings, load: (Int) throws -> CGImage) throws -> PDFDocument {
        try settings.validate()
        guard count > 0 else { throw CreationError.emptyContent }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: settings.size)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CreationError.invalidPage }
        for index in 0..<count {
            let image = try load(index)
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            let available = settings.contentRect
            let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
            let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
            context.draw(image, in: CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height))
            context.endPDFPage()
        }
        context.closePDF()
        guard let doc = PDFDocument(data: data as Data) else { throw CreationError.invalidPage }
        return doc
    }

    public static func combine(_ documents: [(String, PDFDocument)]) throws -> PDFDocument {
        guard !documents.isEmpty else { throw CreationError.emptyContent }
        let result = PDFDocument(), outline = PDFOutline()
        for (name, doc) in documents {
            guard !doc.isLocked else { throw CreationError.conversion("Desbloqueie \(name) antes de combinar.") }
            let first = result.pageCount
            for index in 0..<doc.pageCount {
                guard let copy = doc.page(at: index)?.copy() as? PDFPage else { throw CreationError.conversion("Não foi possível copiar uma página de \(name).") }
                result.insert(copy, at: result.pageCount)
            }
            if let page = result.page(at: first) {
                let entry = PDFOutline(); entry.label = name
                entry.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).maxY))
                outline.insertChild(entry, at: outline.numberOfChildren)
            }
        }
        guard result.pageCount > 0 else { throw CreationError.emptyContent }
        result.outlineRoot = outline
        return result
    }

    public static func template(_ template: DocumentTemplate, title: String, settings: PageSettings) throws -> PDFDocument {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.rawValue : title
        let body: String
        switch template {
        case .meeting: body = "Data: ____________________     Horário: __________\n\nParticipantes\n\n________________________________________________\n\nPauta\n\n1. ______________________________________________\n\n2. ______________________________________________\n\n3. ______________________________________________\n\nDecisões e responsáveis\n\n________________________________________________\n\n________________________________________________\n\nPróximos passos\n\n________________________________________________"
        case .report: body = "Data: ____________________     Responsável: ____________________\n\nObjetivo\n\n________________________________________________\n\nAtividades realizadas\n\n________________________________________________\n\n________________________________________________\n\nResultados\n\n________________________________________________\n\nPendências e próximos passos\n\n________________________________________________"
        case .notes: body = "Data: ____________________\n\n" + Array(repeating: "________________________________________________", count: 14).joined(separator: "\n\n")
        case .letterhead: body = "________________________________________________________________\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nContato: _______________________________________________________"
        }
        let text = NSMutableAttributedString(string: heading + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.black])
        text.append(NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black]))
        return try self.text(text, settings: settings)
    }
}
