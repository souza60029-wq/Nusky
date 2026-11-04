// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

import SwiftUI
import UIKit

/// Medida de texto para o motor, com CoreText (UIFont), igual à usada na renderização.
private let medirTextoDiagnostico: @convention(c) (UnsafePointer<CChar>?, Float, Int32) -> Float = { texto, tamanho, negrito in
    guard let texto else { return 0 }
    let fonte = negrito != 0
        ? UIFont.boldSystemFont(ofSize: CGFloat(tamanho))
        : UIFont.systemFont(ofSize: CGFloat(tamanho))
    let largura = NSString(string: String(cString: texto)).size(withAttributes: [.font: fonte]).width
    return Float(largura)
}

/// Ponte com `nusky_diagnose`. Gera o relatório em texto a partir do HTML.
enum DiagnosticoPagina {
    static func gerar(html: String) -> String {
        let largura = Float(UIScreen.main.bounds.width)
        let texto: String? = html.withCString { ptr in
            guard let saida = nusky_diagnose(ptr, largura, medirTextoDiagnostico) else { return nil }
            defer { nusky_free_string(saida) }
            return String(cString: saida)
        }
        return texto ?? "O motor não conseguiu gerar o relatório."
    }
}

/// Testa a janela de desenho da ContentView sem a tela: para cada posição de rolagem,
/// confere se todo item visível naquela posição está na faixa que seria renderizada.
/// Não simula a rolagem real, só a conta da janela.
enum DiagnosticoJanela {
    // Mesmos valores usados em ContentView.
    private static let passo: CGFloat = 400
    private static let margem: CGFloat = 400
    private static let alcance: CGFloat = 1800
    /// Altura aproximada da área visível (tela menos as barras).
    private static let alturaVisivel: CGFloat = 600

    static func analisar(html: String) -> String {
        let itens = Engine.render(html: html, width: Float(UIScreen.main.bounds.width))
        var linhas: [String] = ["TESTE DE JANELA", "Itens desenhados: \(itens.count)"]
        guard !itens.isEmpty else {
            linhas.append("Nada para testar.")
            return linhas.joined(separator: "\n")
        }

        var ordenado = true
        for i in 1..<itens.count where CGFloat(itens[i].y) < CGFloat(itens[i - 1].y) {
            ordenado = false
            break
        }
        linhas.append(ordenado
            ? "Ordem por altura: crescente (ok)"
            : "Ordem por altura: FORA DE ORDEM (a busca da janela pode pular itens)")

        let alturaTotal = itens.reduce(CGFloat(0)) { maior, item in
            max(maior, CGFloat(item.y) + CGFloat(item.fontSize) + 80)
        }
        linhas.append("Altura total: \(Int(alturaTotal)) pt")

        var falhas = 0
        var primeira: String? = nil
        var offset: CGFloat = 0
        while offset <= alturaTotal {
            let faixa = CGFloat(Int(offset / passo))
            let renderizado = intervalo(itens, faixa * passo - margem, faixa * passo + alcance)
            let esperado = intervalo(itens, offset, offset + alturaVisivel)
            let faltando = esperado.filter { !renderizado.contains($0) }
            if !faltando.isEmpty {
                falhas += 1
                if primeira == nil {
                    let exemplo = String(itens[faltando[0]].text.prefix(40))
                    primeira = "Rolagem \(Int(offset)) pt: faltam \(faltando.count) de \(esperado.count) itens visíveis. Exemplo: \"\(exemplo)\" (y \(Int(itens[faltando[0]].y)))"
                }
            }
            offset += passo
        }

        linhas.append(falhas == 0
            ? "Resultado: nenhuma posição de rolagem perde itens visíveis (ok)."
            : "Resultado: FALHA em \(falhas) posições de rolagem.")
        if let primeira = primeira {
            linhas.append(primeira)
        }
        return linhas.joined(separator: "\n")
    }

    /// Mesma busca de ContentView.linhasVisiveis: índices dos itens com altura entre inicio e fim.
    private static func intervalo(_ itens: [DrawItem], _ inicio: CGFloat, _ fim: CGFloat) -> Range<Int> {
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
        var fimIndice = baixo
        while fimIndice < itens.count && CGFloat(itens[fimIndice].y) <= fim {
            fimIndice += 1
        }
        return baixo..<fimIndice
    }
}

/// Tela que baixa a página de novo, gera o relatório e permite copiá-lo.
struct DiagnosticoView: View {
    let url: URL?
    @State private var texto: String? = nil
    @State private var copiado = false

    var body: some View {
        ScrollView {
            Group {
                if let texto = texto {
                    Text(texto)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Analisando a página…")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if texto != nil {
                botaoCopiar
            }
        }
        .task { await analisar() }
    }

    private var botaoCopiar: some View {
        Button {
            UIPasteboard.general.string = texto ?? ""
            copiado = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copiado = false
            }
        } label: {
            Text(copiado ? "Copiado" : "Copiar relatório")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Baixa a página do mesmo jeito que o app faz (com folhas externas) e gera o relatório.
    private func analisar() async {
        guard texto == nil else { return }
        guard let url = url else {
            texto = "Nenhuma página aberta para analisar."
            return
        }
        do {
            let (dados, resposta) = try await DownloadPagina { _ in }.baixar(url)
            let html = String(decoding: dados, as: UTF8.self)
            let base = resposta.url ?? url
            let completo = await FolhasExternas.incluir(em: html, base: base)
            let (relatorio, janela) = await Task.detached(priority: .userInitiated) {
                (DiagnosticoPagina.gerar(html: completo), DiagnosticoJanela.analisar(html: completo))
            }.value
            texto = "URL: \(base.absoluteString)\n\n" + relatorio + "\n\n" + janela
        } catch {
            texto = "Não foi possível baixar a página:\n\(error.localizedDescription)"
        }
    }
}