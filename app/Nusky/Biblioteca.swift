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

/// Tela com os favoritos e o histórico.
struct BibliotecaView: View {
    @ObservedObject private var biblioteca = Biblioteca.compartilhada
    @Environment(\.dismiss) private var dismiss

    /// Página aberta agora, para o botão de favoritar.
    let urlAtual: URL?
    let aoAbrir: (URL) -> Void

    @State private var aba = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Seção", selection: $aba) {
                    Text("Favoritos").tag(0)
                    Text("Histórico").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if aba == 0 {
                    listaFavoritos
                } else {
                    listaVisitas
                }
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let url = urlAtual {
                        Button {
                            biblioteca.alternarFavorito(url: url)
                        } label: {
                            Image(systemName: biblioteca.ehFavorito(url.absoluteString) ? "star.fill" : "star")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var listaFavoritos: some View {
        if biblioteca.favoritos.isEmpty {
            vazio("Nenhum favorito ainda.", "Toque na estrela para guardar a página aberta.")
        } else {
            List {
                ForEach(biblioteca.favoritos) { f in
                    Button {
                        abrir(f.url)
                    } label: {
                        linha(titulo: f.titulo, endereco: f.url)
                    }
                }
                .onDelete { biblioteca.removerFavoritos(em: $0) }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var listaVisitas: some View {
        if biblioteca.visitas.isEmpty {
            vazio("Histórico vazio.", "As páginas que você abrir aparecem aqui, só neste aparelho.")
        } else {
            List {
                ForEach(biblioteca.visitas) { v in
                    Button {
                        abrir(v.url)
                    } label: {
                        linha(titulo: v.host, endereco: v.url)
                    }
                }
                .onDelete { biblioteca.removerVisitas(em: $0) }
            }
            .listStyle(.plain)
        }
    }

    private func linha(titulo: String, endereco: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(endereco)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func vazio(_ titulo: String, _ detalhe: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(titulo).font(.system(size: 17, weight: .medium))
            Text(detalhe)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private func abrir(_ texto: String) {
        guard let url = URL(string: texto) else { return }
        dismiss()
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