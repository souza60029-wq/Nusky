import Foundation

/// Baixa as folhas de estilo externas (<link rel="stylesheet">) de uma página
/// e junta o conteúdo num bloco <style> colocado no início do HTML.
/// O motor já lê <style> de qualquer lugar do documento.
///
/// Os limites antigos (8 folhas, 400 KB cada, 1 MB no total) cortavam o CSS de sites grandes: o GitHub manda mais de
/// 10 folhas e a principal passa de 400 KB, então a página chegava ao motor quase sem estilo (menu aberto, textos de
/// leitor de tela visíveis). Agora os limites são bem maiores, e o que não serve ao motor (comentários, @font-face,
/// @keyframes, @media print) sai antes de contar (`PodaCSS`).
///
/// Usa a mesma identificação do HTML (a do perfil do site, se houver), para que o CSS venha da mesma versão da página.
enum FolhasExternas {
    static let maximoFolhas = 40
    static let maximoBytesPorFolha = 3_000_000
    static let maximoBytesTotal = 6_000_000
    static let tempoLimite: TimeInterval = 10

    /// Resumo da última página (quantas folhas chegaram e quanto pesaram), para o relatório do Diagnóstico.
    static let ultimoResumo = ResumoCSS()

    /// Devolve o HTML com o CSS externo no começo. Se nada for baixado, devolve o HTML igual.
    static func incluir(em html: String, base: URL, largura: Int = 390, escuro: Bool = false) async -> String {
        let estilo = await bloco(em: html, base: base, largura: largura, escuro: escuro)
        return estilo.isEmpty ? html : estilo + html
    }

    /// Só o bloco <style> com o CSS externo (vazio se não houver). Separado para poder baixar o CSS
    /// ao mesmo tempo em que o JavaScript da página roda: um não depende do outro.
    static func bloco(em html: String, base: URL, largura: Int = 390, escuro: Bool = false) async -> String {
        let perfil = PerfisDeSite.para(host: base.host)
        let limiteFolhas = perfil?.maxFolhas ?? maximoFolhas
        let urls = encontrarFolhas(no: html, base: base, largura: largura, escuro: escuro, maximo: limiteFolhas)
        let extra = perfil?.css ?? ""
        guard !urls.isEmpty else {
            ultimoResumo.valor = "CSS: nenhuma folha externa"
            return extra.isEmpty ? "" : "<style>" + extra + "</style>"
        }

        let textos = await baixarTodas(urls, agente: PerfisDeSite.agente(para: base.host))
        var total = 0
        var partes: [String] = []
        var vistas = Set<Int>()
        for item in textos {
            guard let texto = item else { continue }
            // Duas folhas iguais (o mesmo arquivo em dois endereços) entram uma vez só.
            let marca = texto.hashValue
            if !vistas.insert(marca).inserted { continue }
            let tamanho = texto.utf8.count
            if total + tamanho > maximoBytesTotal { continue }
            total += tamanho
            partes.append(texto)
        }
        let recebidas = textos.compactMap { $0 }.count
        ultimoResumo.valor = "CSS: \(partes.count) de \(urls.count) folhas (\(recebidas) baixadas), \(total / 1024) KB"
        if !extra.isEmpty { partes.append(extra) }
        guard !partes.isEmpty else { return "" }

        // Um "</style" dentro do CSS fecharia o bloco antes da hora.
        let css = partes
            .joined(separator: "\n")
            .replacingOccurrences(of: "</style", with: "", options: .caseInsensitive)
        return "<style>\(css)</style>"
    }

    /// Lista os endereços absolutos das folhas de estilo da página, sem repetir, na ordem em que aparecem.
    static func encontrarFolhas(no html: String, base: URL, largura: Int = 390, escuro: Bool = false, maximo: Int = maximoFolhas) -> [URL] {
        guard let regexLink = try? NSRegularExpression(
            pattern: "<link\\b[^>]*>",
            options: [.caseInsensitive]
        ) else { return [] }

        let analisado = semNoscriptNemComentarios(html)
        let ns = analisado as NSString
        let range = NSRange(location: 0, length: ns.length)
        var urls: [URL] = []

        for m in regexLink.matches(in: analisado, range: range) {
            let tag = ns.substring(with: m.range)
            guard let rel = atributo("rel", em: tag)?.lowercased() else { continue }
            let tokens = rel.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            let ehFolha = tokens.contains("stylesheet") && !tokens.contains("alternate")
            // <link rel="preload" as="style" onload="this.rel='stylesheet'">: o padrão de CSS não bloqueante.
            let ehPreCarga = tokens.contains("preload") && atributo("as", em: tag)?.lowercased() == "style"
            guard ehFolha || ehPreCarga, let hrefBruto = atributo("href", em: tag), !hrefBruto.isEmpty else { continue }
            if temAtributoSolto("disabled", em: tag) { continue }
            if let media = atributo("media", em: tag), !midiaCasa(media, largura: largura, escuro: escuro) {
                continue
            }

            let href = hrefBruto
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            guard url.scheme == "http" || url.scheme == "https" else { continue }

            if !urls.contains(url) {
                urls.append(url)
            }
            if urls.count >= maximo { break }
        }
        return urls
    }

