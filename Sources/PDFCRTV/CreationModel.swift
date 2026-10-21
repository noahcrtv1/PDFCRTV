import AppKit
import PDFCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum CreationMode: String, CaseIterable, Identifiable {
    case file = "Arquivo único", multiple = "Vários arquivos", spaces = "Espaços locais", capture = "Captura de tela"
    case scanner = "Scanner", web = "Página da Web", clipboard = "Área de transferência", blank = "Página em branco", templates = "Modelos"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .file: "doc.badge.plus"
        case .multiple: "square.stack.3d.up"
        case .spaces: "folder.badge.plus"
        case .capture: "viewfinder"
        case .scanner: "scanner"
        case .web: "globe"
        case .clipboard: "doc.on.clipboard"
        case .blank: "doc"
        case .templates: "rectangle.grid.2x2"
        }
    }
    var subtitle: String {
        switch self {
        case .file: "Transforme uma imagem ou documento em PDF."
        case .multiple: "Escolha a ordem dos arquivos e reúna tudo em um PDF."
        case .spaces: "Reúna documentos, links e notas em uma pasta no seu Mac."
        case .capture: "Capture uma área ou janela e transforme em documento."
        case .scanner: "Digitalize com um scanner conectado ao Mac."
        case .web: "Salve uma página da internet em um PDF paginado."
        case .clipboard: "Crie um PDF com a imagem ou o texto que você copiou."
        case .blank: "Escolha o papel e comece um documento do zero."
        case .templates: "Comece com um modelo próprio do PDFCRTV."
        }
    }
}

struct CreationInput: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class CreationModel: ObservableObject {
    @Published var mode: CreationMode = .file
    @Published var inputs: [CreationInput] = []
    @Published var settings = PageSettings()
    @Published var numberOfPages = 1
    @Published var template: DocumentTemplate = .meeting
    @Published var title = ""
    @Published var webAddress = ""
    @Published var preview: PDFDocument?
    @Published var busy: String?
    @Published var error: String?
    @Published var resultNote: String?
    @Published var searchable = false
    @Published var isReady = false
    @Published var officePath = UserDefaults.standard.string(forKey: "OfficeConverterPath") ?? ""
    private var operation: Task<Void, Never>?
    private var scratchURLs: [URL] = []
    private enum CopiedContent {
        case image(NSImage), text(NSAttributedString), pdf(Data)
        func document(settings: PageSettings) throws -> PDFDocument {
            switch self {
            case .image(let image): return try DocumentCreator.image(image, settings: settings)
            case .text(let text): return try DocumentCreator.text(text, settings: settings)
            case .pdf(let data):
                guard let doc = PDFDocument(data: data) else { throw CreationError.emptyContent }
                return doc
            }
        }
    }
    private var copiedContent: CopiedContent?

    var officeURL: URL? { OfficeConverter.discover(customPath: officePath) }
    var needsOffice: Bool { inputs.contains { OfficeConverter.extensions.contains($0.url.pathExtension.lowercased()) } }
    var canCreate: Bool {
        guard busy == nil else { return false }
        switch mode {
        case .file, .multiple, .scanner: return !inputs.isEmpty && (!needsOffice || officeURL != nil)
        case .web: return !webAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .blank, .templates: return true
        case .clipboard, .capture: return copiedContent != nil
        case .spaces: return false
        }
    }

    func changeMode() {
        guard busy == nil else { return }
        preview = nil; resultNote = nil; error = nil; inputs = []; copiedContent = nil; isReady = false
        for url in scratchURLs { try? FileManager.default.removeItem(at: url) }
        scratchURLs = []
    }

    func invalidatePreview() { preview = nil; isReady = false; resultNote = nil }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = mode == .multiple
        panel.allowedContentTypes = [.pdf, .image, .plainText, .rtf, .html] + ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Adicionar"
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func addFiles(_ urls: [URL]) {
        guard busy == nil else { return }
        if mode == .file { inputs = urls.prefix(1).map { CreationInput(url: $0) } }
        else { inputs.append(contentsOf: urls.map { CreationInput(url: $0) }) }
        invalidatePreview()
    }

