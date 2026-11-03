import Foundation
import CoreGraphics

struct DrawItem: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let fontSize: CGFloat
    let bold: Bool
    /// Destino do link, como está no HTML (pode ser relativo). Nil quando não é link.
    let href: String?
    let text: String
}

enum Engine {
    static func render(html: String, width: Float) -> [DrawItem] {
        guard let raw = nusky_render(html, width) else { return [] }
        defer { nusky_free_string(raw) }
        let output = String(cString: raw)

        var items: [DrawItem] = []
        for line in output.split(separator: "\n") {
            // Campos: x, y, tamanho, negrito, link, texto. O texto fica por último.
            let fields = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false)
            guard fields.count == 6,
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
                text: String(fields[5])
            ))
        }
        return items
    }
}