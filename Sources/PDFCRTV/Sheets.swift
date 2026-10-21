import AppKit
import PDFCore
import SwiftUI
import UniformTypeIdentifiers

/// Desenhar, importar ou escolher uma assinatura salva.
struct SignatureSheet: View {
    let onChoose: (NSImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var saved = SignatureStore.all()

    private let canvasSize = CGSize(width: 460, height: 170)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assinatura").font(.title2.weight(.semibold))

            if !saved.isEmpty {
                Text("Salvas").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(saved, id: \.self) { url in
                            if let image = NSImage(contentsOf: url) {
                                Button { choose(image) } label: {
                                    Image(nsImage: image).resizable().scaledToFit()
                                        .frame(width: 150, height: 60).padding(8)
                                        .background(.white, in: .rect(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Apagar", systemImage: "trash", role: .destructive) {
                                        SignatureStore.delete(url)
                                        saved = SignatureStore.all()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text("Desenhe com o mouse ou trackpad").font(.headline)
            Canvas { context, _ in
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(.white, in: .rect(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.gray.opacity(0.4)).frame(height: 1).padding(.horizontal, 30).padding(.bottom, 40)
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if value.translation == .zero { strokes.append([value.location]) } else { strokes[strokes.count - 1].append(value.location) }
            })

            HStack {
                Button("Limpar") { strokes = [] }
                Button("Importar imagem…", action: importImage)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar e usar") { saveDrawing() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(strokes.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 510)
    }

    private var path: Path {
        var path = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            for p in stroke.dropFirst() { path.addLine(to: p) }
        }
        return path
    }

    private func saveDrawing() {
        let box = path.boundingRect.insetBy(dx: -6, dy: -6)
        let content = path.offsetBy(dx: -box.minX, dy: -box.minY)
            .stroke(.black, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .frame(width: box.width, height: box.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.nsImage else { return }
        try? SignatureStore.save(image)
        choose(image)
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        try? SignatureStore.save(image)
        choose(image)
    }

    private func choose(_ image: NSImage) {
        onChoose(image)
        dismiss()
    }
}

struct PasswordSheet: View {
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""

    var body: some View {
        Form {
            Text("Salva uma cópia que só abre com senha.").foregroundStyle(.secondary)
            SecureField("Senha", text: $password)
            SecureField("Repita a senha", text: $repeated)
            if !repeated.isEmpty, repeated != password {
                Text("As senhas não batem.").foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar cópia…") {
                    dismiss()
                    onConfirm(password)
                }
                .disabled(password.isEmpty || password != repeated)
            }
        }
    }
}

struct SplitSheet: View {
    let pageCount: Int
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var every = 1

    var body: some View {
        Form {
            Stepper("Uma parte a cada \(every) página(s)", value: $every, in: 1...max(pageCount, 1))
            Text("Gera \(Int((Double(pageCount) / Double(every)).rounded(.up))) arquivos.").foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Dividir…") {
                    dismiss()
                    onConfirm(every)
                }
            }
        }
    }
}

struct OCRSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Texto reconhecido").font(.title2.weight(.semibold))
            ScrollView {
                Text(text.isEmpty ? "Nenhum texto encontrado." : text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Copiar tudo") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Fechar") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
    }
}
