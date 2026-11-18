import SwiftUI
import UIKit

@MainActor
final class BrowserModel: ObservableObject {
    @Published var address = ""
    @Published var currentHost = ""
    @Published var items: [DrawItem] = []
    /// Caixas de fundo da página (cores, bordas e cantos arredondados).
    @Published var fundos: [Fundo] = []
    /// Cor de fundo da página, quando ela define uma.
    @Published var fundoPagina: CorTexto? = nil
    /// Imagens da página, com a posição já calculada.
    @Published var imagens: [ImagemPagina] = []
    /// Formas de SVG da página (ícones, logotipos).
    @Published var formas: [FormaVetor] = []
    @Published var contentHeight: CGFloat = 0
    @Published var status = ""
    @Published var pageVersion = 0
    @Published var restoreY: CGFloat = 0
    /// Verdadeiro desde o início do carregamento até a página aparecer na tela.
    @Published var carregando = false
    /// Progresso de 0 a 1 do carregamento atual.
    @Published var progresso: Double = 0
    /// Resultados da última busca por nome, do mais relevante para o menos.
    @Published var resultados: [ResultadoBusca] = []
    /// Site parecido com o que foi digitado, quando a busca não acha nada.
    @Published var sugestao: SugestaoBusca?

    let historico = Historico()

    /// O que o JavaScript fez na última página (nil se não rodou). Para o diagnóstico.
    private(set) var ultimoRelatorioJS: JSRodador.Relatorio?

    private(set) var currentURL: URL?
    /// Id da entrada que está realmente na tela. Muda só quando a página é exibida.
    private var exibidaId: UUID?
    /// Não é @Published: muda a cada quadro de rolagem e não deve redesenhar a tela.
    var scrollY: CGFloat = 0

    private var task: Task<Void, Never>?
    private var started = false

    /// JavaScript que continua vivo depois da primeira exibição: cliques, temporizadores e rede.
    private var sessaoViva: JSRodador?
    /// Última versão do HTML vinda da sessão viva, esperando o desenho (só a mais nova importa).
    private var htmlVivoPendente: String?
    private var atualizandoVivo = false
    /// Bloco <style> com o CSS externo da página atual. O JavaScript roda sem ele, e ele entra na hora de desenhar.
    private var cssDaPagina = ""

    // Imagens: o HTML fica guardado para refazer o layout quando o tamanho de uma imagem é descoberto.
    private var htmlAtual = ""
    private var tamanhosImagens: [String: CGSize] = [:]
    private var geracao = 0
    private var tarefaImagens: Task<Void, Never>?

    /// Chave dos ajustes. Se nunca foi gravada, as imagens ficam ligadas.
    static let chaveImagens = "mostrarImagens"
    static var imagensAtivas: Bool {
        UserDefaults.standard.object(forKey: chaveImagens) as? Bool ?? true
    }
    private let textWidth = UIScreen.main.bounds.width

    // MARK: Ciclo de vida

    /// Chamado ao abrir o app: restaura a sessão, ou abre a página inicial na primeira vez.
    func start() {
        guard !started else { return }
        started = true
        // Carrega a lista de sites fora da thread principal, para não atrasar a primeira tela.
        Task.detached(priority: .utility) { _ = Engine.iniciarBusca() }
        if historico.sessaoNova {
            open(url: URL(string: "https://example.com")!)
        } else {
            mostrarAtual()
        }
    }

    /// Chamado ao ir para o segundo plano.
    func saveSession() {
        saveScroll()
        historico.salvar()
    }

    // MARK: Entrada do usuário

    /// Chamado ao confirmar o campo de endereço. Decide se é endereço ou nome para buscar.
    func submitAddress() {
        let texto = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        if pareceEndereco(texto) {
            abrirEndereco(texto)
        } else {
            buscarPorNome(texto)
        }
    }

    /// Busca um site pelo nome na lista embutida e abre o melhor resultado.
    /// Se nada casar, mostra a mensagem e uma sugestão, sem abrir nada.
    func buscarPorNome(_ consulta: String) {
        let achados = Engine.buscar(consulta)
        resultados = achados

        guard let melhor = achados.first else {
            sugestao = Engine.sugestao(para: consulta)
            if let s = sugestao {
                status = "Não encontrei \"\(consulta)\". Você quis dizer \(s.nome)?"
            } else {
                status = "Não encontrei \"\(consulta)\"."
            }
            return
        }

        sugestao = nil
        abrirBusca(melhor.endereco)
    }