    func chooseOffice() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.message = "Selecione o LibreOffice.app instalado no seu Mac."
        if panel.runModal() == .OK, let app = panel.url {
            if let executable = OfficeConverter.executable(in: app) {
                officePath = executable.path
                UserDefaults.standard.set(officePath, forKey: "OfficeConverterPath")
            } else { error = "Escolha o aplicativo LibreOffice para converter documentos do Office." }
        }
    }

    func run(_ name: String, finalized: Bool = false, action: @escaping @MainActor () async throws -> PDFDocument) {
        guard busy == nil else { return }
        busy = name; error = nil; resultNote = nil; isReady = false
        operation = Task {
            defer { busy = nil; operation = nil }
            do {
                await Task.yield()
                let result = try await action()
                try Task.checkCancellation()
                preview = result
                isReady = finalized
            } catch is CancellationError { resultNote = "Operação cancelada." }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel() }

    func create() {
        run("Preparando PDF…", finalized: true) { [self] in
            let result: PDFDocument
            switch mode {
            case .blank: result = try DocumentCreator.blank(pages: numberOfPages, settings: settings)
            case .templates: result = try DocumentCreator.template(template, title: title, settings: settings)
            case .file, .multiple, .scanner:
                var documents: [(String, PDFDocument)] = []
                for (index, input) in inputs.enumerated() {
                    try Task.checkCancellation()
                    busy = "Convertendo \(index + 1) de \(inputs.count)…"
                    documents.append((input.url.deletingPathExtension().lastPathComponent, try await convert(input.url)))
                }
                result = mode == .file && documents.count == 1 ? documents[0].1 : try DocumentCreator.combine(documents)
            case .web:
                let raw = webAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: raw.contains("://") ? raw : "https://" + raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw CreationError.conversion("Digite um endereço de site válido.") }
                result = try await WebPDFRenderer().render(url: url, settings: settings)
            case .clipboard, .capture:
                guard let source = copiedContent else { throw CreationError.emptyContent }
                result = try source.document(settings: settings)
            case .spaces: throw CreationError.emptyContent
            }
            if searchable {
                busy = "Reconhecendo texto…"
                let converted = try await SearchablePDF.create(from: try data(of: result)) { [weak self] page, count in
                    Task { @MainActor in self?.busy = "Reconhecendo página \(min(page + 1, count)) de \(count)…" }
                }
                resultNote = "\(converted.recognizedPages) página(s) reconhecida(s); \(converted.existingTextPages) já tinham texto."
                guard let pdf = PDFDocument(data: converted.data) else { throw CreationError.emptyContent }
                return pdf
            }
            return result
        }
    }

    private func convert(_ url: URL) async throws -> PDFDocument {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return try PageOperations.open(url) }
        if OfficeConverter.extensions.contains(ext) {
            guard let executable = officeURL else { throw CreationError.conversion("Selecione o LibreOffice para converter arquivos do Office.") }
            let bytes = try await OfficeConverter.convert(url, executable: executable)
            guard let doc = PDFDocument(data: bytes) else { throw CreationError.unsupported(url.lastPathComponent) }
            return doc
        }
        if ["html", "htm"].contains(ext) { return try await WebPDFRenderer().render(url: url, settings: settings) }
        if ext == "rtf" {
            let rich = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return try DocumentCreator.text(rich, settings: settings)
        }
        if ["txt", "md", "csv"].contains(ext) {
            var encoding = String.Encoding.utf8
            return try DocumentCreator.plainText(String(contentsOf: url, usedEncoding: &encoding), settings: settings)
        }
        return try DocumentCreator.imageFile(url, settings: settings)
    }

    func readClipboard() {
        run("Lendo área de transferência…") { [self] in
            let board = NSPasteboard.general
            if let bytes = board.data(forType: .pdf), PDFDocument(data: bytes) != nil { copiedContent = .pdf(bytes) }
            else if let image = NSImage(pasteboard: board) { copiedContent = .image(image) }
            else if let rich = board.data(forType: .rtf), let text = NSAttributedString(rtf: rich, documentAttributes: nil) { copiedContent = .text(text) }
            else if let text = board.string(forType: .string), !text.isEmpty { copiedContent = .text(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])) }
            else { copiedContent = nil }
            if let content = copiedContent { return try content.document(settings: settings) }
            throw CreationError.conversion("Copie uma imagem, texto ou conteúdo PDF e clique em Ler conteúdo copiado.")
        }
    }

    func capture(window: Bool) {
        run("Selecione o que deseja capturar. Esc cancela.") { [self] in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("PDFCRTV-captura-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url); CreationWindowController.shared.window?.makeKeyAndOrderFront(nil) }
            CreationWindowController.shared.window?.orderOut(nil)
            try await Task.sleep(for: .milliseconds(300))
            var arguments = ["-i", "-x", "-t", "png"]
            if window { arguments.append("-w") }
            arguments.append(url.path)
            try await ExternalProcess.run(executable: URL(fileURLWithPath: "/usr/sbin/screencapture"), arguments: arguments, timeout: 120)
            guard FileManager.default.fileExists(atPath: url.path) else { throw CancellationError() }
            guard let image = NSImage(contentsOf: url) else { throw CreationError.emptyContent }
            copiedContent = .image(image)
            return try DocumentCreator.image(image, settings: settings)
        }
    }

    func save() {
        guard let preview, busy == nil, isReady else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(title.isEmpty ? "Documento" : title).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(of: preview).write(to: url, options: .atomic)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { Task { @MainActor in self.error = error.localizedDescription } }
            }
            resultNote = "Salvo em \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }
    private func data(of doc: PDFDocument) throws -> Data {
        guard let data = doc.dataRepresentation() else { throw CreationError.conversion("Não foi possível salvar o PDF.") }
        return data
    }
}
