import AppKit
import PDFCore
import SwiftUI

@MainActor
final class SpacesModel: ObservableObject {
    @Published var space: LocalSpace?
    @Published var folder: URL?
    @Published var name = "Meu espaço"
    @Published var query = ""
    @Published var link = ""
    @Published var error: String?

    func create() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), !clean.contains(":"), clean != ".", clean != ".." else { error = "Escolha um nome sem barras ou dois-pontos."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Escolha onde guardar a pasta do espaço."; panel.prompt = "Criar aqui"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let url = parent.appendingPathComponent(clean, isDirectory: true)
        do { space = try LocalSpaceFiles.create(at: url, name: clean); folder = url } catch { self.error = error.localizedDescription }
    }
    func open() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Selecione a pasta de um espaço do PDFCRTV."; panel.prompt = "Abrir espaço"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let loaded = try LocalSpaceFiles.read(from: url); space = loaded; folder = url } catch { self.error = "Não foi possível abrir esse espaço: " + error.localizedDescription }
    }
    func save() {
        guard let space, let folder else { return }
        do { try LocalSpaceFiles.save(space, in: folder) } catch { self.error = error.localizedDescription }
    }
    func addFiles() {
        guard let folder else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { space?.items.append(try LocalSpaceFiles.importFile(url, into: folder)); save() }
            catch { self.error = error.localizedDescription; break }
        }
    }
    func addLink() {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.contains("://") ? value : "https://" + value) else { error = "Link inválido."; return }
        do { space?.items.append(try LocalSpaceFiles.webLink(url)); link = ""; save() }
        catch { self.error = error.localizedDescription }
    }
    func openItem(_ item: LocalSpace.Item) {
        guard let folder else { return }
        do { NSWorkspace.shared.open(try LocalSpaceFiles.destination(for: item, in: folder)) } catch { self.error = error.localizedDescription }
    }
    func remove(_ item: LocalSpace.Item) { space?.items.removeAll { $0.id == item.id }; save() }
}

struct SpacesView: View {
    @ObservedObject var model: SpacesModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let space = model.space {
                HStack {
                    Label(space.name, systemImage: "folder.fill").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Abrir outro…") { model.open() }
                    Button("Mostrar no Finder", systemImage: "folder") {
                        if let folder = model.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                }
                TextField("Buscar pelo nome", text: $model.query).textFieldStyle(.roundedBorder)
                List {
                    ForEach(space.items.filter { model.query.isEmpty || $0.title.localizedCaseInsensitiveContains(model.query) }) { item in
                        HStack {
                            Button { model.openItem(item) } label: {
                                Label(item.title, systemImage: item.link == nil ? "doc" : "link").lineLimit(1)
                            }.buttonStyle(.plain)
                            Spacer()
                            Button { model.remove(item) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("Remover da lista; a cópia do arquivo permanece na pasta")
                        }.padding(.vertical, 4)
                    }
                }.frame(minHeight: 140).clipShape(.rect(cornerRadius: 10))
                HStack {
                    Button("Adicionar arquivos…", systemImage: "plus") { model.addFiles() }
                    TextField("https://…", text: $model.link).textFieldStyle(.roundedBorder)
                    Button("Adicionar link") { model.addLink() }.disabled(model.link.isEmpty)
                }
                Text("Notas").font(.headline)
                TextEditor(text: Binding(get: { model.space?.notes ?? "" }, set: { model.space?.notes = $0; model.save() }))
                    .font(.body).frame(minHeight: 120).padding(8).background(.background, in: .rect(cornerRadius: 10))
                Text("Notas salvas automaticamente. Os arquivos adicionados são copiados para esta pasta.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "folder.badge.plus").font(.system(size: 54, weight: .light)).foregroundStyle(.tint).padding(.top, 24)
                Text("Tudo de um projeto, no mesmo lugar.").font(.title2.weight(.semibold))
                Text("Guarde documentos, links e notas. Você pode compartilhar a pasta completa com a equipe.")
                    .foregroundStyle(.secondary)
                TextField("Nome do espaço", text: $model.name).textFieldStyle(.roundedBorder).frame(maxWidth: 350)
                HStack {
                    Button("Criar espaço…") { model.create() }.buttonStyle(.borderedProminent)
                    Button("Abrir espaço existente…") { model.open() }
                }
                Spacer()
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") {} } message: { Text(model.error ?? "") }
    }
}
