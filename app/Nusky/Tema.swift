// app/Nusky/Tema.swift
import SwiftUI
import UIKit
import AudioToolbox

// MARK: - Chaves dos ajustes de aparência e toque

enum ChavesTema {
    static let desfoque = "efeitoDesfoque"
    static let forcarNoturno = "forcarNoturno"
    static let feedbackLuminoso = "feedbackLuminoso"
    static let feedbackExpansivo = "feedbackExpansivo"
    static let feedbackTatil = "feedbackTatil"
    static let padraoFeedback = "padraoFeedback"
}

/// Intensidade do feedback de toque. Vale para os três efeitos ao mesmo tempo.
enum PadraoFeedback: Int, CaseIterable, Identifiable {
    case leve = 0
    case padrao = 1
    case extravagante = 2

    var id: Int { rawValue }

    var nome: String {
        switch self {
        case .leve: return "Leve"
        case .padrao: return "Padrão"
        case .extravagante: return "Extravagante"
        }
    }

    /// Quanto tempo o brilho e a pulsação duram.
    var duracao: Double {
        switch self {
        case .leve: return 0.4
        case .padrao: return 0.65
        case .extravagante: return 1.1
        }
    }

    /// Força do brilho no ponto do toque.
    var forca: Double {
        switch self {
        case .leve: return 0.4
        case .padrao: return 0.7
        case .extravagante: return 1.0
        }
    }

    /// Quanto o botão encolhe antes de voltar.
    var profundidade: CGFloat {
        switch self {
        case .leve: return 0.03
        case .padrao: return 0.07
        case .extravagante: return 0.15
        }
    }

    /// Mola da volta: quanto menor, mais o botão balança.
    var amortecimento: Double {
        switch self {
        case .leve: return 0.8
        case .padrao: return 0.55
        case .extravagante: return 0.3
        }
    }
}

// MARK: - Aparência

enum Aparencia {
    /// Verdadeiro quando os sites devem receber o tema escuro (`prefers-color-scheme`):
    /// modo noturno do app, tema automático com o iPhone no escuro, ou "forçar modo noturno".
    @MainActor
    static func sitesEmModoEscuro() -> Bool {
        let ajustes = UserDefaults.standard
        if ajustes.bool(forKey: ChavesTema.forcarNoturno) { return true }
        let automatico = ajustes.object(forKey: "themeAuto") as? Bool ?? true
        if automatico {
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark
        }
        return ajustes.bool(forKey: "nightMode")
    }
}

// MARK: - Modo noturno forçado

/// Inverte a claridade das cores de uma página clara, mantendo o tom. Páginas que já são escuras
/// não mudam: a regra só vale quando o fundo da página é claro (ou a página não define fundo).
enum ModoNoturnoForcado {
    static func aplicar(_ pagina: PaginaDesenhada) -> PaginaDesenhada {
        let claro = pagina.fundoPagina.map { $0.luminancia > 0.55 } ?? true
        guard claro else { return pagina }

        var saida = pagina
        saida.fundoPagina = pagina.fundoPagina.map(inverter) ?? CorTexto(r: 0.09, g: 0.09, b: 0.10)
        saida.fundos = pagina.fundos.map { f in
            Fundo(
                x: f.x, y: f.y, w: f.w, h: f.h,
                cor: f.cor.map(inverter),
                bordaLargura: f.bordaLargura,
                bordaCor: f.bordaCor.map(inverter),
                raio: f.raio
            )
        }
        saida.formas = pagina.formas.map { forma in
            var f = forma
            f.preenchimento = inverterTinta(forma.preenchimento)
            f.traco = inverterTinta(forma.traco)
            return f
        }
        saida.itens = pagina.itens.map { i in
            DrawItem(
                x: i.x, y: i.y, fontSize: i.fontSize, bold: i.bold, href: i.href,
                cor: i.cor.map(inverter),
                text: i.text,
                italico: i.italico, serifa: i.serifa,
                fundo: i.fundo.map(inverter)
            )
        }
        return saida
    }

