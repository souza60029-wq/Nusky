import SwiftUI
import UIKit

/// Desenha a página com UIKit. A rolagem é do UIScrollView, e o desenho é feito
/// em blocos (CATiledLayer): só os blocos que aparecem na tela são desenhados.
struct PaginaView: UIViewRepresentable {
    let itens: [DrawItem]
    let fundos: [Fundo]
    let imagens: [ImagemPagina]
    let formas: [FormaVetor]
    /// Endereço da página, para completar os endereços relativos das imagens.
    let baseURL: URL?
    let fundoPagina: CorTexto?
    let altura: CGFloat
    let escuro: Bool
    let restoreY: CGFloat
    let aoRolar: (CGFloat) -> Void
    let aoAbrirLink: (String) -> Void
    let aoTocarPagina: () -> Void
    /// O dedo começou a arrastar a página (a barra recolhe).
    let aoComecarRolar: () -> Void
    /// Desenha a página na GPU (Metal), quando o aparelho dá suporte.
    let usarMetal: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PaginaScroll {
        let scroll = PaginaScroll()
        scroll.delegate = context.coordinator
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        return scroll
    }

    func updateUIView(_ scroll: PaginaScroll, context: Context) {
        let c = context.coordinator
        c.pai = self

        // Se a página define a cor de fundo, ela manda: o texto escolhe contraste em cima dela.
        let escuroEfetivo = fundoPagina.map { $0.luminancia < 0.5 } ?? escuro
        if let f = fundoPagina {
            scroll.backgroundColor = UIColor(red: CGFloat(f.r), green: CGFloat(f.g), blue: CGFloat(f.b), alpha: 1)
        } else {
            scroll.backgroundColor = escuro ? .black : .white
        }
        scroll.alturaDaPagina = altura
        scroll.definirMetal(usarMetal)
        scroll.vistaMetal?.corDeFundo = scroll.backgroundColor ?? .white

        let desenho = scroll.desenho
        if desenho.escuro != escuroEfetivo {
            desenho.escuro = escuroEfetivo
            desenho.setNeedsDisplay()
            scroll.vistaMetal?.escuro = escuroEfetivo
            scroll.vistaMetal?.limparCache()
            scroll.setNeedsLayout()
        }
        desenho.aoTocarLink = { link in c.pai.aoAbrirLink(link) }
        desenho.aoTocarPagina = { c.pai.aoTocarPagina() }

        // Página nova: o primeiro item muda, porque cada carregamento gera ids novos.
        let identificacao = itens.first?.id ?? fundos.first?.id ?? imagens.first?.id ?? formas.first?.id
        if identificacao != c.identificacao {
            c.identificacao = identificacao
            desenho.trocarItens(itens, fundos: fundos, imagens: imagens, formas: formas, base: baseURL)
            scroll.vistaMetal?.limparCache()
            scroll.setNeedsLayout()
            scroll.layoutIfNeeded()
            scroll.setContentOffset(CGPoint(x: 0, y: restoreY), animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var pai: PaginaView
        var identificacao: UUID? = nil

        init(_ pai: PaginaView) {
            self.pai = pai
        }

        func scrollViewDidScroll(_ scroll: UIScrollView) {
            pai.aoRolar(max(0, scroll.contentOffset.y))
        }

        func scrollViewWillBeginDragging(_ scroll: UIScrollView) {
            pai.aoComecarRolar()
        }
    }
}

/// UIScrollView que contém o desenho e ajusta o tamanho da página.
final class PaginaScroll: UIScrollView {
    let desenho = DesenhoPagina()
    /// Desenho na GPU, quando ligado nos ajustes e o aparelho aceita.
    private(set) var vistaMetal: VistaMetal?

    /// Liga ou desliga o desenho em Metal. Se o Metal não estiver disponível, fica o desenho normal.
    func definirMetal(_ ativo: Bool) {
        if ativo {
            if vistaMetal == nil, let nova = VistaMetal.criar() {
                nova.fonte = desenho
                nova.escuro = desenho.escuro
                addSubview(nova)
                vistaMetal = nova
            }
        } else if vistaMetal != nil {
            vistaMetal?.removeFromSuperview()
            vistaMetal = nil
        }
        let ligado = vistaMetal != nil
        if desenho.modoMetal != ligado {
            desenho.modoMetal = ligado
            desenho.setNeedsDisplay()
            setNeedsLayout()
        }
    }

    var alturaDaPagina: CGFloat = 0 {
        didSet {
            if alturaDaPagina != oldValue {
                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(desenho)
    }

    required init?(coder: NSCoder) {
        fatalError("não usado")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        desenho.frame = CGRect(x: 0, y: 0, width: bounds.width, height: alturaDaPagina)
        contentSize = desenho.frame.size
        // A vista Metal acompanha a parte visível; rolar só muda o deslocamento.
        if let metal = vistaMetal {
            metal.frame = bounds
            metal.deslocamento = bounds.origin.y
            metal.renderizar()
        }
    }
}

/// Área que desenha o texto. Usa CATiledLayer: o sistema pede só os blocos visíveis.
final class DesenhoPagina: UIView {
    private let trava = NSLock()
    private var lista: [DrawItem] = []
    private var caixas: [Fundo] = []
    /// Imagens da página, cada uma com a chave do cache (nil se o endereço não vale).
    private var figuras: [(imagem: ImagemPagina, chave: String?)] = []
    private var observador: NSObjectProtocol?
    private var vetores: [FormaVetor] = []

    var escuro = false
    /// Com o Metal ligado, este desenho não pinta nada: só guarda os dados e recebe os toques.
    var modoMetal = false
    var aoTocarLink: ((String) -> Void)?
    var aoTocarPagina: (() -> Void)?

    override class var layerClass: AnyClass {
        CATiledLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        if let camada = layer as? CATiledLayer {
            camada.tileSize = CGSize(width: 256, height: 256)
            camada.levelsOfDetail = 1
            camada.levelsOfDetailBias = 0
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tocou(_:))))
        // Quando uma imagem termina de baixar, a tela se desenha de novo.
        observador = NotificationCenter.default.addObserver(
            forName: ArmazemImagens.aoCarregar, object: nil, queue: .main
        ) { [weak self] _ in
            self?.setNeedsDisplay()
        }
    }

    deinit {
        if let observador { NotificationCenter.default.removeObserver(observador) }
    }

    required init?(coder: NSCoder) {
        fatalError("não usado")
    }

    func trocarItens(_ novos: [DrawItem], fundos: [Fundo], imagens: [ImagemPagina], formas: [FormaVetor], base: URL?) {
        let ordenados = novos.sorted { CGFloat($0.y) < CGFloat($1.y) }
        let preparadas: [(imagem: ImagemPagina, chave: String?)] = imagens.map { img in
            guard let base, let url = resolverEnderecoDeImagem(img.src, base: base) else { return (img, nil) }
            return (img, ArmazemImagens.chave(para: url))
        }
        trava.lock()
        lista = ordenados
        caixas = fundos
        figuras = preparadas
        vetores = formas
        trava.unlock()
        setNeedsDisplay()
    }

    private func copia() -> [DrawItem] {
        trava.lock()
        defer { trava.unlock() }
        return lista
    }

    private func copiaCaixas() -> [Fundo] {
        trava.lock()
        defer { trava.unlock() }
        return caixas
    }

    private func copiaVetores() -> [FormaVetor] {
        trava.lock()
        defer { trava.unlock() }
        return vetores
    }

    /// Cor de uma tinta de SVG. `currentColor` vale a cor padrão do texto.
    private func cor(de tinta: TintaSvg, opacidade: CGFloat) -> UIColor? {
        switch tinta {
        case .nenhuma:
            return nil
        case .atual:
            return (escuro ? UIColor.white : UIColor.black).withAlphaComponent(opacidade)
        case .rgb(let r, let g, let b):
            return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: opacidade)
        }
    }

    /// Desenha os ícones e logotipos em SVG que tocam o bloco.
    private func desenharFormas(_ rect: CGRect) {
        guard let contexto = UIGraphicsGetCurrentContext() else { return }
        for forma in copiaVetores() where forma.caixa.intersects(rect) {
            if let cor = cor(de: forma.preenchimento, opacidade: forma.opacidadePreenchimento) {
                contexto.setFillColor(cor.cgColor)
                contexto.addPath(forma.caminho)
                contexto.fillPath(using: forma.parImpar ? .evenOdd : .winding)
            }
            if forma.larguraTraco > 0, let cor = cor(de: forma.traco, opacidade: forma.opacidadeTraco) {
                contexto.setStrokeColor(cor.cgColor)
                contexto.setLineWidth(forma.larguraTraco)
                contexto.setLineCap(.round)
                contexto.setLineJoin(.round)
                contexto.addPath(forma.caminho)
                contexto.strokePath()
            }
        }
    }

    private func copiaFiguras() -> [(imagem: ImagemPagina, chave: String?)] {
        trava.lock()
        defer { trava.unlock() }
        return figuras
    }

    /// Desenha as imagens que tocam o bloco. Enquanto a imagem não chegou, aparece um retângulo neutro.
    private func desenharImagens(_ rect: CGRect) {
        for figura in copiaFiguras() {
            let img = figura.imagem
            guard img.w > 0, img.h > 0 else { continue }
            let quadro = CGRect(x: img.x, y: img.y, width: img.w, height: img.h)
            guard quadro.intersects(rect) else { continue }
            if let chave = figura.chave, let pronta = ArmazemImagens.compartilhado.imagem(para: chave) {
                pronta.draw(in: quadro)
            } else {
                UIColor.gray.withAlphaComponent(0.18).setFill()
                UIBezierPath(roundedRect: quadro, cornerRadius: 6).fill()
            }
        }
    }

    /// Pinta as caixas de fundo que tocam o bloco. A lista vem de fora para dentro,
    /// então caixas de dentro ficam por cima das de fora.
    private func desenharFundos(_ rect: CGRect) {
        for f in copiaCaixas() {
            let quadro = CGRect(x: f.x, y: f.y, width: f.w, height: f.h)
            guard quadro.intersects(rect) else { continue }
            let raio = min(f.raio, min(quadro.width, quadro.height) / 2)
            if let cor = f.cor {
                UIColor(red: CGFloat(cor.r), green: CGFloat(cor.g), blue: CGFloat(cor.b), alpha: 1).setFill()
                UIBezierPath(roundedRect: quadro, cornerRadius: raio).fill()
            }
            if f.bordaLargura > 0, let borda = f.bordaCor {
                let meio = f.bordaLargura / 2
                let caminho = UIBezierPath(
                    roundedRect: quadro.insetBy(dx: meio, dy: meio),
                    cornerRadius: max(0, raio - meio)
                )
                caminho.lineWidth = f.bordaLargura
                UIColor(red: CGFloat(borda.r), green: CGFloat(borda.g), blue: CGFloat(borda.b), alpha: 1).setStroke()
                caminho.stroke()
            }
        }
    }

    /// Cópia dos dados da página para a vista Metal.
    struct DadosParaGPU {
        let itens: [DrawItem]
        let caixas: [Fundo]
        let figuras: [(imagem: ImagemPagina, chave: String?)]
        let vetores: [FormaVetor]
    }

    func dadosParaGPU() -> DadosParaGPU {
        trava.lock()
        defer { trava.unlock() }
        return DadosParaGPU(itens: lista, caixas: caixas, figuras: figuras, vetores: vetores)
    }

    override func draw(_ rect: CGRect) {
        if modoMetal { return }
        let inicioDoBloco = CACurrentMediaTime()
        defer { Desempenho.compartilhado.registrarDesenho((CACurrentMediaTime() - inicioDoBloco) * 1000) }
        desenharFundos(rect)
        desenharImagens(rect)
        desenharFormas(rect)
        let itens = copia()
        var i = primeiroAPartir(itens, rect.minY - 80)
        while i < itens.count && CGFloat(itens[i].y) <= rect.maxY {
            desenhar(itens[i])
            i += 1
        }
    }

    private func desenhar(_ item: DrawItem) {
        let texto = NSAttributedString(string: item.text, attributes: atributos(item))
        if let fundo = item.fundo {
            // Destaque atrás do texto, um pouco maior que ele.
            let tamanho = texto.size()
            let quadro = CGRect(x: CGFloat(item.x) - 6, y: CGFloat(item.y), width: tamanho.width + 12, height: tamanho.height)
            UIColor(red: CGFloat(fundo.r), green: CGFloat(fundo.g), blue: CGFloat(fundo.b), alpha: 1).setFill()
            UIRectFill(quadro)
        }
        texto.draw(at: CGPoint(x: CGFloat(item.x), y: CGFloat(item.y)))
    }

    func atributos(_ item: DrawItem) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            .font: fonte(item),
            .foregroundColor: cor(item)
        ]
        if item.href != nil {
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return a
    }

