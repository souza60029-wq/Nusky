import Foundation

/// Baixa uma página e informa o progresso (0 a 1) conforme os bytes chegam.
/// Usa delegate, não leitura byte a byte, que é lenta no iPhone 6s.
final class DownloadPagina: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let aoProgredir: @Sendable (Double) -> Void
    private var dados = Data()
    private var resposta: URLResponse?
    private var esperado: Int64 = 0
    private var ultimoAviso: Double = -1
    private var continuacao: CheckedContinuation<(Data, URLResponse), Error>?
    private var sessao: URLSession?

    init(aoProgredir: @escaping @Sendable (Double) -> Void) {
        self.aoProgredir = aoProgredir
    }

    func baixar(_ url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, URLResponse), Error>) in
            self.continuacao = cont
            let sessao = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.sessao = sessao
            sessao.dataTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        resposta = response
        esperado = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dados.append(data)
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

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuacao?.resume(throwing: error)
        } else if let resposta {
            continuacao?.resume(returning: (dados, resposta))
        } else {
            continuacao?.resume(throwing: URLError(.badServerResponse))
        }
        continuacao = nil
        sessao?.finishTasksAndInvalidate()
        sessao = nil
    }
}