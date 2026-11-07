// app/Nusky/Diagnostico.swift
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

/// Etapas do diagnóstico, na ordem em que aparecem no painel.
enum Etapa: CaseIterable, Hashable {
    case baixar, folhas, scripts, montar, janela, relatorio

    /// Texto mostrado enquanto a etapa roda.
    var titulo: String {
        switch self {
        case .baixar: return "Baixando a página"
        case .folhas: return "Carregando estilos externos"
        case .scripts: return "Lendo scripts e dados"
        case .montar: return "Montando a página"
        case .janela: return "Testando a rolagem"
        case .relatorio: return "Gerando o relatório"
        }
    }

    /// Nome usado na seção de tempos do relatório.
    var rotulo: String {
        switch self {
        case .baixar: return "Baixar a página (inclui a rede)"
        case .folhas: return "Carregar estilos externos"
        case .scripts: return "Ler scripts e dados"
        case .montar: return "Montar a página (motor)"
        case .janela: return "Testar a rolagem"
        case .relatorio: return "Gerar o relatório (motor)"
        }
    }

    /// Símbolo do SF Symbols usado no painel.
    var simbolo: String {
        switch self {
        case .baixar: return "arrow.down.circle"
        case .folhas: return "paintbrush"
        case .scripts: return "chevron.left.forwardslash.chevron.right"
        case .montar: return "rectangle.3.group"
        case .janela: return "arrow.up.and.down.circle"
        case .relatorio: return "doc.text"
        }
    }
}

/// Roda o trabalho e devolve o resultado junto com o tempo gasto, em segundos.
private func medir<T>(_ trabalho: () -> T) -> (T, Double) {
    let inicio = CFAbsoluteTimeGetCurrent()
    let valor = trabalho()
    return (valor, CFAbsoluteTimeGetCurrent() - inicio)
}

/// Segundos no formato brasileiro, por exemplo "0,82 s".
private func formatarSegundos(_ segundos: Double) -> String {
    String(format: "%.2f", segundos).replacingOccurrences(of: ".", with: ",") + " s"
}

/// Ponte com `nusky_diagnose`. Gera o relatório em texto a partir do HTML.
enum DiagnosticoPagina {
    static func gerar(html: String, largura: Float) -> String {
        let texto: String? = html.withCString { ptr in
            guard let saida = nusky_diagnose(ptr, largura, medirTextoDiagnostico) else { return nil }
            defer { nusky_free_string(saida) }
            return String(cString: saida)
        }
        return texto ?? "O motor não conseguiu gerar o relatório."
    }
}