    private func fonte(_ item: DrawItem) -> UIFont {
        let base = UIFont.systemFont(ofSize: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular)
        guard item.serifa || item.italico else { return base }
        var descritor = base.fontDescriptor
        if item.serifa, let serifada = descritor.withDesign(.serif) {
            descritor = serifada
        }
        if item.italico, let inclinada = descritor.withSymbolicTraits(descritor.symbolicTraits.union(.traitItalic)) {
            descritor = inclinada
        }
        return UIFont(descriptor: descritor, size: CGFloat(item.fontSize))
    }

    /// Cor da linha: a que a página pediu pelo CSS.
    /// Só troca por cor do tema quando o contraste fica abaixo de 1,5.
    /// Links sem cor própria ficam azuis.
    private func cor(_ item: DrawItem) -> UIColor {
        // Texto sobre um destaque: o contraste conta contra a cor do destaque, não contra a página.
        let fundoLuminancia: Double
        let sobreEscuro: Bool
        if let destaque = item.fundo {
            fundoLuminancia = luminanciaRelativa(destaque)
            sobreEscuro = fundoLuminancia < 0.18
        } else {
            fundoLuminancia = escuro ? 0 : 1
            sobreEscuro = escuro
        }
        let padrao: UIColor = item.href != nil ? .systemBlue : (sobreEscuro ? .white : .black)
        guard let c = item.cor else { return padrao }
        let contraste = razaoDeContraste(luminanciaRelativa(c), fundoLuminancia)
        if contraste < 1.5 { return padrao }
        return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }

