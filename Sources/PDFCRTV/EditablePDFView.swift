import AppKit
import PDFCore
import PDFKit
import SwiftUI

/// PDFView com as ferramentas de anotação. Não guarda estado de app: lê tudo pelos closures.
final class EditablePDFView: PDFView {
    var tool: () -> Tool = { .select }
    var color: () -> NSColor = { .systemYellow }
    var lineWidth: () -> CGFloat = { 3 }
    var signature: () -> NSImage? = { nil }
    var onAdd: (PDFAnnotation, PDFPage) -> Void = { _, _ in }
    var onRemove: (PDFAnnotation, PDFPage) -> Void = { _, _ in }
    var onTextChange: (PDFAnnotation, String?) -> Void = { _, _ in }
    var onNeedSignature: () -> Void = {}

    private var dragPage: PDFPage?
    private var dragStart: CGPoint = .zero
    private var inkPoints: [CGPoint] = []
    private var live: PDFAnnotation?

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: true) else { return super.mouseDown(with: event) }
        let p = convert(point, to: page)

        if event.clickCount == 2, let existing = page.annotation(at: p), editableText(existing) {
            editText(of: existing)
            return
        }

        switch tool() {
        case .select, .highlight, .underline, .strike:
            super.mouseDown(with: event)
        case .note:
            guard let text = TextPrompt.ask("Nova nota", initial: "") else { return }
            let note = PDFAnnotation(bounds: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20), forType: .text, withProperties: nil)
            note.contents = text
            note.color = color()
            add(note, to: page)
        case .text:
            guard let text = TextPrompt.ask("Texto na página", initial: ""), !text.isEmpty else { return }
            let box = PDFAnnotation(bounds: textBounds(text, at: p), forType: .freeText, withProperties: nil)
            box.contents = text
            box.font = .systemFont(ofSize: 14)
            box.fontColor = color()
            box.color = .clear
            box.border = border(0)
            add(box, to: page)
        case .signature:
            guard let image = signature() else { return onNeedSignature() }
            let width: CGFloat = 180
            let height = width * image.size.height / max(image.size.width, 1)
            add(ImageStampAnnotation(image: image, bounds: CGRect(x: p.x - width / 2, y: p.y - height / 2, width: width, height: height)), to: page)
        case .draw:
            dragPage = page
            inkPoints = [p]
            updateInk()
        case .rectangle:
            dragPage = page
            dragStart = p
            let rect = PDFAnnotation(bounds: CGRect(origin: p, size: .zero), forType: .square, withProperties: nil)
            rect.color = color()
            rect.border = border(lineWidth())
            page.addAnnotation(rect)
            live = rect
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let page = dragPage else { return super.mouseDragged(with: event) }
        let p = convert(convert(event.locationInWindow, from: nil), to: page)
        switch tool() {
        case .draw:
            inkPoints.append(p)
            updateInk()
        case .rectangle:
            live?.bounds = CGRect(x: min(dragStart.x, p.x), y: min(dragStart.y, p.y),
                                  width: abs(p.x - dragStart.x), height: abs(p.y - dragStart.y))
            annotationsChanged(on: page)
        default:
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let page = dragPage {
            if let annotation = live {
                page.removeAnnotation(annotation)
                if annotation.bounds.width > 3 || annotation.bounds.height > 3 { add(annotation, to: page) }
            }
            dragPage = nil
            live = nil
            inkPoints = []
            return
        }
        super.mouseUp(with: event)
        let tool = tool()
        guard tool.isMarkup, let selection = currentSelection else { return }
        let type: PDFAnnotationSubtype = switch tool {
        case .underline: .underline
        case .strike: .strikeOut
        default: .highlight
        }
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let markup = PDFAnnotation(bounds: line.bounds(for: page), forType: type, withProperties: nil)
                markup.color = tool == .highlight ? color().withAlphaComponent(0.45) : color()
                add(markup, to: page)
            }
        }
        clearSelection()
    }

    /// Recria o traço a cada movimento, com o bounds justo ao desenho.
    private func updateInk() {
        guard let page = dragPage, let first = inkPoints.first else { return }
        if let live { page.removeAnnotation(live) }
        let width = lineWidth()
        let xs = inkPoints.map(\.x), ys = inkPoints.map(\.y)
        let bounds = CGRect(x: xs.min()! - width, y: ys.min()! - width,
                            width: xs.max()! - xs.min()! + width * 2, height: ys.max()! - ys.min()! + width * 2)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: first.x - bounds.minX, y: first.y - bounds.minY))
        for p in inkPoints.dropFirst() { path.line(to: CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY)) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let ink = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        ink.color = color()
        ink.border = border(width)
        ink.add(path)
        page.addAnnotation(ink)
        live = ink
    }

    // MARK: Menu de contexto

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: false),
              let annotation = page.annotation(at: convert(point, to: page)),
              annotation.type != PDFAnnotationSubtype.link.rawValue,
              annotation.type != PDFAnnotationSubtype.widget.rawValue else { return menu }

        menu.insertItem(.separator(), at: 0)
        if editableText(annotation) {
            menu.insertItem(ClosureMenuItem("Editar texto…") { [weak self] in self?.editText(of: annotation) }, at: 0)
        }
        menu.insertItem(ClosureMenuItem("Remover anotação") { [weak self] in
            page.removeAnnotation(annotation)
            self?.onRemove(annotation, page)
        }, at: 0)
        return menu
    }

    // MARK: Ajudantes

    private func add(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        onAdd(annotation, page)
    }

    private func editableText(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == PDFAnnotationSubtype.freeText.rawValue || annotation.type == PDFAnnotationSubtype.text.rawValue
    }

    private func editText(of annotation: PDFAnnotation) {
        let old = annotation.contents
        guard let text = TextPrompt.ask("Editar texto", initial: old ?? ""), text != old else { return }
        annotation.contents = text
        if annotation.type == PDFAnnotationSubtype.freeText.rawValue {
            annotation.bounds = textBounds(text, at: CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY))
        }
        if let page = annotation.page { annotationsChanged(on: page) }
        onTextChange(annotation, old)
    }

    /// Caixa que cabe o texto, com o canto superior esquerdo em `topLeft`.
    private func textBounds(_ text: String, at topLeft: CGPoint) -> CGRect {
        let size = (text as NSString).boundingRect(with: CGSize(width: 320, height: 2000), options: [.usesLineFragmentOrigin],
                                                   attributes: [.font: NSFont.systemFont(ofSize: 14)]).size
        let w = ceil(size.width) + 12, h = ceil(size.height) + 8
        return CGRect(x: topLeft.x, y: topLeft.y - h, width: w, height: h)
    }

    private func border(_ width: CGFloat) -> PDFBorder {
        let b = PDFBorder()
        b.lineWidth = width
        return b
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

enum TextPrompt {
    @MainActor static func ask(_ title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 72))
        field.stringValue = initial
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

// MARK: Ponte com SwiftUI

struct PDFKitView: NSViewRepresentable {
    @ObservedObject var document: PDFFileDocument
    let model: ViewerModel
    let undoManager: UndoManager?

    func makeNSView(context: Context) -> EditablePDFView {
        let view = EditablePDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .underPageBackgroundColor
        view.document = document.pdf
        model.pdfView = view

        let center = NotificationCenter.default
        context.coordinator.observers = [
            center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { _ in
                if let page = view.currentPage, let index = view.document?.index(for: page) { model.currentPageIndex = index }
            },
            center.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { _ in
                model.scale = view.scaleFactor
            },
        ]
        return view
    }

    func updateNSView(_ view: EditablePDFView, context: Context) {
        if view.document !== document.pdf {
            let index = model.currentPageIndex
            view.document = document.pdf
            if let page = document.pdf.page(at: min(index, document.pdf.pageCount - 1)) { view.go(to: page) }
        }
        if context.coordinator.revision != document.revision {
            context.coordinator.revision = document.revision
            for page in view.visiblePages { view.annotationsChanged(on: page) }
        }
        let doc = document, undo = undoManager
        view.tool = { model.tool }
        view.color = { model.nsColor }
        view.lineWidth = { model.lineWidth }
        view.signature = { model.signature }
        view.onAdd = { doc.recordAdded($0, on: $1, undo: undo) }
        view.onRemove = { doc.recordRemoved($0, from: $1, undo: undo) }
        view.onTextChange = { doc.recordTextChange($0, from: $1, undo: undo) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var revision = -1
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
