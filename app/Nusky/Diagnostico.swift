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
            let relatorio = await Task.detached(priority: .userInitiated) {
                DiagnosticoPagina.gerar(html: completo)
            }.value
            texto = "URL: \(base.absoluteString)\n\n" + relatorio
        } catch {
            texto = "Não foi possível baixar a página:\n\(error.localizedDescription)"
        }
    }
}