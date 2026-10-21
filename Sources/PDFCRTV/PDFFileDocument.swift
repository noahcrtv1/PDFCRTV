import PDFCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

final class PDFFileDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    @Published var pdf: PDFDocument
    /// Muda a cada edição; views que dependem do conteúdo das páginas observam isso.
    @Published var revision = 0

    init() {
        pdf = PDFDocument()
        PageOperations.insertBlank(pdf, at: 0)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let doc = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pdf = doc
    }

    func snapshot(contentType: UTType) throws -> Data {
        guard let data = pdf.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    // MARK: Edição com desfazer

    /// Mudança estrutural (páginas). Desfazer restaura o documento inteiro de antes.
    func performPageChange(_ name: String, undo: UndoManager?, _ change: (PDFDocument) throws -> Void) rethrows {
        let before = pdf.dataRepresentation()
        try change(pdf)
        revision += 1
        guard let before else { return }
        undo?.registerUndo(withTarget: self) { $0.restore(before, name: name, undo: undo) }
        undo?.setActionName(name)
    }

    private func restore(_ data: Data, name: String, undo: UndoManager?) {
        let current = pdf.dataRepresentation()
        if let doc = PDFDocument(data: data) { pdf = doc }
        revision += 1
        guard let current else { return }
        undo?.registerUndo(withTarget: self) { $0.restore(current, name: name, undo: undo) }
        undo?.setActionName(name)
    }

    func recordAdded(_ annotation: PDFAnnotation, on page: PDFPage, undo: UndoManager?) {
        revision += 1
        undo?.registerUndo(withTarget: self) { doc in
            page.removeAnnotation(annotation)
            doc.recordRemoved(annotation, from: page, undo: undo)
        }
        undo?.setActionName("Anotação")
    }

    func recordRemoved(_ annotation: PDFAnnotation, from page: PDFPage, undo: UndoManager?) {
        revision += 1
        undo?.registerUndo(withTarget: self) { doc in
            page.addAnnotation(annotation)
            doc.recordAdded(annotation, on: page, undo: undo)
        }
        undo?.setActionName("Remover anotação")
    }

    func recordTextChange(_ annotation: PDFAnnotation, from old: String?, undo: UndoManager?) {
        revision += 1
        let new = annotation.contents
        undo?.registerUndo(withTarget: self) { doc in
            annotation.contents = old
            doc.recordTextChange(annotation, from: new, undo: undo)
        }
        undo?.setActionName("Editar texto")
    }
}
