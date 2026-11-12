// app/Nusky/Desempenho.swift
import UIKit
import QuartzCore

/// Medidor de desempenho do app, usado pelo diagnóstico para dizer o que está pesando.
///
/// Conta o tempo de cada quadro da tela (um CADisplayLink leve), o tempo de desenhar a página,
/// o tempo do layout do motor e o tempo do desenho em Metal. Também mede a fluidez nos 1,5 segundo
/// seguintes a ações marcadas (abrir ajustes, abrir a barra, começar a rolar).
final class Desempenho: NSObject, @unchecked Sendable {
    static let compartilhado = Desempenho()

    private let trava = NSLock()
    private var link: CADisplayLink?
    private var ultimoQuadro: CFTimeInterval = 0
    private var quadros: [Double] = []

    private struct Janela {
        var nome: String
        var inicio: CFTimeInterval
        var quadros = 0
        var lentos = 0
        var pior = 0.0
    }
    private var janela: Janela?
    private var eventos: [String] = []

    private var desenhos: [Double] = []
    private var layouts: [Double] = []
    private var metais: [Double] = []

    /// Quantidade de coisas na página aberta: itens de texto, caixas de fundo, imagens e formas de SVG.
    var conteudo: (itens: Int, fundos: Int, imagens: Int, formas: Int) = (0, 0, 0, 0)