    private static func inverterTinta(_ tinta: TintaSvg) -> TintaSvg {
        if case .rgb(let r, let g, let b) = tinta {
            let nova = inverter(CorTexto(r: r, g: g, b: b))
            return .rgb(nova.r, nova.g, nova.b)
        }
        return tinta
    }

    private static func inverter(_ cor: CorTexto) -> CorTexto {
        var (h, s, l) = paraHSL(cor)
        l = min(0.94, max(0.06, 1 - l))
        s = s * 0.92
        return deHSL(h, s, l)
    }

    private static func paraHSL(_ c: CorTexto) -> (Double, Double, Double) {
        let maior = max(c.r, c.g, c.b)
        let menor = min(c.r, c.g, c.b)
        let l = (maior + menor) / 2
        let delta = maior - menor
        if delta == 0 { return (0, 0, l) }
        let s = l > 0.5 ? delta / (2 - maior - menor) : delta / (maior + menor)
        var h: Double
        if maior == c.r {
            h = (c.g - c.b) / delta + (c.g < c.b ? 6 : 0)
        } else if maior == c.g {
            h = (c.b - c.r) / delta + 2
        } else {
            h = (c.r - c.g) / delta + 4
        }
        h /= 6
        return (h, s, l)
    }

    private static func deHSL(_ h: Double, _ s: Double, _ l: Double) -> CorTexto {
        if s == 0 { return CorTexto(r: l, g: l, b: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func canal(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return CorTexto(r: canal(h + 1.0 / 3), g: canal(h), b: canal(h - 1.0 / 3))
    }
}

// MARK: - Háptico

enum Haptico {
    /// Vibração curta do sistema. Usa os sons de vibração do iOS (peek, pop e nope),
    /// que funcionam também no iPhone 6s, onde a API de feedback do iOS não vibra.
    static func disparar(_ padrao: PadraoFeedback) {
        func tocar(_ codigo: UInt32, depois atraso: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + atraso) {
                AudioServicesPlaySystemSound(SystemSoundID(codigo))
            }
        }
        switch padrao {
        case .leve:
            tocar(1519, depois: 0)
        case .padrao:
            tocar(1520, depois: 0)
        case .extravagante:
            tocar(1520, depois: 0)
            tocar(1521, depois: 0.12)
            tocar(1520, depois: 0.26)
        }
    }
}

// MARK: - Forma

/// Forma usada pelos botões e pelo efeito de toque: cápsula, círculo ou retângulo arredondado.
struct FormaVidro: Shape {
    enum Tipo {
        case capsula
        case circulo
        case retangulo(CGFloat)
    }

    var tipo: Tipo

    static let capsula = FormaVidro(tipo: .capsula)
    static let circulo = FormaVidro(tipo: .circulo)
    static func retangulo(_ raio: CGFloat) -> FormaVidro { FormaVidro(tipo: .retangulo(raio)) }

    func path(in rect: CGRect) -> Path {
        switch tipo {
        case .capsula:
            return Capsule().path(in: rect)
        case .circulo:
            return Circle().path(in: rect)
        case .retangulo(let raio):
            return RoundedRectangle(cornerRadius: raio, style: .continuous).path(in: rect)
        }
    }
}

// MARK: - Onde o dedo tocou

/// Guarda o ponto do último toque dentro de um botão.
final class RegistroToque {
    var ponto: CGPoint?
}

/// Vista invisível que só descobre onde o dedo tocou. Ela coloca um reconhecedor na janela que nunca
/// "reconhece" nada (devolve falso em `shouldReceive`), então não atrapalha nenhum toque; só anota o ponto.
struct LocalizadorDeToque: UIViewRepresentable {
    let registro: RegistroToque

    func makeUIView(context: Context) -> VistaLocalizadora {
        let vista = VistaLocalizadora()
        vista.registro = registro
        vista.isUserInteractionEnabled = false
        vista.backgroundColor = .clear
        return vista
    }

    func updateUIView(_ vista: VistaLocalizadora, context: Context) {
        vista.registro = registro
    }
}

final class VistaLocalizadora: UIView, UIGestureRecognizerDelegate {
    var registro: RegistroToque?
    private let reconhecedor = UILongPressGestureRecognizer()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reconhecedor.view?.removeGestureRecognizer(reconhecedor)
        if let janela = window {
            reconhecedor.delegate = self
            reconhecedor.minimumPressDuration = 0
            reconhecedor.cancelsTouchesInView = false
            reconhecedor.delaysTouchesBegan = false
            janela.addGestureRecognizer(reconhecedor)
        }
    }

    deinit {
        reconhecedor.view?.removeGestureRecognizer(reconhecedor)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let ponto = touch.location(in: self)
        if bounds.contains(ponto) {
            registro?.ponto = ponto
        }
        return false
    }
}

// MARK: - Botão padrão

/// Estilo de todos os botões do app: fundo de vidro (ou liso, se o desfoque estiver desligado),
/// sombra discreta em volta (clara sobre fundo escuro, escura sobre fundo claro) e o feedback de toque.
struct EstiloToque: ButtonStyle {
    var forma: FormaVidro = .capsula
    /// Falso quando o botão já está sobre um fundo próprio (por exemplo, dentro da barra de ferramentas).
    var comFundo = true

