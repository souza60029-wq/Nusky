import Foundation

// Histórico em duas camadas:
// - Quente: a página ativa. Só ela tem layout e views na RAM (BrowserModel).
// - Frio: URL e posição de rolagem, em disco. Abrir uma página fria baixa de novo.
//
// Regras:
// - Cada aba tem sua própria pilha de voltar e avançar.
// - A rolagem de um site é mantida enquanto a navegação fica no mesmo site.
//   Ao sair do site, a rolagem dele é apagada, e voltar a ele abre no topo.
// - Fechar uma aba apaga a pilha dela.
// - Os dados ficam em Application Support/Nusky/sessao.json, pasta que o iOS não apaga.

struct Entrada: Codable, Equatable, Identifiable {
    var id = UUID()
    var url: String
    var rolagem: Double = 0

    var host: String { URL(string: url)?.host ?? "" }
}

struct Aba: Codable, Equatable, Identifiable {
    var id = UUID()
    var entradas: [Entrada] = []
    var indice = -1

    var entradaAtual: Entrada? {
        entradas.indices.contains(indice) ? entradas[indice] : nil
    }

    var podeVoltar: Bool { indice > 0 }
    var podeAvancar: Bool { indice >= 0 && indice < entradas.count - 1 }

    var titulo: String {
        guard let host = entradaAtual?.host, !host.isEmpty else { return "Nova aba" }
        return host
    }
}

private struct Sessao: Codable {
    var abas: [Aba]
    var indiceAtivo: Int
}

final class Historico: ObservableObject {
    private let limiteEntradas = 50

    @Published private(set) var abas: [Aba] = []
    @Published private(set) var indiceAtivo = 0

    /// Verdadeiro quando não havia sessão salva (primeira abertura do app).
    private(set) var sessaoNova = false

    var abaAtual: Aba { abas[indiceAtivo] }
    var entradaAtual: Entrada? { abaAtual.entradaAtual }

    init() {
        carregar()
    }

    // MARK: Abas

    func novaAba() {
        abas.append(Aba())
        indiceAtivo = abas.count - 1
        salvar()
    }

    func trocarAba(_ id: UUID) {
        guard let i = abas.firstIndex(where: { $0.id == id }) else { return }
        indiceAtivo = i
        salvar()
    }

    func fecharAbas(_ ids: Set<UUID>) {
        let ativaAntes = abaAtual.id
        abas.removeAll { ids.contains($0.id) }
        if abas.isEmpty {
            abas = [Aba()]
        }
        if let i = abas.firstIndex(where: { $0.id == ativaAntes }) {
            indiceAtivo = i
        } else {
            // A aba ativa foi apagada: a próxima (ou a anterior, se era a última) assume.
            indiceAtivo = min(indiceAtivo, abas.count - 1)
        }
        salvar()
    }

    // MARK: Navegação

    /// Nova página na aba atual. Descarta o "avançar" e registra a entrada.
    func navegar(para url: URL) {
        let hostAnterior = entradaAtual?.host
        let limite = limiteEntradas
        editarAbaAtual { aba in
            let proxima = aba.indice + 1
            if proxima < aba.entradas.count {
                aba.entradas.removeSubrange(proxima...)
            }
            aba.entradas.append(Entrada(url: url.absoluteString))
            aba.indice = aba.entradas.count - 1

            let excesso = aba.entradas.count - limite
            if excesso > 0 {
                aba.entradas.removeFirst(excesso)
                aba.indice -= excesso
            }
        }
        apagarRolagemAoSair(de: hostAnterior, para: url.host ?? "")
        salvar()
    }

    func voltar() -> Entrada? {
        guard abaAtual.podeVoltar else { return nil }
        let anterior = entradaAtual?.host
        editarAbaAtual { $0.indice -= 1 }
        apagarRolagemAoSair(de: anterior, para: entradaAtual?.host ?? "")
        salvar()
        return entradaAtual
    }

    func avancar() -> Entrada? {
        guard abaAtual.podeAvancar else { return nil }
        let anterior = entradaAtual?.host
        editarAbaAtual { $0.indice += 1 }
        apagarRolagemAoSair(de: anterior, para: entradaAtual?.host ?? "")
        salvar()
        return entradaAtual
    }

    /// Guarda a rolagem da entrada que está na tela. Procura em todas as abas,
    /// porque a página exibida pode ser de uma aba que já não é a ativa.
    func atualizarRolagem(_ y: Double, entradaId id: UUID) {
        for t in abas.indices {
            if let i = abas[t].entradas.firstIndex(where: { $0.id == id }) {
                abas[t].entradas[i].rolagem = y
                return
            }
        }
    }

    // MARK: Internos

    private func editarAbaAtual(_ bloco: (inout Aba) -> Void) {
        bloco(&abas[indiceAtivo])
    }

    /// Ao trocar de site, apaga a rolagem das entradas do site que foi deixado.
    private func apagarRolagemAoSair(de hostAnterior: String?, para hostNovo: String) {
        guard let antigo = hostAnterior, !antigo.isEmpty, antigo != hostNovo else { return }
        editarAbaAtual { aba in
            for i in aba.entradas.indices where aba.entradas[i].host == antigo {
                aba.entradas[i].rolagem = 0
            }
        }
    }

    func salvar() {
        let sessao = Sessao(abas: abas, indiceAtivo: indiceAtivo)
        guard let dados = try? JSONEncoder().encode(sessao) else { return }
        try? dados.write(to: Caminhos.sessao, options: .atomic)
    }

    private func carregar() {
        if let dados = try? Data(contentsOf: Caminhos.sessao),
           let sessao = try? JSONDecoder().decode(Sessao.self, from: dados),
           !sessao.abas.isEmpty {
            abas = sessao.abas
            indiceAtivo = min(max(sessao.indiceAtivo, 0), abas.count - 1)
        } else {
            abas = [Aba()]
            indiceAtivo = 0
            sessaoNova = true
        }
    }
}

enum Caminhos {
    static let sessao: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let pasta = base.appendingPathComponent("Nusky", isDirectory: true)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta.appendingPathComponent("sessao.json")
    }()
}