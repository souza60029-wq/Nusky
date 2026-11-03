import SwiftUI
import UIKit

/// Tela de abas no estilo do iOS: grade de cartões, barra de navegação e barra inferior.
struct ListaAbas: View {
    @ObservedObject var historico: Historico
    let onSelect: (UUID) -> Void
    let onNew: () -> Void
    let onDelete: (Set<UUID>) -> Void
    let onClose: () -> Void

    @State private var editando = false
    @State private var selecao = Set<UUID>()

    private let colunas = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var contagem: String {
        let n = historico.abas.count
        return n == 1 ? "1 aba" : "\(n) abas"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: colunas, spacing: 12) {
                    ForEach(historico.abas) { aba in
                        cartao(aba)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Abas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !editando {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("Fechar")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: alternarEdicao) {
                        Text(editando ? "OK" : "Selecionar")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    if editando {
                        Spacer()
                        Button(role: .destructive, action: apagarSelecionadas) {
                            Text(selecao.isEmpty ? "Apagar" : "Apagar \(selecao.count)")
                        }
                        .disabled(selecao.isEmpty)
                        Spacer()
                    } else {
                        Text(contagem)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: onNew) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("Nova aba")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func cartao(_ aba: Aba) -> some View {
        let ativa = aba.id == historico.abaAtual.id
        let marcada = selecao.contains(aba.id)

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 110)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                    )

                if editando {
                    Image(systemName: marcada ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(marcada ? .accentColor : .secondary)
                        .background(Circle().fill(Color(uiColor: .systemBackground)))
                        .padding(6)
                }
            }

            Text(aba.titulo)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Text(aba.entradaAtual?.url ?? "Sem página")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ativa ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { toque(aba) }
        .contextMenu {
            Button(role: .destructive) {
                onDelete([aba.id])
            } label: {
                Label("Apagar", systemImage: "trash")
            }
        }
    }

    private func toque(_ aba: Aba) {
        if editando {
            if selecao.contains(aba.id) {
                selecao.remove(aba.id)
            } else {
                selecao.insert(aba.id)
            }
        } else {
            onSelect(aba.id)
        }
    }

    private func alternarEdicao() {
        selecao.removeAll()
        editando.toggle()
    }

    private func apagarSelecionadas() {
        onDelete(selecao)
        selecao.removeAll()
        editando = false
    }
}