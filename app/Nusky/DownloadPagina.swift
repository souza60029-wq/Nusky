import Foundation

/// Identificação que o Nusky envia ao servidor ao baixar uma página.
/// Os sites escolhem a versão (mobile ou desktop) por este texto.
enum IdentificacaoNavegador {
    /// Chave dos ajustes. Ligada = pede a versão desktop.
    static let chaveDesktop = "solicitarVersaoDesktop"

    static let mobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_8_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1"

    static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// iPhone com iOS 17, para os perfis de site que precisam dizer que o aparelho é mais novo.
    static let mobileIOS17 = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// Identificação a usar agora, conforme o ajuste.
    static var atual: String {
        UserDefaults.standard.bool(forKey: chaveDesktop) ? desktop : mobile
    }
}

/// Baixa uma página e informa o progresso (0 a 1) conforme os bytes chegam.
/// Usa a sessão compartilhada (conexão reaproveitada) e entrega os pedaços por delegate, não por
/// leitura byte a byte, que é lenta no iPhone 6s.
final class DownloadPagina: @unchecked Sendable {
    private let aoProgredir: @Sendable (Double) -> Void
    private var dados = Data()
    private var resposta: URLResponse?
    private var esperado: Int64 = 0
    private var ultimoAviso: Double = -1
    private var continuacao: CheckedContinuation<(Data, URLResponse), Error>?
    private var tarefa: URLSessionDataTask?

    init(aoProgredir: @escaping @Sendable (Double) -> Void) {
        self.aoProgredir = aoProgredir
    }

    func baixar(_ url: URL) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, URLResponse), Error>) in
                self.continuacao = cont
                var pedido = URLRequest(url: url)
                pedido.setValue(PerfisDeSite.agente(para: url.host), forHTTPHeaderField: "User-Agent")
                let nova = RedeNusky.sessao.dataTask(with: pedido)
                // A página que o usuário pediu passa na frente de qualquer outra coisa.
                nova.priority = URLSessionTask.highPriority
                self.tarefa = nova
                RedeNusky.roteador.registrar(nova, self)
                nova.resume()
            }
        } onCancel: {
            // Saiu da página antes de terminar: para de gastar banda com ela.
            self.tarefa?.cancel()
        }
    }

    func receber(resposta nova: URLResponse) {
        resposta = nova
        esperado = nova.expectedContentLength
    }

    func receber(dados novos: Data) {
        dados.append(novos)
        let fracao: Double
        if esperado > 0 {
            fracao = min(1, Double(dados.count) / Double(esperado))
        } else {
            // O servidor não informou o tamanho: estima com uma curva que sobe devagar.
            fracao = Double(dados.count) / (Double(dados.count) + 100_000)
        }
        // Avisa a cada 2%, para não redesenhar a tela a cada pacote.
        if fracao - ultimoAviso >= 0.02 || fracao >= 1 {
            ultimoAviso = fracao
            aoProgredir(fracao)
        }
    }

    func concluir(erro: Error?) {
        if let erro {
            continuacao?.resume(throwing: erro)
        } else if let resposta {
            continuacao?.resume(returning: (dados, resposta))
        } else {
            continuacao?.resume(throwing: URLError(.badServerResponse))
        }
        continuacao = nil
        tarefa = nil
    }
}
