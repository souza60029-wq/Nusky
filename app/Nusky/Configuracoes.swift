// app/Nusky/Configuracoes.swift
import SwiftUI

/// Tópicos da tela de ajustes.
private enum Topico: String, CaseIterable, Identifiable {
    case aparencia = "Aparência"
    case toque = "Toque"
    case navegacao = "Navegação"
    case privacidade = "Privacidade"
    case sobre = "Sobre"

    var id: String { rawValue }

    var icone: String {
        switch self {
        case .aparencia: return "paintbrush"
        case .toque: return "hand.tap"
        case .navegacao: return "safari"
        case .privacidade: return "hand.raised"
        case .sobre: return "info.circle"
        }
    }
}

/// Ajustes do app, sobre a página desfocada. A cor do texto segue a claridade do que está atrás:
/// fundo escuro, texto branco; fundo claro, texto preto.
struct PainelAjustes: View {
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("nightMode") private var noturno = false
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage(IdentificacaoNavegador.chaveDesktop) private var versaoDesktop = false
    @AppStorage(JSRodador.chaveAtivo) private var javascriptLigado = true
    @AppStorage(BrowserModel.chaveImagens) private var imagensLigadas = true
    @AppStorage(ChavesTema.desfoque) private var desfoque = true
    @AppStorage("usarMetal") private var usarMetal = false
    @AppStorage(ChavesTema.forcarNoturno) private var forcarNoturno = false
    @AppStorage(ChavesTema.feedbackLuminoso) private var feedbackLuminoso = true
    @AppStorage(ChavesTema.feedbackExpansivo) private var feedbackExpansivo = true
    @AppStorage(ChavesTema.feedbackTatil) private var feedbackTatil = true
    @AppStorage(ChavesTema.padraoFeedback) private var padraoBruto = 1
    @AppStorage(ChavesTermos.dataAceite) private var dataAceite = ""
    @AppStorage("listaEtag") private var etagLista = ""

    /// Verdadeiro quando o que está atrás do painel é escuro.
    let fundoEscuro: Bool
    /// Há uma página aberta (o diagnóstico precisa de uma).
    let temPagina: Bool
    let aoAbrirURL: (URL) -> Void
    let aoAbrirDiagnostico: () -> Void
    let aoAbrirTermos: () -> Void
    let aoFechar: () -> Void

    @State private var topico: Topico = .aparencia
    @State private var avisoPrivacidade = ""

    /// Mensagem mostrada depois de tocar em "Procurar atualização da lista".
    @State private var mensagemLista = ""
    /// Verdadeiro enquanto o app consulta o GitHub.
    @State private var verificando = false
    /// Lista baixada e pronta para ser aplicada, depois da confirmação.
    @State private var listaNova: ListaBaixada? = nil
    /// Controla o aviso de confirmação antes de trocar a lista.
    @State private var confirmarAtualizacao = false

    @State private var versaoApp: VersaoPublicada? = nil
    @State private var verificandoApp = false
    @State private var mensagemApp = ""
    @State private var confirmarApp = false

    private var versao: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Data do aceite dos termos, em formato de leitura. Vazia se ainda não aceitou.
    private var dataAceiteTexto: String {
        guard let data = ISO8601DateFormatter().date(from: dataAceite) else { return "" }
        return data.formatted(date: .numeric, time: .omitted)
    }

    /// Data da lista que o motor está usando agora, em formato de leitura.
    private var dataListaTexto: String {
        let iso = Engine.dataEmUso
        return iso.isEmpty ? "Desconhecida" : formatarData(iso)
    }

