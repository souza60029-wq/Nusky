// app/Nusky/RedeNusky.swift
import Foundation

/// Uma única sessão de rede para a página, o CSS e os scripts (as imagens têm a delas, com cache próprio).
///
/// Antes, cada navegação criava uma sessão nova e a jogava fora: cada página refazia DNS, TCP e TLS do zero,
/// e nem o HTML, nem o CSS, nem os scripts do mesmo site dividiam uma conexão. Com uma sessão só, a conexão
/// HTTP/2 fica aberta (vários arquivos do mesmo site viajam nela) e o cache em disco guarda bibliotecas
/// (jQuery, React, fontes de ícones) que voltam em outras páginas sem baixar de novo.
enum RedeNusky {
    static let roteador = RoteadorDeRede()

    static let sessao: URLSession = {
        let config = URLSessionConfiguration.default
        // Pouca RAM no iPhone 6s: o cache vive principalmente em disco.
        config.urlCache = URLCache(memoryCapacity: 6 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config, delegate: roteador, delegateQueue: nil)
    }()
}

/// Entrega o progresso e a resposta de cada download de página a quem o pediu.
/// Pedidos feitos com bloco de conclusão (scripts, CSS) não passam por aqui.
final class RoteadorDeRede: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let trava = NSLock()
    private var downloads: [Int: DownloadPagina] = [:]

    func registrar(_ tarefa: URLSessionTask, _ download: DownloadPagina) {
        trava.lock()
        downloads[tarefa.taskIdentifier] = download
        trava.unlock()
    }

    private func procurar(_ tarefa: URLSessionTask) -> DownloadPagina? {
        trava.lock()
        defer { trava.unlock() }
        return downloads[tarefa.taskIdentifier]
    }

    private func remover(_ tarefa: URLSessionTask) {
        trava.lock()
        downloads[tarefa.taskIdentifier] = nil
        trava.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        procurar(dataTask)?.receber(resposta: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        procurar(dataTask)?.receber(dados: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let download = procurar(task) else { return }
        remover(task)
        download.concluir(erro: error)
    }
}
