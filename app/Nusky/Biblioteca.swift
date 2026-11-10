// app/Nusky/Biblioteca.swift
import SwiftUI
import UIKit

/// Favorito guardado no aparelho.
struct Favorito: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: String
    var titulo: String
}

/// Página visitada. Só o endereço e a hora, no aparelho.
struct Visita: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: String
    var data: Date

    var host: String { URL(string: url)?.host ?? url }
}

/// Favoritos e histórico de visitas. Tudo fica em Application Support/Nusky, nada sai do aparelho.
@MainActor
final class Biblioteca: ObservableObject {
    static let compartilhada = Biblioteca()

    @Published private(set) var favoritos: [Favorito] = []
    @Published private(set) var visitas: [Visita] = []

    private let limiteVisitas = 300

    private init() {
        favoritos = Biblioteca.ler([Favorito].self, de: Biblioteca.arquivoFavoritos) ?? []
        visitas = Biblioteca.ler([Visita].self, de: Biblioteca.arquivoVisitas) ?? []
    }

    // MARK: Favoritos

    func ehFavorito(_ url: String) -> Bool {
        favoritos.contains { $0.url == url }
    }

    func alternarFavorito(url: URL) {
        let texto = url.absoluteString
        if let i = favoritos.firstIndex(where: { $0.url == texto }) {
            favoritos.remove(at: i)
        } else {
            favoritos.insert(Favorito(url: texto, titulo: url.host ?? texto), at: 0)
        }
        Biblioteca.gravar(favoritos, em: Biblioteca.arquivoFavoritos)
    }

    func removerFavoritos(em posicoes: IndexSet) {
        favoritos.remove(atOffsets: posicoes)
        Biblioteca.gravar(favoritos, em: Biblioteca.arquivoFavoritos)
    }

    // MARK: Visitas

    func registrarVisita(_ url: URL) {
        let texto = url.absoluteString
        if visitas.first?.url == texto { return }
        visitas.insert(Visita(url: texto, data: Date()), at: 0)
        if visitas.count > limiteVisitas {
            visitas.removeLast(visitas.count - limiteVisitas)
        }
        Biblioteca.gravar(visitas, em: Biblioteca.arquivoVisitas)
    }

    func removerVisitas(em posicoes: IndexSet) {
        visitas.remove(atOffsets: posicoes)
        Biblioteca.gravar(visitas, em: Biblioteca.arquivoVisitas)
    }

    func limparVisitas() {
        visitas = []
        Biblioteca.gravar(visitas, em: Biblioteca.arquivoVisitas)
    }

    // MARK: Disco

    private static var pasta: URL {
        Caminhos.sessao.deletingLastPathComponent()
    }

    private static var arquivoFavoritos: URL { pasta.appendingPathComponent("favoritos.json") }
    private static var arquivoVisitas: URL { pasta.appendingPathComponent("visitas.json") }

    private static func ler<T: Decodable>(_ tipo: T.Type, de arquivo: URL) -> T? {
        guard let dados = try? Data(contentsOf: arquivo) else { return nil }
        return try? JSONDecoder().decode(tipo, from: dados)
    }

    private static func gravar<T: Encodable>(_ valor: T, em arquivo: URL) {
        guard let dados = try? JSONEncoder().encode(valor) else { return }
        try? dados.write(to: arquivo, options: .atomic)
    }
}

/// Tela com os favoritos e o histórico, no estilo dos menus do app.
struct BibliotecaView: View {
    @ObservedObject private var biblioteca = Biblioteca.compartilhada

    /// Página aberta agora, para o botão de favoritar.
    let urlAtual: URL?
    let fundoEscuro: Bool
    let aoAbrir: (URL) -> Void
    let aoFechar: () -> Void

    @State private var aba = 0

    var body: some View {
        PainelVidro(titulo: "Biblioteca", fundoEscuro: fundoEscuro, aoFechar: aoFechar) {
            VStack(spacing: 0) {
                abas
                ScrollView {
                    VStack(spacing: 10) {
                        if aba == 0 {
                            favoritos
                        } else {
                            visitas
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var abas: some View {
        HStack(spacing: 8) {
            chip("Favoritos", "star", 0)
            chip("Histórico", "clock", 1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func chip(_ titulo: String, _ icone: String, _ valor: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { aba = valor }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icone)
                    .font(.system(size: 13, weight: .semibold))
                Text(titulo)
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .opacity(aba == valor ? 1 : 0.6)
            .contentShape(Capsule())
        }
        .buttonStyle(EstiloToque(forma: .capsula))
    }

    @ViewBuilder
    private var favoritos: some View {
        if let url = urlAtual {
            Button {
                biblioteca.alternarFavorito(url: url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: biblioteca.ehFavorito(url.absoluteString) ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .medium))
                    Text(biblioteca.ehFavorito(url.absoluteString) ? "Página atual nos favoritos" : "Adicionar a página atual")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(EstiloToque(forma: .retangulo(18)))
        }

        if biblioteca.favoritos.isEmpty {
            vazio("Nenhum favorito ainda.", "Toque em \"Adicionar a página atual\" para guardar o site aberto.")
        } else {
            ForEach(biblioteca.favoritos) { f in
                linha(titulo: f.titulo, endereco: f.url, host: URL(string: f.url)?.host ?? "") {
                    abrir(f.url)
                } apagar: {
                    if let i = biblioteca.favoritos.firstIndex(of: f) {
                        biblioteca.removerFavoritos(em: IndexSet(integer: i))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var visitas: some View {
        if biblioteca.visitas.isEmpty {
            vazio("Histórico vazio.", "As páginas que você abrir aparecem aqui, só neste aparelho.")
        } else {
            ForEach(biblioteca.visitas) { v in
                linha(titulo: v.host, endereco: v.url, host: v.host) {
                    abrir(v.url)
                } apagar: {
                    if let i = biblioteca.visitas.firstIndex(of: v) {
                        biblioteca.removerVisitas(em: IndexSet(integer: i))
                    }
                }
            }
        }
    }

    private func linha(
        titulo: String,
        endereco: String,
        host: String,
        abrir: @escaping () -> Void,
        apagar: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: abrir) {
                HStack(spacing: 12) {
                    IconeDoSite(host: host, tamanho: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titulo)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(endereco)
                            .font(.system(size: 12))
                            .opacity(0.6)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(EstiloToque(forma: .retangulo(18)))

            Button(action: apagar) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(EstiloToque(forma: .circulo))
            .accessibilityLabel("Apagar")
        }
    }

    private func vazio(_ titulo: String, _ detalhe: String) -> some View {
        VStack(spacing: 6) {
            Text(titulo).font(.system(size: 17, weight: .semibold))
            Text(detalhe)
                .font(.system(size: 14))
                .opacity(0.6)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private func abrir(_ texto: String) {
        guard let url = URL(string: texto) else { return }
        aoFechar()
        aoAbrir(url)
    }
}

/// Folha de compartilhamento do iOS.
struct FolhaDeCompartilhar: UIViewControllerRepresentable {
    let itens: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: itens, applicationActivities: nil)
    }

    func updateUIViewController(_ controlador: UIActivityViewController, context: Context) {}
}