    var body: some View {
        PainelVidro(titulo: "Ajustes", fundoEscuro: fundoEscuro, aoFechar: aoFechar) {
            VStack(spacing: 0) {
                abasDeTopicos
                ScrollView {
                    VStack(spacing: 12) {
                        conteudo
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
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
        .alert("Atualizar o Nusky?", isPresented: $confirmarApp) {
            Button("Cancelar", role: .cancel) {}
            Button("Atualizar") {
                Task { await atualizarApp() }
            }
        } message: {
            Text("O TrollStore vai instalar a nova versão por cima desta, e a lista de sites é atualizada junto. Favoritos, histórico e ajustes continuam no aparelho.")
        }
    }

    // MARK: - Estrutura

    private var abasDeTopicos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Topico.allCases) { t in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { topico = t }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.icone)
                                .font(.system(size: 13, weight: .semibold))
                            Text(t.rawValue)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .opacity(topico == t ? 1 : 0.6)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(EstiloToque(forma: .capsula))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        switch topico {
        case .aparencia: topicoAparencia
        case .toque: topicoToque
        case .navegacao: topicoNavegacao
        case .privacidade: topicoPrivacidade
        case .sobre: topicoSobre
        }
    }

    // MARK: - Tópicos

    private var topicoAparencia: some View {
        VStack(spacing: 12) {
            cartao {
                linhaChave("Automático", detalhe: "Segue o modo claro ou escuro do iPhone.", valor: $automatico)
                divisor
                linhaChave("Modo noturno", detalhe: automatico ? "Desligue o automático para escolher." : nil, valor: $noturno)
                    .disabled(automatico)
                    .opacity(automatico ? 0.5 : 1)
            }
            cartao {
                linhaChave(
                    "Forçar modo noturno nos sites",
                    detalhe: "Escurece as páginas claras. Páginas que já são escuras não mudam.",
                    valor: $forcarNoturno,
                    desempenho: true
                )
            }
            cartao {
                linhaChave("Barra embaixo", detalhe: "Desligado: a barra fica em cima.", valor: $barraEmbaixo)
                divisor
                linhaChave(
                    "Efeito de desfoque",
                    detalhe: "Desligado: barras e menus ficam com fundo liso.",
                    valor: $desfoque,
                    desempenho: true
                )
            }
        }
    }

    private var topicoToque: some View {
        VStack(spacing: 12) {
            cartao {
                linhaChave(
                    "Feedback luminoso",
                    detalhe: "Um brilho nasce onde você toca e se espalha pelo botão, enfraquecendo até sumir.",
                    valor: $feedbackLuminoso,
                    desempenho: true
                )
                divisor
                linhaChave(
                    "Feedback expansivo",
                    detalhe: "O botão pulsa e volta ao normal.",
                    valor: $feedbackExpansivo,
                    desempenho: true
                )
                divisor
                linhaChave("Feedback tátil", detalhe: "Vibração a cada toque.", valor: $feedbackTatil)
            }

            cartao {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Intensidade")
                        .font(.system(size: 17))
                    HStack(spacing: 8) {
                        ForEach(PadraoFeedback.allCases) { nivel in
                            Button {
                                padraoBruto = nivel.rawValue
                            } label: {
                                Text(nivel.nome)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .opacity(padraoBruto == nivel.rawValue ? 1 : 0.55)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(EstiloToque(forma: .capsula))
                        }
                    }
                    Text("A intensidade vale para os três efeitos ao mesmo tempo. Extravagante é bem forte e dura mais; Leve é rápido e discreto.")
                        .font(.system(size: 13))
                        .opacity(0.6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private var topicoNavegacao: some View {
        VStack(spacing: 12) {
            cartao {
                linhaChave(
                    "Solicitar versão desktop",
                    detalhe: "Ao fechar os ajustes, a página recarrega se a opção mudou.",
                    valor: $versaoDesktop
                )
            }
            cartao {
                linhaChave(
                    "Mostrar imagens",
                    detalhe: "Desligado: a página abre sem imagens e gasta menos dados e memória.",
                    valor: $imagensLigadas,
                    desempenho: true
                )
                divisor
                linhaChave(
                    "Executar JavaScript",
                    detalhe: "Necessário em sites que montam a página no aparelho. O limite é de 6 segundos.",
                    valor: $javascriptLigado,
                    desempenho: true
                )
            }
            cartao {
                linhaChave(
                    "Metal (desenho na GPU)",
                    detalhe: "O texto, as imagens e os ícones viram texturas na GPU, e rolar a página não redesenha nada pela CPU. Se o aparelho não aceitar, o desenho normal continua.",
                    valor: $usarMetal,
                    ajuda: true
                )
            }
        }
    }

    private var topicoPrivacidade: some View {
        VStack(spacing: 12) {
            cartao {
                botaoLinha("Limpar histórico de visitas", icone: "clock.arrow.circlepath") {
                    Biblioteca.compartilhada.limparVisitas()
                    avisoPrivacidade = "Histórico de visitas apagado."
                }
                divisor
                botaoLinha("Limpar cookies e cache", icone: "trash") {
                    HTTPCookieStorage.shared.removeCookies(since: Date(timeIntervalSince1970: 0))
                    URLCache.shared.removeAllCachedResponses()
                    ArmazemImagens.compartilhado.limpar()
                    avisoPrivacidade = "Cookies, cache e imagens guardadas foram apagados."
                }
            }
            if !avisoPrivacidade.isEmpty {
                rodape(avisoPrivacidade)
            }
            rodape("Histórico, favoritos, pesquisas, cookies e sessões ficam só neste aparelho. Nada é enviado a ninguém.")
        }
    }

    private var topicoSobre: some View {
        VStack(spacing: 12) {
            cartao {
                linhaInfo("Versão do app", versao)
                divisor
                linhaInfo("Licença", "MPL-2.0")
                divisor
                botaoLinha("Repositório do projeto", icone: "chevron.left.forwardslash.chevron.right") {
                    aoAbrirURL(AtualizadorApp.repositorio)
                }
            }

            cartao {
                linhaInfo("Lista de sites", "Versão \(Engine.versaoEmUso)")
                divisor
                linhaInfo("Data da lista", dataListaTexto)
                divisor
                botaoLinha(verificando ? "Verificando…" : "Atualizar só a lista de sites", icone: "arrow.triangle.2.circlepath") {
                    Task { await verificarAtualizacao() }
                }
                .disabled(verificando)
                if let nova = listaNova {
                    divisor
                    linhaInfo("Disponível", "Versão \(nova.versao), de \(nova.dataTexto)")
                    divisor
                    botaoLinha("Aplicar a nova lista", icone: "square.and.arrow.down") {
                        confirmarAtualizacao = true
                    }
                }
            }
            if !mensagemLista.isEmpty {
                rodape(mensagemLista)
            }

            cartao {
                botaoLinha(verificandoApp ? "Verificando…" : "Atualizar o app (inclui a lista)", icone: "arrow.down.app") {
                    Task { await verificarApp() }
                }
                .disabled(verificandoApp)
                if let nova = versaoApp {
                    divisor
                    linhaInfo("Disponível", "Versão \(nova.versao)")
                    divisor
                    botaoLinha("Instalar com o TrollStore", icone: "square.and.arrow.down") {
                        confirmarApp = true
                    }
                }
            }
            if !mensagemApp.isEmpty {
                rodape(mensagemApp)
            }
            rodape("Nada é verificado em segundo plano: só quando você toca. Atualizar o app também atualiza a lista de sites.")

            cartao {
                botaoLinha("Analisar a página atual", icone: "waveform.path.ecg") {
                    aoAbrirDiagnostico()
                }
                .disabled(!temPagina)
                .opacity(temPagina ? 1 : 0.5)
                divisor
                botaoLinha("Termos de uso", icone: "doc.text") {
                    aoAbrirTermos()
                }
            }
            if dataAceiteTexto.isEmpty {
                rodape("Versão dos termos: \(versaoDosTermos).")
            } else {
                rodape("Versão dos termos: \(versaoDosTermos). Aceitos em \(dataAceiteTexto).")
            }
        }
    }

    // MARK: - Peças

    private func cartao<Conteudo: View>(@ViewBuilder _ conteudo: () -> Conteudo) -> some View {
        VStack(spacing: 0) {
            conteudo()
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.09)))
        .shadow(color: fundoEscuro ? Color.white.opacity(0.08) : Color.black.opacity(0.1), radius: 6, x: 0, y: 2)
    }

    private var divisor: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func linhaChave(
        _ titulo: String,
        detalhe: String?,
        valor: Binding<Bool>,
        desempenho: Bool = false,
        ajuda: Bool = false
    ) -> some View {
        Toggle(isOn: valor) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(titulo)
                        .font(.system(size: 17))
                    if desempenho || ajuda {
                        EtiquetaDesempenho(ajuda: ajuda)
                    }
                }
                if let detalhe {
                    Text(detalhe)
                        .font(.system(size: 13))
                        .opacity(0.6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func linhaInfo(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo)
                .font(.system(size: 17))
            Spacer()
            Text(valor)
                .font(.system(size: 17))
                .opacity(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func botaoLinha(_ titulo: String, icone: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 12) {
                Image(systemName: icone)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                Text(titulo)
                    .font(.system(size: 17))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.35)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloToque(forma: .retangulo(18), comFundo: false))
    }

    private func rodape(_ texto: String) -> some View {
        Text(texto)
            .font(.system(size: 13))
            .opacity(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }

    // MARK: - Atualização do app

    /// Consulta a última versão publicada no GitHub. Não instala nada.
    private func verificarApp() async {
        verificandoApp = true
        mensagemApp = ""
        versaoApp = nil
        defer { verificandoApp = false }
        do {
            let publicada = try await AtualizadorApp.buscar()
            if AtualizadorApp.ehMaisNova(publicada.versao, que: versao) {
                versaoApp = publicada
            } else {
                mensagemApp = "Você já tem a versão mais recente (\(versao))."
            }
        } catch ErroAtualizacao.semPublicacao {
            mensagemApp = "Ainda não há uma versão publicada no GitHub."
        } catch ErroAtualizacao.semIPA {
            mensagemApp = "A versão publicada não traz o arquivo de instalação (.ipa)."
        } catch {
            mensagemApp = mensagemFalha
        }
    }

    /// Atualiza a lista de sites e entrega o novo app ao TrollStore.
    private func atualizarApp() async {
        guard let nova = versaoApp else { return }
        await verificarAtualizacao()
        if listaNova != nil {
            await aplicarAtualizacao()
        }
        AtualizadorApp.instalar(nova)
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
                mensagemLista = "Você já tem a lista mais recente (versão \(Engine.versaoEmUso))."
                return
            }
            guard http.statusCode == 200 else {
                mensagemLista = mensagemFalha
                return
            }

            let cabecalho = try await Task.detached(priority: .utility) {
                try JSONDecoder().decode(Cabecalho.self, from: dados)
            }.value

            guard cabecalho.versao > Engine.versaoEmUso else {
                mensagemLista = "Você já tem a lista mais recente (versão \(Engine.versaoEmUso))."
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
    /// Se não conseguir salvar no aparelho, volta a carregar a lista anterior.
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
            // Sem salvar, a lista nova não pode ficar só na memória: recarrega a anterior.
            _ = await Task.detached(priority: .utility) {
                Engine.iniciarBusca()
            }.value
            listaNova = nil
            mensagemLista = "Não consegui salvar a lista no aparelho. A lista atual foi mantida. Tente de novo."
            return
        }

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