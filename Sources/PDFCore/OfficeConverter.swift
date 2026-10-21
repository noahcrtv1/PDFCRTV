import Foundation
import PDFKit

public enum OfficeConverter {
    public static let extensions: Set<String> = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp"]

    public static func executable(in app: URL) -> URL? {
        let candidate = app.appendingPathComponent("Contents/MacOS/soffice")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    public static func discover(customPath: String? = nil) -> URL? {
        let candidates = [customPath, "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                          NSHomeDirectory() + "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                          "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    public static func convert(_ source: URL, executable: URL) async throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PDFCRTV-Office-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = folder.appendingPathComponent("profile").absoluteString
        try await ExternalProcess.run(executable: executable, arguments: ["-env:UserInstallation=" + profile, "--headless", "--nologo", "--nodefault", "--nofirststartwizard", "--convert-to", "pdf", "--outdir", folder.path, source.path], timeout: 120)
        let result = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".pdf")
        guard let data = try? Data(contentsOf: result), let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw CreationError.conversion("O LibreOffice não conseguiu converter \(source.lastPathComponent). Confira se o arquivo abre normalmente e se não exige senha.")
        }
        return data
    }
}

public enum ExternalProcess {
    /// Argumentos passam diretamente ao processo. Nenhum nome de arquivo é interpretado por um shell.
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw CreationError.conversion("A operação demorou mais que o esperado. Tente novamente com um arquivo menor.") }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
        guard process.terminationStatus == 0 else { throw CreationError.conversion("A operação foi cancelada ou não pôde ser concluída.") }
    }
}
