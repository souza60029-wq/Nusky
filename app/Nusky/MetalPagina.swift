// app/Nusky/MetalPagina.swift
import UIKit
import Metal
import QuartzCore
import simd

// MARK: - Shaders

/// Os shaders vão como texto e são compilados quando o Metal liga. Se a compilação falhar,
/// o app continua com o desenho normal (CATiledLayer).
private let fonteDosShaders = """
#include <metal_stdlib>
using namespace metal;

struct UniformesTela {
    float2 tamanho;
    float deslocamento;
    float reserva;
};

struct InstanciaRet {
    float4 quadro;        // x, y, largura, altura em pontos da página
    float4 preenchimento;
    float4 contorno;
    float4 params;        // raio, largura da borda
};

struct SaidaRet {
    float4 posicao [[position]];
    float2 local;
    float2 metade;
    float4 preenchimento;
    float4 contorno;
    float raio;
    float borda;
};

constant float2 cantos[6] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 0), float2(1, 1), float2(0, 1) };

float4 paraTela(float2 ponto, constant UniformesTela &u) {
    float x = ponto.x / u.tamanho.x * 2.0 - 1.0;
    float y = 1.0 - (ponto.y - u.deslocamento) / u.tamanho.y * 2.0;
    return float4(x, y, 0.0, 1.0);
}

vertex SaidaRet vertice_ret(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            constant InstanciaRet *instancias [[buffer(0)]],
                            constant UniformesTela &u [[buffer(1)]]) {
    InstanciaRet r = instancias[iid];
    float2 canto = cantos[vid];
    float2 margem = float2(1.0, 1.0);
    float2 origem = r.quadro.xy - margem;
    float2 tamanho = r.quadro.zw + margem * 2.0;
    SaidaRet saida;
    saida.posicao = paraTela(origem + canto * tamanho, u);
    saida.local = canto * tamanho - tamanho * 0.5;
    saida.metade = r.quadro.zw * 0.5;
    saida.preenchimento = r.preenchimento;
    saida.contorno = r.contorno;
    saida.raio = r.params.x;
    saida.borda = r.params.y;
    return saida;
}

fragment float4 fragmento_ret(SaidaRet entrada [[stage_in]]) {
    float raio = min(entrada.raio, min(entrada.metade.x, entrada.metade.y));
    float2 q = abs(entrada.local) - (entrada.metade - float2(raio));
    float distancia = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - raio;
    float suave = max(fwidth(distancia), 0.0001);
    float cobertura = clamp(0.5 - distancia / suave, 0.0, 1.0);
    float dentro = entrada.borda > 0.0 ? clamp(0.5 - (distancia + entrada.borda) / suave, 0.0, 1.0) : 1.0;
    float4 cor = mix(entrada.contorno, entrada.preenchimento, dentro);
    cor.a *= cobertura;
    return float4(cor.rgb * cor.a, cor.a);
}

struct SaidaTextura {
    float4 posicao [[position]];
    float2 uv;
};

vertex SaidaTextura vertice_textura(uint vid [[vertex_id]],
                                    constant float4 &quadro [[buffer(0)]],
                                    constant UniformesTela &u [[buffer(1)]]) {
    float2 canto = cantos[vid];
    SaidaTextura saida;
    saida.posicao = paraTela(quadro.xy + canto * quadro.zw, u);
    saida.uv = canto;
    return saida;
}

fragment float4 fragmento_textura(SaidaTextura entrada [[stage_in]],
                                  texture2d<float> textura [[texture(0)]],
                                  sampler amostra [[sampler(0)]]) {
    return textura.sample(amostra, entrada.uv);
}
"""

private struct InstanciaRet {
    var quadro: SIMD4<Float>
    var preenchimento: SIMD4<Float>
    var contorno: SIMD4<Float>
    var params: SIMD4<Float>
}

private struct UniformesTela {
    var tamanho: SIMD2<Float>
    var deslocamento: Float
    var reserva: Float
}

/// Uma textura pronta e o espaço que ela ocupa na memória da GPU.
private final class Texturizado {
    let textura: MTLTexture
    let bytes: Int

    init(textura: MTLTexture, bytes: Int) {
        self.textura = textura
        self.bytes = bytes
    }
}

