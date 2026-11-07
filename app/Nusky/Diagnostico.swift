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

/// Executa um trabalho e devolve o resultado com o tempo gasto, em segundos.
private func cronometrar<T>(_ trabalho: () -> T) -> (T, Double) {
    let inicio = CFAbsoluteTimeGetCurrent()
    let resultado = trabalho()
    return (resultado, CFAbsoluteTimeGetCurrent() - inicio)
}

/// "0,82 s", com vírgula.
private func formatarSegundos(_ segundos: Double) -> String {
    String(format: "%.2f s", segundos).replacingOccurrences(of: ".", with: ",")
}

/// Número com separador de milhar, no padrão brasileiro.
private func numero(_ valor: Int) -> String {
    let formatador = NumberFormatter()
    formatador.numberStyle = .decimal
    formatador.locale = Locale(identifier: "pt_BR")
    return formatador.string(from: NSNumber(value: valor)) ?? String(valor)
}

// MARK: - Etapas

enum Etapa: CaseIterable, Hashable {
    case baixar, folhas, scripts, montar, relatorio, janela

    /// Nome curto, embaixo do símbolo.
    var rotulo: String {
        switch self {
        case .baixar: return "Baixar"
        case .folhas: return "Estilos"
        case .scripts: return "Scripts"
        case .montar: return "Montar"
        case .relatorio: return "Relatório"
        case .janela: return "Janela"
        }
    }

    /// Frase mostrada enquanto a etapa roda.
    var titulo: String {
        switch self {
        case .baixar: return "Baixando a página"
        case .folhas: return "Lendo as folhas de estilo"
        case .scripts: return "Lendo scripts e dados"
        case .montar: return "Montando a página e gerando o relatório"
        case .relatorio: return "Gerando o relatório do motor"
        case .janela: return "Testando a janela de desenho"
        }
    }

    /// Nome da linha em TEMPOS DO APP.
    var linhaTempo: String {
        switch self {
        case .baixar: return "Baixar a página"
        case .folhas: return "Folhas de estilo"
        case .scripts: return "Scripts e dados"
        case .montar: return "Montar a página"
        case .relatorio: return "Relatório do motor (ao mesmo tempo que a montagem)"
        case .janela: return "Teste de janela"
        }
    }

    /// Símbolo do SF Symbols.
    var simbolo: String {
        switch self {
        case .baixar: return "arrow.down.circle"
        case .folhas: return "paintbrush"
        case .scripts: return "chevron.left.forwardslash.chevron.right"
        case .montar: return "rectangle.3.group"
        case .relatorio: return "doc.text"
        case .janela: return "arrow.up.and.down.circle"
        }
    }
}

// MARK: - Scripts e dados

/// Seção SCRIPTS E DADOS: quantos scripts a página tem e quais dados vêm dentro dela.
enum DiagnosticoScripts {
    static func analisar(html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<script\\b([^>]*)>([\\s\\S]*?)</script\\s*>",
            options: [.caseInsensitive]
        ) else {
            return "SCRIPTS E DADOS\nNão foi possível ler os scripts."
        }

        let ns = html as NSString
        let achados = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var semSrc = 0
        var bytesSemSrc = 0
        var comSrc: [String] = []
        var blocosJSON = 0
        var bytesJSON = 0
        var nextData: Int? = nil

        for achado in achados {
            let atributos = ns.substring(with: achado.range(at: 1))
            let corpo = ns.substring(with: achado.range(at: 2))
            let tag = "<script" + atributos + ">"
            let bytes = corpo.utf8.count

            if (" " + atributos).range(of: "\\ssrc\\s*=", options: [.regularExpression, .caseInsensitive]) != nil {
                comSrc.append(FolhasExternas.atributo("src", em: tag) ?? "(endereço não legível)")
            } else {
                semSrc += 1
                bytesSemSrc += bytes
            }

            let tipo = (FolhasExternas.atributo("type", em: tag) ?? "").lowercased()
            if tipo == "application/json" || tipo == "application/ld+json" {
                blocosJSON += 1
                bytesJSON += bytes
            }

            if atributos.contains("__NEXT_DATA__") {
                nextData = bytes
            }
        }

        var linhas = [
            "SCRIPTS E DADOS",
            "Scripts na página: \(achados.count)",
            "Sem endereço (código dentro da página): \(semSrc), \(numero(bytesSemSrc)) bytes",
            "Com endereço (arquivo externo): \(comSrc.count)",
            "Blocos JSON (application/json e ld+json): \(blocosJSON), \(numero(bytesJSON)) bytes",
            "__NEXT_DATA__: " + (nextData.map { "sim, \(numero($0)) bytes" } ?? "não")
        ]

