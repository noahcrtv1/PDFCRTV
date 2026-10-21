import SwiftUI

/// Paleta flutuante de ferramentas de anotação sobre o documento.
struct AnnotationBar: View {
    @Bindable var model: ViewerModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                        .background {
                            if model.tool == tool {
                                Capsule().fill(Color.accentColor)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(tool.title)
                if tool == .select || tool == .strike || tool == .rectangle {
                    Divider().frame(height: 18).padding(.horizontal, 4)
                }
            }
            ColorPicker("Cor", selection: $model.color, supportsOpacity: false)
                .labelsHidden()
                .help("Cor da anotação")
                .padding(.leading, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.18), value: model.tool)
    }
}
