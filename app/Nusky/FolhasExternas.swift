import Foundation

/// Baixa as folhas de estilo externas (<link rel="stylesheet">) de uma página
/// e junta o conteúdo num bloco <style> colocado no início do HTML.
/// O motor já lê <style> de qualquer lugar do documento.
/// Folhas para impressão são ignoradas.
enum FolhasExternas {
    static let maximoFolhas = 8
    static let maximoBytesPorFolha = 400_000
    static let maximoBytesTotal = 1_000_000
    static let tempoLimite: TimeInterval = 8

    /// Devolve o HTML com o CSS externo no começo. Se nada for baixado, devolve o HTML igual.
    static func incluir(em html: String, base: URL) async -> String {
        let urls = encontrarFolhas(no: html, base: base)
        guard !urls.isEmpty else { return html }

        let textos = await baixarTodas(urls)
        var total = 0
        var partes: [String] = []
        for item in textos {
            guard let texto = item else { continue }
            let tamanho = texto.utf8.count
            if total + tamanho > maximoBytesTotal { break }
            total += tamanho
            partes.append(texto)
        }
        guard !partes.isEmpty else { return html }

        // Um "</style" dentro do CSS fecharia o bloco antes da hora.
        let css = partes
            .joined(separator: "\n")
            .replacingOccurrences(of: "</style", with: "", options: .caseInsensitive)
        return "<style>\(css)</style>" + html
    }

    /// Lista os endereços absolutos das folhas de estilo da página, sem repetir.
    static func encontrarFolhas(no html: String, base: URL) -> [URL] {
        guard let regexLink = try? NSRegularExpression(
            pattern: "<link\\b[^>]*>",
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        var urls: [URL] = []

        for m in regexLink.matches(in: html, range: range) {
            let tag = ns.substring(with: m.range)
            guard let rel = atributo("rel", em: tag),
                  rel.lowercased().contains("stylesheet"),
                  let hrefBruto = atributo("href", em: tag) else { continue }
            if let media = atributo("media", em: tag), media.lowercased().contains("print") {
                continue
            }

            let href = hrefBruto.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            guard url.scheme == "http" || url.scheme == "https" else { continue }

            if !urls.contains(url) {
                urls.append(url)
            }
            if urls.count >= maximoFolhas { break }
        }
        return urls
    }

    /// Lê o valor de um atributo dentro de uma tag, por exemplo href="...".
    static func atributo(_ nome: String, em tag: String) -> String? {
        let padrao = "\\b\(nome)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: padrao, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = tag as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: tag, range: range) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Baixa todas as folhas ao mesmo tempo. A resposta mantém a ordem da página.
    static func baixarTodas(_ urls: [URL]) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self) { grupo in
            for (indice, url) in urls.enumerated() {
                grupo.addTask { () async -> (Int, String?) in
                    let texto = await baixar(url)
                    return (indice, texto)
                }
            }
            var resultados = [String?](repeating: nil, count: urls.count)
            for await (indice, texto) in grupo {
                resultados[indice] = texto
            }
            return resultados
        }
    }

    /// Baixa uma folha. Devolve nil em caso de erro, status diferente de 2xx,
    /// tamanho acima do limite ou texto que não seja UTF-8.
    static func baixar(_ url: URL) async -> String? {
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = tempoLimite
        do {
            let (dados, resposta) = try await URLSession.shared.data(for: pedido)
            guard let http = resposta as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            guard dados.count <= maximoBytesPorFolha else { return nil }
            return String(data: dados, encoding: .utf8)
        } catch {
            return nil
        }
    }
}