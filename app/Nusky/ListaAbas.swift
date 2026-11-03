import SwiftUI

struct ListaAbas: View {
    @ObservedObject var historico: Historico
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onDelete: (Set<UUID>) -> Void
    let onClose: () -> Void

    @State private var editMode: EditMode = .inactive
    @State private var selecao = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider()

            List(selection: $selecao) {
                ForEach(historico.abas) { aba in
                    linha(aba)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)

            if editMode == .active {
                Button(role: .destructive) {
                    onDelete(selecao)
                    selecao.removeAll()
                    editMode = .inactive
                } label: {
                    Text(selecao.isEmpty ? "Apagar" : "Apagar \(selecao.count)")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .disabled(selecao.isEmpty)
            }
        }
    }

    private var cabecalho: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
            }

            Spacer()

            Text("Abas")
                .font(.headline)

            Spacer()

            Button(action: alternarEdicao) {
                Text(editMode == .active ? "OK" : "Selecionar")
            }

            Button(action: onNew) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.leading, 12)
        }
        .buttonStyle(.plain)
        .padding()
    }

    private func alternarEdicao() {
        selecao.removeAll()
        editMode = editMode == .active ? .inactive : .active
    }

    private func linha(_ aba: Aba) -> some View {
        let ativa = aba.id == historico.abaAtual.id
        return VStack(alignment: .leading, spacing: 2) {
            Text(aba.titulo)
                .font(.system(size: 16, weight: ativa ? .semibold : .regular))
                .lineLimit(1)
            Text(aba.entradaAtual?.url ?? "Sem página")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if editMode == .inactive {
                onSelect(aba.id)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete([aba.id])
            } label: {
                Label("Apagar", systemImage: "trash")
            }
        }
        .tag(aba.id)
    }
}