// MARK: - A vista

/// Desenha a página na GPU, como opção.
///
/// Como funciona: o texto, as imagens e os ícones em SVG viram texturas, uma vez cada, só quando chegam perto
/// da tela. Caixas de fundo, bordas e cantos arredondados são desenhados direto pela GPU, sem textura.
/// Rolar a página vira só mudar um número (o deslocamento): nada é redesenhado pela CPU a cada quadro.
/// As texturas ficam num cache com limite de memória.
final class VistaMetal: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    /// De onde vêm os dados da página (os mesmos do desenho normal).
    weak var fonte: DesenhoPagina?
    var deslocamento: CGFloat = 0
    var corDeFundo: UIColor = .white
    var escuro = false

    private let dispositivo: MTLDevice
    private let fila: MTLCommandQueue
    private let pipelineRetangulos: MTLRenderPipelineState
    private let pipelineTexturas: MTLRenderPipelineState
    private let amostrador: MTLSamplerState

    private var cache: [String: Texturizado] = [:]
    private var ordem: [String] = []
    private var bytesNoCache = 0
    private let limiteDeBytes = 48 * 1024 * 1024
    private let maximoPorQuadro = 14
    private var observador: NSObjectProtocol?

    private var camada: CAMetalLayer { layer as! CAMetalLayer }

    /// Cria a vista. Devolve nil se este aparelho não tem Metal ou se os shaders não compilam.
    static func criar() -> VistaMetal? {
        guard let dispositivo = MTLCreateSystemDefaultDevice(),
              let fila = dispositivo.makeCommandQueue(),
              let biblioteca = try? dispositivo.makeLibrary(source: fonteDosShaders, options: nil) else { return nil }

        func pipeline(_ vertice: String, _ fragmento: String) -> MTLRenderPipelineState? {
            guard let v = biblioteca.makeFunction(name: vertice),
                  let f = biblioteca.makeFunction(name: fragmento) else { return nil }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            let cor = d.colorAttachments[0]!
            cor.pixelFormat = .bgra8Unorm
            cor.isBlendingEnabled = true
            cor.rgbBlendOperation = .add
            cor.alphaBlendOperation = .add
            // Cores já multiplicadas pelo alfa.
            cor.sourceRGBBlendFactor = .one
            cor.sourceAlphaBlendFactor = .one
            cor.destinationRGBBlendFactor = .oneMinusSourceAlpha
            cor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? dispositivo.makeRenderPipelineState(descriptor: d)
        }

        let descritorAmostra = MTLSamplerDescriptor()
        descritorAmostra.minFilter = .linear
        descritorAmostra.magFilter = .linear
        descritorAmostra.sAddressMode = .clampToEdge
        descritorAmostra.tAddressMode = .clampToEdge

        guard let ret = pipeline("vertice_ret", "fragmento_ret"),
              let tex = pipeline("vertice_textura", "fragmento_textura"),
              let amostra = dispositivo.makeSamplerState(descriptor: descritorAmostra) else { return nil }

        return VistaMetal(dispositivo: dispositivo, fila: fila, ret: ret, tex: tex, amostra: amostra)
    }

    private init(
        dispositivo: MTLDevice,
        fila: MTLCommandQueue,
        ret: MTLRenderPipelineState,
        tex: MTLRenderPipelineState,
        amostra: MTLSamplerState
    ) {
        self.dispositivo = dispositivo
        self.fila = fila
        self.pipelineRetangulos = ret
        self.pipelineTexturas = tex
        self.amostrador = amostra
        super.init(frame: .zero)
        isOpaque = true
        isUserInteractionEnabled = false
        camada.device = dispositivo
        camada.pixelFormat = .bgra8Unorm
        camada.framebufferOnly = true
        camada.contentsScale = UIScreen.main.scale
        // Quando uma imagem termina de baixar, a vista desenha de novo.
        observador = NotificationCenter.default.addObserver(
            forName: ArmazemImagens.aoCarregar, object: nil, queue: .main
        ) { [weak self] _ in
            self?.renderizar()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("não usado")
    }

    deinit {
        if let observador { NotificationCenter.default.removeObserver(observador) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let escala = UIScreen.main.scale
        let novo = CGSize(width: max(1, bounds.width * escala), height: max(1, bounds.height * escala))
        if camada.drawableSize != novo {
            camada.drawableSize = novo
        }
    }

    /// Esvazia as texturas (por exemplo, ao trocar de página ou de tema).
    func limparCache() {
        cache.removeAll()
        ordem.removeAll()
        bytesNoCache = 0
    }

    // MARK: Cache

    private func guardar(_ chave: String, _ item: Texturizado) {
        cache[chave] = item
        ordem.append(chave)
        bytesNoCache += item.bytes
        // Passou do limite: solta as mais antigas.
        while bytesNoCache > limiteDeBytes, let antiga = ordem.first {
            ordem.removeFirst()
            if let removida = cache.removeValue(forKey: antiga) {
                bytesNoCache -= removida.bytes
            }
        }
    }

    /// Cria uma textura desenhando com CoreGraphics. O contexto chega com a origem no canto de cima
    /// e a escala da tela já aplicada: dá para desenhar em pontos, como no UIKit.
    private func criarTextura(largura: Int, altura: Int, escala: CGFloat, desenho: (CGContext) -> Void) -> Texturizado? {
        guard largura > 0, altura > 0, largura <= 4096, altura <= 4096 else { return nil }
        let bytesPorLinha = largura * 4
        var dados = [UInt8](repeating: 0, count: bytesPorLinha * altura)
        let espaco = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let resultado: MTLTexture? = dados.withUnsafeMutableBytes { ponteiro in
            guard let base = ponteiro.baseAddress,
                  let contexto = CGContext(
                    data: base, width: largura, height: altura, bitsPerComponent: 8,
                    bytesPerRow: bytesPorLinha, space: espaco, bitmapInfo: info
                  ) else { return nil }
            contexto.translateBy(x: 0, y: CGFloat(altura))
            contexto.scaleBy(x: escala, y: -escala)
            UIGraphicsPushContext(contexto)
            desenho(contexto)
            UIGraphicsPopContext()

            let descritor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: largura, height: altura, mipmapped: false
            )
            descritor.usage = .shaderRead
            guard let textura = self.dispositivo.makeTexture(descriptor: descritor) else { return nil }
            textura.replace(
                region: MTLRegionMake2D(0, 0, largura, altura),
                mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPorLinha
            )
            return textura
        }
        guard let textura = resultado else { return nil }
        return Texturizado(textura: textura, bytes: bytesPorLinha * altura)
    }

    /// Textura de uma linha de texto (com o destaque de fundo, se houver). Devolve também o quadro na página.
    private func texturaDeTexto(_ item: DrawItem, fonte: DesenhoPagina) -> (Texturizado, SIMD4<Float>)? {
        let chave = "t\(item.id)"
        let escala = UIScreen.main.scale
        let texto = NSAttributedString(string: item.text, attributes: fonte.atributos(item))
        let tamanho = texto.size()
        let folga: CGFloat = item.fundo != nil ? 6 : 0
        let largura = ceil(tamanho.width) + folga * 2 + 2
        let altura = ceil(tamanho.height) + 2
        let quadro = SIMD4<Float>(
            Float(CGFloat(item.x) - folga), Float(CGFloat(item.y) - 1), Float(largura), Float(altura)
        )
        if let pronta = cache[chave] { return (pronta, quadro) }
        guard let novo = criarTextura(
            largura: Int(largura * escala), altura: Int(altura * escala), escala: escala,
            desenho: { _ in
                if let destaque = item.fundo {
                    UIColor(red: CGFloat(destaque.r), green: CGFloat(destaque.g), blue: CGFloat(destaque.b), alpha: 1).setFill()
                    UIRectFill(CGRect(x: 0, y: 1, width: largura, height: ceil(tamanho.height)))
                }
                texto.draw(at: CGPoint(x: folga, y: 1))
            }
        ) else { return nil }
        guardar(chave, novo)
        return (novo, quadro)
    }

    private func texturaDeImagem(_ imagem: UIImage, chave: String, largura: CGFloat, altura: CGFloat) -> Texturizado? {
        let escala = UIScreen.main.scale
        let id = "i\(chave)|\(Int(largura))x\(Int(altura))"
        if let pronta = cache[id] { return pronta }
        guard let novo = criarTextura(
            largura: Int(largura * escala), altura: Int(altura * escala), escala: escala,
            desenho: { _ in imagem.draw(in: CGRect(x: 0, y: 0, width: largura, height: altura)) }
        ) else { return nil }
        guardar(id, novo)
        return novo
    }

    private func texturaDeForma(_ forma: FormaVetor) -> Texturizado? {
        let chave = "v\(forma.id)"
        if let pronta = cache[chave] { return pronta }
        let escala = UIScreen.main.scale
        let caixa = forma.caixa
        guard caixa.width > 0, caixa.height > 0 else { return nil }
        let corAtual: UIColor = escuro ? .white : .black
        guard let novo = criarTextura(
            largura: Int(ceil(caixa.width * escala)), altura: Int(ceil(caixa.height * escala)), escala: escala,
            desenho: { contexto in
                contexto.translateBy(x: -caixa.minX, y: -caixa.minY)
                func cor(_ tinta: TintaSvg, _ opacidade: CGFloat) -> UIColor? {
                    switch tinta {
                    case .nenhuma: return nil
                    case .atual: return corAtual.withAlphaComponent(opacidade)
                    case .rgb(let r, let g, let b): return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: opacidade)
                    }
                }
                if let c = cor(forma.preenchimento, forma.opacidadePreenchimento) {
                    contexto.setFillColor(c.cgColor)
                    contexto.addPath(forma.caminho)
                    contexto.fillPath(using: forma.parImpar ? .evenOdd : .winding)
                }
                if forma.larguraTraco > 0, let c = cor(forma.traco, forma.opacidadeTraco) {
                    contexto.setStrokeColor(c.cgColor)
                    contexto.setLineWidth(forma.larguraTraco)
                    contexto.setLineCap(.round)
                    contexto.setLineJoin(.round)
                    contexto.addPath(forma.caminho)
                    contexto.strokePath()
                }
            }
        ) else { return nil }
        guardar(chave, novo)
        return novo
    }

    // MARK: Desenho

    private func vetor(_ cor: UIColor?, alfa: Float = 1) -> SIMD4<Float> {
        guard let cor else { return SIMD4<Float>(0, 0, 0, 0) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a) * alfa)
    }

    private func uiCor(_ cor: CorTexto?) -> UIColor? {
        guard let cor else { return nil }
        return UIColor(red: CGFloat(cor.r), green: CGFloat(cor.g), blue: CGFloat(cor.b), alpha: 1)
    }

    /// Desenha um quadro. Só mexe com o que está perto da tela.
    func renderizar() {
        guard bounds.width > 0, bounds.height > 0, let fonte else { return }
        let inicioDoQuadro = CACurrentMediaTime()
        defer { Desempenho.compartilhado.registrarMetal((CACurrentMediaTime() - inicioDoQuadro) * 1000) }
        guard let drawable = camada.nextDrawable() else { return }
        let dados = fonte.dadosParaGPU()
        let topo = Float(deslocamento) - 80
        let base = Float(deslocamento + bounds.height) + 80

        var fundoR: CGFloat = 0, fundoG: CGFloat = 0, fundoB: CGFloat = 0, fundoA: CGFloat = 1
        corDeFundo.getRed(&fundoR, green: &fundoG, blue: &fundoB, alpha: &fundoA)
        let passe = MTLRenderPassDescriptor()
        passe.colorAttachments[0].texture = drawable.texture
        passe.colorAttachments[0].loadAction = .clear
        passe.colorAttachments[0].storeAction = .store
        passe.colorAttachments[0].clearColor = MTLClearColor(red: Double(fundoR), green: Double(fundoG), blue: Double(fundoB), alpha: 1)

        guard let comandos = fila.makeCommandBuffer(),
              let codificador = comandos.makeRenderCommandEncoder(descriptor: passe) else { return }

        var uniformes = UniformesTela(
            tamanho: SIMD2<Float>(Float(bounds.width), Float(bounds.height)),
            deslocamento: Float(deslocamento),
            reserva: 0
        )
        var criadas = 0
        var faltou = false

        // 1) Caixas de fundo e espaços de imagens que ainda não chegaram.
        var instancias: [InstanciaRet] = []
        for f in dados.caixas {
            let y = Float(f.y)
            if y > base || y + Float(f.h) < topo { continue }
            instancias.append(InstanciaRet(
                quadro: SIMD4<Float>(Float(f.x), y, Float(f.w), Float(f.h)),
                preenchimento: vetor(uiCor(f.cor)),
                contorno: vetor(uiCor(f.bordaCor)),
                params: SIMD4<Float>(Float(f.raio), f.bordaCor == nil ? 0 : Float(f.bordaLargura), 0, 0)
            ))
        }
        var imagensProntas: [(UIImage, String, ImagemPagina)] = []
        for figura in dados.figuras {
            let img = figura.imagem
            guard img.w > 0, img.h > 0 else { continue }
            let y = Float(img.y)
            if y > base || y + Float(img.h) < topo { continue }
            if let chave = figura.chave, let pronta = ArmazemImagens.compartilhado.imagem(para: chave) {
                imagensProntas.append((pronta, chave, img))
            } else {
                instancias.append(InstanciaRet(
                    quadro: SIMD4<Float>(Float(img.x), y, Float(img.w), Float(img.h)),
                    preenchimento: SIMD4<Float>(0.5, 0.5, 0.5, 0.18),
                    contorno: SIMD4<Float>(0, 0, 0, 0),
                    params: SIMD4<Float>(6, 0, 0, 0)
                ))
            }
        }
        if !instancias.isEmpty,
           let buffer = dispositivo.makeBuffer(
            bytes: instancias, length: MemoryLayout<InstanciaRet>.stride * instancias.count, options: .storageModeShared
           ) {
            codificador.setRenderPipelineState(pipelineRetangulos)
            codificador.setVertexBuffer(buffer, offset: 0, index: 0)
            codificador.setVertexBytes(&uniformes, length: MemoryLayout<UniformesTela>.stride, index: 1)
            codificador.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instancias.count)
        }

        // 2) Texturas: imagens, ícones em SVG e texto, nessa ordem.
        codificador.setRenderPipelineState(pipelineTexturas)
        codificador.setFragmentSamplerState(amostrador, index: 0)
        codificador.setVertexBytes(&uniformes, length: MemoryLayout<UniformesTela>.stride, index: 1)

        func desenharTextura(_ item: Texturizado, _ quadro: SIMD4<Float>) {
            var q = quadro
            codificador.setVertexBytes(&q, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            codificador.setFragmentTexture(item.textura, index: 0)
            codificador.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        for (imagem, chave, info) in imagensProntas {
            if cache["i\(chave)|\(Int(info.w))x\(Int(info.h))"] == nil {
                if criadas >= maximoPorQuadro { faltou = true; continue }
                criadas += 1
            }
            if let textura = texturaDeImagem(imagem, chave: chave, largura: info.w, altura: info.h) {
                desenharTextura(textura, SIMD4<Float>(Float(info.x), Float(info.y), Float(info.w), Float(info.h)))
            }
        }

        for forma in dados.vetores {
            let caixa = forma.caixa
            if Float(caixa.minY) > base || Float(caixa.maxY) < topo { continue }
            if cache["v\(forma.id)"] == nil {
                if criadas >= maximoPorQuadro { faltou = true; continue }
                criadas += 1
            }
            if let textura = texturaDeForma(forma) {
                desenharTextura(textura, SIMD4<Float>(Float(caixa.minX), Float(caixa.minY), Float(caixa.width), Float(caixa.height)))
            }
        }

        for item in dados.itens {
            let y = Float(item.y)
            if y > base { break }
            if y + Float(item.fontSize) * 1.5 < topo { continue }
            if cache["t\(item.id)"] == nil {
                if criadas >= maximoPorQuadro { faltou = true; continue }
                criadas += 1
            }
            if let (textura, quadro) = texturaDeTexto(item, fonte: fonte) {
                desenharTextura(textura, quadro)
            }
        }

        codificador.endEncoding()
        comandos.present(drawable)
        comandos.commit()

        // Havia mais texturas para criar do que o limite por quadro: continua no próximo quadro.
        if faltou {
            DispatchQueue.main.async { [weak self] in self?.renderizar() }
        }
    }
}
