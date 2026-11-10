// app/Nusky/ContentView.swift
import SwiftUI
import UIKit

/// Menus que cobrem a página com o fundo desfocado.
enum PainelAtivo {
    case ajustes
    case abas
    case biblioteca
    case diagnostico
    case termos
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    @AppStorage("nightMode") private var noturno = false
    @AppStorage("themeAuto") private var automatico = true
    @AppStorage("barAtBottom") private var barraEmbaixo = true
    @AppStorage(ChavesTema.desfoque) private var desfoque = true
    @AppStorage(IdentificacaoNavegador.chaveDesktop) private var versaoDesktop = false
    @AppStorage(ChavesTermos.versaoAceita) private var versaoAceita = ""
    @AppStorage(ChavesTermos.dataAceite) private var dataAceite = ""

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var sistema

    /// A barra está aberta (campo de endereço e ferramentas).
    @State private var expandida = false
    /// O campo de endereço está com o teclado.
    @State private var editando = false
    /// 0 = ferramentas guardadas dentro da barra; 1 = ferramentas abertas. Passa de 1 na mola, e o "chiclete" estica.
    @State private var gomo: CGFloat = 0
    @State private var painel: PainelAtivo? = nil
    @State private var versaoNaAbertura = false
    @State private var mostrarBoasVindas = false
    @State private var controle = PaginaControle()

    // Medidas da barra
    private let alturaReservada: CGFloat = 56   // área de toque da barra
    private let alturaPilula: CGFloat = 44      // altura da barra de endereço aberta
    private let alturaFina: CGFloat = 24        // altura da barra recolhida, como a barra de status
    private let alturaFerramentas: CGFloat = 48
    private let folgaPescoco: CGFloat = 18      // distância entre a barra e as ferramentas, com tudo aberto
    private let espacoDaPagina: CGFloat = 36    // espaço que a página deixa para a barra recolhida

    // MARK: - Cores

    private var esquemaPreferido: ColorScheme? {
        automatico ? nil : (noturno ? .dark : .light)
    }

    private var escuro: Bool {
        automatico ? sistema == .dark : noturno
    }

    /// A claridade da página manda nas cores da barra e dos menus: fundo escuro, texto branco;
    /// fundo claro, texto preto. Assim o desfoque nunca destoa do que está atrás, mesmo quando
    /// a página não segue o modo do app.
    private var fundoEscuro: Bool {
        if let f = model.fundoPagina { return f.luminancia < 0.5 }
        return escuro
    }

    /// Fundo atrás da página e das barras.
    private var fundo: Color {
        if let f = model.fundoPagina { return Color(red: f.r, green: f.g, blue: f.b) }
        return escuro ? Color.black : Color.white
    }

    private var textoCor: Color { fundoEscuro ? Color.white : Color.black }
    private var corPilula: Color { fundoEscuro ? Color(white: 0.2) : Color(white: 0.96) }
    private var corBorda: Color { fundoEscuro ? Color.white.opacity(0.14) : Color.black.opacity(0.08) }
    private var corSombra: Color { fundoEscuro ? Color.white.opacity(0.16) : Color.black.opacity(0.2) }
    private var larguraTela: CGFloat { UIScreen.main.bounds.width - 24 }

    /// Altura da barra de status (hora, bateria). No iPhone 6s é 20 pt.
    private var alturaDoTopo: CGFloat {
        let janelas = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let janela = janelas.first(where: { $0.isKeyWindow }) ?? janelas.first
        return janela?.safeAreaInsets.top ?? 20
    }

    // MARK: - Corpo

