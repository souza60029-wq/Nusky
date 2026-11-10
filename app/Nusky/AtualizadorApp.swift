// app/Nusky/AtualizadorApp.swift
import Foundation
import UIKit

/// Versão do app publicada no GitHub (Releases).
struct VersaoPublicada {
    let versao: String
    let ipa: URL
}

enum ErroAtualizacao: Error {
    /// O repositório ainda não tem nenhuma versão publicada.
    case semPublicacao
    /// A versão publicada não traz o arquivo de instalação.
    case semIPA
    case rede
}

/// Atualização do próprio app: consulta a última versão publicada no GitHub e entrega o arquivo de
/// instalação ao TrollStore. Só roda quando o usuário toca no botão; nada é verificado sozinho.
enum AtualizadorApp {
    static let repositorio = URL(string: "https://github.com/souza60029-wq/Nusky")!
    private static let api = URL(string: "https://api.github.com/repos/souza60029-wq/Nusky/releases/latest")!

    private struct Publicacao: Decodable {
        let tag_name: String
        let assets: [Arquivo]

        struct Arquivo: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    /// Consulta a publicação mais recente e o arquivo `.ipa` dela.
    static func buscar() async throws -> VersaoPublicada {
        var pedido = URLRequest(url: api)
        pedido.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        pedido.setValue("Nusky", forHTTPHeaderField: "User-Agent")
        pedido.timeoutInterval = 15
        pedido.cachePolicy = .reloadIgnoringLocalCacheData

        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        guard let http = resposta as? HTTPURLResponse else { throw ErroAtualizacao.rede }
        if http.statusCode == 404 { throw ErroAtualizacao.semPublicacao }
        guard http.statusCode == 200 else { throw ErroAtualizacao.rede }

        let publicacao = try JSONDecoder().decode(Publicacao.self, from: dados)
        guard let arquivo = publicacao.assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") }),
              let url = URL(string: arquivo.browser_download_url) else {
            throw ErroAtualizacao.semIPA
        }
        let versao = publicacao.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return VersaoPublicada(versao: versao, ipa: url)
    }

    /// Compara versões no formato 0.0.5, número por número.
    static func ehMaisNova(_ remota: String, que local: String) -> Bool {
        let a = remota.split(separator: ".").map { Int($0) ?? 0 }
        let b = local.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Abre o TrollStore para instalar o arquivo. O app fecha durante a instalação.
    @MainActor
    static func instalar(_ versao: VersaoPublicada) {
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "&=+?#")
        guard let codificado = versao.ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: permitidos),
              let url = URL(string: "apple-magnet://install?url=\(codificado)") else { return }
        UIApplication.shared.open(url)
    }
}
