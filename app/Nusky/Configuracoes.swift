import SwiftUI

struct Configuracoes: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("nightMode") private var noturno = false
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage("useButtons") private var botoes = true

    /// Página aberta no momento, usada pelo diagnóstico.
    var urlAtual: URL? = nil

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Automático", isOn: $automatico)
                    Toggle("Modo noturno", isOn: $noturno)
                        .disabled(automatico)
                } header: {
                    Text("Aparência")
                } footer: {
                    Text("Automático segue o modo claro ou escuro do iPhone.")
                }

                Section {
                    Toggle("Barra embaixo", isOn: $barraEmbaixo)
                } header: {
                    Text("Barra")
                } footer: {
                    Text("Desligado: a barra fica em cima.")
                }

                Section {
                    Toggle("Botões na barra", isOn: $botoes)
                } header: {
                    Text("Navegação")
                } footer: {
                    Text("Desligado: arraste a barra para voltar, avançar e abrir as abas. Ligado: ao expandir a barra, aparecem os botões de voltar, avançar e abas.")
                }

                Section {
                    NavigationLink {
                        DiagnosticoView(url: urlAtual)
                    } label: {
                        Text("Analisar página atual")
                    }
                    .disabled(urlAtual == nil)
                } header: {
                    Text("Diagnóstico")
                } footer: {
                    Text("Baixa de novo a página aberta e gera um relatório de texto para copiar. Não altera a página.")
                }
            }
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}