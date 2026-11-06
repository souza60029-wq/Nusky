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
        guard let raw = nusky_render(html, width, measureCallback) else { return [] }
        defer { nusky_free_string(raw) }
        let output = String(cString: raw)

        var items: [DrawItem] = []
        for line in output.split(separator: "\n") {
            // Campos: x, y, tamanho, negrito, link, cor, texto. O texto fica por último.
            let fields = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count == 7,
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
                text: String(fields[6])
            ))
        }
        return items
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

    /// Carrega a lista embutida no app e as contagens salvas. Chamar uma vez, ao abrir o app.
    /// Devolve false se a lista embutida não conseguir ser lida.
    @discardableResult
    static func iniciarBusca() -> Bool {
        let ok = nusky_busca_carregar(nil) == 0
        nusky_busca_definir_usos(textoDeUsos(usosSalvos()))
        return ok
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