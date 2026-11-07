// app/Nusky/JSRodador.swift
import Foundation
import JavaScriptCore

/// Roda os scripts de uma página com JavaScriptCore, num ambiente mínimo de navegador.
/// Esta etapa não desenha nada: executa os scripts, conta os erros e mede o tempo.
/// O DOM de verdade entra na etapa seguinte.
final class JSRodador {

    /// Um script da página: endereço de origem (ou "inline n") e o código.
    struct Script {
        let origem: String
        let codigo: String
    }

    /// O que aconteceu na execução. É o que o diagnóstico vai mostrar.
    struct Relatorio {
        var executados = 0
        var erros: [String] = []
        var tempo: Double = 0
        var estourouLimite = false
    }

    /// Roda os scripts em ordem, fora da thread principal.
    /// Se passar de `limite` segundos, devolve o relatório parcial com `estourouLimite = true`.
    /// Limite de verdade: o JavaScriptCore não tem interrupção pública. A thread que estourou
    /// continua até terminar, então isso precisa ser medido no aparelho antes de confiar nele.
    static func executar(
        pagina: URL,
        scripts: [Script],
        limite: TimeInterval
    ) async -> Relatorio {
        await withCheckedContinuation { (continuacao: CheckedContinuation<Relatorio, Never>) in
            let entrega = Entrega(continuacao)
            let inicio = CFAbsoluteTimeGetCurrent()

            DispatchQueue.global(qos: .userInitiated).async {
                let relatorio = JSRodador.rodar(pagina: pagina, scripts: scripts, inicio: inicio)
                entrega.entregar(relatorio)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limite) {
                var relatorio = Relatorio()
                relatorio.estourouLimite = true
                relatorio.tempo = limite
                entrega.entregar(relatorio)
            }
        }
    }

    // MARK: - Execução

    private static func rodar(pagina: URL, scripts: [Script], inicio: CFAbsoluteTime) -> Relatorio {
        var relatorio = Relatorio()

        guard let contexto = JSContext() else {
            relatorio.erros.append("Não consegui criar o contexto de JavaScript.")
            relatorio.tempo = CFAbsoluteTimeGetCurrent() - inicio
            return relatorio
        }

        let coletor = ColetorErros()
        // Erros não tratados do JavaScript caem aqui; a execução segue no script seguinte.
        contexto.exceptionHandler = { _, excecao in
            coletor.adicionar(excecao?.toString() ?? "erro desconhecido")
        }
        // Ponte para o ambiente JS registrar erros (ex.: console.error, temporizadores).
        let erroPelaPagina: @convention(block) (String) -> Void = { texto in
            coletor.adicionar(texto)
        }
        contexto.setObject(erroPelaPagina, forKeyedSubscript: "__erro" as NSString)
        contexto.setObject(dadosDaPagina(pagina), forKeyedSubscript: "__pagina" as NSString)

        _ = contexto.evaluateScript(ambienteMinimo, withSourceURL: URL(string: "nusky://ambiente.js"))

        for script in scripts {
            _ = contexto.evaluateScript(script.codigo, withSourceURL: URL(string: script.origem))
            relatorio.executados += 1
        }

        // Roda os temporizadores que os scripts agendaram (com teto, para não girar para sempre).
        if let drenar = contexto.objectForKeyedSubscript("__drenar") {
            _ = drenar.call(withArguments: [2000])
        }

        relatorio.erros = coletor.itens
        relatorio.tempo = CFAbsoluteTimeGetCurrent() - inicio
        return relatorio
    }

    private static func dadosDaPagina(_ url: URL) -> [String: String] {
        [
            "href": url.absoluteString,
            "protocolo": (url.scheme ?? "https") + ":",
            "host": url.host ?? "",
            "caminho": url.path.isEmpty ? "/" : url.path,
            "busca": url.query.map { "?" + $0 } ?? ""
        ]
    }

    // MARK: - Ambiente mínimo do navegador

