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
}