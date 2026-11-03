import SwiftUI
import UIKit

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    @AppStorage("nightMode") private var noturno = false
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage("useButtons") private var botoes = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var sistema
    @FocusState private var campoFocado: Bool

    @State private var expandida = false
    @State private var bolhasAbertas = false
    @State private var mostrarConfiguracoes = false
    @State private var mostrarAbas = false
    @State private var faixa = 0

    private let altura: CGFloat = 56      // espaço reservado para a barra
    private let fade: CGFloat = 14
    private let passo: CGFloat = 400      // a janela só é recalculada ao cruzar esta distância
    private let margem: CGFloat = 400     // linhas extras acima da área visível
    private let alcance: CGFloat = 1800   // até onde a janela vai, a partir da faixa atual
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
            Configuracoes()
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
    }

    // MARK: - Página

    private var conteudo: some View {
        ZStack {
            ScrollViewReader { leitor in
                ScrollView {
                    pagina
                }
                .coordinateSpace(name: "rolagem")
                .onPreferenceChange(ScrollOffsetKey.self) { y in
                    let deslocado = max(0, -y)
                    model.scrollY = deslocado
                    let nova = Int(deslocado / passo)
                    if nova != faixa { faixa = nova }
                }
                .onChange(of: model.pageVersion) { _ in
                    faixa = Int(CGFloat(model.restoreY) / passo)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        leitor.scrollTo("ancora", anchor: .top)
                    }
                }
            }

            if model.items.isEmpty {
                telaVazia
            }
        }
        .padding(barraEmbaixo ? .bottom : .top, altura)
        .simultaneousGesture(TapGesture().onEnded {
            if expandida { recolher() }
        })
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

    private var pagina: some View {
        let inicio = CGFloat(faixa) * passo - margem
        let fim = CGFloat(faixa) * passo + alcance
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(model.contentHeight))

            Color.clear
                .frame(width: 1, height: 1)
                .id("ancora")
                .padding(.top, CGFloat(model.restoreY))

            ForEach(linhasVisiveis(inicio, fim)) { item in
                linha(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: geo.frame(in: .named("rolagem")).minY
                )
            }
        )
    }

    /// Itens ordenados por altura. Busca binária para achar o começo da faixa.
    private func linhasVisiveis(_ inicio: CGFloat, _ fim: CGFloat) -> [DrawItem] {
        let itens = model.items
        var baixo = 0
        var alto = itens.count
        while baixo < alto {
            let meio = (baixo + alto) / 2
            if CGFloat(itens[meio].y) < inicio {
                baixo = meio + 1
            } else {
                alto = meio
            }
        }
        var saida: [DrawItem] = []
        var i = baixo
        while i < itens.count && CGFloat(itens[i].y) <= fim {
            saida.append(itens[i])
            i += 1
        }
        return saida
    }

    private func linha(_ item: DrawItem) -> some View {
        let link = item.href != nil
        return Text(item.text)
            .font(.system(size: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular))
            .foregroundColor(corDaLinha(item))
            .underline(link)
            .fixedSize()
            .offset(x: CGFloat(item.x), y: CGFloat(item.y))
            .onTapGesture {
                if let destino = item.href {
                    model.open(href: destino)
                }
            }
    }

    /// Cor da linha: a que a página pediu pelo CSS.
    /// Só troca por cor do tema quando o texto ficaria quase invisível sobre o fundo
    /// (contraste abaixo de 1,5 para 1). Nos outros casos, vale a cor da página.
    /// Links sem cor própria continuam azuis.
    private func corDaLinha(_ item: DrawItem) -> Color {
        let padrao: Color = item.href != nil ? .blue : textoCor
        guard let cor = item.cor else { return padrao }
        let fundoLuminancia: Double = escuro ? 0 : 1
        let contraste = razaoDeContraste(luminanciaRelativa(cor), fundoLuminancia)
        if contraste < 1.5 { return padrao }
        return Color(red: cor.r, green: cor.g, blue: cor.b)
    }

    /// Luminância relativa pela regra de acessibilidade da web (WCAG): 0 é preto, 1 é branco.
    /// Corrige a gama do sRGB, porque o olho não percebe brilho de forma linear.
    private func luminanciaRelativa(_ cor: CorTexto) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(cor.r) + 0.7152 * linear(cor.g) + 0.0722 * linear(cor.b)
    }

    /// Razão de contraste entre duas luminâncias relativas. Vai de 1 (igual) a 21 (preto contra branco).
    private func razaoDeContraste(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
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