    /// Objetos que um site espera encontrar: window, document, location, storage, temporizadores.
    /// Nesta etapa, o document é falso: aceita tudo, mas não guarda uma árvore de verdade.
    private static let ambienteMinimo = """
    (function () {
      var G = this;
      var pagina = __pagina;
      var inicioMs = Date.now();
      var agente = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_8_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1";
      var silencio = function () {};
      var fila = [];
      var proximoId = 1;

      function elementoFalso(tag) {
        var nome = String(tag || 'div').toUpperCase();
        var el = {
          tagName: nome, nodeName: nome, nodeType: 1,
          children: [], childNodes: [], style: {}, dataset: {}, attributes: {},
          textContent: '', innerHTML: '', value: '', checked: false,
          appendChild: function (f) { this.childNodes.push(f); return f; },
          insertBefore: function (f) { this.childNodes.push(f); return f; },
          removeChild: function (f) { return f; },
          setAttribute: function (n, v) { this.attributes[n] = String(v); },
          getAttribute: function (n) { return Object.prototype.hasOwnProperty.call(this.attributes, n) ? this.attributes[n] : null; },
          removeAttribute: function (n) { delete this.attributes[n]; },
          hasAttribute: function (n) { return Object.prototype.hasOwnProperty.call(this.attributes, n); },
          addEventListener: silencio, removeEventListener: silencio,
          dispatchEvent: function () { return true; },
          focus: silencio, blur: silencio, click: silencio,
          getBoundingClientRect: function () { return { x: 0, y: 0, top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0 }; },
          querySelector: function () { return null; },
          querySelectorAll: function () { return []; },
          contains: function () { return false; }
        };
        el.classList = { add: silencio, remove: silencio, toggle: function () { return false; }, contains: function () { return false; } };
        return el;
      }

      function armazenamento() {
        var dados = {};
        return {
          getItem: function (k) { return Object.prototype.hasOwnProperty.call(dados, k) ? dados[k] : null; },
          setItem: function (k, v) { dados[k] = String(v); },
          removeItem: function (k) { delete dados[k]; },
          clear: function () { dados = {}; },
          key: function (i) { return Object.keys(dados)[i] || null; },
          get length() { return Object.keys(dados).length; }
        };
      }

      var documento = elementoFalso('html');
      documento.nodeType = 9;
      documento.readyState = 'complete';
      documento.title = '';
      documento.cookie = '';
      documento.documentElement = elementoFalso('html');
      documento.head = elementoFalso('head');
      documento.body = elementoFalso('body');
      documento.createElement = function (t) { return elementoFalso(t); };
      documento.createElementNS = function (ns, t) { return elementoFalso(t); };
      documento.createTextNode = function (t) { var n = elementoFalso('#text'); n.nodeType = 3; n.textContent = String(t); return n; };
      documento.createDocumentFragment = function () { return elementoFalso('#fragment'); };
      documento.getElementById = function () { return null; };
      documento.getElementsByTagName = function () { return []; };
      documento.getElementsByClassName = function () { return []; };
      documento.querySelector = function () { return null; };
      documento.querySelectorAll = function () { return []; };

      var localizacao = {
        href: pagina.href, protocol: pagina.protocolo, host: pagina.host,
        hostname: pagina.host, pathname: pagina.caminho, search: pagina.busca,
        hash: '', origin: pagina.protocolo + '//' + pagina.host,
        assign: silencio, replace: silencio, reload: silencio
      };

      function agendar(fn, args) {
        var id = proximoId++;
        fila.push({ id: id, fn: fn, args: args });
        return id;
      }

      G.setTimeout = function (fn) {
        if (typeof fn !== 'function') return 0;
        return agendar(fn, Array.prototype.slice.call(arguments, 2));
      };
      G.clearTimeout = function (id) {
        fila = fila.filter(function (t) { return t.id !== id; });
      };
      G.setInterval = function () { return 0; };
      G.clearInterval = silencio;
      G.requestAnimationFrame = function (fn) {
        return agendar(function () { fn(Date.now() - inicioMs); }, []);
      };
      G.cancelAnimationFrame = G.clearTimeout;
      G.queueMicrotask = function (fn) { agendar(fn, []); };

      G.__drenar = function (maximo) {
        var n = 0;
        while (fila.length > 0 && n < maximo) {
          var t = fila.shift();
          n++;
          try { t.fn.apply(null, t.args); } catch (e) { __erro('temporizador: ' + e); }
        }
        return fila.length;
      };

      G.console = {
        log: silencio, info: silencio, debug: silencio, warn: silencio, trace: silencio,
        table: silencio, time: silencio, timeEnd: silencio, group: silencio, groupEnd: silencio,
        error: function () { __erro('console.error: ' + Array.prototype.join.call(arguments, ' ')); }
      };

      G.window = G;
      G.self = G;
      G.top = G;
      G.parent = G;
      G.document = documento;
      documento.defaultView = G;
      G.location = localizacao;
      G.navigator = {
        userAgent: agente, appVersion: agente, platform: 'iPhone',
        language: 'pt-BR', languages: ['pt-BR', 'pt'], onLine: true,
        maxTouchPoints: 5, cookieEnabled: true, vendor: 'Apple Computer, Inc.'
      };
      G.localStorage = armazenamento();
      G.sessionStorage = armazenamento();
      G.performance = { now: function () { return Date.now() - inicioMs; }, timeOrigin: inicioMs };
      G.screen = { width: 375, height: 812, availWidth: 375, availHeight: 812, colorDepth: 24 };
      G.innerWidth = 375;
      G.innerHeight = 812;
      G.devicePixelRatio = 2;
      G.scrollX = 0;
      G.scrollY = 0;
      G.scrollTo = silencio;
      G.scroll = silencio;
      G.open = silencio;
      G.alert = silencio;
      G.confirm = function () { return false; };
      G.prompt = function () { return null; };
      G.addEventListener = silencio;
      G.removeEventListener = silencio;
      G.dispatchEvent = function () { return true; };
      G.getSelection = function () { return null; };
      G.getComputedStyle = function () { return { getPropertyValue: function () { return ''; } }; };
      G.matchMedia = function (q) {
        return { matches: false, media: String(q), addListener: silencio, removeListener: silencio, addEventListener: silencio, removeEventListener: silencio };
      };
      G.history = { pushState: silencio, replaceState: silencio, back: silencio, forward: silencio, go: silencio, state: null, length: 1 };
      G.crypto = {
        getRandomValues: function (a) { for (var i = 0; i < a.length; i++) { a[i] = Math.floor(Math.random() * 256); } return a; },
        randomUUID: function () {
          return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
            var r = Math.random() * 16 | 0;
            return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
          });
        }
      };
      G.fetch = function () { return Promise.reject(new Error('fetch ainda não ligado')); };
      G.Image = function () { return elementoFalso('img'); };
      G.Event = function (t) { this.type = t; };
      G.CustomEvent = G.Event;
      G.HTMLElement = function () {};
      G.Element = G.HTMLElement;
      G.Node = G.HTMLElement;
      G.Text = G.HTMLElement;
      G.MutationObserver = function () { this.observe = silencio; this.disconnect = silencio; this.takeRecords = function () { return []; }; };
      G.ResizeObserver = G.MutationObserver;
      G.IntersectionObserver = G.MutationObserver;
    })();
    """
}

// MARK: - Apoio

/// Guarda os erros da execução. Só é usado pela thread que roda o JavaScript.
private final class ColetorErros {
    private(set) var itens: [String] = []

    func adicionar(_ texto: String) {
        guard itens.count < 200 else { return }
        itens.append(texto)
    }
}

/// Entrega o resultado uma vez só, mesmo que a execução e o limite de tempo terminem juntos.
private final class Entrega {
    private let trava = NSLock()
    private var continuacao: CheckedContinuation<JSRodador.Relatorio, Never>?

    init(_ continuacao: CheckedContinuation<JSRodador.Relatorio, Never>) {
        self.continuacao = continuacao
    }

    func entregar(_ relatorio: JSRodador.Relatorio) {
        trava.lock()
        let c = continuacao
        continuacao = nil
        trava.unlock()
        c?.resume(returning: relatorio)
    }
}