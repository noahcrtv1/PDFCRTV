import AppKit
import PDFCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum ActiveSheet: Identifiable {
    case signature, password, split, ocr(String)
    var id: String {
        switch self {
        case .signature: "signature"
        case .password: "password"
        case .split: "split"
        case .ocr: "ocr"
        }
    }
}

struct ContentView: View {
    @ObservedObject var document: PDFFileDocument
    @State private var model = ViewerModel()
    @State private var sheet: ActiveSheet?
    @State private var error: String?
    @State private var working: String?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if document.pdf.isLocked {
                UnlockView(document: document)
            } else {
                editor
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .signature:
                SignatureSheet { image in
                    model.signature = image
                    model.tool = .signature
                }
            case .password:
                PasswordSheet { password in export(name: "protegido", type: .pdf) { try Exporter.writeEncrypted(document.pdf, to: $0, password: password) } }
            case .split:
                SplitSheet(pageCount: document.pdf.pageCount) { split(every: $0) }
            case .ocr(let text):
                OCRSheet(text: text)
            }
        }
        .alert("Não deu certo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    private var editor: some View {
        NavigationSplitView {
            SidebarView(document: document, model: model, actions: pageActions)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 320)
        } detail: {
            PDFKitView(document: document, model: model, undoManager: undoManager)
                .overlay(alignment: .bottom) { statusPill }
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        AnnotationBar(model: model)
                        if let working {
                            Label(working, systemImage: "hourglass")
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .glassEffect()
                        }
                    }
                    .padding(.top, 12)
                }
        }
        .toolbar { toolbar }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Buscar no PDF")
        .onSubmit(of: .search) {
            if model.searchResults.isEmpty { model.search() } else { model.searchNext() }
        }
        .onChange(of: model.searchText) { _, text in
            if text.isEmpty { model.clearSearch() } else { model.searchResults = [] }
        }
        .onChange(of: model.tool) { _, tool in
            if tool == .signature, model.signature == nil { sheet = .signature }
        }
    }

    // MARK: Barra de ferramentas

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Diminuir", systemImage: "minus.magnifyingglass") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Ajustar", systemImage: "arrow.up.left.and.arrow.down.right") { model.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Aumentar", systemImage: "plus.magnifyingglass") { model.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
        }

        ToolbarItem {
            Menu("Ferramentas", systemImage: "square.grid.2x2") {
                Section("Páginas") {
                    Button("Girar à esquerda", systemImage: "rotate.left") { pageActions.rotate(targetPages, -90) }
                        .keyboardShortcut("l", modifiers: .command)
                    Button("Girar à direita", systemImage: "rotate.right") { pageActions.rotate(targetPages, 90) }
                        .keyboardShortcut("r", modifiers: .command)
                    Button("Inserir página em branco", systemImage: "doc.badge.plus") { pageActions.insertBlank(model.currentPageIndex + 1) }
                    Button("Inserir PDF…", systemImage: "doc.on.doc") { pageActions.insertFile(model.currentPageIndex + 1) }
                    Button("Extrair páginas…", systemImage: "square.and.arrow.up.on.square") { pageActions.extract(targetPages) }
                    Button("Dividir PDF…", systemImage: "scissors") { sheet = .split }
                    Button("Excluir página", systemImage: "trash", role: .destructive) { pageActions.delete(targetPages) }
                }
                Section("Documento") {
                    Button("Criar PDF…", systemImage: "doc.badge.plus") { CreationWindowController.shared.show() }
                    Button("Salvar cópia pesquisável (OCR)…", systemImage: "doc.text.magnifyingglass") { exportSearchable() }
                    Button("Reconhecer texto (OCR)", systemImage: "text.viewfinder") { runOCR(all: false) }
                    Button("OCR do documento inteiro", systemImage: "doc.text.viewfinder") { runOCR(all: true) }
                    Button("Gerenciar assinaturas…", systemImage: "signature") { sheet = .signature }
                    Button("Imprimir…", systemImage: "printer") { model.pdfView?.print(with: .shared, autoRotate: true) }
                        .keyboardShortcut("p", modifiers: .command)
                }
                Section("Exportar") {
                    Button("Cópia comprimida…", systemImage: "arrow.down.right.and.arrow.up.left") {
                        export(name: "comprimido", type: .pdf) { try Exporter.writeCompressed(document.pdf, to: $0) }
                    }
                    Button("Cópia com senha…", systemImage: "lock") { sheet = .password }
                    Button("Páginas como imagens…", systemImage: "photo.on.rectangle") { exportImages() }
                    Button("Texto (.txt)…", systemImage: "doc.plaintext") {
                        export(name: "texto", type: .plainText) { try Exporter.writeText(document.pdf, to: $0) }
                    }
                }
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 12) {
            Text("Página \(model.currentPageIndex + 1) de \(document.pdf.pageCount)")
            Divider().frame(height: 14)
            Text("\(Int((model.scale * 100).rounded()))%")
            if !model.searchResults.isEmpty {
                Divider().frame(height: 14)
                Text("\(model.searchIndex + 1)/\(model.searchResults.count) resultados")
            }
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14).padding(.vertical, 7)
        .glassEffect()
        .padding(.bottom, 14)
    }

    // MARK: Ações

    /// Páginas selecionadas na barra lateral, ou a página atual.
    private var targetPages: IndexSet {
        model.selectedPages.isEmpty ? [model.currentPageIndex] : IndexSet(model.selectedPages)
    }

    private var pageActions: PageActions {
        PageActions(document: document, model: model, undo: undoManager, fail: { error = $0.localizedDescription })
    }

    private var baseName: String {
        (document.pdf.documentURL?.deletingPathExtension().lastPathComponent).map { $0 } ?? "Documento"
    }

    private func export(name: String, type: UTType, write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "\(baseName) (\(name)).\(type.preferredFilenameExtension ?? "pdf")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try write(url) } catch { self.error = error.localizedDescription }
    }

    private func exportImages() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Exportar aqui"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let files = try Exporter.writePNGs(document.pdf, pages: model.selectedPages.isEmpty ? nil : IndexSet(model.selectedPages),
                                               to: folder, baseName: baseName)
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func split(every count: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Salvar partes aqui"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            var files: [URL] = []
            for (i, part) in PageOperations.split(document.pdf, pagesPerPart: count).enumerated() {
                let url = folder.appendingPathComponent("\(baseName) parte \(i + 1).pdf")
                try Exporter.write(part, to: url)
                files.append(url)
            }
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runOCR(all: Bool) {
        let pages = all ? IndexSet(0..<document.pdf.pageCount) : targetPages
        working = "Reconhecendo texto…"
        Task {
            defer { working = nil }
            do {
                sheet = .ocr(try await OCR.recognize(document.pdf, pages: pages))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func exportSearchable() {
        guard working == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(baseName) (pesquisável).pdf"
        panel.message = "Cria uma cópia com texto selecionável nas páginas digitalizadas."
        guard panel.runModal() == .OK, let destination = panel.url, let data = document.pdf.dataRepresentation() else { return }
        working = "Preparando OCR…"
        Task {
            defer { working = nil }
            do {
                let result = try await SearchablePDF.create(from: data) { page, count in
                    Task { @MainActor in working = "Reconhecendo página \(min(page + 1, count)) de \(count)…" }
                }
                try result.data.write(to: destination, options: .atomic)
                NSDocumentController.shared.openDocument(withContentsOf: destination, display: true) { _, _, failure in
                    if let failure { Task { @MainActor in error = failure.localizedDescription } }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Operações de página com desfazer, usadas pelo menu e pela barra lateral.
struct PageActions {
    let document: PDFFileDocument
    let model: ViewerModel
    let undo: UndoManager?
    let fail: (Error) -> Void

    func rotate(_ pages: IndexSet, _ degrees: Int) {
        document.performPageChange("Girar", undo: undo) { PageOperations.rotate($0, pages: pages, by: degrees) }
    }

    func delete(_ pages: IndexSet) {
        do {
            try document.performPageChange("Excluir páginas", undo: undo) { try PageOperations.delete($0, pages: pages) }
            model.selectedPages = []
        } catch { fail(error) }
    }

    func move(_ source: IndexSet, to destination: Int) {
        document.performPageChange("Mover páginas", undo: undo) { PageOperations.move($0, from: source, to: destination) }
        model.selectedPages = []
    }

    func insertBlank(_ index: Int) {
        document.performPageChange("Inserir página", undo: undo) { PageOperations.insertBlank($0, at: index) }
    }

    func insertFile(_ index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.performPageChange("Inserir PDF", undo: undo) { try PageOperations.insertPages(from: url, into: $0, at: index) }
        } catch { fail(error) }
    }

    func extract(_ pages: IndexSet) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Páginas extraídas.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.write(PageOperations.extract(document.pdf, pages: pages), to: url)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } catch { fail(error) }
    }
}

struct UnlockView: View {
    @ObservedObject var document: PDFFileDocument
    @State private var password = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
            Text("Este PDF é protegido por senha").font(.title2.weight(.semibold))
            SecureField("Senha", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(unlock)
            if wrong { Text("Senha incorreta.").foregroundStyle(.red) }
            Button("Desbloquear", action: unlock)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() {
        wrong = !document.pdf.unlock(withPassword: password)
        if !wrong { document.revision += 1 }
    }
}
