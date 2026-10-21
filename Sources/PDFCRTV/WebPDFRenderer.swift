import AppKit
import PDFCore
import PDFKit
import WebKit

@MainActor
final class WebPDFRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var navigation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var pdfContinuation: CheckedContinuation<Data, Error>?

    func render(url: URL, settings: PageSettings) async throws -> PDFDocument {
        try settings.validate()
        guard ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "") else { throw CreationError.conversion("Informe um endereço http ou https válido.") }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        defer { timeout?.cancel(); view.stopLoading(); webView = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                navigation = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(45))
                    if !Task.isCancelled { self?.finish(.failure(CreationError.conversion("A página não terminou de carregar. Confira o endereço e tente novamente."))) }
                }
                if url.isFileURL { view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
                else { view.load(URLRequest(url: url, timeoutInterval: 40)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
        try Task.checkCancellation()
        let height = (try await view.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)")) as? Double ?? 800
        guard height.isFinite, height > 0, height < 300_000 else { throw CreationError.conversion("A página web é grande demais. Salve uma seção menor.") }
        // Evita cortar linhas de texto na divisão entre folhas.
        let lineRects = (try? await view.evaluateJavaScript("""
            (() => {
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              const lines = []; let node;
              while ((node = walker.nextNode()) && lines.length < 30000) {
                if (!node.textContent.trim()) continue;
                const range = document.createRange(); range.selectNodeContents(node);
                for (const r of range.getClientRects()) if (r.height > 0)
                  lines.push([r.top + window.scrollY, r.bottom + window.scrollY]);
              }
              return lines;
            })()
            """)) as? [[Double]] ?? []
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: settings.size)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw CreationError.emptyContent }
        let printable = settings.contentRect
        let scale = printable.width / 1000
        let maxSlice = printable.height / scale
        var offset: CGFloat = 0
        var count = 0
        while offset < height - 0.01 {
            try Task.checkCancellation()
            count += 1
            guard count <= 500 else { throw CreationError.conversion("A página web excede o limite de 500 folhas.") }
            var end = min(offset + maxSlice, height)
            if end < height {
                let crossed = lineRects.filter { $0.count == 2 && $0[0] < end && $0[1] > end }
                if let top = crossed.map({ $0[0] }).min(), top > offset + maxSlice * 0.5 { end = max(offset + 1, top - 1) }
            }
            let bytes = try await capture(view, rect: CGRect(x: 0, y: offset, width: 1000, height: end - offset))
            guard let provider = CGDataProvider(data: bytes as CFData), let sourceDocument = CGPDFDocument(provider),
                  let source = sourceDocument.page(at: 1) else { throw CreationError.emptyContent }
            let target = CGRect(x: printable.minX, y: printable.maxY - (end - offset) * scale, width: printable.width, height: (end - offset) * scale)
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor); context.fill(mediaBox)
            context.saveGState()
            context.clip(to: target)
            context.concatenate(source.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(source)
            context.restoreGState()
            context.endPDFPage()
            offset = end
        }
        context.closePDF()
        guard let document = PDFDocument(data: output as Data), document.pageCount > 0 else { throw CreationError.emptyContent }
        return document
    }

    private func capture(_ view: WKWebView, rect: CGRect) async throws -> Data {
        let config = WKPDFConfiguration(); config.rect = rect
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pdfContinuation = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(45))
                    if !Task.isCancelled { self?.finishPDF(.failure(CreationError.conversion("A página demorou demais para gerar o PDF. Tente uma página menor."))) }
                }
                view.createPDF(configuration: config) { [weak self] result in self?.finishPDF(result) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishPDF(.failure(CancellationError())) }
        }
    }

    private func finishPDF(_ result: Result<Data, Error>) {
        guard let continuation = pdfContinuation else { return }
        pdfContinuation = nil; timeout?.cancel(); continuation.resume(with: result)
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation = navigation else { return }
        navigation = nil; timeout?.cancel(); continuation.resume(with: result)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(CreationError.conversion("A página web foi interrompida. Tente novamente."))) }
}
