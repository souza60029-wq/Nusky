import SwiftUI
import UIKit

@MainActor
final class BrowserModel: ObservableObject {
    @Published var address = ""
    @Published var currentHost = ""
    @Published var items: [DrawItem] = []
    @Published var contentHeight: CGFloat = 0
    @Published var status = ""
    @Published var pageVersion = 0
    @Published var restoreY: CGFloat = 0
    /// Verdadeiro desde o início do carregamento até a página aparecer na tela.
    @Published var carregando = false
    /// Progresso de 0 a 1 do carregamento atual.
    @Published var progresso: Double = 0

    let historico = Historico()

    private(set) var currentURL: URL?
    /// Id da entrada que está realmente na tela. Muda só quando a página é exibida.
    private var exibidaId: UUID?
    /// Não é @Published: muda a cada quadro de rolagem e não deve redesenhar a tela.
    var scrollY: CGFloat = 0

    private var task: Task<Void, Never>?
    private var started = false
    private let textWidth = UIScreen.main.bounds.width

    // MARK: Ciclo de vida

    /// Chamado ao abrir o app: restaura a sessão, ou abre a página inicial na primeira vez.
    func start() {
        guard !started else { return }
        started = true
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

    func submitAddress() {
        let texto = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        let completo = texto.contains("://") ? texto : "https://" + texto
        guard let url = URL(string: completo), url.host != nil else {
            status = "Endereço inválido."
            return
        }
        open(url: url)
    }

    /// Link tocado na página. Resolve relativos pela URL final da página atual.
    func open(href: String) {
        guard let base = currentURL,
              let url = URL(string: href, relativeTo: base)?.absoluteURL,
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

    // MARK: Internos

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
        items = []
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
        status = ""
        items = []
        contentHeight = 0
        carregando = true
        progresso = 0.05
    }

    private func carregar(_ url: URL, entradaId: UUID?, restoreY y: CGFloat, navegar: Bool) async {
        iniciarCarregamento()
        do {
            let (html, finalURL) = try await download(url)
            guard !Task.isCancelled else { return }
            var id = entradaId
            if navegar {
                historico.navegar(para: finalURL)
                id = historico.entradaAtual?.id
            }
            progresso = 0.9
            await show(html: html, url: finalURL, entradaId: id, restoreY: y)
        } catch {
            guard !Task.isCancelled else { return }
            carregando = false
            progresso = 0
            status = "Não foi possível abrir a página."
        }
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
        let width = Float(textWidth)
        let novosItens = await Task.detached(priority: .userInitiated) {
            Engine.render(html: html, width: width)
        }.value
        guard !Task.isCancelled else { return }

        items = novosItens
        contentHeight = (novosItens.map { CGFloat($0.y) + CGFloat($0.fontSize) }.max() ?? 0) + 80
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
    }
}