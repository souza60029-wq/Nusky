import SwiftUI
import UIKit

final class BrowserModel: ObservableObject {
    @Published var address = "https://example.com"
    @Published var currentHost = ""
    @Published var items: [DrawItem] = []
    @Published var contentHeight: CGFloat = 0
    @Published var status = ""

    /// Endereço final da página atual, depois de redirecionamentos. Base para links relativos.
    private var currentURL: URL?

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

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
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
                self.currentURL = response?.url ?? url
                self.items = items
                self.contentHeight = height + 16
                self.status = items.isEmpty ? "Página sem texto" : ""
            }
        }.resume()
    }

    /// Abre um link da página. Aceita caminhos relativos e só segue http e https.
    func open(_ href: String) {
        guard let target = URL(string: href, relativeTo: currentURL)?.absoluteURL,
              let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        address = target.absoluteString
        load()
    }
}

private enum BarMode {
    case collapsed   // linha fina com o domínio
    case expanded    // barra com botões, sem teclado
    case editing     // barra com botões e teclado
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var mode: BarMode = .expanded
    @State private var showSettings = false
    @FocusState private var focused: Bool
    @AppStorage("nightMode") private var nightMode = false
    @AppStorage("barAtBottom") private var barAtBottom = false

    /// Espaço reservado para a barra expandida. Fixo, para a página não se mexer ao retrair a barra.
    private let reserve: CGFloat = 56

    /// Largura da faixa de fade e recuo do texto. Os dois usam o mesmo valor,
    /// assim o texto começa logo depois da faixa e não é apagado por ela.
    private let fadeWidth: CGFloat = 14

    var body: some View {
        ZStack(alignment: barAtBottom ? Alignment.bottom : Alignment.top) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(model.items) { item in
                        Text(item.text)
                            .font(.system(size: item.fontSize, weight: item.bold ? .bold : .regular))
                            .foregroundColor(item.href == nil ? .primary : .blue)
                            .underline(item.href != nil)
                            .offset(x: item.x, y: item.y)
                            .onTapGesture {
                                if let href = item.href { model.open(href) }
                            }
                    }

                    if model.items.isEmpty && !model.status.isEmpty {
                        Text(model.status)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: model.contentHeight, alignment: .topLeading)
                .padding(barAtBottom ? Edge.Set.bottom : Edge.Set.top, reserve)
            }
            // Toque em qualquer lugar do conteúdo retrai a barra, sem bloquear a rolagem.
            .simultaneousGesture(TapGesture().onEnded { collapse() })

            addressBar
        }
        .preferredColorScheme(nightMode ? .dark : .light)
        .onAppear { model.load() }
        .onChange(of: focused) { isFocused in
            if !isFocused { collapse() }
        }
        .confirmationDialog("Configurações", isPresented: $showSettings, titleVisibility: .hidden) {
            Button(nightMode ? "Modo diurno" : "Modo noturno") {
                nightMode.toggle()
            }
            Button(barAtBottom ? "Mover barra para cima" : "Mover barra para baixo") {
                barAtBottom.toggle()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var addressBar: some View {
        let collapsed = mode == .collapsed

        return HStack(spacing: 6) {
            if !collapsed {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            barField(collapsed: collapsed)
                .frame(maxWidth: .infinity)

            if !collapsed {
                Button { model.load() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, collapsed ? 14 : 6)
        .frame(height: collapsed ? 26 : 40)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 12)
        // A área de toque é maior que a barra visível, principalmente quando retraída.
        .frame(maxWidth: .infinity, minHeight: collapsed ? 44 : 56)
        .contentShape(Rectangle())
        .onTapGesture { handleBarTap() }
    }

    @ViewBuilder
    private func barField(collapsed: Bool) -> some View {
        if collapsed {
            Text(model.currentHost.isEmpty ? "Pesquisar" : model.currentHost)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else {
            TextField("Endereço ou pesquisa", text: $model.address)
                .focused($focused)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.webSearch)
                .submitLabel(.go)
                // Na fase expandida, o toque passa para a barra e não para o campo.
                .allowsHitTesting(mode == .editing)
                // Recuo interno: o texto começa depois da faixa de fade.
                .padding(.horizontal, fadeWidth)
                .mask(fadeMask)
                .onSubmit {
                    model.load()
                    collapse()
                }
        }
    }

    /// Faixas de largura fixa nas bordas, com fade. O meio fica opaco.
    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Rectangle()
                .fill(Color.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
        }
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