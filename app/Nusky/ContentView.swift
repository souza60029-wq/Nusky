import SwiftUI
import UIKit

final class BrowserModel: ObservableObject {
    @Published var address = "https://example.com"
    @Published var currentHost = ""
    @Published var items: [DrawItem] = []
    @Published var contentHeight: CGFloat = 0
    @Published var status = ""

    func load() {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else {
            status = "Endereço inválido"
            return
        }

        currentHost = url.host ?? s
        status = "Carregando…"
        let width = Float(UIScreen.main.bounds.width)

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let html = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let items = Engine.render(html: html, width: width)
            let height = items.map { $0.y + $0.fontSize * 1.3 }.max() ?? 0

            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.items = []
                    self.status = error.localizedDescription
                    return
                }
                self.items = items
                self.contentHeight = height + 16
                self.status = items.isEmpty ? "Página sem texto" : ""
            }
        }.resume()
    }
}

private enum BarMode {
    case collapsed   // linha fina com o domínio
    case expanded    // barra normal, sem teclado
    case editing     // barra normal, com teclado
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var mode: BarMode = .expanded
    @FocusState private var focused: Bool

    /// Altura reservada no topo do conteúdo. Fixa, para a página não se mexer durante a animação.
    private let topInset: CGFloat = 44

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(model.items) { item in
                        Text(item.text)
                            .font(.system(size: item.fontSize, weight: item.bold ? .bold : .regular))
                            .offset(x: item.x, y: item.y)
                    }

                    if model.items.isEmpty && !model.status.isEmpty {
                        Text(model.status)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: model.contentHeight, alignment: .topLeading)
                .padding(.top, topInset)
            }
            // Toque em qualquer lugar do conteúdo retrai a barra, sem bloquear a rolagem.
            .simultaneousGesture(TapGesture().onEnded { collapse() })

            addressBar
        }
        .onAppear { model.load() }
        .onChange(of: focused) { isFocused in
            if !isFocused { collapse() }
        }
    }

    private var addressBar: some View {
        VStack(spacing: 0) {
            if mode == .collapsed {
                Text(model.currentHost.isEmpty ? "Pesquisar" : model.currentHost)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
            } else {
                TextField("Endereço ou pesquisa", text: $model.address)
                    .focused($focused)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    // Na fase expandida, o toque passa para a barra e não para o campo.
                    .allowsHitTesting(mode == .editing)
                    .padding(.horizontal, 8)
                    .onSubmit {
                        model.load()
                        collapse()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mode == .collapsed ? topInset : 56)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { handleBarTap() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func handleBarTap() {
        switch mode {
        case .collapsed:
            withAnimation(.easeInOut(duration: 0.2)) { mode = .expanded }
        case .expanded:
            mode = .editing
            focused = true
        case .editing:
            break
        }
    }

    private func collapse() {
        guard mode != .collapsed else { return }
        focused = false
        withAnimation(.easeInOut(duration: 0.2)) { mode = .collapsed }
    }
}