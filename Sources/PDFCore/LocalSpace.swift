import Foundation

public struct LocalSpace: Codable {
    public struct Item: Codable, Identifiable {
        public var id: UUID
        public var title: String
        public var file: String?
        public var link: URL?
    }
    public var version = 1
    public var name: String
    public var notes = ""
    public var items: [Item] = []
    public init(name: String) { self.name = name }
}

public enum LocalSpaceFiles {
    public static let manifest = "Espaco.pdfcrtv.json"
    public static func create(at folder: URL, name: String) throws -> LocalSpace {
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw CreationError.conversion("Já existe uma pasta com esse nome. Escolha outro nome.") }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Arquivos"), withIntermediateDirectories: true)
        let space = LocalSpace(name: name)
        try save(space, in: folder)
        return space
    }
    public static func read(from folder: URL) throws -> LocalSpace {
        let result = try JSONDecoder().decode(LocalSpace.self, from: Data(contentsOf: folder.appendingPathComponent(manifest)))
        guard result.version == 1 else { throw CreationError.conversion("Este espaço foi criado em uma versão mais recente do PDFCRTV.") }
        for item in result.items { _ = try destination(for: item, in: folder) }
        return result
    }
    public static func save(_ space: LocalSpace, in folder: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(space).write(to: folder.appendingPathComponent(manifest), options: .atomic)
    }
    public static func importFile(_ url: URL, into folder: URL) throws -> LocalSpace.Item {
        let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        let relative = "Arquivos/" + UUID().uuidString + ext
        let item = LocalSpace.Item(id: UUID(), title: url.lastPathComponent, file: relative, link: nil)
        try FileManager.default.copyItem(at: url, to: destination(for: item, in: folder))
        return item
    }
    public static func webLink(_ url: URL) throws -> LocalSpace.Item {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw CreationError.conversion("Informe um link http ou https válido.") }
        return LocalSpace.Item(id: UUID(), title: url.absoluteString, file: nil, link: url)
    }
    public static func destination(for item: LocalSpace.Item, in folder: URL) throws -> URL {
        if let link = item.link {
            guard item.file == nil, ["http", "https"].contains(link.scheme?.lowercased() ?? ""), link.host != nil else { throw CreationError.conversion("Link inválido no espaço.") }
            return link
        }
        guard let file = item.file, file.hasPrefix("Arquivos/"), !file.contains(".."), !file.hasPrefix("/"), file.split(separator: "/").count == 2 else { throw CreationError.conversion("O espaço contém um caminho de arquivo inválido.") }
        let url = folder.appendingPathComponent(file).resolvingSymlinksInPath()
        let root = folder.appendingPathComponent("Arquivos").resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(root) else { throw CreationError.conversion("O arquivo está fora deste espaço.") }
        return url
    }
}
