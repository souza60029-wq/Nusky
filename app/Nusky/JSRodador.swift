// app/Nusky/JSRodador.swift
import Foundation
import JavaScriptCore

/// Roda os scripts de uma página com JavaScriptCore, sobre um DOM de verdade (ver AmbienteJS).
///
/// Fluxo: o motor (Rust) entrega a árvore do HTML em JSON; o JavaScript monta o `document`,
/// baixa e roda os scripts na ordem da página, atende fetch/XHR pela rede do app, roda os
/// temporizadores em tempo virtual e, no fim, devolve o HTML já alterado para o motor desenhar.
///
/// Segurança de threads: todo o JavaScript roda numa única fila serial. A rede responde
/// em outras threads, mas sempre volta para essa fila antes de tocar no JavaScript.
///
/// Limite de tempo: o JavaScriptCore não tem interrupção pública. Usamos a função interna
/// `JSContextGroupSetExecutionTimeLimit`, procurada em tempo de execução (se não existir,
/// o app segue sem ela). Além disso, passado o limite a página volta ao HTML original.
/// Isso precisa ser medido no iPhone 6s antes de confiar.
final class JSRodador: @unchecked Sendable {

    /// O que aconteceu na execução. É o que o diagnóstico vai mostrar.
    struct Relatorio {
        var executados = 0
        var ignorados = 0
        var erros: [String] = []
        var requisicoes = 0
        var tempo: Double = 0
        var estourouLimite = false
        /// Verdadeiro quando o HTML final veio do JavaScript. Falso = HTML original.
        var usouResultado = false
    }

    /// Chave dos ajustes. Se nunca foi gravada, o JavaScript fica ligado.
    static let chaveAtivo = "executarJavaScript"
    static let limitePadrao: TimeInterval = 6

    static var ativo: Bool {
        UserDefaults.standard.object(forKey: chaveAtivo) as? Bool ?? true
    }

    // MARK: - Entrada

    /// Roda os scripts da página e devolve o HTML final. Se não houver script, se o
    /// JavaScript estiver desligado ou se algo falhar, devolve o HTML original.
    static func processar(
        html: String,
        pagina: URL,
        largura: Int,
        limite: TimeInterval = limitePadrao
    ) async -> (html: String, relatorio: Relatorio?) {
        guard ativo, temScript(html) else { return (html, nil) }
        guard let arvore = Engine.arvore(html: html) else { return (html, nil) }

        let resultado: Resultado = await withCheckedContinuation { cont in
            let rodador = JSRodador(pagina: pagina, largura: largura, limite: limite, continuacao: cont)
            rodador.comecar(arvore: arvore)
        }

        var relatorio = resultado.relatorio
        // Sem nenhum script rodado, o HTML original é igual e mais barato.
        guard let final = resultado.html, relatorio.executados > 0, !final.isEmpty else {
            return (html, relatorio)
        }
        relatorio.usouResultado = true
        return (final, relatorio)
    }

    private struct Resultado {
        let html: String?
        let relatorio: Relatorio
    }

    /// Procura "<script" sem copiar o texto inteiro.
    private static func temScript(_ html: String) -> Bool {
        html.range(of: "<script", options: .caseInsensitive) != nil
    }

    // MARK: - Estado (só a fila de JavaScript mexe aqui)

    private let fila = DispatchQueue(label: "nusky.javascript", qos: .userInitiated)
    private let pagina: URL
    private let largura: Int
    private let limite: TimeInterval
    private let inicio = CFAbsoluteTimeGetCurrent()
    private let sessao = URLSession(configuration: .ephemeral)

    private var contexto: JSContext?
    private var relatorio = Relatorio()
    private var terminado = false

    // A entrega pode vir de duas filas (fim normal ou desistência): protegida por trava.
    private let trava = NSLock()
    private var continuacao: CheckedContinuation<Resultado, Never>?

    private init(pagina: URL, largura: Int, limite: TimeInterval, continuacao: CheckedContinuation<Resultado, Never>) {
        self.pagina = pagina
        self.largura = largura
        self.limite = limite
        self.continuacao = continuacao
    }

    private func comecar(arvore: String) {
        fila.async { self.preparar(arvore: arvore) }
        // Passou o tempo: fecha com o que já foi montado.
        fila.asyncAfter(deadline: .now() + limite) { self.estourou() }
        // Se a fila estiver presa num script que não parou, volta ao HTML original.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limite + 2) { self.desistir() }
    }

