import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    @AppStorage("nightMode") private var noturno = false
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage("useButtons") private var botoes = true
    @AppStorage(IdentificacaoNavegador.chaveDesktop) private var versaoDesktop = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var sistema
    @FocusState private var campoFocado: Bool

    @State private var expandida = false
    @State private var bolhasAbertas = false
    @State private var mostrarConfiguracoes = false
    @State private var mostrarAbas = false
    @State private var versaoNaAbertura = false

    private let altura: CGFloat = 56      // espaço reservado para a barra
    private let fade: CGFloat = 14
    private let alturaBolha: CGFloat = 44 // altura de um botão de bolha
    private let folgaBolha: CGFloat = 6   // distância da bolha aberta até a borda da barra

    private var esquemaPreferido: ColorScheme? {
        automatico ? nil : (noturno ? .dark : .light)
    }

    private var escuro: Bool {
        automatico ? sistema == .dark : noturno
    }

    private var fundo: Color { escuro ? Color.black : Color.white }
    private var textoCor: Color { escuro ? Color.white : Color.black }
    private var corBarra: Color { escuro ? Color(white: 0.16) : Color(white: 0.93) }

    /// Altura da barra de status (hora, bateria). No iPhone 6s é 20 pt.
    private var alturaDoTopo: CGFloat {
        let janelas = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let janela = janelas.first(where: { $0.isKeyWindow }) ?? janelas.first
        return janela?.safeAreaInsets.top ?? 20
    }

    var body: some View {
        ZStack(alignment: barraEmbaixo ? .bottom : .top) {
            fundo.ignoresSafeArea()
            conteudo
            barraComBolhas
        }
        // Faixa com a cor da página sob a barra de status, para o texto não passar por trás dela.
        .overlay(alignment: .top) {
            fundo
                .frame(height: alturaDoTopo)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(esquemaPreferido)
        .sheet(isPresented: $mostrarConfiguracoes) {
            Configuracoes(urlAtual: model.currentURL)
                .preferredColorScheme(esquemaPreferido)
        }
        .fullScreenCover(isPresented: $mostrarAbas) {
            ListaAbas(
                historico: model.historico,
                onSelect: { id in
                    model.selecionarAba(id)
                    mostrarAbas = false
                },
                onNew: {
                    model.novaAba()
                    mostrarAbas = false
                },
                onDelete: { ids in
                    model.fecharAbas(ids)
                },
                onClose: {
                    mostrarAbas = false
                }
            )
            .preferredColorScheme(esquemaPreferido)
        }
        .onAppear { model.start() }
        .onChange(of: scenePhase) { fase in
            if fase != .active { model.saveSession() }
        }
        // Ao fechar Ajustes, recarrega a página só se a opção de versão desktop mudou.
        .onChange(of: mostrarConfiguracoes) { aberta in
            if aberta {
                versaoNaAbertura = versaoDesktop
            } else if versaoDesktop != versaoNaAbertura {
                model.reload()
            }
        }
    }

    // MARK: - Página

    private var conteudo: some View {
        ZStack {
            PaginaView(
                itens: model.items,
                altura: CGFloat(model.contentHeight),
                escuro: escuro,
                restoreY: CGFloat(model.restoreY),
                aoRolar: { posicao in model.scrollY = posicao },
                aoAbrirLink: { link in model.open(href: link) },
                aoTocarPagina: { if expandida { recolher() } }
            )

            if model.items.isEmpty {
                telaVazia
            }
        }
        .padding(barraEmbaixo ? .bottom : .top, altura)
    }

    /// Enquanto a página não está pronta: barra de progresso no centro, ou a mensagem de erro.
    @ViewBuilder
    private var telaVazia: some View {
        if model.carregando {
            VStack(spacing: 14) {
                ProgressView(value: model.progresso, total: 1)
                    .frame(width: 180)
                Text("Carregando…")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
            }
        } else if !model.status.isEmpty {
            Text(model.status)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Barra

    private var barraComBolhas: some View {
        barra
            .padding(.horizontal, 12)
            .padding(barraEmbaixo ? .bottom : .top, 6)
    }

    private var barra: some View {
        Group {
            if expandida {
                barraExpandida
            } else {
                barraRecolhida
            }
        }
    }

    /// Fundo da barra com a linha de progresso na borda de baixo, enquanto a página carrega.
    private var fundoBarra: some View {
        Capsule()
            .fill(corBarra)
            .overlay(alignment: .bottom) {
                if model.carregando {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(6, geo.size.width * CGFloat(model.progresso)), height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .clipShape(Capsule())
                }
            }
    }

    private var barraRecolhida: some View {
        Text(model.currentHost.isEmpty ? "Nusky" : model.currentHost)
            .font(.system(size: 13))
            .foregroundColor(textoCor.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(fundoBarra)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture { expandir() }
    }

    private var barraExpandida: some View {
        HStack(spacing: 0) {
            Button {
                mostrarConfiguracoes = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(textoCor)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            TextField("Endereço", text: $model.address)
                .focused($campoFocado)
                .font(.system(size: 17))
                .foregroundColor(textoCor)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .onSubmit {
                    model.submitAddress()
                    recolher()
                }
                .mask(bordasEsmaecidas)

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                    .foregroundColor(textoCor)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        // As bolhas ficam sobrepostas à barra, fora do fluxo de layout: a barra não sai do lugar.
        .overlay(alignment: barraEmbaixo ? .top : .bottom) {
            if botoes {
                bolhasFlutuantes
            }
        }
        .background(fundoBarra)
        .frame(height: 56)
        .simultaneousGesture(gestoDaBarra)
    }

    private var bordasEsmaecidas: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
        }
    }

    /// Bolhas encostadas na borda da barra. Fechadas, ficam na borda; abertas, sobem um pouco.
    /// A escala cresce a partir da borda, então parecem sair dela.
    private var bolhasFlutuantes: some View {
        let sinal: CGFloat = barraEmbaixo ? -1 : 1
        return bolhas
            .offset(y: sinal * (bolhasAbertas ? alturaBolha + folgaBolha : alturaBolha))
    }

    private var bolhas: some View {
        HStack(spacing: 0) {
            botao("chevron.left", ativo: model.historico.abaAtual.podeVoltar) {
                model.goBack()
                recolher()
            }
            botao("chevron.right", ativo: model.historico.abaAtual.podeAvancar) {
                model.goForward()
                recolher()
            }
            botao("rectangle.stack", ativo: true) {
                mostrarAbas = true
                recolher()
            }
        }
        .background(Capsule().fill(corBarra))
        .scaleEffect(bolhasAbertas ? 1 : 0.4, anchor: barraEmbaixo ? .bottom : .top)
        .opacity(bolhasAbertas ? 1 : 0)
        .allowsHitTesting(bolhasAbertas)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                bolhasAbertas = true
            }
        }
    }

    private func botao(_ icone: String, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(textoCor.opacity(ativo ? 1 : 0.3))
                .frame(width: 56, height: alturaBolha)
        }
        .buttonStyle(.plain)
        .disabled(!ativo)
    }

    private var gestoDaBarra: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { valor in
                guard !botoes else { return }
                let dx = valor.translation.width
                let dy = valor.translation.height
                if abs(dx) > abs(dy) {
                    if dx > 60 {
                        model.goBack()
                    } else if dx < -60 {
                        model.goForward()
                    }
                } else {
                    let abrir = barraEmbaixo ? dy < -60 : dy > 60
                    if abrir { mostrarAbas = true }
                }
            }
    }

    private func expandir() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandida = true
        }
    }

    private func recolher() {
        campoFocado = false
        withAnimation(.easeIn(duration: 0.15)) {
            bolhasAbertas = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandida = false
            }
        }
    }
}