    /// Abre a sugestão mostrada quando a busca não acha nada.
    func abrirSugestao() {
        guard let s = sugestao else { return }
        sugestao = nil
        abrirBusca(s.endereco)
    }

    /// Link tocado na página. Resolve relativos pela URL final da página atual.
    func open(href: String) {
        if href.hasPrefix(BrowserModel.prefixoToqueJS) {
            tocarJS(href)
            return
        }
        guard let base = currentURL,
              let url = URL(string: codificarEndereco(href), relativeTo: base)?.absoluteURL,
              let esquema = url.scheme?.lowercased(),
              esquema == "http" || esquema == "https" else { return }
        open(url: url)
    }

    /// Abre uma página nova na aba atual.
    func open(url: URL) {
        saveScroll()
        task?.cancel()
        task = Task { await self.carregar(url, entradaId: nil, restoreY: 0, navegar: true) }
    }

    // MARK: Navegação

    func goBack() {
        saveScroll()
        guard let entrada = historico.voltar() else { return }
        mostrarEntrada(entrada)
    }

    func goForward() {
        saveScroll()
        guard let entrada = historico.avancar() else { return }
        mostrarEntrada(entrada)
    }

    func reload() {
        guard let url = currentURL else { return }
        let y = scrollY
        task?.cancel()
        task = Task { await self.carregar(url, entradaId: self.exibidaId, restoreY: y, navegar: false) }
    }

    // MARK: Abas

    func novaAba() {
        saveScroll()
        historico.novaAba()
        mostrarAtual()
    }

    func selecionarAba(_ id: UUID) {
        guard id != historico.abaAtual.id else { return }
        saveScroll()
        historico.trocarAba(id)
        mostrarAtual()
    }

    func fecharAbas(_ ids: Set<UUID>) {
        let ativaAntes = historico.abaAtual.id
        saveScroll()
        historico.fecharAbas(ids)
        if ids.contains(ativaAntes) {
            mostrarAtual()
        }
    }

    // MARK: Endereço e busca

    /// Endereço se tiver "://" ou um ponto sem espaço (ex.: github.com). Caso contrário, é nome para buscar.
    private func pareceEndereco(_ texto: String) -> Bool {
        if texto.contains("://") { return true }
        if texto.contains(where: { $0.isWhitespace }) { return false }
        let partes = texto.split(separator: ".", omittingEmptySubsequences: false)
        return partes.count >= 2
            && partes.allSatisfy { !$0.isEmpty }
            && (partes.last?.count ?? 0) >= 2
    }

    private func abrirEndereco(_ texto: String) {
        let completo = texto.contains("://") ? texto : "https://" + texto
        guard let url = URL(string: codificarEndereco(completo)), url.host != nil else {
            status = "Endereço inválido."
            return
        }
        open(url: url)
    }

    /// Abre um site ou atalho encontrado pela busca. Conta a abertura, que fica só no aparelho.
    private func abrirBusca(_ endereco: String) {
        guard let url = URL(string: endereco) else { return }
        status = ""
        Engine.registrarUso(endereco: endereco)
        open(url: url)
    }

    // MARK: Internos

    /// Codifica só o que a URL não aceita (acentos, espaços).
    /// Mantém % e # como estão, para não codificar duas vezes o que já está codificado.
    private func codificarEndereco(_ texto: String) -> String {
        let permitidos = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%#"))
        return texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? texto
    }

    private func mostrarAtual() {
        if let entrada = historico.entradaAtual {
            mostrarEntrada(entrada)
        } else {
            limparPagina()
        }
    }

    /// Mostra uma entrada já existente: baixa de novo, porque a página fria não guarda HTML.
    private func mostrarEntrada(_ entrada: Entrada) {
        guard let url = URL(string: entrada.url) else { return }
        task?.cancel()
        task = Task {
            await self.carregar(url, entradaId: entrada.id, restoreY: CGFloat(entrada.rolagem), navegar: false)
        }
    }

    private func limparPagina() {
        task?.cancel()
        encerrarSessaoViva()
        items = []
        fundos = []
        fundoPagina = nil
        contentHeight = 0
        currentURL = nil
        currentHost = ""
        address = ""
        status = "Digite um endereço acima."
        carregando = false
        progresso = 0
        exibidaId = nil
        scrollY = 0
        restoreY = 0
        pageVersion += 1
    }

