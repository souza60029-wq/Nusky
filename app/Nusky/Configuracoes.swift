import SwiftUI

struct Configuracoes: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("nightMode") private var noturno = false
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage("useButtons") private var botoes = true
    @AppStorage(IdentificacaoNavegador.chaveDesktop) private var versaoDesktop = false
    @AppStorage(ChavesTermos.dataAceite) private var dataAceite = ""
    @AppStorage("listaVersao") private var versaoLista = 0
    @AppStorage("listaData") private var dataLista = ""

    /// Página aberta no momento, usada pelo diagnóstico.
    var urlAtual: URL? = nil

    /// Mensagem mostrada depois de tocar em "Procurar atualização".
    @State private var mensagemLista = ""

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Data do aceite dos termos, em formato de leitura. Vazia se ainda não aceitou.
    private var dataAceiteTexto: String {
        guard let data = ISO8601DateFormatter().date(from: dataAceite) else { return "" }
        return data.formatted(date: .numeric, time: .omitted)
    }

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
                    Toggle("Solicitar versão desktop", isOn: $versaoDesktop)
                } header: {
                    Text("Site")
                } footer: {
                    Text("Ligado: pede a versão desktop. Desligado: pede a versão para celular. Ao fechar esta tela, a página aberta recarrega se a opção mudou.")
                }

                Section {
                    HStack {
                        Text("Versão da lista")
                        Spacer()
                        Text(versaoLista == 0 ? "Nenhuma" : "\(versaoLista)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Última atualização")
                        Spacer()
                        Text(dataLista.isEmpty ? "Nunca" : dataLista)
                            .foregroundColor(.secondary)
                    }
                    Button("Procurar atualização") {
                        procurarAtualizacao()
                    }
                    if !mensagemLista.isEmpty {
                        Text(mensagemLista)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Endereços")
                } footer: {
                    Text("A lista de sites serve para achar sites pelo nome. Ela só é atualizada quando você toca em \"Procurar atualização\". Nada é verificado em segundo plano.")
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

                Section {
                    HStack {
                        Text("Versão")
                        Spacer()
                        Text(versao)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Licença")
                        Spacer()
                        Text("MPL-2.0")
                            .foregroundColor(.secondary)
                    }
                    NavigationLink {
                        TermosDeUso()
                    } label: {
                        Text("Termos de uso")
                    }
                } header: {
                    Text("Sobre")
                } footer: {
                    if dataAceiteTexto.isEmpty {
                        Text("Versão dos termos: \(versaoDosTermos).")
                    } else {
                        Text("Versão dos termos: \(versaoDosTermos). Aceitos em \(dataAceiteTexto).")
                    }
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

    /// Ainda não há lista publicada. A busca na lista, com o download, entra depois.
    private func procurarAtualizacao() {
        mensagemLista = "Ainda não há lista publicada."
    }
}