        if !comSrc.isEmpty {
            linhas.append("Endereços dos scripts com endereço (até 10):")
            linhas += comSrc.prefix(10).map { "  \($0)" }
            if comSrc.count > 10 {
                linhas.append("  … e mais \(comSrc.count - 10)")
            }
        }
        return linhas.joined(separator: "\n")
    }
}

// MARK: - Teste de janela

/// Seção TESTE DE JANELA: confere se a busca da janela de desenho nunca deixa de fora
/// um item visível. Não desenha nada de novo.
enum DiagnosticoJanela {
    // Mesmos valores usados em ContentView.
    private static let passo: CGFloat = 400
    private static let margem: CGFloat = 400
    private static let alcance: CGFloat = 1800
    /// Altura aproximada da área visível (tela menos as barras).
    private static let alturaVisivel: CGFloat = 600

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

// MARK: - Página e relatório do motor

enum DiagnosticoPagina {
    struct Saida {
        let itens: [DrawItem]
        let tempoMontagem: Double
        let relatorio: String
        let tempoRelatorio: Double
    }

    /// Baixa a página. Devolve o HTML e o endereço final, depois de redirecionamentos.
    static func baixar(_ url: URL) async throws -> (html: String, base: URL) {
        let descarga = DownloadPagina { _ in }
        let (dados, resposta) = try await descarga.baixar(url)
        let html = String(decoding: dados, as: UTF8.self)
        return (html, resposta.url ?? url)
    }

    /// Monta a página e gera o relatório do motor ao mesmo tempo.
    static func montarERelatorio(html: String, largura: Float) async -> Saida {
        async let montagem: ([DrawItem], Double) = Task.detached(priority: .userInitiated) {
            cronometrar { Engine.render(html: html, width: largura) }
        }.value

        async let relatorio: (String, Double) = Task.detached(priority: .userInitiated) {
            cronometrar { relatorioDoMotor(html: html, largura: largura) }
        }.value

        let (itens, tempoMontagem) = await montagem
        let (texto, tempoRelatorio) = await relatorio
        return Saida(
            itens: itens,
            tempoMontagem: tempoMontagem,
            relatorio: texto,
            tempoRelatorio: tempoRelatorio
        )
    }
}

/// Texto do relatório do motor (DIAGNÓSTICO NUSKY até ÁRVORE).
private func relatorioDoMotor(html: String, largura: Float) -> String {
    let texto: String? = html.withCString { ptr in
        guard let saida = nusky_diagnose(ptr, largura, medirTextoDiagnostico) else { return nil }
        defer { nusky_free_string(saida) }
        return String(cString: saida)
    }
    return texto ?? "O motor não conseguiu gerar o relatório."
}

// MARK: - Modelo da tela

@MainActor
final class DiagnosticoModel: ObservableObject {
    @Published private(set) var atual: Etapa?
    @Published private(set) var concluidas: Set<Etapa> = []
    @Published private(set) var texto = ""
    @Published private(set) var erro: String?

    private var tarefa: Task<Void, Never>?
    private var tempos: [Etapa: Double] = [:]

    /// Começa a análise. Não faz nada se ela já tiver começado.
    func iniciar(url: URL) {
        guard tarefa == nil else { return }
        tarefa = Task { await executar(url: url) }
    }

    private func executar(url: URL) async {
        let inicio = CFAbsoluteTimeGetCurrent()
        var marca = inicio

        func concluir(_ etapa: Etapa) {
            let agora = CFAbsoluteTimeGetCurrent()
            tempos[etapa] = agora - marca
            marca = agora
            concluidas.insert(etapa)
        }

        // 1. Baixar
        atual = .baixar
        let pagina: (html: String, base: URL)
        do {
            pagina = try await DiagnosticoPagina.baixar(url)
        } catch {
            erro = "Não foi possível baixar a página:\n\(error.localizedDescription)"
            atual = nil
            return
        }
        concluir(.baixar)

        // 2. Folhas de estilo externas
        atual = .folhas
        let comCss = await FolhasExternas.incluir(em: pagina.html, base: pagina.base)
        concluir(.folhas)

        // 3. Scripts e dados
        atual = .scripts
        let htmlCompleto = comCss
        let secaoScripts = await Task.detached(priority: .userInitiated) {
            DiagnosticoScripts.analisar(html: htmlCompleto)
        }.value
        concluir(.scripts)

        // 4. Montagem e relatório do motor, em paralelo
        atual = .montar
        let largura = Float(UIScreen.main.bounds.width)
        let saida = await DiagnosticoPagina.montarERelatorio(html: comCss, largura: largura)
        tempos[.montar] = saida.tempoMontagem
        tempos[.relatorio] = saida.tempoRelatorio
        concluidas.formUnion([.montar, .relatorio])
        marca = CFAbsoluteTimeGetCurrent()

        // 5. Teste de janela, sobre os itens já montados
        atual = .janela
        let itens = saida.itens
        let secaoJanela = await Task.detached(priority: .userInitiated) {
            DiagnosticoJanela.analisar(itens: itens)
        }.value
        concluir(.janela)

        atual = nil
        texto = montarTexto(
            url: pagina.base,
            motor: saida.relatorio,
            scripts: secaoScripts,
            janela: secaoJanela,
            total: CFAbsoluteTimeGetCurrent() - inicio
        )
    }

