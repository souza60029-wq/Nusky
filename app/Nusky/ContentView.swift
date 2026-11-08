// app/Nusky/ContentView.swift
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    @AppStorage("nightMode") private var noturno = false
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage("useButtons") private var botoes = true
    @AppStorage(IdentificacaoNavegador.chaveDesktop) private var versaoDesktop = false
    @AppStorage(ChavesTermos.versaoAceita) private var versaoAceita = ""
    @AppStorage(ChavesTermos.dataAceite) private var dataAceite = ""

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var sistema
    @FocusState private var campoFocado: Bool

    @State private var expandida = false
    @State private var bolhasAbertas = false
    @State private var mostrarConfiguracoes = false
    @State private var mostrarAbas = false
    @State private var versaoNaAbertura = false
    @State private var mostrarBoasVindas = false

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
        // Boas-vindas e termos: aparecem na primeira abertura e quando a versão dos termos muda.
        .fullScreenCover(isPresented: $mostrarBoasVindas) {
            BoasVindas(aoAceitar: aceitarTermos)
                .preferredColorScheme(esquemaPreferido)
        }
        .onAppear {
            model.start()
            mostrarBoasVindas = versaoAceita != versaoDosTermos
        }
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
        // Enquanto o campo tem foco, a lista de resultados acompanha o que está sendo digitado.
        .onChange(of: model.address) { texto in
            atualizarResultados(texto)
        }
    }

    // MARK: - Termos

    /// Grava só no aparelho a versão aceita e a data do aceite.
    private func aceitarTermos() {
        versaoAceita = versaoDosTermos
        dataAceite = ISO8601DateFormatter().string(from: Date())
        mostrarBoasVindas = false
    }

    // MARK: - Busca

    /// Atualiza os resultados enquanto o usuário digita. Fora do campo, ou com a barra recolhida, limpa tudo.
    private func atualizarResultados(_ texto: String) {
        let consulta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expandida, campoFocado, !consulta.isEmpty else {
            fecharBusca()
            return
        }
        let achados = Engine.buscar(consulta)
        model.resultados = achados
        model.sugestao = achados.isEmpty ? Engine.sugestao(para: consulta) : nil
    }

    private func fecharBusca() {
        model.resultados = []
        model.sugestao = nil
    }

    /// Envia o campo. Se a busca não achar nada, a barra fica aberta para mostrar a sugestão.
    /// Se abrir um site ou endereço, a barra recolhe.
    private func enviarCampo() {
        model.sugestao = nil
        model.submitAddress()
        if model.sugestao == nil || !model.resultados.isEmpty {
            recolher()
        }
    }

    /// Abre um site ou atalho da lista. Conta a abertura, que fica só no aparelho.
    private func abrirResultado(_ r: ResultadoBusca) {
        guard let url = URL(string: r.endereco) else { return }
        Engine.registrarUso(endereco: r.endereco)
        fecharBusca()
        model.open(url: url)
        recolher()
    }

    /// Painel com os resultados, ou a sugestão "você quis dizer…?".
    /// Só aparece com a barra expandida. Fica acima da barra quando ela está embaixo, e abaixo quando está em cima.
    @ViewBuilder
    private var painelBusca: some View {
        if expandida, let s = model.sugestao {
            linhaSugestao(s)
                .background(RoundedRectangle(cornerRadius: 16).fill(corBarra))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if expandida && !model.resultados.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.resultados) { r in
                        Button {
                            abrirResultado(r)
                        } label: {
                            linhaResultado(r)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(RoundedRectangle(cornerRadius: 16).fill(corBarra))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func linhaResultado(_ r: ResultadoBusca) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.titulo.isEmpty ? r.nome : "\(r.nome) · \(r.titulo)")
                .font(.system(size: 16))
                .foregroundColor(textoCor)
                .lineLimit(1)
            Text(r.endereco)
                .font(.system(size: 12))
                .foregroundColor(textoCor.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func linhaSugestao(_ s: SugestaoBusca) -> some View {
        Button {
            model.abrirSugestao()
            recolher()
        } label: {
            Text("Não encontrei. Você quis dizer \(s.nome)?")
                .font(.system(size: 15))
                .foregroundColor(textoCor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Página

    private var conteudo: some View {
        ZStack {
            PaginaView(
                itens: model.items,
                fundos: model.fundos,
                fundoPagina: model.fundoPagina,
                altura: CGFloat(model.contentHeight),
                escuro: escuro,
                restoreY: CGFloat(model.restoreY),
                aoRolar: { posicao in model.scrollY = posicao },
                aoAbrirLink: { link in model.open(href: link) },
                aoTocarPagina: {
                    fecharBusca()
                    if expandida { recolher() }
                }
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
        VStack(spacing: 6) {
            if barraEmbaixo {
                painelBusca
                barra
            } else {
                barra
                painelBusca
            }
        }
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
                    enviarCampo()
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

    /// Recolhe a barra e limpa a busca na hora, para nenhum resultado ou sugestão sobrar na tela.
    private func recolher() {
        campoFocado = false
        fecharBusca()
        withAnimation(.easeIn(duration: 0.15)) {
            bolhasAbertas = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandida = false
            }
            fecharBusca()
        }
    }
}