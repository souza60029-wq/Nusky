// app/Nusky/Engine.swift
import Foundation
import UIKit
import CoreGraphics

/// Cor de texto vinda do CSS da página, com componentes de 0 a 1.
struct CorTexto {
    let r: Double
    let g: Double
    let b: Double

    /// Luminância perceptiva: 0 é preto, 1 é branco.
    var luminancia: Double { 0.299 * r + 0.587 * g + 0.114 * b }
}

struct DrawItem: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let fontSize: CGFloat
    let bold: Bool
    /// Destino do link, como está no HTML (pode ser relativo). Nil quando não é link.
    let href: String?
    /// Cor definida pelo CSS da página. Nil quando a página não definiu cor.
    let cor: CorTexto?
    let text: String
    /// Itálico e fonte com serifa, como a página pediu.
    var italico = false
    var serifa = false
    /// Cor de destaque atrás do texto (por exemplo, uma palavra marcada).
    var fundo: CorTexto? = nil
}

/// Caixa de fundo de um bloco da página: cor sólida e/ou borda, com cantos arredondados.
struct Fundo: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
    let cor: CorTexto?
    let bordaLargura: CGFloat
    let bordaCor: CorTexto?
    let raio: CGFloat
}

/// Imagem (`<img>`) da página. Com largura e altura 0 o tamanho ainda não é conhecido:
/// o app baixa a imagem, aprende o tamanho e pede o layout de novo.
struct ImagemPagina: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let h: CGFloat
    /// Destino do link que envolve a imagem. Nil quando não é link.
    let href: String?
    /// Endereço como está no HTML (pode ser relativo).
    let src: String
}

/// Tinta de uma forma de SVG.
enum TintaSvg {
    case nenhuma
    /// `currentColor`: a cor do texto da página.
    case atual
    case rgb(Double, Double, Double)

    /// Lê `""` (nenhuma), `cur` ou `r,g,b`.
    init(_ texto: Substring) {
        if texto.isEmpty {
            self = .nenhuma
        } else if texto == "cur" {
            self = .atual
        } else {
            let partes = texto.split(separator: ",").compactMap { Double($0) }
            if partes.count == 3 {
                self = .rgb(partes[0] / 255, partes[1] / 255, partes[2] / 255)
            } else {
                self = .nenhuma
            }
        }
    }
}

/// Um caminho de SVG já na posição da página.
struct FormaVetor: Identifiable {
    let id = UUID()
    var preenchimento: TintaSvg
    var opacidadePreenchimento: CGFloat
    var traco: TintaSvg
    var opacidadeTraco: CGFloat
    var larguraTraco: CGFloat
    var parImpar: Bool
    let caminho: CGPath
    /// Retângulo que contém o caminho, com a folga do traço.
    let caixa: CGRect

    /// Lê os comandos `M x y`, `L x y`, `C x1 y1 x2 y2 x y` e `Z`.
    static func caminho(de texto: Substring) -> CGPath? {
        let caminho = CGMutablePath()
        let t = texto.split(separator: " ")
        var i = 0
        func numeros(_ n: Int) -> [CGFloat]? {
            guard i + n <= t.count else { return nil }
            var saida: [CGFloat] = []
            for k in 0..<n {
                guard let v = Double(t[i + k]) else { return nil }
                saida.append(CGFloat(v))
            }
            i += n
            return saida
        }
        while i < t.count {
            let comando = t[i]
            i += 1
            switch comando {
            case "M":
                guard let n = numeros(2) else { return nil }
                caminho.move(to: CGPoint(x: n[0], y: n[1]))
            case "L":
                guard let n = numeros(2) else { return nil }
                caminho.addLine(to: CGPoint(x: n[0], y: n[1]))
            case "C":
                guard let n = numeros(6) else { return nil }
                caminho.addCurve(
                    to: CGPoint(x: n[4], y: n[5]),
                    control1: CGPoint(x: n[0], y: n[1]),
                    control2: CGPoint(x: n[2], y: n[3])
                )
            case "Z":
                caminho.closeSubpath()
            default:
                return nil
            }
        }
        return caminho
    }
}

/// Tudo o que o motor desenha numa página: textos, caixas de fundo, imagens, formas de SVG
/// e a cor de fundo da página.
struct PaginaDesenhada {
    var itens: [DrawItem] = []
    var fundos: [Fundo] = []
    var imagens: [ImagemPagina] = []
    var formas: [FormaVetor] = []
    var fundoPagina: CorTexto? = nil
}

/// Um resultado da busca por nome: um site ou um atalho de site.
struct ResultadoBusca: Identifiable, Equatable {
    /// Endereço para abrir.
    let endereco: String
    /// Nome do site, como está na lista.
    let nome: String
    /// Título do atalho. Vazio quando o resultado é o próprio site.
    let titulo: String

    var id: String { endereco }
}

/// Sugestão mostrada quando a busca não acha nada ("você quis dizer…").
struct SugestaoBusca: Equatable {
    let nome: String
    let endereco: String
}

