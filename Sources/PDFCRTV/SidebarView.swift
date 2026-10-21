import PDFCore
import PDFKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var document: PDFFileDocument
    @Bindable var model: ViewerModel
    let actions: PageActions

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mostrar", selection: $model.sidebarMode) {
                ForEach(SidebarMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            switch model.sidebarMode {
            case .pages: pages
            case .outline: outline
            case .annotations: annotations
            }
        }
    }

    // MARK: Páginas

    private var pages: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selectedPages) {
                ForEach(0..<document.pdf.pageCount, id: \.self) { index in
                    if let page = document.pdf.page(at: index) {
                        PageThumbnail(page: page, number: index + 1, isCurrent: index == model.currentPageIndex, revision: document.revision)
                            .tag(index)
                            .id(index)
                    }
                }
                .onMove { actions.move($0, to: $1) }
            }
            .contextMenu(forSelectionType: Int.self) { items in
                let pages = IndexSet(items)
                if !items.isEmpty {
                    Button("Girar à esquerda", systemImage: "rotate.left") { actions.rotate(pages, -90) }
                    Button("Girar à direita", systemImage: "rotate.right") { actions.rotate(pages, 90) }
                    Divider()
                    Button("Inserir página em branco depois", systemImage: "doc.badge.plus") { actions.insertBlank(pages.last! + 1) }
                    Button("Inserir PDF depois…", systemImage: "doc.on.doc") { actions.insertFile(pages.last! + 1) }
                    Button("Extrair para novo PDF…", systemImage: "square.and.arrow.up.on.square") { actions.extract(pages) }
                    Divider()
                    Button(items.count == 1 ? "Excluir página" : "Excluir \(items.count) páginas", systemImage: "trash", role: .destructive) {
                        actions.delete(pages)
                    }
                }
            } primaryAction: { items in
                if let first = items.min() { model.go(toPage: first) }
            }
            .onChange(of: model.selectedPages) { _, selection in
                if selection.count == 1, let index = selection.first { model.go(toPage: index) }
            }
            .onChange(of: model.currentPageIndex) { _, index in
                withAnimation { proxy.scrollTo(index) }
            }
            .onDeleteCommand { actions.delete(IndexSet(model.selectedPages)) }
        }
    }

    // MARK: Sumário

    private var outline: some View {
        let items = OutlineItem.children(of: document.pdf.outlineRoot, in: document.pdf)
        return Group {
            if items.isEmpty {
                ContentUnavailableView("Sem sumário", systemImage: "list.bullet.indent", description: Text("Este PDF não tem marcadores."))
            } else {
                List(items, children: \.children) { item in
                    Button { model.go(toPage: item.page) } label: {
                        HStack {
                            Text(item.label).lineLimit(2)
                            Spacer()
                            Text("\(item.page + 1)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Anotações

    private var annotations: some View {
        let items = AnnotationItem.all(in: document.pdf)
        _ = document.revision
        return Group {
            if items.isEmpty {
                ContentUnavailableView("Sem anotações", systemImage: "highlighter", description: Text("Destaques, notas e desenhos aparecem aqui."))
            } else {
                List(items) { item in
                    Button { model.go(toPage: item.pageIndex) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Color(nsColor: item.annotation.color)).frame(width: 10, height: 10).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.callout.weight(.medium))
                                if let text = item.detail { Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                Text("Página \(item.pageIndex + 1)").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remover", systemImage: "trash", role: .destructive) {
                            item.page.removeAnnotation(item.annotation)
                            actions.document.recordRemoved(item.annotation, from: item.page, undo: actions.undo)
                        }
                    }
                }
            }
        }
    }
}

struct PageThumbnail: View {
    let page: PDFPage
    let number: Int
    let isCurrent: Bool
    let revision: Int
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary).aspectRatio(0.71, contentMode: .fit)
                }
            }
            .background(.white)
            .clipShape(.rect(cornerRadius: 4))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
                    .padding(-3)
            }
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(isCurrent ? .primary : .secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .task(id: "\(revision)-\(page.rotation)") {
            image = page.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
        }
    }
}

struct OutlineItem: Identifiable {
    let id = UUID()
    let label: String
    let page: Int
    let children: [OutlineItem]?

    static func children(of node: PDFOutline?, in doc: PDFDocument) -> [OutlineItem] {
        guard let node else { return [] }
        return (0..<node.numberOfChildren).compactMap { i in
            guard let child = node.child(at: i) else { return nil }
            let page = child.destination?.page.map { doc.index(for: $0) } ?? 0
            let kids = children(of: child, in: doc)
            return OutlineItem(label: child.label ?? "Sem título", page: page, children: kids.isEmpty ? nil : kids)
        }
    }
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    let annotation: PDFAnnotation
    let page: PDFPage
    let pageIndex: Int

    private static let titles: [String: String] = [
        PDFAnnotationSubtype.highlight.rawValue: "Destaque",
        PDFAnnotationSubtype.underline.rawValue: "Sublinhado",
        PDFAnnotationSubtype.strikeOut.rawValue: "Riscado",
        PDFAnnotationSubtype.text.rawValue: "Nota",
        PDFAnnotationSubtype.freeText.rawValue: "Texto",
        PDFAnnotationSubtype.ink.rawValue: "Desenho",
        PDFAnnotationSubtype.square.rawValue: "Retângulo",
        PDFAnnotationSubtype.circle.rawValue: "Círculo",
        PDFAnnotationSubtype.stamp.rawValue: "Assinatura/carimbo",
    ]

    var title: String { Self.titles[annotation.type ?? ""] ?? (annotation.type ?? "Anotação") }

    var detail: String? {
        if let text = annotation.contents, !text.isEmpty { return text }
        let markup = [PDFAnnotationSubtype.highlight, .underline, .strikeOut].map(\.rawValue)
        guard markup.contains(annotation.type ?? "") else { return nil }
        return page.selection(for: annotation.bounds)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func all(in doc: PDFDocument) -> [AnnotationItem] {
        (0..<doc.pageCount).flatMap { index -> [AnnotationItem] in
            guard let page = doc.page(at: index) else { return [] }
            return page.annotations
                .filter { titles[$0.type ?? ""] != nil }
                .map { AnnotationItem(annotation: $0, page: page, pageIndex: index) }
        }
    }
}
