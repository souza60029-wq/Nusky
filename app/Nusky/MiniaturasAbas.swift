// app/Nusky/MiniaturasAbas.swift
import UIKit

/// Miniaturas das abas para a tela de abas. Ficam em memória e em Application Support/Nusky/miniaturas,
/// só no aparelho. Cada miniatura é um JPEG pequeno.
@MainActor
final class MiniaturasAbas {
    static let compartilhada = MiniaturasAbas()

    private var memoria: [UUID: UIImage] = [:]

    private var pasta: URL {
        Caminhos.sessao.deletingLastPathComponent().appendingPathComponent("miniaturas", isDirectory: true)
    }

    private func arquivo(_ id: UUID) -> URL {
        pasta.appendingPathComponent("\(id.uuidString).jpg")
    }

    func guardar(_ imagem: UIImage, para id: UUID) {
        memoria[id] = imagem
        guard let dados = imagem.jpegData(compressionQuality: 0.6) else { return }
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try? dados.write(to: arquivo(id), options: .atomic)
    }

    func imagem(para id: UUID) -> UIImage? {
        if let pronta = memoria[id] { return pronta }
        guard let dados = try? Data(contentsOf: arquivo(id)), let lida = UIImage(data: dados) else { return nil }
        memoria[id] = lida
        return lida
    }

    func apagar(_ id: UUID) {
        memoria[id] = nil
        try? FileManager.default.removeItem(at: arquivo(id))
    }

    /// Apaga as miniaturas de abas que não existem mais.
    func manter(apenas ids: Set<UUID>) {
        for id in Array(memoria.keys) where !ids.contains(id) {
            apagar(id)
        }
    }
}