    /// Esvazia a tela e mostra o início do carregamento.
    private func iniciarCarregamento() {
        encerrarSessaoViva()
        tarefaImagens?.cancel()
        geracao += 1
        status = ""
        items = []
        fundos = []
        imagens = []
        formas = []
        fundoPagina = nil
        contentHeight = 0
        carregando = true
        progresso = 0.05
    }

    private func carregar(_ url: URL, entradaId: UUID?, restoreY y: CGFloat, navegar: Bool) async {
        iniciarCarregamento()
        let inicio = CFAbsoluteTimeGetCurrent()
        var etapas: [(String, Double)] = []
        func marcar(_ nome: String, desde: CFAbsoluteTime) {
            etapas.append((nome, (CFAbsoluteTimeGetCurrent() - desde) * 1000))
        }
        do {
            let (html, finalURL) = try await download(url)
            guard !Task.isCancelled else { return }
            marcar("HTML", desde: inicio)
            progresso = 0.9

            // Três coisas começam ao mesmo tempo, porque nenhuma depende da outra: baixar o CSS externo,
            // rodar o JavaScript e (quando o CSS chega) desenhar a página.
            let inicioCSS = CFAbsoluteTimeGetCurrent()
            async let estiloExterno = FolhasExternas.bloco(em: html, base: finalURL)
            let largura = Int(textWidth)
            let escuro = Aparencia.sitesEmModoEscuro()
            var tarefaJS: Task<JSRodador.Saida, Never>?
            if JSRodador.vaiRodar(html) {
                // Qualquer falha devolve o HTML original, então a página sempre abre.
                tarefaJS = Task {
                    await JSRodador.processar(html: html, pagina: finalURL, largura: largura, escuro: escuro)
                }
            }
            let inicioJS = CFAbsoluteTimeGetCurrent()

            let estilo = await estiloExterno
            marcar("CSS", desde: inicioCSS)
            guard !Task.isCancelled else {
                abandonar(tarefaJS)
                return
            }
            cssDaPagina = estilo
            let minhaGeracao = geracao
            var id = entradaId
            if navegar {
                historico.navegar(para: finalURL)
                Biblioteca.compartilhada.registrarVisita(finalURL)
                id = historico.entradaAtual?.id
            }

            // 1ª pintura: o HTML que o servidor mandou, com o CSS, sem esperar o JavaScript.
            // Páginas que já vêm prontas (a maioria dos sites de notícia) aparecem aqui; as que dependem do
            // JavaScript ganham o conteúdo na 2ª pintura, sem perder a posição da rolagem.
            progresso = 0.95
            let inicioPintura = CFAbsoluteTimeGetCurrent()
            await show(html: estilo + html, url: finalURL, entradaId: id, restoreY: y)
            marcar("1ª pintura", desde: inicioPintura)
            guard !Task.isCancelled, minhaGeracao == geracao else {
                abandonar(tarefaJS)
                return
            }

            if let tarefaJS {
                let rodado = await tarefaJS.value
                marcar("JavaScript", desde: inicioJS)
                ultimoRelatorioJS = rodado.relatorio
                guard !Task.isCancelled, minhaGeracao == geracao else {
                    rodado.sessao?.fechar()
                    return
                }
                if rodado.html != html {
                    let inicioTroca = CFAbsoluteTimeGetCurrent()
                    await trocarPelaVersaoDoJS(rodado.html, geracao: minhaGeracao)
                    marcar("2ª pintura", desde: inicioTroca)
                }
                anexarSessaoViva(rodado.sessao, geracao: minhaGeracao)
            }
            Desempenho.compartilhado.registrarCarregamento(host: finalURL.host ?? "", etapas: etapas)
        } catch {
            guard !Task.isCancelled else { return }
            carregando = false
            progresso = 0
            status = "Não foi possível abrir a página."
        }
    }

    /// O JavaScript já estava rodando quando o usuário saiu da página: fecha a sessão que ele acabar devolvendo.
    private func abandonar(_ tarefa: Task<JSRodador.Saida, Never>?) {
        guard let tarefa else { return }
        Task { await tarefa.value.sessao?.fechar() }
    }

    /// A 2ª pintura: troca o HTML do servidor pelo que o JavaScript montou, mantendo a rolagem.
    private func trocarPelaVersaoDoJS(_ html: String, geracao g: Int) async {
        htmlVivoPendente = html
        guard !atualizandoVivo else { return }
        atualizandoVivo = true
        await desenharVivo(geracao: g)
    }

