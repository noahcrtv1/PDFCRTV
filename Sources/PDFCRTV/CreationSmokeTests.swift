#if DEBUG
import AppKit
import PDFCore
import PDFKit

/// Teste de integração opt-in, presente apenas no build de desenvolvimento.
@MainActor
enum CreationSmokeTests {
    static func run(folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        CreationWindowController.shared.show(.blank)
        let model = CreationWindowController.shared.model
        try await Task.sleep(for: .milliseconds(400))
        model.numberOfPages = 2
        model.settings.landscape = true
        try await Task.sleep(for: .milliseconds(150))
        model.create()
        try await completed(model)
        try require(model.preview?.pageCount == 2, "Página em branco")
        try snapshot("01-pagina-em-branco", folder: folder)

        model.mode = .templates
        try await Task.sleep(for: .milliseconds(200))
        model.title = "Equipe CRTV"; model.settings.landscape = false
        try await Task.sleep(for: .milliseconds(100))
        model.create(); try await completed(model)
        try require(model.preview?.string?.contains("Equipe CRTV") == true, "Modelo")
        try snapshot("02-modelos", folder: folder)

        model.mode = .multiple
        try await Task.sleep(for: .milliseconds(200))
        let first = folder.appendingPathComponent("Primeiro.txt"), second = folder.appendingPathComponent("Segundo.txt")
        try "PRIMEIRO arquivo".write(to: first, atomically: true, encoding: .utf8)
        try "SEGUNDO arquivo".write(to: second, atomically: true, encoding: .utf8)
        model.addFiles([second, first]); model.create(); try await completed(model)
        try require(model.preview?.pageCount == 2 && model.preview?.page(at: 0)?.string?.contains("SEGUNDO") == true, "Combinação ordenada")
        try snapshot("03-varios-arquivos", folder: folder)

        let html = folder.appendingPathComponent("Pagina.html")
        let paragraphs = (0..<70).map { "<p style='margin:24px 0'>Linha \($0) — documento da equipe</p>" }.joined()
        try "<!doctype html><html><head><meta charset='utf-8'></head><body style='font:24px sans-serif'><h1>Página de teste</h1>\(paragraphs)<p>ULTIMO MARCADOR</p></body></html>".write(to: html, atomically: true, encoding: .utf8)
        model.mode = .file
        try await Task.sleep(for: .milliseconds(200))
        model.addFiles([html]); model.create(); try await completed(model)
        try require((model.preview?.pageCount ?? 0) > 1 && model.preview?.string?.contains("ULTIMO MARCADOR") == true, "HTML paginado")
        let allText = model.preview?.string ?? ""
        for index in 0..<70 {
            let marker = "Linha \(index) — documento da equipe"
            try require(allText.components(separatedBy: marker).count == 2, "Texto web sem perda ou duplicação")
        }
        try model.preview!.dataRepresentation()!.write(to: folder.appendingPathComponent("web-paginado.pdf"))
        try snapshot("04-pagina-web", folder: folder)

        model.mode = .spaces
        try await Task.sleep(for: .milliseconds(200))
        try snapshot("05-espacos", folder: folder)
        try "OK: página em branco, modelo, combinação em ordem, HTML paginado e abertura das telas.\n".write(to: folder.appendingPathComponent("RESULTADO.txt"), atomically: true, encoding: .utf8)
    }

    static func completed(_ model: CreationModel) async throws {
        let deadline = Date().addingTimeInterval(90)
        while model.busy != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        if let error = model.error { throw CreationError.conversion(error) }
        try require(model.busy == nil && model.isReady, "Conclusão da operação")
        try await Task.sleep(for: .milliseconds(200))
    }
    static func require(_ value: Bool, _ label: String) throws {
        if !value { throw CreationError.conversion("Teste falhou: " + label) }
    }
    static func snapshot(_ name: String, folder: URL) throws {
        if let window = CreationWindowController.shared.window {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), folder.appendingPathComponent(name + "-janela.png").path]
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        guard let view = CreationWindowController.shared.window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CreationError.emptyContent }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
