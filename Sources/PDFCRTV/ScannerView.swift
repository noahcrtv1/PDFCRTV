import AppKit
import ImageCaptureCore
import Quartz
import SwiftUI

@MainActor
final class ScannerModel: NSObject, ObservableObject, @preconcurrency ICDeviceBrowserDelegate {
    @Published var devices: [ICScannerDevice] = []
    @Published var selectedID: String = ""
    @Published var error: String?
    let browser = ICDeviceBrowser()
    let downloadFolder = FileManager.default.temporaryDirectory.appendingPathComponent("PDFCRTV-Scanner-" + UUID().uuidString)
    var onScan: ((URL) -> Void)?
    var selected: ICScannerDevice? { devices.first { ($0.uuidString ?? $0.name ?? "") == selectedID } }
    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.scanner.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
        do { try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription }
    }
    func start() { if !browser.isBrowsing { browser.start() } }
    func stop() { browser.stop() }
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        devices.append(scanner)
        if selectedID.isEmpty { selectedID = scanner.uuidString ?? scanner.name ?? "" }
    }
    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        devices.removeAll { $0 === device }
        if selected == nil { selectedID = devices.first?.uuidString ?? devices.first?.name ?? "" }
    }
    func received(_ url: URL?) {
        guard let url else { error = "O scanner não entregou um arquivo."; return }
        onScan?(url)
    }
}

struct ScannerPane: View {
    @ObservedObject var model: ScannerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.devices.isEmpty {
                ContentUnavailableView("Nenhum scanner encontrado", systemImage: "scanner", description: Text("Conecte e ligue um scanner compatível com Captura de Imagem do macOS."))
                Button("Procurar novamente") { model.stop(); model.start() }
            } else {
                Picker("Scanner", selection: $model.selectedID) {
                    ForEach(model.devices, id: \.self) { device in Text(device.name ?? "Scanner").tag(device.uuidString ?? device.name ?? "") }
                }
                NativeScannerView(model: model).frame(minWidth: 480, minHeight: 360)
                Text("As digitalizações aparecem na lista de arquivos. Depois clique em Preparar PDF.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .alert("Scanner", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") {} } message: { Text(model.error ?? "") }
    }
}

struct NativeScannerView: NSViewRepresentable {
    let model: ScannerModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> IKScannerDeviceView {
        let view = IKScannerDeviceView()
        view.delegate = context.coordinator
        view.transferMode = .fileBased
        view.downloadsDirectory = model.downloadFolder
        view.mode = .simple
        view.hasDisplayModeAdvanced = true
        view.scannerDevice = model.selected
        return view
    }
    func updateNSView(_ view: IKScannerDeviceView, context: Context) {
        if view.scannerDevice !== model.selected { view.scannerDevice = model.selected }
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency IKScannerDeviceViewDelegate {
        let model: ScannerModel
        init(_ model: ScannerModel) { self.model = model }
        func scannerDeviceView(_ scannerDeviceView: IKScannerDeviceView!, didScanTo url: URL!, error: Error!) {
            if let error { model.error = error.localizedDescription } else { model.received(url) }
        }
        func scannerDeviceView(_ scannerDeviceView: IKScannerDeviceView!, didEncounterError error: Error!) {
            model.error = error?.localizedDescription
        }
    }
}
