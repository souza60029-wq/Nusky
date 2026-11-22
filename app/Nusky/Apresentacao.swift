// app/Nusky/Apresentacao.swift
import Foundation

/// Escolhas de desenho que dependem da página aberta.
enum Apresentacao {
    /// Se os links devem ser sublinhados. O motor ainda não lê `text-decoration`, então ele não sabe quando o site
    /// tirou o sublinhado (quase todos tiram). Página com CSS decide sozinha: só páginas sem CSS nenhum sublinham.
    static var sublinharLinks = true

    /// A página traz CSS (um `<style>` ou um link para folha de estilo)?
    static func paginaTemCSS(_ html: String) -> Bool {
        html.range(of: "<style", options: .caseInsensitive) != nil
            || html.range(of: "stylesheet", options: .caseInsensitive) != nil
    }

    /// Quantos caracteres de texto a página mostra (sem tags, scripts e estilos, e sem espaços). É uma estimativa
    /// barata, só para comparar duas versões da mesma página.
    static func quantidadeDeTexto(_ html: String) -> Int {
        var total = 0
        var dentroDeTag = false
        var ignorando: String?
        var nome = ""
        var lendoNome = false
        for c in html {
            if dentroDeTag {
                if lendoNome {
                    if c.isLetter || c == "/" { nome.append(c) } else { lendoNome = false }
                }
                if c == ">" {
                    dentroDeTag = false
                    let n = nome.lowercased()
                    if n == "script" || n == "style" { ignorando = n }
                    else if let alvo = ignorando, n == "/" + alvo { ignorando = nil }
                }
                continue
            }
            if c == "<" {
                dentroDeTag = true
                lendoNome = true
                nome = ""
                continue
            }
            if ignorando != nil { continue }
            if !c.isWhitespace { total += 1 }
        }
        return total
    }

    /// A versão que o JavaScript montou ficou vazia perto da que o servidor mandou? Nesse caso o JavaScript falhou
    /// no meio e trocar a página só deixaria a tela em branco: vale mais manter a primeira pintura.
    static func versaoDoJSEstaVazia(servidor: String, javascript: String) -> Bool {
        let antes = quantidadeDeTexto(servidor)
        guard antes > 200 else { return false }
        return quantidadeDeTexto(javascript) < 20
    }
}
