import AppKit
import PDFKit

/// Assinaturas salvas como PNG em ~/Library/Application Support/PDFCRTV/Assinaturas.
public enum SignatureStore {
    public static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PDFCRTV/Assinaturas", isDirectory: true)
    }

    public static func all() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult
    public static func save(_ image: NSImage) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = Exporter.pngData(image) else { throw CocoaError(.fileWriteUnknown) }
        let url = folder.appendingPathComponent("assinatura-\(Int(Date().timeIntervalSince1970)).png")
        try data.write(to: url)
        return url
    }

    public static func delete(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// Carimbo que desenha uma imagem (assinatura, rubrica). O PDFKit grava a aparência ao salvar.
public final class ImageStampAnnotation: PDFAnnotation {
    public let image: NSImage

    public init(image: NSImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { nil }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}