    func makeBody(configuration: Configuration) -> some View {
        CorpoDoBotao(configuracao: configuration, forma: forma, comFundo: comFundo)
    }
}

private struct CorpoDoBotao: View {
    let configuracao: ButtonStyle.Configuration
    let forma: FormaVidro
    let comFundo: Bool

    @AppStorage(ChavesTema.desfoque) private var desfoque = true
    @AppStorage(ChavesTema.feedbackLuminoso) private var luminoso = true
    @AppStorage(ChavesTema.feedbackExpansivo) private var expansivo = true
    @AppStorage(ChavesTema.feedbackTatil) private var tatil = true
    @AppStorage(ChavesTema.padraoFeedback) private var padraoBruto = 1
    @Environment(\.colorScheme) private var esquema

    /// Progresso do brilho: 0 = começou, 1 = acabou (sem brilho).
    @State private var progresso: CGFloat = 1
    @State private var escala: CGFloat = 1
    @State private var origem: CGPoint = .zero
    @State private var tamanho: CGSize = .zero
    @State private var registro = RegistroToque()

    private var escuro: Bool { esquema == .dark }
    private var padrao: PadraoFeedback { PadraoFeedback(rawValue: padraoBruto) ?? .padrao }

    var body: some View {
        configuracao.label
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { tamanho = geo.size }
                        .onChange(of: geo.size) { novo in tamanho = novo }
                }
            )
            .background(fundoDeVidro)
            .overlay(brilho)
            .overlay(LocalizadorDeToque(registro: registro).allowsHitTesting(false))
            .scaleEffect(escala)
            .onChange(of: configuracao.isPressed) { pressionado in
                if pressionado { disparar() }
            }
    }

    @ViewBuilder
    private var fundoDeVidro: some View {
        if comFundo {
            ZStack {
                if desfoque {
                    forma.fill(.ultraThinMaterial)
                } else {
                    forma.fill(escuro ? Color(white: 0.18) : Color(white: 0.94))
                }
                forma.stroke(escuro ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: escuro ? Color.white.opacity(0.1) : Color.black.opacity(0.16), radius: 5, x: 0, y: 2)
        }
    }

    /// Uma bolinha de luz desfocada que nasce no ponto do toque e se espalha por todo o botão.
    /// Quanto mais longe ela vai, mais fraca fica, até sumir.
    @ViewBuilder
    private var brilho: some View {
        if luminoso && progresso < 1 {
            let raioFinal = max(tamanho.width, tamanho.height) * 1.2 + 30
            // Sai rápido do ponto do toque e desacelera.
            let avanco = 1 - (1 - progresso) * (1 - progresso)
            let raio = 12 + raioFinal * avanco
            let forca = padrao.forca * Double((1 - progresso) * (1 - progresso))
            let cor: Color = escuro ? Color.white : Color(red: 0.2, green: 0.45, blue: 1.0)
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: cor.opacity(forca), location: 0),
                            .init(color: cor.opacity(forca * 0.5), location: 0.5),
                            .init(color: cor.opacity(0), location: 1)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: raio
                    )
                )
                .frame(width: raio * 2, height: raio * 2)
                .blur(radius: 5)
                .position(x: origem.x, y: origem.y)
                .clipShape(forma)
                .allowsHitTesting(false)
        }
    }

    private func disparar() {
        let nivel = padrao
        if tatil {
            Haptico.disparar(nivel)
        }
        if luminoso {
            origem = registro.ponto ?? CGPoint(x: tamanho.width / 2, y: tamanho.height / 2)
            progresso = 0
            // O valor 0 precisa ser desenhado antes de a animação começar.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: nivel.duracao)) {
                    progresso = 1
                }
            }
        }
        if expansivo {
            withAnimation(.easeOut(duration: 0.1)) {
                escala = 1 - nivel.profundidade
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: nivel.duracao * 0.7, dampingFraction: nivel.amortecimento)) {
                    escala = 1
                }
            }
        }
    }
}