    private func saveScroll() {
        // Com a tela esvaziada, a rolagem atual não vale: não sobrescreve a salva.
        guard !carregando, let id = exibidaId else { return }
        historico.atualizarRolagem(Double(scrollY), entradaId: id)
    }

    private func download(_ url: URL) async throws -> (String, URL) {
        let baixador = DownloadPagina { [weak self] fracao in
            Task { @MainActor in
                guard let self, self.carregando else { return }
                self.progresso = 0.05 + fracao * 0.85
            }
        }
        let (data, response) = try await baixador.baixar(url)
        return (String(decoding: data, as: UTF8.self), response.url ?? url)
    }

    /// Gera os itens de desenho fora da thread principal e atualiza a tela.
    private func show(html: String, url: URL, entradaId: UUID?, restoreY y: CGFloat) async {
        htmlAtual = html
        tamanhosImagens = [:]
        let desenhada = await desenhar(html)
        guard !Task.isCancelled else { return }

        aplicar(desenhada)
        currentURL = url
        currentHost = url.host ?? ""
        address = url.absoluteString
        status = ""
        exibidaId = entradaId
        scrollY = y
        restoreY = y
        carregando = false
        progresso = 0
        pageVersion += 1
        iniciarImagens(desenhada.imagens, base: url, geracao: geracao)
    }

    // MARK: JavaScript vivo

    /// Os elementos que o JavaScript escuta chegam do motor como `nusky-js:<id>|<link de reserva>`.
    private static let prefixoToqueJS = "nusky-js:"

    private func encerrarSessaoViva() {
        sessaoViva?.fechar()
        sessaoViva = nil
        htmlVivoPendente = nil
    }

    private func anexarSessaoViva(_ sessao: JSRodador?, geracao g: Int) {
        guard let sessao else { return }
        sessaoViva = sessao
        sessao.aoEncerrar = { [weak self] in
            Task { @MainActor in
                // Só solta se ainda for a sessão desta página.
                if self?.sessaoViva === sessao { self?.sessaoViva = nil }
            }
        }
        sessao.ligar { [weak self] html in
            Task { @MainActor in self?.receberHTMLVivo(html, geracao: g) }
        }
    }

    /// O JavaScript mudou a página. Se o desenho anterior ainda não acabou, só a versão mais nova vale.
    private func receberHTMLVivo(_ html: String, geracao g: Int) {
        guard g == geracao, sessaoViva != nil else { return }
        htmlVivoPendente = html
        guard !atualizandoVivo else { return }
        atualizandoVivo = true
        Task { await self.desenharVivo(geracao: g) }
    }

    private func desenharVivo(geracao g: Int) async {
        defer { atualizandoVivo = false }
        while let html = htmlVivoPendente {
            htmlVivoPendente = nil
            guard g == geracao, !carregando, let url = currentURL else { return }
            let completo = cssDaPagina + html
            if completo == htmlAtual { continue }
            htmlAtual = completo
            let inicio = CFAbsoluteTimeGetCurrent()
            let desenhada = await desenhar(completo)
            guard g == geracao, !Task.isCancelled else { return }
            // Mantém a rolagem onde o dedo estava.
            restoreY = scrollY
            aplicar(desenhada)
            iniciarImagens(desenhada.imagens, base: url, geracao: g)
            // A cadência do JavaScript acompanha o custo real de desenhar esta página.
            sessaoViva?.informarCusto(CFAbsoluteTimeGetCurrent() - inicio)
        }
    }

    /// Toque numa área que o JavaScript escuta. Sem sessão viva, cai no link de reserva (se houver).
    private func tocarJS(_ carga: String) {
        let resto = carga.dropFirst(BrowserModel.prefixoToqueJS.count)
        let partes = resto.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let id = partes.first.flatMap({ Int($0) }) else { return }
        let reserva = partes.count > 1 ? String(partes[1]) : ""
        guard let sessao = sessaoViva else {
            if !reserva.isEmpty { open(href: reserva) }
            return
        }
        let g = geracao
        Task {
            let resposta = await sessao.tocar(id: id)
            guard g == self.geracao else { return }
            switch resposta {
            case .navegar(let destino): self.open(href: destino)
            case .tratado: break
            case .perdido: if !reserva.isEmpty { self.open(href: reserva) }
            }
        }
    }

