import Foundation
import CoreGraphics

struct DrawItem: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let fontSize: CGFloat
    let bold: Bool
    let text: String
}

enum Engine {
    static func render(html: String, width: Float) -> [DrawItem] {
        guard let raw = nusky_render(html, width) else { return [] }
        defer { nusky_free_string(raw) }
        let output = String(cString: raw)

        var items: [DrawItem] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let x = Float(fields[0]),
                  let y = Float(fields[1]),
                  let size = Float(fields[2]),
                  let bold = Int(fields[3]) else { continue }
            items.append(DrawItem(
                x: CGFloat(x),
                y: CGFloat(y),
                fontSize: CGFloat(size),
                bold: bold == 1,
                text: String(fields[4])
            ))
        }
        return items
    }
}