    // MARK: - Preparação

    private func preparar(arvore: String) {
        guard let ctx = JSContext() else {
            relatorio.erros.append("Não consegui criar o contexto de JavaScript.")
            finalizar()
            return
        }
        contexto = ctx
        ctx.exceptionHandler = { [weak self] _, excecao in
            self?.registrarErro(excecao?.toString() ?? "erro desconhecido")
        }

        instalarPonte(em: ctx)
        limitarExecucao(de: ctx)

        _ = ctx.evaluateScript(AmbienteJS.codigo, withSourceURL: URL(string: "nusky://ambiente.js"))
        // Monta o document, roda os scripts na ordem e segue enquanto houver rede ou temporizador.
        _ = ctx.objectForKeyedSubscript("__iniciar")?.call(withArguments: [arvore])
    }

    private func instalarPonte(em ctx: JSContext) {
        let desktop = UserDefaults.standard.bool(forKey: IdentificacaoNavegador.chaveDesktop)
        let dados: [String: Any] = [
            "href": pagina.absoluteString,
            "protocolo": (pagina.scheme ?? "https") + ":",
            "host": pagina.host ?? "",
            "agente": IdentificacaoNavegador.atual,
            "plataforma": desktop ? "MacIntel" : "iPhone",
            "toque": !desktop,
            "largura": desktop ? 1280 : largura,
            "altura": desktop ? 800 : 812,
            "escala": 2,
            "escuro": false
        ]
        ctx.setObject(dados, forKeyedSubscript: "__pagina" as NSString)

        let aoErrar: @convention(block) (String) -> Void = { [weak self] texto in
            self?.registrarErro(texto)
        }
        ctx.setObject(aoErrar, forKeyedSubscript: "__erro" as NSString)

        // O mesmo parser do motor (Rust) serve para innerHTML e document.write.
        let aoLerHTML: @convention(block) (String) -> String = { html in
            Engine.arvore(html: html) ?? "[]"
        }
        ctx.setObject(aoLerHTML, forKeyedSubscript: "__parse" as NSString)

        let aoPedir: @convention(block) (Int, String, String, String, String) -> Void = {
            [weak self] id, url, metodo, cabecalhos, corpo in
            self?.pedir(id: id, url: url, metodo: metodo, cabecalhos: cabecalhos, corpo: corpo)
        }
        ctx.setObject(aoPedir, forKeyedSubscript: "__pedir" as NSString)

        // O JavaScript avisa que não há mais nada a fazer. Fecha fora da pilha atual.
        let aoTerminar: @convention(block) () -> Void = { [weak self] in
            self?.fila.async { self?.finalizar() }
        }
        ctx.setObject(aoTerminar, forKeyedSubscript: "__fim" as NSString)
    }

    /// Para scripts que não terminam. A função é interna do JavaScriptCore e pode não existir:
    /// por isso é procurada na hora, sem linkar direto.
    private func limitarExecucao(de ctx: JSContext) {
        typealias Retorno = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Bool
        typealias Funcao = @convention(c) (UnsafeRawPointer?, Double, Retorno?, UnsafeMutableRawPointer?) -> Void

        guard let simbolo = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit"),
              let grupo = JSContextGetGroup(ctx.jsGlobalContextRef) else { return }
        let definir = unsafeBitCast(simbolo, to: Funcao.self)
        let parar: Retorno = { _, _ in true }
        definir(UnsafeRawPointer(grupo), limite, parar, nil)
    }

    // MARK: - Rede

    private static let cabecalhosProibidos: Set<String> = [
        "user-agent", "host", "content-length", "cookie", "connection", "referer"
    ]
    private static let maximoRequisicoes = 120
    private static let maximoBytesResposta = 3_000_000