// MARK: - Menus

/// Fundo dos menus: a página desfocada por trás, ou um fundo liso se o desfoque estiver desligado.
struct FundoDeMenu: View {
    let fundoEscuro: Bool
    @AppStorage(ChavesTema.desfoque) private var desfoque = true

    var body: some View {
        ZStack {
            if desfoque {
                Rectangle().fill(.ultraThinMaterial)
                (fundoEscuro ? Color.black.opacity(0.25) : Color.white.opacity(0.25))
            } else {
                fundoEscuro ? Color(white: 0.08) : Color(white: 0.96)
            }
        }
        .ignoresSafeArea()
    }
}

/// Moldura de todos os menus do app: título, botão de fechar e o fundo desfocado.
/// O texto fica branco sobre fundo escuro e preto sobre fundo claro.
struct PainelVidro<Conteudo: View>: View {
    let titulo: String
    let fundoEscuro: Bool
    let aoFechar: () -> Void
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        ZStack {
            FundoDeMenu(fundoEscuro: fundoEscuro)
            VStack(spacing: 0) {
                HStack {
                    Text(titulo)
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    Button(action: aoFechar) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .buttonStyle(EstiloToque(forma: .circulo))
                    .accessibilityLabel("Fechar")
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 12)

                conteudo()
            }
        }
        .foregroundColor(fundoEscuro ? Color.white : Color.black)
        .environment(\.colorScheme, fundoEscuro ? .dark : .light)
    }
}

/// Etiqueta de desempenho: laranja nas opções que podem pesar, azul nas que ajudam.
struct EtiquetaDesempenho: View {
    var ajuda = false

    var body: some View {
        let cor: Color = ajuda ? Color.blue : Color.orange
        Text("Desempenho")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(cor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(cor.opacity(0.22)))
    }
}

// MARK: - Ícone do site

/// Ícone do site (o `favicon.ico` do próprio site). Sem ícone, mostra a primeira letra.
struct IconeDoSite: View {
    let host: String
    var tamanho: CGFloat = 26

    @State private var imagem: UIImage?

    var body: some View {
        Group {
            if let imagem {
                Image(uiImage: imagem)
                    .resizable()
                    .scaledToFit()
                    .padding(tamanho * 0.08)
            } else {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(.system(size: tamanho * 0.5, weight: .bold))
                    .foregroundColor(Color.primary.opacity(0.7))
            }
        }
        .frame(width: tamanho, height: tamanho)
        .background(Color.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: tamanho * 0.24, style: .continuous))
        .task(id: host) {
            imagem = await ArmazemImagens.compartilhado.icone(host: host)
        }
    }
}
