import AppKit
import PDFCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct PDFCRTVApp: App {
    @NSApplicationDelegateAdaptor(PDFAppDelegate.self) private var delegate
    var body: some Scene {
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            ContentView(document: file.document)
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Criar PDF…") { CreationWindowController.shared.show() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Abrir PDF…") { NSDocumentController.shared.openDocument(nil) }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Juntar arquivos…") { CreationWindowController.shared.show(.multiple) }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Espaços locais…") { CreationWindowController.shared.show(.spaces) }
            }
        }
    }
}

@MainActor
final class PDFAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.count > index + 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                do { try await CreationSmokeTests.run(folder: folder) }
                catch { try? error.localizedDescription.write(to: folder.appendingPathComponent("ERRO.txt"), atomically: true, encoding: .utf8) }
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if NSDocumentController.shared.documents.isEmpty { CreationWindowController.shared.show() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { CreationWindowController.shared.show() }
        return true
    }
}

/// Escolhe vários PDFs, junta na ordem escolhida e abre o resultado.
enum MergeFlow {
    @MainActor static func run() {
        let open = NSOpenPanel()
        open.title = "Escolha os PDFs para juntar"
        open.message = "Eles entram em ordem alfabética. Depois dá para reordenar as páginas."
        open.allowedContentTypes = [.pdf]
        open.allowsMultipleSelection = true
        guard open.runModal() == .OK, !open.urls.isEmpty else { return }
        let urls = open.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let save = NSSavePanel()
        save.allowedContentTypes = [.pdf]
        save.nameFieldStringValue = "Combinado.pdf"
        guard save.runModal() == .OK, let target = save.url else { return }
        do {
            try Exporter.write(try PageOperations.merge(urls), to: target)
            NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, _ in }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
