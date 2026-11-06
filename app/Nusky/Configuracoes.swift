// app/Nusky/Configuracoes.swift
import SwiftUI

/// Versão e data da lista que vem dentro do app.
/// Manter igual ao `versao` e `data` de dados/sites.json sempre que a lista mudar.
enum ListaEmbutida {
    static let versao = 1
    static let data = "2026-11-05"
}

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
    @AppStorage("listaEtag") private var etagLista = ""

    /// Página aberta no momento, usada pelo diagnóstico.
    var urlAtual: URL? = nil

    /// Mensagem mostrada depois de tocar em "Procurar atualização".
    @State private var mensagemLista = ""
    /// Verdadeiro enquanto o app consulta o GitHub.
    @State private var verificando = false
    /// Lista baixada e pronta para ser aplicada, depois da confirmação.
    @State private var listaNova: ListaBaixada? = nil
    /// Controla o aviso de confirmação antes de trocar a lista.
    @State private var confirmarAtualizacao = false

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Versão da lista que o app está usando agora.
    /// Se nenhuma lista foi baixada, a que está em uso é a que vem com o app.
    private var versaoEmUso: Int {
        versaoLista > 0 ? versaoLista : ListaEmbutida.versao
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
                        Text("\(versaoEmUso)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Última atualização")
                        Spacer()
                        Text(dataLista.isEmpty ? "Nunca" : dataLista)
                            .foregroundColor(.secondary)
                    }
                    Button {
                        Task { await verificarAtualizacao() }
                    } label: {
                        Text(verificando ? "Verificando…" : "Procurar atualização")
                    }
                    .disabled(verificando)

                    if let nova = listaNova {
                        Text("Versão \(nova.versao), de \(nova.dataTexto).")
                            .foregroundColor(.secondary)
                        Button("Atualizar endereços") {
                            confirmarAtualizacao = true
                        }
                    }
                    if !mensagemLista.isEmpty {
                        Text(mensagemLista)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Endereços")
                } footer: {
                    Text("A lista de sites serve para achar sites pelo nome. Ela só é atualizada quando você toca em \"Procurar atualização\" e confirma. Nada é verificado em segundo plano.")
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
            .alert("Atualizar endereços?", isPresented: $confirmarAtualizacao) {
                Button("Cancelar", role: .cancel) {}
                Button("Atualizar") {
                    Task { await aplicarAtualizacao() }
                }
            } message: {
                Text("Os sites encontrados pelo nome passam a vir da lista nova.")
            }
        }
    }

    // MARK: - Atualização da lista

    /// Consulta o GitHub. Não altera a lista em uso; só guarda a lista nova para o usuário confirmar.
    private func verificarAtualizacao() async {
        verificando = true
        mensagemLista = ""
        listaNova = nil
        defer { verificando = false }

        var pedido = URLRequest(url: ArquivoLista.endereco)
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        pedido.timeoutInterval = 20
        if !etagLista.isEmpty {
            pedido.setValue(etagLista, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (dados, resposta) = try await URLSession.shared.data(for: pedido)
            guard let http = resposta as? HTTPURLResponse else {
                mensagemLista = mensagemFalha
                return
            }

            // 304: o arquivo não mudou desde a última atualização aplicada.
            if http.statusCode == 304 {
                mensagemLista = "Você já tem a lista mais recente (versão \(versaoEmUso))."
                return
            }
            guard http.statusCode == 200 else {
                mensagemLista = mensagemFalha
                return
            }

            let cabecalho = try await Task.detached(priority: .utility) {
                try JSONDecoder().decode(Cabecalho.self, from: dados)
            }.value

            guard cabecalho.versao > versaoEmUso else {
                mensagemLista = "Você já tem a lista mais recente (versão \(versaoEmUso))."
                return
            }

            listaNova = ListaBaixada(
                texto: String(decoding: dados, as: UTF8.self),
                versao: cabecalho.versao,
                dataTexto: formatarData(cabecalho.data),
                etag: http.value(forHTTPHeaderField: "ETag") ?? ""
            )
        } catch {
            mensagemLista = mensagemFalha
        }
    }

    /// Aplica a lista confirmada. Só troca a lista se ela passar na verificação do motor.
    private func aplicarAtualizacao() async {
        guard let nova = listaNova else { return }

        let aceita = await Task.detached(priority: .utility) {
            Engine.atualizarLista(json: nova.texto)
        }.value

        guard aceita else {
            listaNova = nil
            mensagemLista = "A lista baixada não passou na verificação. A lista atual foi mantida."
            return
        }

        do {
            try ArquivoLista.salvar(nova.texto)
        } catch {
            mensagemLista = "Não consegui salvar a lista no aparelho. Tente de novo."
            return
        }

        versaoLista = nova.versao
        dataLista = nova.dataTexto
        etagLista = nova.etag
        listaNova = nil
        mensagemLista = "Endereços atualizados para a versão \(nova.versao)."
    }

    private var mensagemFalha: String {
        "Não consegui verificar agora. Confira a conexão e tente de novo."
    }

    /// Converte a data da lista (aaaa-mm-dd) para o formato de leitura do aparelho.
    private func formatarData(_ iso: String) -> String {
        let formatador = DateFormatter()
        formatador.locale = Locale(identifier: "en_US_POSIX")
        formatador.dateFormat = "yyyy-MM-dd"
        guard let data = formatador.date(from: iso) else { return iso }
        return data.formatted(date: .numeric, time: .omitted)
    }
}

// MARK: - Apoio da atualização da lista

/// Endereço e local de guarda da lista de sites. O Engine lê este arquivo ao abrir o app.
enum ArquivoLista {
    static let endereco = URL(string: "https://raw.githubusercontent.com/souza60029-wq/Nusky/main/dados/sites.json")!

    static func caminho() throws -> URL {
        let suporte = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let pasta = suporte.appendingPathComponent("Nusky", isDirectory: true)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("sites.json")
    }

    static func salvar(_ texto: String) throws {
        try texto.write(to: caminho(), atomically: true, encoding: .utf8)
    }
}

/// Lista baixada, esperando a confirmação do usuário.
private struct ListaBaixada {
    let texto: String
    let versao: Int
    let dataTexto: String
    let etag: String
}

/// Só os campos de cabeçalho da lista, para comparar a versão sem ler os sites.
private struct Cabecalho: Decodable {
    let versao: Int
    let data: String
}