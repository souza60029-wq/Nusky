import SwiftUI

// Tela de configurações, no estilo Ajustes do iOS.
// As preferências ficam em @AppStorage, com as mesmas chaves usadas pelo ContentView.

struct Configuracoes: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nightMode") private var nightMode = false
    @AppStorage("barAtBottom") private var barAtBottom = false
    @AppStorage("useButtons") private var useButtons = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Aparência")) {
                    opcao("Diurno", selecionada: !nightMode) { nightMode = false }
                    opcao("Noturno", selecionada: nightMode) { nightMode = true }
                }

                Section(header: Text("Barra")) {
                    opcao("Em cima", selecionada: !barAtBottom) { barAtBottom = false }
                    opcao("Embaixo", selecionada: barAtBottom) { barAtBottom = true }
                }

                Section(
                    header: Text("Navegação"),
                    footer: Text("Gestos: arraste a barra para voltar, avançar e abrir as abas. Botões: ao expandir a barra, aparecem três botões para voltar, avançar e abrir as abas.")
                ) {
                    opcao("Gestos", selecionada: !useButtons) { useButtons = false }
                    opcao("Botões", selecionada: useButtons) { useButtons = true }
                }
            }
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func opcao(_ titulo: String, selecionada: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack {
                Text(titulo)
                    .foregroundColor(.primary)
                Spacer()
                if selecionada {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}