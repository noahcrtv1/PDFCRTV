import AppKit
import Observation
import PDFKit
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case select, highlight, underline, strike, text, note, draw, rectangle, signature
    var id: Self { self }

    var title: String {
        switch self {
        case .select: "Selecionar"
        case .highlight: "Destacar"
        case .underline: "Sublinhar"
        case .strike: "Riscar"
        case .text: "Texto"
        case .note: "Nota"
        case .draw: "Desenhar"
        case .rectangle: "Retângulo"
        case .signature: "Assinar"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strike: "strikethrough"
        case .text: "character.textbox"
        case .note: "note.text"
        case .draw: "scribble"
        case .rectangle: "rectangle"
        case .signature: "signature"
        }
    }

    /// Ferramentas que agem sobre texto selecionado.
    var isMarkup: Bool { [.highlight, .underline, .strike].contains(self) }
}

enum SidebarMode: String, CaseIterable, Identifiable {
    case pages = "Páginas", outline = "Sumário", annotations = "Anotações"
    var id: Self { self }
}

@Observable
final class ViewerModel {
    @ObservationIgnored weak var pdfView: EditablePDFView?

    var tool: Tool = .select
    var color: Color = .yellow
    var lineWidth: CGFloat = 3
    var sidebarMode: SidebarMode = .pages
    var currentPageIndex = 0
    var scale: CGFloat = 1
    var selectedPages: Set<Int> = []
    var signature: NSImage?

    var searchText = ""
    var searchResults: [PDFSelection] = []
    var searchIndex = 0

    var nsColor: NSColor { NSColor(color) }

    func go(toPage index: Int) {
        guard let view = pdfView, let page = view.document?.page(at: index) else { return }
        view.go(to: page)
    }

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func zoomToFit() { pdfView?.autoScales = true }

    func search() {
        guard let view = pdfView, let doc = view.document else { return }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        searchResults = query.isEmpty ? [] : doc.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        for result in searchResults { result.color = .systemYellow.withAlphaComponent(0.5) }
        view.highlightedSelections = searchResults.isEmpty ? nil : searchResults
        searchIndex = -1
        searchNext()
    }

    func searchNext() {
        guard !searchResults.isEmpty, let view = pdfView else { return }
        searchIndex = (searchIndex + 1) % searchResults.count
        let hit = searchResults[searchIndex]
        view.setCurrentSelection(hit, animate: true)
        view.go(to: hit)
    }

    func clearSearch() {
        searchResults = []
        pdfView?.highlightedSelections = nil
    }
}
