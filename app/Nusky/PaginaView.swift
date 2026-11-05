import SwiftUI
import UIKit

/// Desenha a página com UIKit. A rolagem é do UIScrollView, e o desenho é feito
/// em blocos (CATiledLayer): só os blocos que aparecem na tela são desenhados.
struct PaginaView: UIViewRepresentable {
    let itens: [DrawItem]
    let altura: CGFloat
    let escuro: Bool
    let restoreY: CGFloat
    let aoRolar: (CGFloat) -> Void
    let aoAbrirLink: (String) -> Void
    let aoTocarPagina: () -> Void

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

        scroll.backgroundColor = escuro ? .black : .white
        scroll.alturaDaPagina = altura

        let desenho = scroll.desenho
        if desenho.escuro != escuro {
            desenho.escuro = escuro
            desenho.setNeedsDisplay()
        }
        desenho.aoTocarLink = { link in c.pai.aoAbrirLink(link) }
        desenho.aoTocarPagina = { c.pai.aoTocarPagina() }

        // Página nova: o primeiro item muda, porque cada carregamento gera ids novos.
        let identificacao = itens.first?.id
        if identificacao != c.identificacao {
            c.identificacao = identificacao
            desenho.trocarItens(itens)
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
    }
}

/// UIScrollView que contém o desenho e ajusta o tamanho da página.
final class PaginaScroll: UIScrollView {
    let desenho = DesenhoPagina()

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
    }
}

/// Área que desenha o texto. Usa CATiledLayer: o sistema pede só os blocos visíveis.
final class DesenhoPagina: UIView {
    private let trava = NSLock()
    private var lista: [DrawItem] = []

    var escuro = false
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
    }

    required init?(coder: NSCoder) {
        fatalError("não usado")
    }

    func trocarItens(_ novos: [DrawItem]) {
        let ordenados = novos.sorted { CGFloat($0.y) < CGFloat($1.y) }
        trava.lock()
        lista = ordenados
        trava.unlock()
        setNeedsDisplay()
    }

    private func copia() -> [DrawItem] {
        trava.lock()
        defer { trava.unlock() }
        return lista
    }

    override func draw(_ rect: CGRect) {
        let itens = copia()
        var i = primeiroAPartir(itens, rect.minY - 80)
        while i < itens.count && CGFloat(itens[i].y) <= rect.maxY {
            desenhar(itens[i])
            i += 1
        }
    }

    private func desenhar(_ item: DrawItem) {
        let texto = NSAttributedString(string: item.text, attributes: atributos(item))
        texto.draw(at: CGPoint(x: CGFloat(item.x), y: CGFloat(item.y)))
    }

    private func atributos(_ item: DrawItem) -> [NSAttributedString.Key: Any] {
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
        UIFont.systemFont(ofSize: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular)
    }

    /// Cor da linha: a que a página pediu pelo CSS.
    /// Só troca por cor do tema quando o contraste fica abaixo de 1,5.
    /// Links sem cor própria ficam azuis.
    private func cor(_ item: DrawItem) -> UIColor {
        let padrao: UIColor = item.href != nil ? .systemBlue : (escuro ? .white : .black)
        guard let c = item.cor else { return padrao }
        let fundoLuminancia: Double = escuro ? 0 : 1
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