    /// Liga o contador de quadros. Chamar uma vez, na tela principal.
    @MainActor
    func iniciar() {
        guard link == nil else { return }
        let novo = CADisplayLink(target: self, selector: #selector(passouQuadro(_:)))
        novo.add(to: .main, forMode: .common)
        link = novo
    }

    @objc private func passouQuadro(_ l: CADisplayLink) {
        let agora = l.timestamp
        defer { ultimoQuadro = agora }
        guard ultimoQuadro > 0 else { return }
        let ms = (agora - ultimoQuadro) * 1000
        // Intervalo enorme: o app ficou em segundo plano. Não conta.
        guard ms < 700 else { return }

        trava.lock()
        quadros.append(ms)
        if quadros.count > 600 { quadros.removeFirst(quadros.count - 600) }
        if var j = janela {
            j.quadros += 1
            if ms > 25 { j.lentos += 1 }
            j.pior = max(j.pior, ms)
            if agora - j.inicio >= 1.5 {
                eventos.append("\(j.nome): \(j.quadros) quadros, \(j.lentos) lentos (acima de 25 ms), pior \(Int(j.pior)) ms")
                if eventos.count > 10 { eventos.removeFirst() }
                janela = nil
            } else {
                janela = j
            }
        }
        trava.unlock()
    }

    /// Começa a medir a fluidez dos próximos 1,5 segundo, com este nome.
    func marcar(_ nome: String) {
        trava.lock()
        if janela == nil {
            janela = Janela(nome: nome, inicio: CACurrentMediaTime())
        }
        trava.unlock()
    }

    func registrarDesenho(_ ms: Double) { acrescentar(&desenhos, ms) }
    func registrarLayout(_ ms: Double) { acrescentar(&layouts, ms) }
    func registrarMetal(_ ms: Double) { acrescentar(&metais, ms) }

    private func acrescentar(_ lista: inout [Double], _ ms: Double) {
        trava.lock()
        lista.append(ms)
        if lista.count > 400 { lista.removeFirst(lista.count - 400) }
        trava.unlock()
    }

    // MARK: Relatório

    private func resumo(_ lista: [Double]) -> (n: Int, media: Double, pior: Double) {
        guard !lista.isEmpty else { return (0, 0, 0) }
        return (lista.count, lista.reduce(0, +) / Double(lista.count), lista.max() ?? 0)
    }

    private func ms(_ v: Double) -> String {
        String(format: "%.1f ms", v)
    }

    /// Texto para o diagnóstico: números e as causas mais prováveis, na ordem em que aparecem.
    func relatorio() -> String {
        trava.lock()
        let q = quadros
        let ev = eventos
        let d = resumo(desenhos)
        let l = resumo(layouts)
        let m = resumo(metais)
        let c = conteudo
        trava.unlock()

        let ajustes = UserDefaults.standard
        func ligado(_ chave: String, padrao: Bool) -> Bool {
            ajustes.object(forKey: chave) as? Bool ?? padrao
        }
        let desfoque = ligado(ChavesTema.desfoque, padrao: true)
        let metal = ligado("usarMetal", padrao: false)
        let luminoso = ligado(ChavesTema.feedbackLuminoso, padrao: true)
        let expansivo = ligado(ChavesTema.feedbackExpansivo, padrao: true)
        let noturno = ligado(ChavesTema.forcarNoturno, padrao: false)

        var linhas = ["DESEMPENHO DO APP"]

        if q.isEmpty {
            linhas.append("Fluidez da interface: sem medição ainda (use o app por alguns segundos e meça de novo).")
        } else {
            let media = q.reduce(0, +) / Double(q.count)
            let pior = q.max() ?? 0
            let lentos = q.filter { $0 > 25 }.count
            let porcento = Double(lentos) / Double(q.count) * 100
            linhas.append(String(
                format: "Fluidez da interface (últimos %d quadros): média %.1f ms (cerca de %d quadros por segundo), pior %d ms",
                q.count, media, Int(1000 / max(media, 1)), Int(pior)
            ))
            linhas.append(String(format: "Quadros lentos (acima de 25 ms): %d, ou %.0f%%", lentos, porcento))
        }

        linhas.append("")
        linhas.append("Fluidez logo depois de cada ação (1,5 s):")
        if ev.isEmpty {
            linhas.append("  nenhuma ação medida ainda")
        } else {
            for e in ev.suffix(6) { linhas.append("  - " + e) }
        }

        linhas.append("")
        linhas.append("Tempos do desenho:")
        linhas.append(d.n == 0
            ? "  Blocos desenhados pela CPU: nenhum"
            : "  Blocos desenhados pela CPU: \(d.n), média \(ms(d.media)), pior \(ms(d.pior))")
        linhas.append(m.n == 0
            ? "  Quadros em Metal: nenhum"
            : "  Quadros em Metal: \(m.n), média \(ms(m.media)), pior \(ms(m.pior))")
        linhas.append(l.n == 0
            ? "  Layout do motor: nenhum"
            : "  Layout do motor: \(l.n), média \(ms(l.media)), pior \(ms(l.pior))")

        linhas.append("")
        linhas.append("Página aberta: \(c.itens) textos, \(c.fundos) caixas de fundo, \(c.imagens) imagens, \(c.formas) formas de SVG")
        linhas.append("Opções: desfoque \(desfoque ? "ligado" : "desligado"), Metal \(metal ? "ligado" : "desligado"), "
            + "brilho de toque \(luminoso ? "ligado" : "desligado"), pulso de toque \(expansivo ? "ligado" : "desligado"), "
            + "modo noturno forçado \(noturno ? "ligado" : "desligado")")

        // Causas prováveis, da mais forte para a mais fraca.
        var causas: [String] = []
        let lentosTotal = q.isEmpty ? 0 : Double(q.filter { $0 > 25 }.count) / Double(q.count)
        if d.n > 0 && d.media > 10 {
            causas.append("O desenho da página pela CPU está pesado (média \(ms(d.media)) por bloco). Ligue o Metal em Ajustes > Navegação.")
        }
        if l.n > 0 && l.media > 120 {
            causas.append("O layout do motor demora (média \(ms(l.media))). A página é grande ou tem muitas imagens que refazem o layout.")
        }
        for e in ev where e.contains("Ajustes") && e.contains("pior") {
            if let trecho = e.split(separator: " ").last, let valor = Int(trecho.replacingOccurrences(of: "ms", with: "")), valor > 90 {
                causas.append("Abrir os Ajustes teve um quadro de \(valor) ms. Com o desfoque ligado, o fundo do menu é uma foto borrada tirada uma vez; se ainda trava, desligue o desfoque para comparar.")
            }
        }
        if desfoque && lentosTotal > 0.1 {
            causas.append("Há muitos quadros lentos com o desfoque ligado. Desligue o efeito de desfoque em Ajustes > Aparência e meça de novo.")
        }
        if luminoso && expansivo && lentosTotal > 0.1 {
            causas.append("O brilho e o pulso de toque rodam juntos. Desligue um dos dois e meça de novo.")
        }
        if c.imagens > 30 {
            causas.append("Muitas imagens na página (\(c.imagens)). Desligue \"Mostrar imagens\" para comparar.")
        }
        if causas.isEmpty {
            linhas.append("")
            linhas.append("Nenhuma causa óbvia nos números. Se ainda parece travar, faça a ação lenta e rode o diagnóstico logo em seguida: a fluidez de cada ação aparece acima.")
        } else {
            linhas.append("")
            linhas.append("POSSÍVEIS CAUSAS:")
            for causa in causas { linhas.append("  - " + causa) }
        }
        return linhas.joined(separator: "\n")
    }
}
