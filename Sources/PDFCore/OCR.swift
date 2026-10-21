import AppKit
import PDFKit
import Vision

/// Reconhecimento de texto local (Vision), sem internet.
public enum OCR {
    public static func recognize(_ page: PDFPage) async throws -> String {
        let image = Exporter.render(page, scale: 3)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US", "es-ES"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cg).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func recognize(_ doc: PDFDocument, pages indexes: IndexSet) async throws -> String {
        var parts: [String] = []
        for i in indexes {
            guard let page = doc.page(at: i) else { continue }
            let text = try await recognize(page)
            parts.append("— Página \(i + 1) —\n\(text)")
        }
        return parts.joined(separator: "\n\n")
    }
}
