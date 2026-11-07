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

// MARK: - Memória

/// Leituras de memória do próprio app. O iOS encerra o app quando o uso (phys_footprint)
/// chega perto do limite; "disponível" diz quanto ainda falta para esse limite.
enum Memoria {
    /// Memória que conta para o limite do iOS, em bytes.
    static func usada() -> UInt64 {
        var info = task_vm_info_data_t()
        var contagem = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let resultado = withUnsafeMutablePointer(to: &info) { ponteiro in
            ponteiro.withMemoryRebound(to: integer_t.self, capacity: Int(contagem)) { inteiros in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), inteiros, &contagem)
            }
        }
        return resultado == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Quanto ainda cabe antes de o iOS encerrar o app, em bytes. Zero se o iOS não informar.
    static func disponivel() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    /// Memória RAM total do aparelho, em bytes.
    static var fisica: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// "312,4 MB" ou "1,95 GB", com vírgula.
    static func texto(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024).replacingOccurrences(of: ".", with: ",")
        }
        return String(format: "%.1f MB", mb).replacingOccurrences(of: ".", with: ",")
    }
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

    /// Nome da linha em TEMPOS DO APP e MEMÓRIA DO APP.
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

// MARK: - Dados dentro dos scripts e trechos escondidos

/// Seção DADOS NOS SCRIPTS: procura, sem rodar JavaScript, sinais de dados e de
/// renderização em partes (Next.js e React) dentro do próprio HTML.
enum DiagnosticoDados {
    static func analisar(html: String) -> String {
        var linhas = ["DADOS NOS SCRIPTS"]

        let inline = scriptsInline(html)
        let bytes = inline.reduce(0) { $0 + $1.utf8.count }
        linhas.append("Scripts inline: \(inline.count), \(numero(bytes)) bytes")

        let juntos = inline.joined(separator: "\n")
        linhas.append("Chamadas __next_f.push (dados do Next): \(ocorrencias("__next_f.push", em: juntos))")
        linhas.append("Chamadas $RC (troca de trechos do React): \(ocorrencias("$RC(", em: juntos))")
        linhas.append("Ocorrências de \"model\" nos scripts inline: \(ocorrencias("model", em: juntos.lowercased()))")

        let escondidos = trechosEscondidos(html)
        linhas.append("Elementos com atributo hidden: \(escondidos.count)")
        let maior = escondidos.map { $0.count }.max() ?? 0
        linhas.append("Maior trecho escondido (texto aproximado): \(numero(maior)) caracteres")

        let comTexto = escondidos.filter { !$0.isEmpty }
        if !comTexto.isEmpty {
            linhas.append("Início dos trechos escondidos com texto (até 5):")
            linhas += comTexto.prefix(5).map { "  \"" + String($0.prefix(80)) + "\"" }
        }

        if !inline.isEmpty {
            linhas.append("Início dos scripts inline (até 4):")
            linhas += inline.prefix(4).map { "  " + resumir($0, 100) }
        }
        return linhas.joined(separator: "\n")
    }

    /// Conteúdo de cada <script> sem atributo src.
    private static func scriptsInline(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<script\\b([^>]*)>([\\s\\S]*?)</script\\s*>",
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { achado in
            let atributos = ns.substring(with: achado.range(at: 1))
            if (" " + atributos).range(of: "\\ssrc\\s*=", options: [.regularExpression, .caseInsensitive]) != nil {
                return nil
            }
            return ns.substring(with: achado.range(at: 2))
        }
    }

    /// Para cada tag com o atributo hidden (não o da classe CSS), o texto que vem logo depois,
    /// até o próximo <script>. Valor aproximado: pode incluir texto que não está escondido.
    private static func trechosEscondidos(_ html: String) -> [String] {
        guard let tags = try? NSRegularExpression(pattern: "<[a-zA-Z][^>]*>"),
              let aspas = try? NSRegularExpression(pattern: "\"[^\"]*\"|'[^']*'"),
              let atributoHidden = try? NSRegularExpression(pattern: "\\shidden(?=[\\s/>])", options: [.caseInsensitive])
        else { return [] }

        let ns = html as NSString
        var trechos: [String] = []
        for achado in tags.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: achado.range)
            // Tira os valores entre aspas, para que class="... hidden ..." não conte.
            let semAspas = aspas.stringByReplacingMatches(
                in: tag,
                options: [],
                range: NSRange(location: 0, length: (tag as NSString).length),
                withTemplate: "\"\""
            )
            let semAspasNS = semAspas as NSString
            guard atributoHidden.firstMatch(in: semAspas, options: [], range: NSRange(location: 0, length: semAspasNS.length)) != nil else {
                continue
            }

            let inicio = achado.range.location + achado.range.length
            let resto = NSRange(location: inicio, length: ns.length - inicio)
            let proximoScript = ns.range(of: "<script", options: .caseInsensitive, range: resto).location
            let fim = proximoScript == NSNotFound ? ns.length : proximoScript
            trechos.append(textoDe(ns.substring(with: NSRange(location: inicio, length: fim - inicio))))
        }
        return trechos
    }

    /// Texto puro de um trecho de HTML, com espaços simples.
    private static func textoDe(_ trecho: String) -> String {
        let semTags = trecho.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return semTags.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func resumir(_ texto: String, _ limite: Int) -> String {
        let limpo = texto.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return limpo.count > limite ? String(limpo.prefix(limite)) + "…" : limpo
    }

    private static func ocorrencias(_ termo: String, em texto: String) -> Int {
        texto.components(separatedBy: termo).count - 1
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

    // Memória
    private var amostragem: Task<Void, Never>?
    private var usadaInicio: UInt64 = 0
    private var picoUsada: UInt64 = 0
    private var menorDisponivel: UInt64 = UInt64.max
    private var contagemAmostras = 0
    private var usadaAposEtapa: [Etapa: UInt64] = [:]

    /// Começa a análise. Não faz nada se ela já tiver começado.
    func iniciar(url: URL) {
        guard tarefa == nil else { return }
        tarefa = Task { await executar(url: url) }
    }

    /// Lê a memória a cada 50 ms, para achar o pico e a menor folga durante a análise.
    private func iniciarAmostragem() {
        amostragem = Task { [weak self] in
            while !Task.isCancelled {
                self?.amostrar()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        