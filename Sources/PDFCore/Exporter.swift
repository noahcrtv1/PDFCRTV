import AppKit
import PDFKit

public enum Exporter {
    /// Salva uma cópia com imagens recomprimidas em JPEG e reduzidas para tela.
    public static func writeCompressed(_ doc: PDFDocument, to url: URL) throws {
        let options: [PDFDocumentWriteOption: Any] = [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true,
        ]
        guard doc.write(to: url, withOptions: options) else { throw PDFCoreError.writeFailed(url) }
    }

    /// Salva uma cópia que exige senha para abrir. `ownerPassword` vazio usa a mesma senha.
    public static func writeEncrypted(_ doc: PDFDocument, to url: URL, password: String, ownerPassword: String = "") throws {
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: ownerPassword.isEmpty ? password : ownerPassword,
        ]
        guard doc.write(to: url, withOptions: options) else { throw PDFCoreError.writeFailed(url) }
    }

    public static func write(_ doc: PDFDocument, to url: URL) throws {
        guard doc.write(to: url) else { throw PDFCoreError.writeFailed(url) }
    }

    public static func writeText(_ doc: PDFDocument, to url: URL) throws {
        try (doc.string ?? "").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Uma imagem PNG por página em `folder`. Devolve os arquivos criados.
    @discardableResult
    public static func writePNGs(_ doc: PDFDocument, pages indexes: IndexSet? = nil, to folder: URL, baseName: String, scale: CGFloat = 2) throws -> [URL] {
        var written: [URL] = []
        for i in indexes ?? IndexSet(0..<doc.pageCount) {
            guard let page = doc.page(at: i), let data = pngData(page, scale: scale) else { continue }
            let url = folder.appendingPathComponent(String(format: "%@-%03d.png", baseName, i + 1))
            try data.write(to: url)
            written.append(url)
        }
        return written
    }

    public static func render(_ page: PDFPage, scale: CGFloat) -> NSImage {
        let size = page.bounds(for: .mediaBox).size
        let rotated = page.rotation % 180 == 0 ? size : CGSize(width: size.height, height: size.width)
        return page.thumbnail(of: CGSize(width: rotated.width * scale, height: rotated.height * scale), for: .mediaBox)
    }

    public static func pngData(_ page: PDFPage, scale: CGFloat) -> Data? {
        pngData(render(page, scale: scale))
    }

    public static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