    private func montarTexto(url: URL, motor: String, scripts: String, janela: String, total: Double) -> String {
        var linhasTempo = ["TEMPOS DO APP"]
        for etapa in Etapa.allCases {
            if let tempo = tempos[etapa] {
                linhasTempo.append("\(etapa.linhaTempo): \(formatarSegundos(tempo))")
            }
        }
        linhasTempo.append("Total: \(formatarSegundos(total))")

        return [
            "URL: \(url.absoluteString)",
            motor,
            scripts,
            janela,
            linhasTempo.joined(separator: "\n")
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "\n\n")
    }
}

// MARK: - Telas

/// Um símbolo por etapa: pulsa na etapa atual e fica com um quadrado verde quando conclui.
private struct PassoEtapa: View {
    let etapa: Etapa
    let atual: Bool
    let concluida: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: etapa.simbolo)
                .font(.system(size: 22))
                .foregroundColor(atual || concluida ? Color.accentColor : Color.secondary)
                .scaleEffect(atual ? 1.18 : 1)
                .animation(
                    atual
                        ? Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : Animation.easeOut(duration: 0.2),
                    value: atual
                )

            RoundedRectangle(cornerRadius: 1.5)
                .fill(concluida ? Color.green : Color.secondary.opacity(0.25))
                .frame(width: 8, height: 8)
                .animation(.easeOut(duration: 0.25), value: concluida)

            Text(etapa.rotulo)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PainelEtapas: View {
    let atual: Etapa?
    let concluidas: Set<Etapa>

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Etapa.allCases, id: \.self) { etapa in
                PassoEtapa(
                    etapa: etapa,
                    atual: atual == etapa,
                    concluida: concluidas.contains(etapa)
                )
            }
        }
        .padding(.vertical, 8)
    }
}

/// Relatório em texto selecionável, com rolagem própria.
private struct RelatorioTexto: UIViewRepresentable {
    let texto: String

    final class Coordenador {
        var mostrado = ""
    }

    func makeCoordinator() -> Coordenador {
        Coordenador()
    }

    func makeUIView(context: Context) -> UITextView {
        let vista = UITextView()
        vista.isEditable = false
        vista.isSelectable = true
        vista.backgroundColor = .clear
        vista.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        vista.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        vista.alwaysBounceVertical = true
        return vista
    }

    func updateUIView(_ vista: UITextView, context: Context) {
        guard context.coordinator.mostrado != texto else { return }
        context.coordinator.mostrado = texto
        vista.text = texto
    }
}

struct DiagnosticoView: View {
    let url: URL?
    @StateObject private var modelo = DiagnosticoModel()
    @State private var copiado = false

    init(url: URL?) {
        self.url = url
    }

    var body: some View {
        VStack(spacing: 10) {
            PainelEtapas(atual: modelo.atual, concluidas: modelo.concluidas)
                .padding(.horizontal, 12)

            Text(legenda)
                .font(.footnote)
                .foregroundColor(.secondary)

            if let erro = modelo.erro {
                Text(erro)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            RelatorioTexto(texto: modelo.texto)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                UIPasteboard.general.string = modelo.texto
                copiado = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copiado = false
                }
            } label: {
                Text(copiado ? "Copiado" : "Copiar relatório")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(modelo.texto.isEmpty)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .navigationTitle("Diagnóstico")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let url = url {
                modelo.iniciar(url: url)
            }
        }
    }

    private var legenda: String {
        guard url != nil else { return "Abra uma página antes de analisar." }
        if let atual = modelo.atual { return "\(atual.titulo)…" }
        if modelo.erro != nil { return "Análise interrompida." }
        return modelo.texto.isEmpty ? "Analisando…" : "Relatório pronto"
    }
}