    private func retangulo(_ item: DrawItem) -> CGRect {
        let tamanho = NSAttributedString(string: item.text, attributes: [.font: fonte(item)]).size()
        return CGRect(origin: CGPoint(x: CGFloat(item.x), y: CGFloat(item.y)), size: tamanho)
    }

    @objc private func tocou(_ gesto: UITapGestureRecognizer) {
        let ponto = gesto.location(in: self)
        let itens = copia()
        var i = primeiroAPartir(itens, ponto.y - 80)
        while i < itens.count && CGFloat(itens[i].y) <= ponto.y {
            let item = itens[i]
            if let link = item.href, retangulo(item).insetBy(dx: -6, dy: -6).contains(ponto) {
                aoTocarLink?(link)
                return
            }
            i += 1
        }
        for figura in copiaFiguras() {
            let img = figura.imagem
            guard let link = img.href else { continue }
            let quadro = CGRect(x: img.x, y: img.y, width: img.w, height: img.h)
            if quadro.contains(ponto) {
                aoTocarLink?(link)
                return
            }
        }
        aoTocarPagina?()
    }
}

/// Busca binária: primeiro índice com altura maior ou igual a `y`. A lista precisa estar ordenada.
private func primeiroAPartir(_ lista: [DrawItem], _ y: CGFloat) -> Int {
    var baixo = 0
    var alto = lista.count
    while baixo < alto {
        let meio = (baixo + alto) / 2
        if CGFloat(lista[meio].y) < y {
            baixo = meio + 1
        } else {
            alto = meio
        }
    }
    return baixo
}

/// Luminância relativa pela regra WCAG: 0 é preto, 1 é branco.
private func luminanciaRelativa(_ cor: CorTexto) -> Double {
    func linear(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(cor.r) + 0.7152 * linear(cor.g) + 0.0722 * linear(cor.b)
}

/// Razão de contraste entre duas luminâncias: de 1 (igual) a 21 (preto contra branco).
private func razaoDeContraste(_ a: Double, _ b: Double) -> Double {
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
