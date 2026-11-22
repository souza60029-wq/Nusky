// app/Nusky/PerfisDeSite.swift
import Foundation

/// Ajustes de UM site. Cada perfil vale só para o endereço dele (e subdomínios): consertar o GitHub não muda o YouTube.
///
/// Onde ficam: a tabela de fábrica está aqui embaixo (`padrao`, em JSON, para ser fácil de ler e de editar). Se a lista
/// de sites baixada em Ajustes > Sobre trouxer um campo `"perfis"`, ele vale por cima: assim um conserto novo chega
/// pelo botão "Atualizar só a lista de sites", sem instalar o app de novo.
///
/// Campos (todos opcionais):
/// - `agente`: `"mobile"`, `"ios17"`, `"desktop"` ou um User-Agent inteiro. Vale para a página, o CSS e o fetch.
/// - `css`: CSS extra, aplicado por último.
/// - `js`: JavaScript que roda antes dos scripts da página (para definir uma função que o site espera).
/// - `honesto`: o navegador se apresenta como o iOS 15 de verdade: não define o JavaScript novo (Promise.withResolvers,
///   TextDecoderStream...), para sites que escolhem a versão do código pelo que existe.
/// - `semJS`: não roda o JavaScript do site (fica só o HTML do servidor com o CSS).
/// - `tempoJS`: segundos de espera pela primeira exibição (o padrão é 6).
/// - `maxFolhas`: máximo de folhas de CSS externas.
/// - `ignorarScripts`: trechos de endereço de scripts que não devem rodar.
/// - `nota`: só para quem edita; o app não usa.
struct PerfilDeSite: Decodable, Equatable {
    var agente: String?
    var css: String?
    var js: String?
    var honesto: Bool?
    var semJS: Bool?
    var tempoJS: Double?
    var maxFolhas: Int?
    var ignorarScripts: [String]?
    var nota: String?
}

enum PerfisDeSite {
    /// Tabela de fábrica. A chave é o domínio; vale também para os subdomínios (m.youtube.com usa "youtube.com").
    static let padrao = #"""
    {
      "claude.ai": {
        "honesto": true,
        "tempoJS": 10,
        "nota": "EXPERIMENTAL. O site mostra 'sua versão está desatualizada'. No Safari do mesmo aparelho ele abre, então a decisão parece vir do que o navegador diz ter. O modo honesto esconde o JavaScript novo que o Nusky costuma emprestar."
      },
      "youtube.com": {
        "tempoJS": 10,
        "nota": "Página pesada: espera mais pela primeira exibição."
      },
      "chatgpt.com": {
        "tempoJS": 10,
        "nota": "Página pesada: espera mais pela primeira exibição."
      },
      "arena.ai": {
        "tempoJS": 8
      }
    }
    """#

    private static let tabela: [String: PerfilDeSite] = carregar()

    /// Perfil do site, se houver. `host` pode vir com "www." e em qualquer caixa.
    static func para(host: String?) -> PerfilDeSite? {
        guard var h = host?.lowercased(), !h.isEmpty else { return nil }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        var melhor: (chave: String, perfil: PerfilDeSite)?
        for (chave, perfil) in tabela {
            guard h == chave || h.hasSuffix("." + chave) else { continue }
            if melhor == nil || chave.count > melhor!.chave.count {
                melhor = (chave, perfil)
            }
        }
        return melhor?.perfil
    }

    /// User-Agent para o site: o do perfil, se houver; senão o geral (mobile ou desktop, conforme os ajustes).
    static func agente(para host: String?) -> String {
        guard let escolha = para(host: host)?.agente, !escolha.isEmpty else {
            return IdentificacaoNavegador.atual
        }
        switch escolha.lowercased() {
        case "mobile": return IdentificacaoNavegador.mobile
        case "desktop": return IdentificacaoNavegador.desktop
        case "ios17": return IdentificacaoNavegador.mobileIOS17
        default: return escolha
        }
    }

    // MARK: - Leitura

    private static func carregar() -> [String: PerfilDeSite] {
        var resultado = decodificar(Data(padrao.utf8))
        if let caminho = try? ArquivoLista.caminho(),
           FileManager.default.fileExists(atPath: caminho.path),
           let dados = try? Data(contentsOf: caminho),
           let raiz = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
           let perfis = raiz["perfis"],
           JSONSerialization.isValidJSONObject(perfis),
           let bruto = try? JSONSerialization.data(withJSONObject: perfis) {
            for (chave, perfil) in decodificar(bruto) {
                resultado[chave] = perfil
            }
        }
        return resultado
    }

    /// Lê um perfil por vez: um perfil malformado não derruba os outros.
    private static func decodificar(_ dados: Data) -> [String: PerfilDeSite] {
        guard let objeto = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] else { return [:] }
        var saida: [String: PerfilDeSite] = [:]
        for (chave, valor) in objeto {
            guard JSONSerialization.isValidJSONObject(valor),
                  let bruto = try? JSONSerialization.data(withJSONObject: valor),
                  let perfil = try? JSONDecoder().decode(PerfilDeSite.self, from: bruto) else { continue }
            saida[chave.lowercased()] = perfil
        }
        return saida
    }
}