    var body: some View {
        ZStack(alignment: barraEmbaixo ? .bottom : .top) {
            fundo.ignoresSafeArea()
            conteudo
            faixaDeBlur
            if painel == nil {
                grupoDaBarra
            }
            if let ativo = painel {
                conteudoDoPainel(ativo)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        // Faixa com a cor da página sob a barra de status, para o texto não passar por trás dela.
        .overlay(alignment: .top) {
            fundo
                .frame(height: alturaDoTopo)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(esquemaPreferido)
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
        // Enquanto o campo tem o teclado, a lista de resultados acompanha o que está sendo digitado.
        .onChange(of: model.address) { texto in
            atualizarResultados(texto)
        }
        // Digitando, as ferramentas se guardam para dar espaço; ao terminar, voltam.
        .onChange(of: editando) { ativo in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                gomo = ativo ? 0 : (expandida ? 1 : 0)
            }
            if !ativo { fecharBusca() }
        }
    }

    // MARK: - Menus

    @ViewBuilder
    private func conteudoDoPainel(_ ativo: PainelAtivo) -> some View {
        switch ativo {
        case .ajustes:
            PainelAjustes(
                fundoEscuro: fundoEscuro,
                temPagina: model.currentURL != nil,
                aoAbrirURL: { url in
                    fecharPainel()
                    model.open(url: url)
                },
                aoAbrirDiagnostico: { trocarPainel(.diagnostico) },
                aoAbrirTermos: { trocarPainel(.termos) },
                aoFechar: { fecharPainel() }
            )
        case .abas:
            ListaAbas(
                historico: model.historico,
                fundoEscuro: fundoEscuro,
                onSelect: { id in
                    model.selecionarAba(id)
                    fecharPainel()
                },
                onNew: {
                    model.novaAba()
                    fecharPainel()
                },
                onDelete: { ids in
                    model.fecharAbas(ids)
                    for id in ids { MiniaturasAbas.compartilhada.apagar(id) }
                },
                onClose: { fecharPainel() }
            )
        case .biblioteca:
            BibliotecaView(
                urlAtual: model.currentURL,
                fundoEscuro: fundoEscuro,
                aoAbrir: { url in model.open(url: url) },
                aoFechar: { fecharPainel() }
            )
        case .diagnostico:
            PainelVidro(titulo: "Diagnóstico", fundoEscuro: fundoEscuro, aoFechar: { trocarPainel(.ajustes) }) {
                DiagnosticoView(url: model.currentURL)
            }
        case .termos:
            PainelVidro(titulo: "Termos de uso", fundoEscuro: fundoEscuro, aoFechar: { trocarPainel(.ajustes) }) {
                TermosDeUso()
            }
        }
    }

    private func abrirPainel(_ novo: PainelAtivo) {
        if novo == .ajustes { versaoNaAbertura = versaoDesktop }
        if novo == .abas { capturarMiniatura() }
        recolher()
        withAnimation(.easeInOut(duration: 0.25)) { painel = novo }
    }

    private func trocarPainel(_ novo: PainelAtivo) {
        withAnimation(.easeInOut(duration: 0.25)) { painel = novo }
    }

    /// Fecha o menu. Se a opção de versão desktop mudou, recarrega a página.
    private func fecharPainel() {
        withAnimation(.easeInOut(duration: 0.25)) { painel = nil }
        if versaoDesktop != versaoNaAbertura {
            versaoNaAbertura = versaoDesktop
            model.reload()
        }
    }

    /// Guarda a miniatura da aba aberta, para a tela de abas.
    private func capturarMiniatura() {
        guard !model.items.isEmpty || !model.imagens.isEmpty else { return }
        let tamanho = CGSize(width: UIScreen.main.bounds.width, height: 620)
        if let imagem = controle.miniatura(tamanho: tamanho, fundo: UIColor(fundo)) {
            MiniaturasAbas.compartilhada.guardar(imagem, para: model.historico.abaAtual.id)
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
        guard expandida, editando, !consulta.isEmpty else {
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
    /// Fica acima da barra quando ela está embaixo, e abaixo quando está em cima.
    @ViewBuilder
    private var painelBusca: some View {
        if expandida, let s = model.sugestao {
            linhaSugestao(s)
                .background(vidroRetangulo)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if expandida && !model.resultados.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.resultados) { r in
                        Button {
                            abrirResultado(r)
                        } label: {
                            linhaResultado(r)
                        }
                        .buttonStyle(EstiloToque(forma: .retangulo(0), comFundo: false))
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(vidroRetangulo)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func linhaResultado(_ r: ResultadoBusca) -> some View {
        HStack(spacing: 12) {
            IconeDoSite(host: URL(string: r.endereco)?.host ?? "", tamanho: 28)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(EstiloToque(forma: .retangulo(0), comFundo: false))
    }

    /// Fundo de vidro (ou liso, sem desfoque) das caixas retangulares da barra.
    private var vidroRetangulo: some View {
        ZStack {
            if desfoque {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(corPilula.opacity(0.35))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(corPilula)
            }
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(corBorda, lineWidth: 0.5)
        }
        .shadow(color: corSombra, radius: 8, x: 0, y: 3)
    }

    /// Fundo de vidro (ou liso, sem desfoque) das cápsulas da barra.
    private var vidroCapsula: some View {
        ZStack {
            if desfoque {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(corPilula.opacity(0.35))
            } else {
                Capsule().fill(corPilula)
            }
            Capsule().stroke(corBorda, lineWidth: 0.5)
        }
        .shadow(color: corSombra, radius: 8, x: 0, y: 3)
    }

    // MARK: - Página

    private var conteudo: some View {
        ZStack {
            PaginaView(
                itens: model.items,
                fundos: model.fundos,
                imagens: model.imagens,
                baseURL: model.currentURL,
                fundoPagina: model.fundoPagina,
                altura: CGFloat(model.contentHeight),
                escuro: escuro,
                restoreY: CGFloat(model.restoreY),
                aoRolar: { posicao in model.scrollY = posicao },
                aoAbrirLink: { link in model.open(href: link) },
                aoTocarPagina: {
                    fecharBusca()
                    if expandida { recolher() }
                },
                aoComecarRolar: {
                    if expandida { recolher() }
                },
                controle: controle
            )

            if model.items.isEmpty && model.imagens.isEmpty {
                telaVazia
            }
        }
        .padding(barraEmbaixo ? .bottom : .top, espacoDaPagina)
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

    /// Desfoque atrás da barra aberta, com a borda de cima (ou de baixo) esmaecida.
    @ViewBuilder
    private var faixaDeBlur: some View {
        if desfoque {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, fundoEscuro ? .dark : .light)
                .frame(height: 230)
                .mask(
                    LinearGradient(
                        colors: [Color.clear, Color.black, Color.black],
                        startPoint: barraEmbaixo ? .top : .bottom,
                        endPoint: barraEmbaixo ? .bottom : .top
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barraEmbaixo ? .bottom : .top)
                .ignoresSafeArea()
                .opacity(expandida ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private var grupoDaBarra: some View {
        VStack(spacing: 8) {
            if barraEmbaixo {
                painelBusca
                bloco
            } else {
                bloco
                painelBusca
            }
        }
        .padding(.horizontal, 12)
        .padding(barraEmbaixo ? .bottom : .top, 6)
        .environment(\.colorScheme, fundoEscuro ? .dark : .light)
    }

    /// A barra de endereço e, ligada a ela por um "chiclete", a barra de ferramentas.
    private var bloco: some View {
        ZStack {
            ferramentasComPescoco
            pilulaDeEndereco
        }
        .frame(height: alturaReservada)
    }

    // Distância do centro da barra ao centro das ferramentas, com tudo aberto.
    private var distancia: CGFloat { (alturaPilula + alturaFerramentas) / 2 + folgaPescoco }

    /// Comprimento do pescoço: o vão entre a borda da barra e a borda das ferramentas.
    private var comprimentoDoPescoco: CGFloat {
        max(0, distancia * gomo - alturaFerramentas / 2 - alturaPilula / 2)
    }

    /// As ferramentas saem de trás da barra. Enquanto se afastam, o pescoço liga as duas e vai afinando,
    /// como chiclete esticado. A mola passa do ponto e volta, e o pescoço estala fino e se desfaz.
    private var ferramentasComPescoco: some View {
        let sinal: CGFloat = barraEmbaixo ? -1 : 1
        let pescoco = comprimentoDoPescoco
        return ZStack {
            pescocoDoChiclete(esticamento: pescoco / folgaPescoco)
                .frame(width: 70, height: pescoco)
                .offset(y: sinal * (alturaPilula / 2 + pescoco / 2))
                .opacity(pescoco > 0.5 ? 1 : 0)

            barraDeFerramentas
                .scaleEffect(0.7 + 0.3 * min(gomo, 1), anchor: barraEmbaixo ? .bottom : .top)
                .offset(y: sinal * distancia * gomo)
                .opacity(Double(min(1, gomo * 1.6)))
                .allowsHitTesting(expandida && !editando && gomo > 0.8)
        }
    }

    @ViewBuilder
    private func pescocoDoChiclete(esticamento: CGFloat) -> some View {
        if desfoque {
            PescocoChiclete(esticamento: esticamento).fill(.ultraThinMaterial)
        } else {
            PescocoChiclete(esticamento: esticamento).fill(corPilula)
        }
    }

    private var barraDeFerramentas: some View {
        HStack(spacing: 0) {
            botaoDeFerramenta("chevron.left", ativo: model.historico.abaAtual.podeVoltar) {
                model.goBack()
                recolher()
            }
            if model.historico.abaAtual.podeAvancar {
                botaoDeFerramenta("chevron.right", ativo: true) {
                    model.goForward()
                    recolher()
                }
            }
            botaoDeFerramenta("rectangle.stack", ativo: true) {
                abrirPainel(.abas)
            }
            botaoDeFerramenta("books.vertical", ativo: true) {
                abrirPainel(.biblioteca)
            }
            botaoDeFerramenta("square.and.arrow.up", ativo: model.currentURL != nil) {
                compartilhar()
            }
            botaoDeFerramenta("gearshape", ativo: true) {
                abrirPainel(.ajustes)
            }
        }
        .frame(height: alturaFerramentas)
        .padding(.horizontal, 6)
        .background(vidroCapsula)
    }

    /// Abre a folha de compartilhamento do iOS com o endereço da página.
    private func compartilhar() {
        recolher()
        guard let url = model.currentURL else { return }
        let folha = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let janelas = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let raiz = (janelas.first(where: { $0.isKeyWindow }) ?? janelas.first)?.rootViewController else { return }
        var topo = raiz
        while let apresentado = topo.presentedViewController { topo = apresentado }
        folha.popoverPresentationController?.sourceView = topo.view
        topo.present(folha, animated: true)
    }

    private func botaoDeFerramenta(_ icone: String, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(textoCor.opacity(ativo ? 1 : 0.3))
                .frame(width: 52, height: alturaFerramentas)
                .contentShape(Rectangle())
        }
        .buttonStyle(EstiloToque(forma: .circulo, comFundo: false))
        .disabled(!ativo)
    }

    /// Recolhida: uma faixa fina como a barra de status, só com o site. Aberta: a faixa cresce até virar a
    /// pílula do campo de endereço. A área de toque é mais alta que a faixa, para ficar fácil de acertar.
    private var pilulaDeEndereco: some View {
        Group {
            if expandida {
                corpoDaPilula
            } else {
                Button(action: expandir) {
                    corpoDaPilula
                        .frame(maxWidth: .infinity)
                        .frame(height: alturaReservada)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EstiloToque(forma: .capsula, comFundo: false))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: alturaReservada)
    }

    private var corpoDaPilula: some View {
        ZStack {
            rotuloRecolhido
                .opacity(expandida ? 0 : 1)
            linhaExpandida
                .opacity(expandida ? 1 : 0)
                .allowsHitTesting(expandida)
        }
        .frame(width: larguraTela, height: expandida ? alturaPilula : alturaFina)
        .background(
            vidroCapsula
                .overlay(alignment: .bottom) { linhaDeProgresso }
        )
    }

    @ViewBuilder
    private var linhaDeProgresso: some View {
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

    private var ehHTTPS: Bool {
        model.currentURL?.scheme?.lowercased() == "https"
    }

    private var rotuloRecolhido: some View {
        HStack(spacing: 5) {
            Image(systemName: ehHTTPS ? "lock.fill" : "globe")
                .font(.system(size: 9, weight: .semibold))
            Text(model.currentHost.isEmpty ? "Nusky" : model.currentHost)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(textoCor.opacity(0.8))
        .padding(.horizontal, 16)
    }

    private var linhaExpandida: some View {
        HStack(spacing: 0) {
            Image(systemName: ehHTTPS ? "lock.fill" : "globe")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textoCor.opacity(0.5))
                .frame(width: 36)

            CampoDeEndereco(
                texto: $model.address,
                editando: $editando,
                corDoTexto: fundoEscuro ? UIColor.white : UIColor.black,
                aoEnviar: { enviarCampo() }
            )
            .frame(height: 40)

            Button {
                model.reload()
                recolher()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(textoCor)
                    .frame(width: 46, height: alturaPilula)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EstiloToque(forma: .circulo, comFundo: false))
        }
    }

    // MARK: - Abrir e recolher

    private func expandir() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            expandida = true
        }
        // A mola do chiclete é mais solta: ela passa do ponto e volta.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
            gomo = 1
        }
    }

    /// Recolhe a barra e limpa a busca na hora, para nenhum resultado ou sugestão sobrar na tela.
    private func recolher() {
        editando = false
        fecharBusca()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            gomo = 0
            expandida = false
        }
    }
}

// MARK: - Pescoço do chiclete

/// Faixa que liga duas pílulas: larga nas pontas, fina no meio. Quanto mais esticada, mais fina.
struct PescocoChiclete: Shape {
    var esticamento: CGFloat

    var animatableData: CGFloat {
        get { esticamento }
        set { esticamento = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.height > 0.5 else { return p }
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let borda = w / 2
        let fino = max(3, w * 0.30 * (1 - min(0.85, esticamento * 0.5))) / 2

        p.move(to: CGPoint(x: cx - borda, y: 0))
        p.addCurve(
            to: CGPoint(x: cx - fino, y: h / 2),
            control1: CGPoint(x: cx - fino * 1.8, y: 0),
            control2: CGPoint(x: cx - fino, y: h * 0.28)
        )
        p.addCurve(
            to: CGPoint(x: cx - borda, y: h),
            control1: CGPoint(x: cx - fino, y: h * 0.72),
            control2: CGPoint(x: cx - fino * 1.8, y: h)
        )
        p.addLine(to: CGPoint(x: cx + borda, y: h))
        p.addCurve(
            to: CGPoint(x: cx + fino, y: h / 2),
            control1: CGPoint(x: cx + fino * 1.8, y: h),
            control2: CGPoint(x: cx + fino, y: h * 0.72)
        )
        p.addCurve(
            to: CGPoint(x: cx + borda, y: 0),
            control1: CGPoint(x: cx + fino, y: h * 0.28),
            control2: CGPoint(x: cx + fino * 1.8, y: 0)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Campo de endereço

/// Campo de texto do UIKit. Ao receber o toque, seleciona tudo: quem começa a digitar apaga o endereço antigo.
struct CampoDeEndereco: UIViewRepresentable {
    @Binding var texto: String
    @Binding var editando: Bool
    let corDoTexto: UIColor
    let aoEnviar: () -> Void

    func makeCoordinator() -> Coordenador {
        Coordenador(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let campo = UITextField()
        campo.delegate = context.coordinator
        campo.placeholder = "Buscar ou digitar endereço"
        campo.font = UIFont.systemFont(ofSize: 17)
        campo.autocapitalizationType = .none
        campo.autocorrectionType = .no
        campo.spellCheckingType = .no
        campo.keyboardType = .webSearch
        campo.returnKeyType = .go
        campo.clearButtonMode = .whileEditing
        campo.addTarget(context.coordinator, action: #selector(Coordenador.mudou(_:)), for: .editingChanged)
        campo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        campo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return campo
    }

    func updateUIView(_ campo: UITextField, context: Context) {
        context.coordinator.pai = self
        if campo.text != texto {
            campo.text = texto
        }
        campo.textColor = corDoTexto
        campo.tintColor = corDoTexto
        if editando && !campo.isFirstResponder {
            campo.becomeFirstResponder()
        } else if !editando && campo.isFirstResponder {
            campo.resignFirstResponder()
        }
    }

    final class Coordenador: NSObject, UITextFieldDelegate {
        var pai: CampoDeEndereco

        init(_ pai: CampoDeEndereco) {
            self.pai = pai
        }

        @objc func mudou(_ campo: UITextField) {
            pai.texto = campo.text ?? ""
        }

        func textFieldDidBeginEditing(_ campo: UITextField) {
            DispatchQueue.main.async {
                self.pai.editando = true
                campo.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ campo: UITextField) {
            DispatchQueue.main.async {
                self.pai.editando = false
            }
        }

        func textFieldShouldReturn(_ campo: UITextField) -> Bool {
            pai.aoEnviar()
            return true
        }
    }
}
