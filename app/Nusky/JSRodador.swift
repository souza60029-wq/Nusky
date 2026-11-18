// app/Nusky/JSRodador.swift
import Foundation
import JavaScriptCore
import UIKit
import os

/// Roda os scripts de uma página com JavaScriptCore, sobre um DOM de verdade (ver AmbienteJS).
///
/// Fluxo: o motor (Rust) entrega a árvore do HTML em JSON; o JavaScript monta o `document`,
/// baixa e roda os scripts na ordem da página, atende fetch/XHR pela rede do app, roda os
/// temporizadores em tempo virtual e, no fim, devolve o HTML já alterado para o motor desenhar.
/// Todos os contextos vivem numa mesma máquina virtual, que guarda o código já compilado entre páginas.
///
/// Segurança de threads: todo o JavaScript roda numa única fila serial. A rede responde
/// em outras threads, mas sempre volta para essa fila antes de tocar no JavaScript.
///
/// Ciclo de vida: o JavaScript passa por duas fases.
///   1. Primeira exibição (até `limitePadrao` segundos): monta a página com tempo virtual, como antes.
///   2. Modo vivo: o contexto NÃO é destruído. Temporizadores seguem em tempo real (nada é cortado: só
///      os quadros que a tela não conseguiria mostrar deixam de ser calculados), a rede continua atendendo
///      fetch/XHR e os toques do usuário viram cliques de verdade no DOM. Quando o DOM muda, o HTML novo
///      volta para o motor redesenhar.
/// O modo vivo é fechado ao sair da página, em pouca memória ou ao desligar o ajuste.
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
        /// O JavaScript continua rodando depois da primeira exibição.
        var sessaoViva = false
        /// Pedidos e scripts de rastreadores que foram cortados.
        var bloqueados = 0
    }

    /// O que `processar` devolve: o HTML (já alterado pelos scripts), o relatório e a sessão, se continuou viva.
    typealias Saida = (html: String, relatorio: Relatorio?, sessao: JSRodador?)

    /// A página tem scripts e o JavaScript está ligado? Quem chama usa isto para pintar a página antes.
    static func vaiRodar(_ html: String) -> Bool {
        ativo && temScript(html)
    }

    /// Resposta a um toque numa área que o JavaScript escuta.
    enum Toque {
        /// O clique não foi cancelado e termina num link: abrir este endereço.
        case navegar(String)
        /// O JavaScript tratou o clique. A página nova chega pela atualização viva.
        case tratado
        /// A sessão não existe mais ou o elemento sumiu.
        case perdido
    }

    /// Chave dos ajustes. Se nunca foi gravada, o JavaScript fica ligado.
    static let chaveAtivo = "executarJavaScript"
    static let limitePadrao: TimeInterval = 6
    /// Tempo máximo de cada toque ou temporizador no modo vivo.
    static let limiteVivo: TimeInterval = 3
    /// Chave do ajuste "JavaScript interativo". Se nunca foi gravada, fica ligado.
    static let chaveVivo = "javascriptInterativo"
    /// Chave do ajuste "Bloquear rastreadores". Opcional: se nunca foi gravada, fica desligado.
    static let chaveBloquear = "bloquearRastreadores"
    /// Abaixo disto de memória livre, o modo vivo é fechado.
    private static let memoriaMinima = 90 * 1024 * 1024

    // Uma máquina virtual de JavaScript para todas as páginas (cada página tem seu próprio contexto).
    // O JavaScriptCore guarda o código já compilado dentro da máquina: o mesmo script (a mesma biblioteca,
    // o mesmo pacote do site) aberto em outra página não precisa ser lido e compilado de novo.
    private static let travaMaquina = NSLock()
    private static var maquina: JSVirtualMachine?

    static func maquinaVirtual() -> JSVirtualMachine {
        travaMaquina.lock()
        defer { travaMaquina.unlock() }
        if let existente = maquina { return existente }
        let nova: JSVirtualMachine = JSVirtualMachine()
        maquina = nova
        return nova
    }

    /// Em pouca memória, a máquina (e o cache de código dela) vai embora; a próxima página começa com outra.
    static func descartarMaquinaVirtual() {
        travaMaquina.lock()
        maquina = nil
        travaMaquina.unlock()
    }

    static var vivoAtivo: Bool {
        UserDefaults.standard.object(forKey: chaveVivo) as? Bool ?? true
    }
    static var bloquearAtivo: Bool {
        UserDefaults.standard.object(forKey: chaveBloquear) as? Bool ?? false
    }

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
        escuro: Bool = false,
        limite: TimeInterval = limitePadrao
    ) async -> (html: String, relatorio: Relatorio?, sessao: JSRodador?) {
        guard ativo, temScript(html) else { return (html, nil, nil) }
        guard let arvore = Engine.arvore(html: html) else { return (html, nil, nil) }

        let resultado: Resultado = await withCheckedContinuation { cont in
            let rodador = JSRodador(pagina: pagina, largura: largura, escuro: escuro, limite: limite, continuacao: cont)
            rodador.comecar(arvore: arvore)
        }

        var relatorio = resultado.relatorio
        // Sem nenhum script rodado, o HTML original é igual e mais barato.
        guard let final = resultado.html, relatorio.executados > 0, !final.isEmpty else {
            resultado.sessao?.fechar()
            return (html, relatorio, nil)
        }
        relatorio.usouResultado = true
        return (final, relatorio, resultado.sessao)
    }

    private struct Resultado {
        let html: String?
        let relatorio: Relatorio
        /// A própria sessão, quando ela continua viva depois da primeira exibição.
        let sessao: JSRodador?
    }

    /// Procura "<script" sem copiar o texto inteiro.
    private static func temScript(_ html: String) -> Bool {
        html.range(of: "<script", options: .caseInsensitive) != nil
    }

    // MARK: - Estado (só a fila de JavaScript mexe aqui)

    private let fila = DispatchQueue(label: "nusky.javascript", qos: .userInitiated)
    private let pagina: URL
    private let largura: Int
    /// O tema escuro vale para os sites que escolhem as cores por `prefers-color-scheme`.
    private let escuro: Bool
    private let limite: TimeInterval
    private let inicio = CFAbsoluteTimeGetCurrent()
    private let rede = RedeNusky.sessao

    private enum Fase { case boot, vivo, fechado }
    private var fase = Fase.boot

    private var contexto: JSContext?
    private var relatorio = Relatorio()
    private var tarefas: [Int: URLSessionDataTask] = [:]
    /// Texto dos scripts externos, em UTF-8 e terminado em 0. Fica aqui, fora do heap do JavaScript.
    private var scriptsGuardados: [String: [UInt8]] = [:]
    /// Intervalo mínimo entre atualizações da tela; sobe quando desenhar fica caro.
    private var intervalo: TimeInterval = 0.15
    private var despertador: DispatchWorkItem?
    private var flushPendente = false
    private var aoAtualizar: ((String) -> Void)?
    private var observadores: [NSObjectProtocol] = []

    /// Chamado (em qualquer fila) quando a sessão viva se encerra sozinha, por exemplo por falta de memória.
    var aoEncerrar: (() -> Void)?

    // A entrega pode vir de duas filas (fim normal ou desistência): protegida por trava.
    private let trava = NSLock()
    private var continuacao: CheckedContinuation<Resultado, Never>?

    private init(pagina: URL, largura: Int, escuro: Bool, limite: TimeInterval, continuacao: CheckedContinuation<Resultado, Never>) {
        self.pagina = pagina
        self.largura = largura
        self.escuro = escuro
        self.limite = limite
        self.continuacao = continuacao
    }

    private func comecar(arvore: String) {
        fila.async { self.preparar(arvore: arvore) }
        // Passou o tempo da primeira exibição: mostra o que já foi montado e segue no modo vivo.
        fila.asyncAfter(deadline: .now() + limite) { self.estourou() }
        // Se a fila estiver presa num script que não parou, volta ao HTML original.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limite + 2) { self.desistir() }
    }

    // MARK: - Preparação

    private func preparar(arvore: String) {
        guard let ctx = JSContext(virtualMachine: JSRodador.maquinaVirtual()) else {
            relatorio.erros.append("Não consegui criar o contexto de JavaScript.")
            finalizarBoot()
            return
        }
        contexto = ctx
        ctx.exceptionHandler = { [weak self] _, excecao in
            self?.registrarErro(excecao?.toString() ?? "erro desconhecido")
        }

        instalarPonte(em: ctx)
        limitarExecucao(de: ctx, segundos: limite)

        _ = ctx.evaluateScript(AmbienteJS.codigo, withSourceURL: URL(string: "nusky://ambiente.js"))
        // Recursos de navegador que o AmbienteJS ainda não tinha (CSS.supports, streams, MessageChannel...).
        _ = ctx.evaluateScript(AmbienteJS.extra, withSourceURL: URL(string: "nusky://extra.js"))
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
            "escuro": escuro,
            "vivo": JSRodador.vivoAtivo,
            "bloquear": JSRodador.bloquearAtivo
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

        let aoPedir: @convention(block) (Int, String, String, String, String, Bool) -> Void = {
            [weak self] id, url, metodo, cabecalhos, corpo, guardar in
            self?.pedir(id: id, url: url, metodo: metodo, cabecalhos: cabecalhos, corpo: corpo, guardar: guardar)
        }
        ctx.setObject(aoPedir, forKeyedSubscript: "__pedir" as NSString)

        // Scripts rodam como "Script" do JavaScriptCore (não como eval): let, const e class do topo ficam
        // visíveis aos scripts seguintes, como num navegador. Devolve "" ou a mensagem de erro.
        let aoAvaliar: @convention(block) (String, String) -> String = { [weak self] origem, codigo in
            guard let self, let ctx = self.contexto, let fonte = JSStringCreateWithUTF8CString(codigo) else { return "" }
            defer { JSStringRelease(fonte) }
            return self.avaliar(ctx: ctx, fonte: fonte, origem: origem)
        }
        ctx.setObject(aoAvaliar, forKeyedSubscript: "__avaliar" as NSString)

        // Script externo guardado pelo lado nativo: o texto vai direto do disco/rede para o JavaScriptCore,
        // sem nunca virar uma string do JavaScript (que custaria várias cópias de pacotes de megabytes).
        let aoAvaliarGuardado: @convention(block) (String) -> String = { [weak self] url in
            guard let self, let ctx = self.contexto else { return "" }
            guard let bytes = self.scriptsGuardados[url] else { return "script não encontrado: " + url }
            let fonte: JSStringRef? = bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> JSStringRef? in
                guard let base = buffer.baseAddress else { return nil }
                return base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { (ponteiro: UnsafePointer<CChar>) -> JSStringRef? in
                    JSStringCreateWithUTF8CString(ponteiro)
                }
            }
            guard let texto = fonte else { return "" }
            defer { JSStringRelease(texto) }
            let resposta = self.avaliar(ctx: ctx, fonte: texto, origem: url)
            // Pacotes grandes não voltam a ser usados na mesma página: libera já. Os pequenos ficam (tags repetidas).
            if bytes.count > 256_000 { self.scriptsGuardados[url] = nil }
            return resposta
        }
        ctx.setObject(aoAvaliarGuardado, forKeyedSubscript: "__avaliarGuardado" as NSString)

        // O JavaScript avisa que a primeira exibição está pronta. Fecha fora da pilha atual.
        let aoTerminar: @convention(block) () -> Void = { [weak self] in
            self?.fila.async { self?.finalizarBoot() }
        }
        ctx.setObject(aoTerminar, forKeyedSubscript: "__fim" as NSString)

        // Modo vivo: o JavaScript pede para ser acordado daqui a N ms (um único despertador).
        let aoAcordar: @convention(block) (Double) -> Void = { [weak self] ms in
            self?.armarDespertador(ms: ms)
        }
        ctx.setObject(aoAcordar, forKeyedSubscript: "__acordar" as NSString)

        // Modo vivo: o DOM mudou. Junta várias mudanças numa atualização só.
        let aoAvisar: @convention(block) () -> Void = { [weak self] in
            self?.agendarAtualizacao()
        }
        ctx.setObject(aoAvisar, forKeyedSubscript: "__aviso" as NSString)
    }

    /// Para scripts que não terminam. A função é interna do JavaScriptCore e pode não existir:
    /// por isso é procurada na hora, sem linkar direto. Pode ser chamada de novo para trocar o limite.
    private func limitarExecucao(de ctx: JSContext, segundos: TimeInterval) {
        typealias Retorno = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Bool
        typealias Funcao = @convention(c) (UnsafeRawPointer?, Double, Retorno?, UnsafeMutableRawPointer?) -> Void

        guard let simbolo = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit"),
              let grupo = JSContextGetGroup(ctx.jsGlobalContextRef) else { return }
        let definir = unsafeBitCast(simbolo, to: Funcao.self)
        let parar: Retorno = { _, _ in true }
        definir(UnsafeRawPointer(grupo), segundos, parar, nil)
    }

    /// Roda um script no contexto como "Script". Devolve "" se deu certo, ou a mensagem do erro com a posição.
    private func avaliar(ctx: JSContext, fonte: JSStringRef, origem: String) -> String {
        guard let endereco = JSStringCreateWithUTF8CString(origem) else { return "" }
        defer { JSStringRelease(endereco) }
        var excecao: JSValueRef?
        _ = JSEvaluateScript(ctx.jsGlobalContextRef, fonte, nil, endereco, 1, &excecao)
        guard let erro = excecao else { return "" }
        let valor = JSValue(jsValueRef: erro, in: ctx)
        var mensagem = valor?.objectForKeyedSubscript("message")?.toString() ?? valor?.toString() ?? "erro"
        if let linha = valor?.objectForKeyedSubscript("line"), linha.isNumber {
            let coluna = valor?.objectForKeyedSubscript("column")?.toInt32() ?? 0
            mensagem += " (\(origem):\(linha.toInt32()):\(coluna))"
        } else {
            mensagem = origem + ": " + mensagem
        }
        return mensagem
    }

    /// O modelo informa quanto custou desenhar a última atualização. A cadência acompanha: se a tela custa
    /// caro, quadros que ninguém chegaria a ver deixam de ser calculados (como um navegador que perde quadros).
    func informarCusto(_ segundos: TimeInterval) {
        fila.async {
            guard self.fase == .vivo, let ctx = self.contexto else { return }
            self.intervalo = min(2.0, max(0.15, segundos * 3))
            _ = ctx.objectForKeyedSubscript("__cadencia")?.call(withArguments: [self.intervalo * 1000 / 8])
        }
    }

    // MARK: - Rede

    private static let cabecalhosProibidos: Set<String> = [
        "user-agent", "host", "content-length", "cookie", "connection", "referer"
    ]
    private static let maximoRequisicoesBoot = 120
    private static let maximoRequisicoesVivo = 520
    private static let maximoBytesResposta = 3_000_000
    /// Scripts guardados pelo lado nativo não passam pelo heap do JavaScript, então aguentam pacotes maiores.
    private static let maximoBytesScript = 8_000_000

    private func pedir(id: Int, url: String, metodo: String, cabecalhos: String, corpo: String, guardar: Bool) {
        relatorio.requisicoes += 1
        let teto = fase == .boot ? JSRodador.maximoRequisicoesBoot : JSRodador.maximoRequisicoesVivo
        guard relatorio.requisicoes <= teto,
              let destino = URL(string: url),
              let esquema = destino.scheme?.lowercased(),
              esquema == "http" || esquema == "https" else {
            responder(id: id, status: 0, cabecalhos: "{}", texto: "", erro: "pedido bloqueado")
            return
        }

        var pedido = URLRequest(url: destino)
        let metodoFinal = metodo.uppercased()
        pedido.httpMethod = metodoFinal
        pedido.timeoutInterval = fase == .boot ? limite : 15
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

        let tarefa = rede.dataTask(with: pedido) { [weak self] dados, resposta, falha in
            guard let self else { return }
            if let falha {
                self.fila.async { self.responder(id: id, status: 0, cabecalhos: "{}", texto: "", erro: falha.localizedDescription) }
                return
            }
            guard let dados, dados.count <= (guardar ? JSRodador.maximoBytesScript : JSRodador.maximoBytesResposta) else {
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
            let status = http?.statusCode ?? 0
            if guardar, (200..<300).contains(status) {
                // O texto não entra no JavaScript: só o aviso de que chegou.
                var bytes = [UInt8](dados)
                bytes.append(0)
                self.fila.async {
                    self.scriptsGuardados[url] = bytes
                    self.responder(id: id, status: status, cabecalhos: cabJSON, texto: "", erro: "")
                }
                return
            }
            let texto = String(data: dados, encoding: .utf8) ?? String(decoding: dados, as: UTF8.self)
            self.fila.async {
                self.responder(id: id, status: status, cabecalhos: cabJSON, texto: texto, erro: "")
            }
        }
        tarefas[id] = tarefa
        tarefa.resume()
    }

    /// Entrega a resposta ao JavaScript. Sempre na fila do JavaScript.
    private func responder(id: Int, status: Int, cabecalhos: String, texto: String, erro: String) {
        tarefas[id] = nil
        guard fase != .fechado, let ctx = contexto else { return }
        _ = ctx.objectForKeyedSubscript("__resposta")?
            .call(withArguments: [id, status, cabecalhos, texto, erro])
    }

    // MARK: - Primeira exibição

    private func registrarErro(_ texto: String) {
        guard relatorio.erros.count < 200 else { return }
        relatorio.erros.append(texto)
    }

    /// O tempo da primeira exibição acabou: mostra o que há e segue no modo vivo.
    private func estourou() {
        guard fase == .boot else { return }
        relatorio.estourouLimite = true
        finalizarBoot()
    }

    /// Serializa o documento e entrega a primeira exibição. Só na fila do JavaScript.
    /// Se o modo vivo estiver ligado e algum script rodou, o contexto continua; senão é liberado.
    private func finalizarBoot() {
        guard fase == .boot else { return }

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
                relatorio.bloqueados = obj["bloqueados"] as? Int ?? 0
            }
        }
        relatorio.tempo = CFAbsoluteTimeGetCurrent() - inicio

        let manter = JSRodador.vivoAtivo && relatorio.executados > 0 && !(html ?? "").isEmpty && contexto != nil
        if manter, let ctx = contexto {
            fase = .vivo
            relatorio.sessaoViva = true
            limitarExecucao(de: ctx, segundos: JSRodador.limiteVivo)
            _ = ctx.objectForKeyedSubscript("__vivo")?.call(withArguments: [])
            observarSistema()
            entregar(Resultado(html: html, relatorio: relatorio, sessao: self))
        } else {
            encerrar()
            entregar(Resultado(html: html, relatorio: relatorio, sessao: nil))
        }
    }

    /// A fila não respondeu a tempo: segue com o HTML original.
    private func desistir() {
        var r = Relatorio()
        r.estourouLimite = true
        r.tempo = CFAbsoluteTimeGetCurrent() - inicio
        r.erros = ["O JavaScript não parou a tempo; a página foi aberta sem ele."]
        entregar(Resultado(html: nil, relatorio: r, sessao: nil))
    }

    /// Entrega uma vez só, mesmo que o fim normal e a desistência cheguem juntos.
    private func entregar(_ resultado: Resultado) {
        trava.lock()
        let c = continuacao
        continuacao = nil
        trava.unlock()
        c?.resume(returning: resultado)
    }

    // MARK: - Modo vivo

    /// Liga a sessão à tela. A partir daqui, cada mudança do DOM chega como HTML novo.
    func ligar(aoAtualizar ouvinte: @escaping (String) -> Void) {
        fila.async {
            guard self.fase == .vivo else { return }
            self.aoAtualizar = ouvinte
            // Pode ter havido mudança entre a primeira exibição e este momento.
            self.atualizar()
        }
    }

    /// Entrega um toque (identificado pelo número que o motor devolveu no link) ao JavaScript.
    func tocar(id: Int) async -> Toque {
        await withCheckedContinuation { (c: CheckedContinuation<Toque, Never>) in
            fila.async {
                guard self.fase == .vivo, let ctx = self.contexto,
                      let texto = ctx.objectForKeyedSubscript("__tocar")?.call(withArguments: [id])?.toString(),
                      let dados = texto.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
                      (obj["ok"] as? Int) == 1 else {
                    c.resume(returning: .perdido)
                    return
                }
                let href = obj["href"] as? String ?? ""
                c.resume(returning: href.isEmpty ? .tratado : .navegar(href))
            }
        }
    }

    /// Fecha a sessão e libera a memória do JavaScript. Pode ser chamada de qualquer fila.
    func fechar() {
        fila.async { self.encerrar() }
    }

    /// Só na fila do JavaScript.
    private func encerrar() {
        guard fase != .fechado else { return }
        let estavaViva = fase == .vivo
        fase = .fechado
        despertador?.cancel()
        despertador = nil
        for tarefa in tarefas.values { tarefa.cancel() }
        tarefas = [:]
        scriptsGuardados = [:]
        aoAtualizar = nil
        // O JavaScript de uma página grande chega a centenas de MB. Pede a limpeza já,
        // em vez de esperar o sistema, para a memória voltar antes da próxima página.
        if let ctx = contexto {
            JSGarbageCollect(ctx.jsGlobalContextRef)
        }
        contexto = nil
        let lista = observadores
        observadores = []
        if !lista.isEmpty {
            DispatchQueue.main.async { lista.forEach { NotificationCenter.default.removeObserver($0) } }
        }
        if estavaViva { aoEncerrar?() }
        aoEncerrar = nil
    }

    /// Um único despertador: cada pedido novo substitui o anterior.
    private func armarDespertador(ms: Double) {
        guard fase == .vivo else { return }
        despertador?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.tick() }
        despertador = item
        let espera = max(0, min(ms, 60_000))
        fila.asyncAfter(deadline: .now() + .milliseconds(Int(espera)), execute: item)
    }

    private func tick() {
        guard fase == .vivo, let ctx = contexto else { return }
        _ = ctx.objectForKeyedSubscript("__tick")?.call(withArguments: [])
    }

    /// Junta mudanças próximas numa atualização só (no mínimo 0,15 s; mais quando desenhar custa caro).
    private func agendarAtualizacao() {
        guard fase == .vivo, !flushPendente else { return }
        flushPendente = true
        fila.asyncAfter(deadline: .now() + intervalo) { [weak self] in
            self?.flushPendente = false
            self?.atualizar()
        }
    }

    private func atualizar() {
        guard fase == .vivo, let ctx = contexto, let ouvinte = aoAtualizar else { return }
        let valor = ctx.objectForKeyedSubscript("__coletar")?.call(withArguments: [])
        verificarMemoria()
        guard fase == .vivo, let v = valor, v.isString, let html = v.toString(), !html.isEmpty else { return }
        ouvinte(html)
    }

    /// Com pouca memória livre, o JavaScript vivo vai embora e a página fica como está.
    private func verificarMemoria() {
        guard fase == .vivo else { return }
        guard os_proc_available_memory() < JSRodador.memoriaMinima else { return }
        if let ctx = contexto { JSGarbageCollect(ctx.jsGlobalContextRef) }
        if os_proc_available_memory() < JSRodador.memoriaMinima { encerrar() }
    }

    /// Segundo plano pausa os temporizadores; alerta de memória faz limpeza (e fecha, se continuar apertado).
    private func observarSistema() {
        let centro = NotificationCenter.default
        let fundo = centro.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.fila.async {
                guard let self, self.fase == .vivo, let ctx = self.contexto else { return }
                self.despertador?.cancel()
                _ = ctx.objectForKeyedSubscript("__pausar")?.call(withArguments: [])
            }
        }
        let frente = centro.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.fila.async {
                guard let self, self.fase == .vivo, let ctx = self.contexto else { return }
                _ = ctx.objectForKeyedSubscript("__retomar")?.call(withArguments: [])
            }
        }
        let aviso = centro.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.fila.async {
                guard let self, self.fase == .vivo else { return }
                if let ctx = self.contexto { JSGarbageCollect(ctx.jsGlobalContextRef) }
                JSRodador.descartarMaquinaVirtual()
                // Em alerta de memória, é melhor perder a interatividade do que o app inteiro.
                if os_proc_available_memory() < 200 * 1024 * 1024 { self.encerrar() }
            }
        }
        observadores = [fundo, frente, aviso]
    }
}
