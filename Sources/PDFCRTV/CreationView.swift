import AppKit
import PDFCore
import PDFKit
import SwiftUI

struct CreationView: View {
    @ObservedObject var model: CreationModel
    @StateObject private var spaces = SpacesModel()
    @StateObject private var scanner = ScannerModel()
    @State private var advanced = false
    @State private var draggedID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PDFCRTV").font(.headline)
                        Text("Criar e organizar").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 24)
                List(CreationMode.allCases, selection: $model.mode) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).padding(.vertical, 7).tag(mode)
                }.listStyle(.sidebar).disabled(model.busy != nil)
                Button("Abrir um PDF…", systemImage: "folder") { NSDocumentController.shared.openDocument(nil) }
                    .buttonStyle(.plain).padding(20)
            }.frame(width: 220).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.mode == .spaces ? "Espaços locais" : "Criar PDF").font(.system(size: 30, weight: .bold))
                    Text(model.mode.subtitle).foregroundStyle(.secondary)
                }
                if model.mode == .spaces {
                    SpacesView(model: spaces)
                } else {
                    HStack(alignment: .top, spacing: 22) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                sourceControls
                                if model.mode != .scanner { pageControls }
                                if model.mode != .blank && model.mode != .templates {
                                    Toggle("Tornar o texto pesquisável (OCR)", isOn: $model.searchable)
                                    Text("Reconhecimento local. Páginas que já têm texto são preservadas.").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(2)
                        }.frame(maxWidth: .infinity)
                        if model.mode != .scanner { preview.frame(width: 270) }
                    }.disabled(model.busy != nil)
                    Spacer(minLength: 0)
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let note = model.resultNote { Text(note).font(.callout).foregroundStyle(.secondary) }
                    Divider()
                    HStack(spacing: 12) {
                        if let busy = model.busy {
                            ProgressView().controlSize(.small)
                            Text(busy).font(.callout).lineLimit(2)
                            Button("Cancelar") { model.cancel() }
                        } else {
                            Text(model.preview.map { "\($0.pageCount) página(s) na prévia" } ?? "Confira a prévia antes de salvar.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Preparar PDF") { model.create() }.disabled(!model.canCreate)
                        Button("Salvar e abrir…") { model.save() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.preview == nil || model.busy != nil || !model.isReady)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 980, minHeight: 660)
        .onChange(of: model.mode) { _, _ in model.changeMode() }
        .onChange(of: model.settings) { _, _ in model.invalidatePreview() }
        .onChange(of: model.numberOfPages) { _, _ in model.invalidatePreview() }
        .onChange(of: model.template) { _, _ in model.invalidatePreview() }
        .onChange(of: model.title) { _, _ in model.invalidatePreview() }
        .onChange(of: model.webAddress) { _, _ in model.invalidatePreview() }
        .onChange(of: model.searchable) { _, _ in model.isReady = false }
        .onAppear { scanner.onScan = { if model.mode == .scanner { model.addFiles([$0]) } } }
    }

    @ViewBuilder private var sourceControls: some View {
        switch model.mode {
        case .file, .multiple:
            fileList
            Button(model.mode == .file ? "Selecionar arquivo…" : "Adicionar arquivos…", systemImage: "plus") { model.chooseFiles() }
            Text("PDF, imagens, TXT, RTF, HTML e documentos do Office.").font(.caption).foregroundStyle(.secondary)
            if model.needsOffice || advanced {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.officeURL == nil ? "Office requer LibreOffice" : "Conversor Office disponível", systemImage: model.officeURL == nil ? "info.circle" : "checkmark.circle")
                    Text("A conversão de DOCX, XLSX e PPTX usa o LibreOffice instalado neste Mac. O resultado depende das fontes disponíveis.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Selecionar LibreOffice…") { model.chooseOffice() }
                        Link("Baixar", destination: URL(string: "https://www.libreoffice.org/download/download-libreoffice/")!)
                    }
                }.padding(12).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
            }
        case .blank:
            Label("Um documento do seu jeito", systemImage: "doc").font(.title3.weight(.semibold))
            Stepper("\(model.numberOfPages) página(s)", value: $model.numberOfPages, in: 1...500)
        case .templates:
            ForEach(DocumentTemplate.allCases, id: \.self) { template in
                Button { model.template = template } label: {
                    HStack {
                        Label(template.rawValue, systemImage: template.symbol)
                        Spacer()
                        if model.template == template { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                    }.padding(14).background(model.template == template ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            TextField("Título ou nome da organização", text: $model.title).textFieldStyle(.roundedBorder)
        case .web:
            Image(systemName: "globe").font(.system(size: 44, weight: .light)).foregroundStyle(.tint).padding(.top, 12)
            TextField("https://exemplo.com", text: $model.webAddress).textFieldStyle(.roundedBorder)
            Text("Páginas públicas. Sites que exigem login ou carregam conteúdo ao rolar podem não aparecer por completo.").font(.caption).foregroundStyle(.secondary)
        case .clipboard:
            Image(systemName: "doc.on.clipboard").font(.system(size: 44, weight: .light)).foregroundStyle(.tint).padding(.top, 12)
            Text("Copie uma imagem, texto ou PDF em outro aplicativo.")
            Button("Ler conteúdo copiado", systemImage: "clipboard") { model.readClipboard() }
        case .capture:
            Image(systemName: "viewfinder").font(.system(size: 44, weight: .light)).foregroundStyle(.tint).padding(.top, 12)
            Button("Capturar uma área…", systemImage: "crop") { model.capture(window: false) }
            Button("Capturar uma janela…", systemImage: "macwindow") { model.capture(window: true) }
            Text("Esta janela será ocultada durante a captura. Pressione Esc para cancelar. O macOS pode pedir permissão para gravar a tela.").font(.caption).foregroundStyle(.secondary)
        case .scanner:
            ScannerPane(model: scanner)
            if !model.inputs.isEmpty { fileList }
        case .spaces: EmptyView()
        }
    }

    private var fileList: some View {
        VStack(spacing: 8) {
            if model.inputs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 40, weight: .light)).foregroundStyle(.tint)
                    Text("Arraste arquivos para cá").font(.headline)
                    Text("ou use o botão abaixo").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 160)
            }
            ForEach(Array(model.inputs.enumerated()), id: \.element.id) { index, input in
                HStack(spacing: 10) {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: input.url.path)).resizable().frame(width: 28, height: 28)
                    Text(input.url.lastPathComponent).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if model.mode != .file {
                        Button { model.inputs.swapAt(index, index - 1); model.invalidatePreview() } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("Mover para cima")
                        Button { model.inputs.swapAt(index, index + 1); model.invalidatePreview() } label: { Image(systemName: "chevron.down") }.disabled(index + 1 == model.inputs.count).help("Mover para baixo")
                    }
                    Button { model.inputs.removeAll { $0.id == input.id }; model.invalidatePreview() } label: { Image(systemName: "xmark") }.help("Remover arquivo")
                }.buttonStyle(.borderless).padding(10).background(.background, in: .rect(cornerRadius: 8))
                .onDrag { draggedID = input.id; return NSItemProvider(object: input.id.uuidString as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    guard let id = draggedID, let source = model.inputs.firstIndex(where: { $0.id == id }), source != index else { return false }
                    let item = model.inputs.remove(at: source); model.inputs.insert(item, at: min(index, model.inputs.count))
                    draggedID = nil; model.invalidatePreview(); return true
                }
            }
        }.padding(10).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 12))
        .dropDestination(for: URL.self) { urls, _ in model.addFiles(urls.filter(\.isFileURL)); return !urls.isEmpty }
    }

    private var pageControls: some View {
        DisclosureGroup("Configurações de página", isExpanded: $advanced) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Papel", selection: $model.settings.paper) {
                    ForEach(PageSettings.Paper.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Paisagem", isOn: $model.settings.landscape)
                Picker("Margens", selection: $model.settings.margin) {
                    Text("Sem margem").tag(CGFloat(0))
                    Text("Pequenas — 6 mm").tag(CGFloat(18))
                    Text("Normais — 13 mm").tag(CGFloat(36))
                    Text("Largas — 25 mm").tag(CGFloat(72))
                }
                Text("Aplicadas a imagens, texto, modelos e páginas web. PDFs e documentos do Office mantêm seu formato original.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRÉVIA").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            if let doc = model.preview {
                CreationPreview(document: doc).frame(maxHeight: .infinity).clipShape(.rect(cornerRadius: 12))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36, weight: .light))
                    Text("Seu documento aparece aqui").font(.callout)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 12))
            }
        }.frame(minHeight: 370)
    }
}

struct CreationPreview: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.document = document
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) { if view.document !== document { view.document = document; view.autoScales = true } }
}

@MainActor
final class CreationWindowController: NSObject, NSWindowDelegate {
    static let shared = CreationWindowController()
    let model = CreationModel()
    var window: NSWindow?
    func show(_ mode: CreationMode? = nil) {
        if let mode, model.busy == nil { model.mode = mode }
        if window == nil {
            let controller = NSHostingController(rootView: CreationView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Criar PDF — PDFCRTV"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1100, height: 740))
            window.minSize = NSSize(width: 980, height: 660)
            window.isReleasedWhenClosed = false; window.delegate = self; window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { model.cancel() }
}
