// app/Nusky/RedeNusky.swift
import Foundation

/// Uma única sessão de rede para o JavaScript das páginas.
///
/// Antes, cada página criava uma sessão nova: cada script abria uma conexão e um handshake TLS
/// do zero, e nada ficava guardado. Com uma sessão só, as conexões HTTP/2 são reaproveitadas
/// (vários scripts do mesmo site viajam numa conexão) e o cache em disco guarda bibliotecas
/// (jQuery, React, fontes de ícones) que voltam em outras páginas sem baixar de novo.
enum RedeNusky {
    static let sessao: URLSession = {
        let config = URLSessionConfiguration.default
        // Pouca RAM no iPhone 6s: o cache vive principalmente em disco.
        config.urlCache = URLCache(memoryCapacity: 6 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config)
    }()
}
