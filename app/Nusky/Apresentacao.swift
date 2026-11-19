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
}
