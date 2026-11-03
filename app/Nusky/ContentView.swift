import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @AppStorage("nightMode") private var nightMode = false
    @AppStorage("barAtBottom") private var barAtBottom = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var fieldFocused: Bool
    @State private var expanded = false
    @State private var showActions = false
    @State private var showTabs = false

    private let reserve: CGFloat = 56
    private let fadeWidth: CGFloat = 14

    private var background: Color { nightMode ? .black : .white }
    private var textColor: Color { nightMode ? .white : .black }
    private var barFill: Color { nightMode ? Color(white: 0.16) : Color(white: 0.93) }

    var body: some View {
        ZStack(alignment: barAtBottom ? .bottom : .top) {
            background.ignoresSafeArea()

            page
                .padding(barAtBottom ? Edge.Set.bottom : Edge.Set.top, reserve)

            if expanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { collapse() }
            }

            bar
                .animation(.easeInOut(duration: 0.2), value: expanded)
        }
        .preferredColorScheme(nightMode ? .dark : .light)
        .confirmationDialog("Opções", isPresented: $showActions, titleVisibility: .hidden) {
            Button(nightMode ? "Modo diurno" : "Modo noturno") { nightMode.toggle() }
            Button(barAtBottom ? "Mover barra para cima" : "Mover barra para baixo") { barAtBottom.toggle() }
            Button("Cancelar", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showTabs) {
            ListaAbas(
                historico: model.historico,
                onSelect: { id in
                    model.selecionarAba(id)
                    showTabs = false
                },
                onNew: {
                    model.novaAba()
                    showTabs = false
                },
                onDelete: { ids in model.fecharAbas(ids) },
                onClose: { showTabs = false }
            )
        }
        .onAppear { model.start() }
        .onChange(of: scenePhase) { fase in
            if fase != .active { model.saveSession() }
        }
    }

    // MARK: Barra

    @ViewBuilder
    private var bar: some View {
        if expanded {
            expandedBar
        } else {
            collapsedBar
        }
    }

    private var collapsedBar: some View {
        Text(model.currentHost)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(Capsule().fill(barFill))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { expanded = true } }
    }

    private var expandedBar: some View {
        HStack(spacing: 12) {
            Button { showActions = true } label: { icon("gearshape") }

            TextField("Endereço", text: $model.address)
                .font(.system(size: 15))
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .focused($fieldFocused)
                .onSubmit {
                    model.submitAddress()
                    collapse()
                }
                .padding(.horizontal, fadeWidth)
                .mask(fadeMask)
                .frame(maxWidth: .infinity)

            Button { model.reload(); collapse() } label: { icon("arrow.clockwise") }
        }
        .buttonStyle(.plain)
        .foregroundColor(textColor)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(barFill))
        .padding(.horizontal, 12)
        .frame(height: 56)
        .contentShape(Rectangle())
        .simultaneousGesture(gestoDaBarra)
    }

    /// Gestos da barra expandida:
    /// - arrastar para a direita volta, para a esquerda avança;
    /// - arrastar no sentido oposto à barra abre a lista de abas.
    private var gestoDaBarra: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { valor in
                let dx = valor.translation.width
                let dy = valor.translation.height

                if abs(dx) > abs(dy) {
                    guard abs(dx) > 60 else { return }
                    if dx > 0 {
                        model.goBack()
                    } else {
                        model.goForward()
                    }
                } else {
                    guard abs(dy) > 60 else { return }
                    let abrirAbas = barAtBottom ? dy < 0 : dy > 0
                    guard abrirAbas else { return }
                    showTabs = true
                }
                collapse()
            }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
    }

    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
        }
    }

    private func collapse() {
        fieldFocused = false
        withAnimation { expanded = false }
    }

    // MARK: Página

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // Mede a rolagem: fica no topo do conteúdo, então seu minY é -deslocamento.
                    Color.clear
                        .frame(width: 0, height: 0)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: -geo.frame(in: .named("scroll")).minY
                                )
                            }
                        )

                    anchor

                    ForEach(model.items, id: \.id) { item in
                        lineView(item)
                    }
                }
                .frame(width: UIScreen.main.bounds.width,
                       height: model.contentHeight,
                       alignment: .topLeading)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { model.scrollY = $0 }
            .onChange(of: model.pageVersion) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("ancora", anchor: .top)
                }
            }
            .overlay {
                if model.items.isEmpty && !model.status.isEmpty {
                    Text(model.status)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Ponto invisível na altura da rolagem salva. Ao trocar de página, a tela rola até ele.
    private var anchor: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .id("ancora")
            .position(x: 0.5, y: model.restoreY + 0.5)
            .allowsHitTesting(false)
    }

    private func lineView(_ item: DrawItem) -> some View {
        let isLink = item.href != nil
        return Text(item.text)
            .font(.system(size: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular))
            .foregroundColor(isLink ? .blue : textColor)
            .underline(isLink)
            .fixedSize()
            .offset(x: CGFloat(item.x), y: CGFloat(item.y))
            .onTapGesture {
                if let href = item.href { model.open(href: href) }
            }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}