/// Mede a largura de um texto com a mesma fonte do sistema que o SwiftUI usa para desenhar.
/// Não captura nada, para poder ser passada ao motor como função C.
private let measureCallback: nusky_measure_fn = { text, size, bold in
    guard let text = text else { return 0 }
    let string = String(cString: text)
    let font = bold != 0
        ? UIFont.boldSystemFont(ofSize: CGFloat(size))
        : UIFont.systemFont(ofSize: CGFloat(size))
    return Float((string as NSString).size(withAttributes: [.font: font]).width)
}

enum Engine {

    // MARK: - Renderização

    static func render(html: String, width: Float) -> [DrawItem] {
        renderCompleto(html: html, width: width).itens
    }

    /// Textos, caixas de fundo e cor de fundo da página.
    /// Linhas do motor: `B<TAB>r,g,b` (fundo da página), `R<TAB>x y w h cor borda corBorda raio`
    /// (caixa de fundo, de fora para dentro) e as linhas de texto de sempre.
    static func renderCompleto(
        html: String,
        width: Float,
        tamanhos: [String: CGSize] = [:]
    ) -> PaginaDesenhada {
        // Tamanho natural das imagens já baixadas: endereco<TAB>largura<TAB>altura.
        let linhasTamanho = tamanhos.compactMap { (src, tamanho) -> String? in
            guard tamanho.width > 0, tamanho.height > 0 else { return nil }
            let limpo = src.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            return "\(limpo)\t\(tamanho.width)\t\(tamanho.height)"
        }
        let textoTamanhos = linhasTamanho.joined(separator: "\n")
        let bruto: UnsafeMutablePointer<CChar>? = textoTamanhos.withCString { tam in
            nusky_render_imagens(html, width, measureCallback, tam)
        }
        guard let raw = bruto else { return PaginaDesenhada() }
        defer { nusky_free_string(raw) }
        let output = String(cString: raw)

        var items: [DrawItem] = []
        var fundos: [Fundo] = []
        var imagens: [ImagemPagina] = []
        var formas: [FormaVetor] = []
        var fundoPagina: CorTexto? = nil
        for line in output.split(separator: "\n") {
            if line.hasPrefix("V\t") {
                let c = line.split(separator: "\t", maxSplits: 7, omittingEmptySubsequences: false)
                guard c.count == 8,
                      let opPreenchimento = Double(c[2]), let opTraco = Double(c[4]),
                      let largura = Double(c[5]),
                      let caminho = FormaVetor.caminho(de: c[7]) else { continue }
                let folga = CGFloat(largura) + 1
                formas.append(FormaVetor(
                    preenchimento: TintaSvg(c[1]),
                    opacidadePreenchimento: CGFloat(opPreenchimento),
                    traco: TintaSvg(c[3]),
                    opacidadeTraco: CGFloat(opTraco),
                    larguraTraco: CGFloat(largura),
                    parImpar: c[6] == "1",
                    caminho: caminho,
                    caixa: caminho.boundingBoxOfPath.insetBy(dx: -folga, dy: -folga)
                ))
                continue
            }
            if line.hasPrefix("I\t") {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard c.count == 7,
                      let x = Float(c[1]), let y = Float(c[2]),
                      let w = Float(c[3]), let h = Float(c[4]) else { continue }
                imagens.append(ImagemPagina(
                    x: CGFloat(x), y: CGFloat(y), w: CGFloat(w), h: CGFloat(h),
                    href: c[5].isEmpty ? nil : String(c[5]),
                    src: String(c[6])
                ))
                continue
            }
            if line.hasPrefix("B\t") {
                let campos = line.split(separator: "\t", omittingEmptySubsequences: false)
                if campos.count == 2 { fundoPagina = parseCor(campos[1]) }
                continue
            }
            if line.hasPrefix("R\t") {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard c.count == 9,
                      let x = Float(c[1]), let y = Float(c[2]),
                      let w = Float(c[3]), let h = Float(c[4]),
                      let bordaL = Float(c[6]), let raio = Float(c[8]) else { continue }
                fundos.append(Fundo(
                    x: CGFloat(x), y: CGFloat(y), w: CGFloat(w), h: CGFloat(h),
                    cor: parseCor(c[5]),
                    bordaLargura: CGFloat(bordaL),
                    bordaCor: parseCor(c[7]),
                    raio: CGFloat(raio)
                ))
                continue
            }
            // Campos: x, y, tamanho, negrito, link, cor, estilo (i, s), fundo, texto. O texto fica por último.
            let fields = line.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false)
            guard fields.count == 9,
                  let x = Float(fields[0]),
                  let y = Float(fields[1]),
                  let size = Float(fields[2]),
                  let bold = Int(fields[3]) else { continue }

            let href = fields[4].isEmpty ? nil : String(fields[4])
            items.append(DrawItem(
                x: CGFloat(x),
                y: CGFloat(y),
                fontSize: CGFloat(size),
                bold: bold == 1,
                href: href,
                cor: parseCor(fields[5]),
                text: String(fields[8]),
                italico: fields[6].contains("i"),
                serifa: fields[6].contains("s"),
                fundo: parseCor(fields[7])
            ))
        }
        return PaginaDesenhada(itens: items, fundos: fundos, imagens: imagens, formas: formas, fundoPagina: fundoPagina)
    }

    /// Árvore do HTML em JSON (o parser do motor), para o JavaScript montar o document.
    /// Nil se o motor não devolver nada.
    static func arvore(html: String) -> String? {
        guard let raw = nusky_arvore(html) else { return nil }
        defer { nusky_free_string(raw) }
        return String(cString: raw)
    }

    /// "r,g,b" com valores de 0 a 255. Campo vazio quando a página não definiu cor.
    private static func parseCor(_ campo: Substring) -> CorTexto? {
        let partes = campo.split(separator: ",")
        guard partes.count == 3,
              let r = Int(partes[0]),
              let g = Int(partes[1]),
              let b = Int(partes[2]) else { return nil }
        return CorTexto(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
    }

    // MARK: - Busca por nome

    /// Chave onde as contagens de abertura ficam salvas no aparelho.
    private static let chaveUsos = "buscaUsos"

    /// Carrega a lista ao abrir o app.
    /// Usa a lista baixada, se existir e for igual ou mais nova que a embutida.
    /// Se o app novo trouxer uma lista embutida mais nova, a baixada é apagada e a embutida passa a valer.
    /// Devolve false se nem a embutida conseguir ser lida.
    @discardableResult
    static func iniciarBusca() -> Bool {
        // Carrega a embutida primeiro, para saber a versão dela.
        guard nusky_busca_carregar(nil) == 0 else { return false }
        let versaoEmbutida = nusky_busca_versao()

        if let salva = listaSalva(), nusky_busca_carregar(salva) == 0 {
            if nusky_busca_versao() < versaoEmbutida {
                // A lista baixada é mais antiga que a embutida deste app: volta para a embutida.
                _ = nusky_busca_carregar(nil)
                apagarListaSalva()
            }
        }
        nusky_busca_definir_usos(textoDeUsos(usosSalvos()))
        return true
    }

    /// Versão da lista em uso no motor. Zero se nenhuma lista tiver versão legível.
    static var versaoEmUso: Int {
        Int(nusky_busca_versao())
    }

    /// Data da lista em uso, no formato aaaa-mm-dd. Vazia se não houver.
    static var dataEmUso: String {
        guard let raw = nusky_busca_data() else { return "" }
        defer { nusky_free_string(raw) }
        return String(cString: raw)
    }

    /// Texto da lista baixada e guardada no aparelho. Nil se não existir ou não puder ser lido.
    private static func listaSalva() -> String? {
        guard let caminho = try? ArquivoLista.caminho(),
              FileManager.default.fileExists(atPath: caminho.path) else { return nil }
        return try? String(contentsOf: caminho, encoding: .utf8)
    }

    /// Remove a lista baixada do aparelho. Não faz nada se ela não existir.
    private static func apagarListaSalva() {
        guard let caminho = try? ArquivoLista.caminho() else { return }
        try? FileManager.default.removeItem(at: caminho)
    }

    /// Troca a lista em uso pela versão baixada. Se ela estiver errada,
    /// a lista anterior continua valendo e a função devolve false.
    @discardableResult
    static func atualizarLista(json: String) -> Bool {
        nusky_busca_carregar(json) == 0
    }

    /// Soma uma abertura a um endereço aberto pela busca. Fica só no aparelho.
    static func registrarUso(endereco: String) {
        nusky_busca_registrar_uso(endereco)
        var usos = usosSalvos()
        usos[endereco, default: 0] += 1
        UserDefaults.standard.set(usos, forKey: chaveUsos)
    }

    /// Resultados para o que foi digitado, do mais relevante para o menos.
    static func buscar(_ consulta: String) -> [ResultadoBusca] {
        guard let raw = nusky_busca(consulta) else { return [] }
        defer { nusky_free_string(raw) }
        return String(cString: raw).split(separator: "\n").compactMap { linha in
            // Campos: endereço, nome, título do atalho (pode ser vazio).
            let campos = linha.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard campos.count == 3 else { return nil }
            return ResultadoBusca(
                endereco: String(campos[0]),
                nome: String(campos[1]),
                titulo: String(campos[2])
            )
        }
    }

    /// Sugestão para quando a busca não acha nada. Nil se não houver nada parecido.
    static func sugestao(para consulta: String) -> SugestaoBusca? {
        guard let raw = nusky_busca_sugestao(consulta) else { return nil }
        defer { nusky_free_string(raw) }
        let texto = String(cString: raw).trimmingCharacters(in: .newlines)
        let campos = texto.split(separator: "\t", omittingEmptySubsequences: false)
        guard campos.count == 2 else { return nil }
        return SugestaoBusca(nome: String(campos[0]), endereco: String(campos[1]))
    }

    // MARK: - Contagens de abertura

    private static func usosSalvos() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: chaveUsos) as? [String: Int] ?? [:]
    }

    /// Uma linha por endereço, no formato que o motor espera: endereco<TAB>contagem.
    private static func textoDeUsos(_ usos: [String: Int]) -> String {
        usos.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
    }
}