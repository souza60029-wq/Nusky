// app/Nusky/ArmazemImagens.swift
import Foundation
import UIKit
import ImageIO

/// Baixa, decodifica e guarda as imagens das páginas.
///
/// Memória: a imagem é decodificada já reduzida (no máximo `maiorLado` pixels no lado maior),
/// nunca no tamanho original, e o cache tem limite de custo. O que passar do limite o sistema solta.
final class ArmazemImagens: @unchecked Sendable {
    static let compartilhado = ArmazemImagens()

    /// Aviso de que uma imagem nova ficou pronta e a tela pode ser redesenhada.
    static let aoCarregar = Notification.Name("NuskyImagemCarregada")

    private let cache = NSCache<NSString, UIImage>()
    private let sessao: URLSession
    private let limiteBytes = 6_000_000
    private let maiorLado: CGFloat = 1100

    private init() {
        cache.totalCostLimit = 40 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024, directory: nil)
        sessao = URLSession(configuration: config)
    }

    /// Chave do cache: o endereço completo. Imagens `data:` são longas, então usam o resumo do texto.
    static func chave(para url: URL) -> String {
        let texto = url.absoluteString
        if texto.hasPrefix("data:") { return "data:\(texto.hashValue)" }
        return texto
    }

    /// Imagem já pronta, se houver.
    func imagem(para chave: String) -> UIImage? {
        cache.object(forKey: chave as NSString)
    }

    /// Esvazia o cache de memória e o de disco.
    func limpar() {
        cache.removeAllObjects()
        sessao.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Baixa a imagem (ou lê o `data:`), guarda no cache e devolve o tamanho natural em pontos.
    /// Devolve nil se não conseguir ou se o formato não for imagem.
    func carregar(endereco: URL) async -> CGSize? {
        let chave = ArmazemImagens.chave(para: endereco)
        if let pronta = cache.object(forKey: chave as NSString) {
            return tamanhoNatural(de: pronta, guardado: chave)
        }

        let dados: Data
        if endereco.scheme?.lowercased() == "data" {
            guard let lidos = ArmazemImagens.lerDataURL(endereco.absoluteString) else { return nil }
            dados = lidos
        } else {
            do {
                var pedido = URLRequest(url: endereco)
                pedido.setValue("image/*,*/*;q=0.5", forHTTPHeaderField: "Accept")
                pedido.setValue(IdentificacaoNavegador.atual, forHTTPHeaderField: "User-Agent")
                let (baixados, resposta) = try await sessao.data(for: pedido)
                if let http = resposta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                dados = baixados
            } catch {
                return nil
            }
        }
        guard dados.count <= limiteBytes, !Task.isCancelled else { return nil }

        guard let (imagem, natural) = decodificar(dados) else { return nil }
        let custo = Int(imagem.size.width * imagem.size.height * imagem.scale * imagem.scale * 4)
        cache.setObject(imagem, forKey: chave as NSString, cost: custo)
        naturais.set(chave, natural)
        NotificationCenter.default.post(name: ArmazemImagens.aoCarregar, object: nil)
        return natural
    }

    // MARK: - Ícones de sites

    private let semIcone = ConjuntoGuardado()

    /// Ícone do site: o `favicon.ico` do próprio site. Quem não tem ícone não é pedido de novo.
    func icone(host: String) async -> UIImage? {
        guard !host.isEmpty, let url = URL(string: "https://\(host)/favicon.ico") else { return nil }
        let chave = ArmazemImagens.chave(para: url)
        if let pronto = imagem(para: chave) { return pronto }
        if semIcone.contem(host) { return nil }
        if await carregar(endereco: url) == nil {
            semIcone.inserir(host)
            return nil
        }
        return imagem(para: chave)
    }

    // MARK: - Apoio

    /// Tamanhos naturais já conhecidos (a imagem reduzida do cache perde o tamanho original).
    private let naturais = TamanhosGuardados()

    private func tamanhoNatural(de imagem: UIImage, guardado chave: String) -> CGSize {
        naturais.get(chave) ?? imagem.size
    }

    private func decodificar(_ dados: Data) -> (UIImage, CGSize)? {
        let opcoesFonte = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, opcoesFonte) else { return nil }

        var largura: CGFloat = 0
        var altura: CGFloat = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(fonte, 0, nil) as? [CFString: Any] {
            largura = CGFloat((props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0)
            altura = CGFloat((props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0)
        }

        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maiorLado
        ]
        guard let reduzida = CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary) else {
            return nil
        }

        // Se a foto estava girada (EXIF), o tamanho natural troca largura e altura.
        var natural = CGSize(width: largura, height: altura)
        if largura > 0, altura > 0 {
            let reduzidaEmPe = reduzida.height > reduzida.width
            let originalEmPe = altura > largura
            if reduzidaEmPe != originalEmPe { natural = CGSize(width: altura, height: largura) }
        } else {
            natural = CGSize(width: reduzida.width, height: reduzida.height)
        }
        guard natural.width > 0, natural.height > 0 else { return nil }
        return (UIImage(cgImage: reduzida), natural)
    }

    /// Lê `data:image/...;base64,XXXX` ou `data:image/...,texto%20codificado`.
    static func lerDataURL(_ texto: String) -> Data? {
        guard let virgula = texto.firstIndex(of: ",") else { return nil }
        let cabecalho = texto[texto.startIndex..<virgula].lowercased()
        let corpo = String(texto[texto.index(after: virgula)...])
        if cabecalho.contains(";base64") {
            let limpo = corpo.removingPercentEncoding ?? corpo
            return Data(base64Encoded: limpo, options: .ignoreUnknownCharacters)
        }
        return (corpo.removingPercentEncoding ?? corpo).data(using: .utf8)
    }
}

/// Conjunto protegido por trava.
private final class ConjuntoGuardado: @unchecked Sendable {
    private let trava = NSLock()
    private var itens = Set<String>()

    func contem(_ valor: String) -> Bool {
        trava.lock()
        defer { trava.unlock() }
        return itens.contains(valor)
    }

    func inserir(_ valor: String) {
        trava.lock()
        itens.insert(valor)
        trava.unlock()
    }
}

/// Dicionário protegido por trava, para vários downloads gravarem ao mesmo tempo.
private final class TamanhosGuardados: @unchecked Sendable {
    private let trava = NSLock()
    private var mapa: [String: CGSize] = [:]

    func get(_ chave: String) -> CGSize? {
        trava.lock()
        defer { trava.unlock() }
        return mapa[chave]
    }

    func set(_ chave: String, _ tamanho: CGSize) {
        trava.lock()
        mapa[chave] = tamanho
        trava.unlock()
    }
}

/// Transforma o endereço da imagem, como está no HTML, num endereço completo.
/// Só aceita http, https e data.
func resolverEnderecoDeImagem(_ src: String, base: URL) -> URL? {
    let limpo = src.trimmingCharacters(in: .whitespacesAndNewlines)
    if limpo.isEmpty { return nil }
    if limpo.lowercased().hasPrefix("data:") { return URL(string: limpo) }
    if limpo.hasPrefix("//") { return URL(string: "\(base.scheme ?? "https"):\(limpo)") }
    guard let url = URL(string: limpo, relativeTo: base)?.absoluteURL,
          let esquema = url.scheme?.lowercased(),
          esquema == "http" || esquema == "https" else { return nil }
    return url
}