/// Conta scripts e dados dentro da página. Não executa nada: só lê o texto do HTML.
enum DiagnosticoScripts {
    static func analisar(html: String) -> String {
        var quantidade = 0
        var bytes = 0
        var externos = 0
        var blocosJSON = 0
        var busca = html.startIndex..<html.endIndex

        while let abre = html.range(of: "<script", options: .caseInsensitive, range: busca) {
            let fimDaAbertura = html.range(of: ">", range: abre.upperBound..<html.endIndex)?.upperBound ?? html.endIndex
            let abertura = html[abre.lowerBound..<fimDaAbertura].lowercased()
            let fechamento = html.range(of: "</script", options: .caseInsensitive, range: fimDaAbertura..<html.endIndex)
            let fimDoBloco = fechamento?.lowerBound ?? html.endIndex

            quantidade += 1
            bytes += html.utf8.distance(from: abre.lowerBound, to: fimDoBloco)
            if abertura.contains("src=") { externos += 1 }
            if abertura.contains("application/json") { blocosJSON += 1 }

            guard let depois = fechamento?.upperBound else { break }
            busca = depois..<html.endIndex
        }

        let nextData = html.contains("__NEXT_DATA__") ? "presente" : "ausente"
        return [
            "SCRIPTS E DADOS",
            "Scripts na página: \(quantidade) (\(bytes / 1024) KB)",
            "Scripts com endereço externo (src): \(externos)",
            "Blocos JSON dentro da página: \(blocosJSON)",
            "Dados do Next.js (__NEXT_DATA__): \(nextData)",
            "Obs.: o tamanho conta o texto entre <script> e </script>, sem as tags.",
        ].joined(separator: "\n")
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

    /// Recebe os itens já montados, para não montar a página de novo.
    static func analisar(itens: [DrawItem]) -> String {
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

/// Estado do diagnóstico: etapas concluídas, tempos e o relatório final.
@MainActor
final class DiagnosticoModel: ObservableObject {
    @Published private(set) var concluidas: Set<Etapa> = []
    @Published private(set) var texto: String? = nil
    @Published private(set) var erro: String? = nil

    private var iniciou = false
    private var tempos: [Etapa: Double] = [:]

    /// Primeira etapa que ainda não terminou. Nil quando tudo terminou.
    var atual: Etapa? {
        Etapa.allCases.first { !concluidas.contains($0) }
    }

    func iniciar(url: URL?) async {
        guard !iniciou else { return }
        iniciou = true

        guard let url = url else {
            erro = "Nenhuma página aberta para analisar."
            return
        }

        let largura = Float(UIScreen.main.bounds.width)
        let inicioTotal = CFAbsoluteTimeGetCurrent()

        do {
            // 1. Baixar a página do mesmo jeito que o app faz.
            let inicio = CFAbsoluteTimeGetCurrent()
            let (dados, resposta) = try await DownloadPagina { _ in }.baixar(url)
            concluir(.baixar, CFAbsoluteTimeGetCurrent() - inicio)
            let base = resposta.url ?? url
            let html = String(decoding: dados, as: UTF8.self)

            // 2. Folhas de estilo externas, incluídas no HTML.
            let inicioFolhas = CFAbsoluteTimeGetCurrent()
            let completo = await FolhasExternas.incluir(em: html, base: base)
            concluir(.folhas, CFAbsoluteTimeGetCurrent() - inicioFolhas)

            // 3. Contagem de scripts e dados, fora da tela principal.
            let (scripts, segundosScripts) = await Task.detached(priority: .userInitiated) { () -> (String, Double) in
                medir { DiagnosticoScripts.analisar(html: completo) }
            }.value
            concluir(.scripts, segundosScripts)

            // 4. Montagem, relatório e teste de janela.
            // O relatório do motor roda junto com a montagem. A janela usa a montagem já feita.
            let relatorioTask = Task.detached(priority: .userInitiated) { () -> (String, Double) in
                medir { DiagnosticoPagina.gerar(html: completo, largura: largura) }
            }

            let (itens, segundosMontar) = await Task.detached(priority: .userInitiated) { () -> ([DrawItem], Double) in
                medir { Engine.render(html: completo, width: largura) }
            }.value
            concluir(.montar, segundosMontar)

            let (janela, segundosJanela) = await Task.detached(priority: .userInitiated) { () -> (String, Double) in
                medir { DiagnosticoJanela.analisar(itens: itens) }
            }.value
            concluir(.janela, segundosJanela)

            let (relatorio, segundosRelatorio) = await relatorioTask.value
            concluir(.relatorio, segundosRelatorio)

            texto = montarTexto(
                url: base,
                relatorio: relatorio,
                janela: janela,
                scripts: scripts,
                total: CFAbsoluteTimeGetCurrent() - inicioTotal
            )
        } catch {
            erro = "Não foi possível baixar a página:\n\(error.localizedDescription)"
        }
    }

    private func concluir(_ etapa: Etapa, _ segundos: Double) {
        tempos[etapa] = segundos
        withAnimation(.easeOut(duration: 0.35)) {
            _ = concluidas.insert(etapa)
        }
    }

    private func montarTexto(url: URL, relatorio: String, janela: String, scripts: String, total: Double) -> String {
        var linhas = ["TEMPOS DO APP (medidos no aparelho)"]
        for etapa in Etapa.allCases {
            if let segundos = tempos[etapa] {
                linhas.append("\(etapa.rotulo): \(formatarSegundos(segundos))")
            }
        }
        linhas.append("Tempo total: \(formatarSegundos(total))")
        linhas.append("Obs.: montar a página e gerar o relatório rodam juntos, então o total é menor que a soma.")

        return [
            "URL: \(url.absoluteString)",
            relatorio,
            janela,
            scripts,
            linhas.joined(separator: "\n"),
        ].joined(separator: "\n\n")
    }
}

/// Tela que baixa a página, mostra as etapas e permite copiar o relatório.
struct DiagnosticoView: View {
    let url: URL?
    @StateObject private var modelo = DiagnosticoModel()
    @State private var copiado = false

    var body: some View {
        VStack(spacing: 0) {
            PainelEtapas(concluidas: modelo.concluidas, atual: modelo.atual)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            Divider()
            conteudo
        }
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if modelo.texto != nil {
                botaoCopiar
            }
        }
        .task { await modelo.iniciar(url: url) }
    }

    @ViewBuilder
    private var conteudo: some View {
        if let texto = modelo.texto {
            RelatorioTexto(texto: texto)
        } else if let erro = modelo.erro {
            ScrollView {
                Text(erro)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } else {
            Spacer()
        }
    }

    private var botaoCopiar: some View {
        Button {
            UIPasteboard.general.string = modelo.texto ?? ""
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
}

/// Linha de etapas: um símbolo por etapa, com um quadradinho embaixo que fica verde quando a etapa termina.
private struct PainelEtapas: View {
    let concluidas: Set<Etapa>
    let atual: Etapa?
    @State private var pulso = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Etapa.allCases, id: \.self) { etapa in
                    coluna(etapa)
                        .frame(maxWidth: .infinity)
                }
            }
            Text(legenda)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulso = true
            }
        }
    }

    private var legenda: String {
        if let atual = atual {
            return atual.titulo + "…"
        }
        return "Relatório pronto"
    }

    private func coluna(_ etapa: Etapa) -> some View {
        let feita = concluidas.contains(etapa)
        let ativa = etapa == atual
        return VStack(spacing: 8) {
            Image(systemName: etapa.simbolo)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(feita ? Color.green : (ativa ? Color.accentColor : Color.secondary))
                .scaleEffect(ativa && pulso ? 1.12 : 1.0)
                .frame(height: 28)
            RoundedRectangle(cornerRadius: 2)
                .fill(feita ? Color.green : Color.secondary.opacity(0.25))
                .frame(width: 10, height: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(etapa.titulo), \(feita ? "concluída" : "pendente")")
    }
}

/// Mostra o relatório num campo de texto com rolagem própria. Costuma ser mais leve
/// que um Text do SwiftUI para textos longos, e permite selecionar trechos.
private struct RelatorioTexto: UIViewRepresentable {
    let texto: String

    func makeUIView(context: Context) -> UITextView {
        let campo = UITextView()
        campo.isEditable = false
        campo.isSelectable = true
        campo.backgroundColor = .clear
        campo.textColor = .label
        campo.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        campo.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
        campo.alwaysBounceVertical = true
        campo.text = texto
        return campo
    }

    func updateUIView(_ campo: UITextView, context: Context) {
        if campo.text != texto {
            campo.text = texto
        }
    }
}