    /// Tira `<noscript>...</noscript>` e `<!-- ... -->`: links de CSS ali dentro não valem para quem roda JavaScript.
    static func semNoscriptNemComentarios(_ html: String) -> String {
        var texto = html
        if texto.range(of: "<noscript", options: .caseInsensitive) != nil,
           let regex = try? NSRegularExpression(pattern: "<noscript\\b.*?</noscript>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            texto = regex.stringByReplacingMatches(
                in: texto, range: NSRange(location: 0, length: (texto as NSString).length), withTemplate: ""
            )
        }
        if texto.contains("<!--"),
           let regex = try? NSRegularExpression(pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators]) {
            texto = regex.stringByReplacingMatches(
                in: texto, range: NSRange(location: 0, length: (texto as NSString).length), withTemplate: ""
            )
        }
        return texto
    }

    /// A folha vale para esta tela? Julga só o que dá para saber: impressão, tema claro/escuro e largura mínima/máxima.
    /// Na dúvida, vale (baixar uma folha a mais custa menos que perder o estilo da página).
    static func midiaCasa(_ midia: String, largura: Int, escuro: Bool) -> Bool {
        let m = midia.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty || m == "all" || m == "screen" { return true }
        // Lista separada por vírgulas: basta uma consulta casar.
        let consultas = m.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for consulta in consultas where consultaCasa(consulta, largura: largura, escuro: escuro) {
            return true
        }
        return false
    }

    private static func consultaCasa(_ q: String, largura: Int, escuro: Bool) -> Bool {
        if q.hasPrefix("print") || q.hasPrefix("only print") || q.hasPrefix("speech") { return false }
        if q.contains("not ") { return true }
        if q.contains("prefers-color-scheme: dark") && !escuro { return false }
        if q.contains("prefers-color-scheme: light") && escuro { return false }
        if let minimo = valorEmPx(depois: "min-width:", em: q), Double(largura) < minimo { return false }
        if let maximo = valorEmPx(depois: "max-width:", em: q), Double(largura) > maximo { return false }
        return true
    }

    /// Lê o número que vem depois de `chave` (px, em ou rem). Nil se não houver ou não for simples.
    private static func valorEmPx(depois chave: String, em q: String) -> Double? {
        let semEspacos = q.replacingOccurrences(of: " ", with: "")
        guard let achado = semEspacos.range(of: chave.replacingOccurrences(of: " ", with: "")) else { return nil }
        let resto = semEspacos[achado.upperBound...]
        var numero = ""
        var unidade = ""
        for c in resto {
            if (c >= "0" && c <= "9") || c == "." {
                if !unidade.isEmpty { break }
                numero.append(c)
            } else if c.isLetter {
                unidade.append(c)
            } else {
                break
            }
        }
        guard let valor = Double(numero) else { return nil }
        switch unidade {
        case "", "px": return valor
        case "em", "rem": return valor * 16
        default: return nil
        }
    }

    /// Lê o valor de um atributo dentro de uma tag: href="...", href='...' ou href=sem-aspas.
    static func atributo(_ nome: String, em tag: String) -> String? {
        // (?<![\w-]) evita confundir href com data-href.
        let padrao = "(?<![\\w-])\(nome)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let regex = try? NSRegularExpression(pattern: padrao, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = tag as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: tag, range: range) else { return nil }
        for grupo in 1...3 {
            let r = m.range(at: grupo)
            if r.location != NSNotFound { return ns.substring(with: r) }
        }
        return nil
    }

    /// Atributo sem valor, como `disabled`.
    private static func temAtributoSolto(_ nome: String, em tag: String) -> Bool {
        let padrao = "\\s\(nome)(?=[\\s>/=])"
        return tag.range(of: padrao, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Baixa todas as folhas ao mesmo tempo. A resposta mantém a ordem da página.
    static func baixarTodas(_ urls: [URL], agente: String) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self) { grupo in
            for (indice, url) in urls.enumerated() {
                grupo.addTask { () async -> (Int, String?) in
                    let texto = await baixar(url, agente: agente)
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

    /// Baixa uma folha e já a enxuga. Devolve nil em caso de erro (depois de uma segunda tentativa), status diferente
    /// de 2xx ou tamanho acima do limite. Texto fora do UTF-8 não derruba a folha: o byte ruim vira "�".
    static func baixar(_ url: URL, agente: String) async -> String? {
        for tentativa in 0..<2 {
            var pedido = URLRequest(url: url)
            pedido.timeoutInterval = tempoLimite
            pedido.setValue(agente, forHTTPHeaderField: "User-Agent")
            pedido.setValue("text/css,*/*;q=0.1", forHTTPHeaderField: "Accept")
            do {
                let (dados, resposta) = try await RedeNusky.sessao.data(for: pedido)
                guard let http = resposta as? HTTPURLResponse else { return nil }
                // Erro do servidor (5xx) pode passar na segunda tentativa; 4xx não.
                if (500...599).contains(http.statusCode) && tentativa == 0 { continue }
                guard (200...299).contains(http.statusCode) else { return nil }
                guard dados.count <= maximoBytesPorFolha else { return nil }
                var texto = String(data: dados, encoding: .utf8) ?? String(decoding: dados, as: UTF8.self)
                if texto.hasPrefix("\u{FEFF}") { texto.removeFirst() }
                return PodaCSS.enxugar(texto)
            } catch {
                if tentativa == 0 && !Task.isCancelled { continue }
                return nil
            }
        }
        return nil
    }
}

/// Texto guardado com trava, lido pela tela depois que o download termina em outra fila.
final class ResumoCSS: @unchecked Sendable {
    private let trava = NSLock()
    private var texto = ""

    var valor: String {
        get {
            trava.lock()
            defer { trava.unlock() }
            return texto
        }
        set {
            trava.lock()
            texto = newValue
            trava.unlock()
        }
    }
}