    private func pedir(id: Int, url: String, metodo: String, cabecalhos: String, corpo: String) {
        relatorio.requisicoes += 1
        guard relatorio.requisicoes <= JSRodador.maximoRequisicoes,
              let destino = URL(string: url),
              let esquema = destino.scheme?.lowercased(),
              esquema == "http" || esquema == "https" else {
            responder(id: id, status: 0, cabecalhos: "{}", texto: "", erro: "pedido bloqueado")
            return
        }

        var pedido = URLRequest(url: destino)
        let metodoFinal = metodo.uppercased()
        pedido.httpMethod = metodoFinal
        pedido.timeoutInterval = limite
        pedido.setValue(IdentificacaoNavegador.atual, forHTTPHeaderField: "User-Agent")
        pedido.setValue(pagina.absoluteString, forHTTPHeaderField: "Referer")
        if let dados = cabecalhos.data(using: .utf8),
           let objeto = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] {
            for (nome, valor) in objeto where !JSRodador.cabecalhosProibidos.contains(nome.lowercased()) {
                pedido.setValue(String(describing: valor), forHTTPHeaderField: nome)
            }
        }
        if !corpo.isEmpty, metodoFinal != "GET", metodoFinal != "HEAD" {
            pedido.httpBody = corpo.data(using: .utf8)
        }

        sessao.dataTask(with: pedido) { [weak self] dados, resposta, falha in
            guard let self else { return }
            if let falha {
                self.fila.async { self.responder(id: id, status: 0, cabecalhos: "{}", texto: "", erro: falha.localizedDescription) }
                return
            }
            guard let dados, dados.count <= JSRodador.maximoBytesResposta else {
                self.fila.async { self.responder(id: id, status: 0, cabecalhos: "{}", texto: "", erro: "resposta grande demais") }
                return
            }
            let http = resposta as? HTTPURLResponse
            var cab: [String: String] = [:]
            for (k, v) in http?.allHeaderFields ?? [:] {
                cab[String(describing: k).lowercased()] = String(describing: v)
            }
            let cabJSON = (try? JSONSerialization.data(withJSONObject: cab))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let texto = String(data: dados, encoding: .utf8) ?? String(decoding: dados, as: UTF8.self)
            self.fila.async {
                self.responder(id: id, status: http?.statusCode ?? 0, cabecalhos: cabJSON, texto: texto, erro: "")
            }
        }.resume()
    }

    /// Entrega a resposta ao JavaScript. Sempre na fila do JavaScript.
    private func responder(id: Int, status: Int, cabecalhos: String, texto: String, erro: String) {
        guard !terminado, let ctx = contexto else { return }
        _ = ctx.objectForKeyedSubscript("__resposta")?
            .call(withArguments: [id, status, cabecalhos, texto, erro])
    }

    // MARK: - Fim

    private func registrarErro(_ texto: String) {
        guard relatorio.erros.count < 200 else { return }
        relatorio.erros.append(texto)
    }

    private func estourou() {
        guard !terminado else { return }
        relatorio.estourouLimite = true
        finalizar()
    }

    /// Serializa o documento, libera tudo e entrega o resultado. Só na fila do JavaScript.
    private func finalizar() {
        guard !terminado else { return }
        terminado = true

        var html: String?
        if let ctx = contexto {
            if let valor = ctx.objectForKeyedSubscript("__serializar")?.call(withArguments: []), valor.isString {
                html = valor.toString()
            }
            if let texto = ctx.objectForKeyedSubscript("__estatisticas")?.call(withArguments: [])?.toString(),
               let dados = texto.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] {
                relatorio.executados = obj["executados"] as? Int ?? 0
                relatorio.ignorados = obj["ignorados"] as? Int ?? 0
            }
        }
        relatorio.tempo = CFAbsoluteTimeGetCurrent() - inicio
        // O JavaScript de uma página grande chega a centenas de MB. Pede a limpeza já,
        // em vez de esperar o sistema, para a memória voltar antes da próxima página.
        if let ctx = contexto {
            JSGarbageCollect(ctx.jsGlobalContextRef)
        }
        contexto = nil
        sessao.invalidateAndCancel()
        entregar(Resultado(html: html, relatorio: relatorio))
    }

    /// A fila não respondeu a tempo: segue com o HTML original.
    private func desistir() {
        var r = Relatorio()
        r.estourouLimite = true
        r.tempo = CFAbsoluteTimeGetCurrent() - inicio
        r.erros = ["O JavaScript não parou a tempo; a página foi aberta sem ele."]
        entregar(Resultado(html: nil, relatorio: r))
    }

    /// Entrega uma vez só, mesmo que o fim normal e a desistência cheguem juntos.
    private func entregar(_ resultado: Resultado) {
        trava.lock()
        let c = continuacao
        continuacao = nil
        trava.unlock()
        c?.resume(returning: resultado)
    }
}