    // MARK: Desenho e imagens

    /// Gera o desenho fora da thread principal, sabendo o tamanho das imagens já baixadas.
    private func desenhar(_ html: String) async -> PaginaDesenhada {
        let width = Float(textWidth)
        let tamanhos = tamanhosImagens
    Apresentacao.sublinharLinks = !Apresentacao.paginaTemCSS(html)
        // `prefers-color-scheme` das folhas de estilo responde o mesmo que o `matchMedia` do JavaScript.
        Engine.definirEscuro(Aparencia.sitesEmModoEscuro())
        return await Task.detached(priority: .userInitiated) {
            let inicio = CACurrentMediaTime()
            let pagina = Engine.renderCompleto(html: html, width: width, tamanhos: tamanhos)
            Desempenho.compartilhado.registrarLayout((CACurrentMediaTime() - inicio) * 1000)
            return pagina
        }.value
    }

    private func aplicar(_ original: PaginaDesenhada) {
        // "Forçar modo noturno": escurece páginas claras. Páginas que já são escuras não mudam.
        var desenhada = original
        if UserDefaults.standard.bool(forKey: ChavesTema.forcarNoturno) {
            desenhada = ModoNoturnoForcado.aplicar(original)
        }
        let novosItens = desenhada.itens
        items = novosItens
        fundos = desenhada.fundos
        imagens = desenhada.imagens
        formas = desenhada.formas
        fundoPagina = desenhada.fundoPagina
        let fimTexto = novosItens.map { CGFloat($0.y) + CGFloat($0.fontSize) }.max() ?? 0
        let fimFundos = desenhada.fundos.map { $0.y + $0.h }.max() ?? 0
        let fimImagens = desenhada.imagens.map { $0.y + $0.h }.max() ?? 0
        Desempenho.compartilhado.conteudo = (
            desenhada.itens.count, desenhada.fundos.count, desenhada.imagens.count, desenhada.formas.count
        )
        let fimFormas = desenhada.formas.map { $0.caixa.maxY }.max() ?? 0
        contentHeight = max(max(fimTexto, fimFundos), max(fimImagens, fimFormas)) + 80
    }

    /// Baixa as imagens da página aos poucos (6 por vez, no máximo 60). A cada lote, se algum
    /// tamanho foi descoberto, o layout é refeito para abrir espaço para elas.
    private func iniciarImagens(_ lista: [ImagemPagina], base: URL, geracao g: Int) {
        guard BrowserModel.imagensAtivas else { return }
        var vistos = Set<String>()
        var pendentes: [String] = []
        for imagem in lista where tamanhosImagens[imagem.src] == nil && vistos.insert(imagem.src).inserted {
            pendentes.append(imagem.src)
        }
        guard !pendentes.isEmpty else { return }
        pendentes = Array(pendentes.prefix(60))

        tarefaImagens?.cancel()
        tarefaImagens = Task { [weak self] in
            var fila = pendentes
            while !fila.isEmpty {
                let lote = Array(fila.prefix(6))
                fila.removeFirst(lote.count)
                let resultados = await withTaskGroup(of: (String, CGSize?).self) { grupo -> [(String, CGSize?)] in
                    for src in lote {
                        grupo.addTask {
                            guard let url = resolverEnderecoDeImagem(src, base: base) else { return (src, nil) }
                            return (src, await ArmazemImagens.compartilhado.carregar(endereco: url))
                        }
                    }
                    var saida: [(String, CGSize?)] = []
                    for await r in grupo { saida.append(r) }
                    return saida
                }
                guard let self, !Task.isCancelled, self.geracao == g else { return }
                var descobriu = false
                for (src, tamanho) in resultados {
                    // Imagem que falhou fica com 0 x 0 para não ser tentada de novo.
                    self.tamanhosImagens[src] = tamanho ?? .zero
                    if tamanho != nil { descobriu = true }
                }
                if descobriu { await self.redesenharComImagens(geracao: g) }
            }
        }
    }

    /// Refaz o layout da mesma página com os tamanhos novos, sem mexer na posição de rolagem.
    private func redesenharComImagens(geracao g: Int) async {
        let desenhada = await desenhar(htmlAtual)
        guard g == geracao, !Task.isCancelled else { return }
        restoreY = scrollY
        aplicar(desenhada)
    }
}