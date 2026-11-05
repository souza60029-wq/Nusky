// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Prepara o HTML antes do layout.
//!
//! Os sites marcam a tag <html> com "client-nojs" quando não há JavaScript
//! e trocam para "client-js" quando há. O Nusky não roda JavaScript, mas
//! finge que roda na marcação, para que o site mostre o mesmo visual do Safari.

/// Classe que o HTML traz quando não há JavaScript.
pub const CLASSE_SEM_JS: &str = "client-nojs";

/// Classe que o HTML passa a ter.
pub const CLASSE_COM_JS: &str = "client-js";

/// Troca "client-nojs" por "client-js" somente dentro da tag <html>.
/// Se a tag não existir ou não tiver a classe, devolve o HTML igual.
pub fn marcar_com_javascript(html: &str) -> String {
    // to_ascii_lowercase mantém o tamanho em bytes, então os índices
    // encontrados na cópia valem para o HTML original.
    let minusculo = html.to_ascii_lowercase();

    let inicio = match minusculo.find("<html") {
        Some(i) => i,
        None => return html.to_string(),
    };

    let fim = match minusculo[inicio..].find('>') {
        Some(i) => inicio + i + 1,
        None => return html.to_string(),
    };

    let tag = &html[inicio..fim];
    if !tag.contains(CLASSE_SEM_JS) {
        return html.to_string();
    }

    let nova_tag = tag.replacen(CLASSE_SEM_JS, CLASSE_COM_JS, 1);

    let mut saida = String::with_capacity(html.len());
    saida.push_str(&html[..inicio]);
    saida.push_str(&nova_tag);
    saida.push_str(&html[fim..]);
    saida
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn troca_client_nojs_por_client_js_na_tag_html() {
        let entrada = r#"<!DOCTYPE html><html class="client-nojs vector-x"><body></body></html>"#;
        let saida = marcar_com_javascript(entrada);
        assert_eq!(
            saida,
            r#"<!DOCTYPE html><html class="client-js vector-x"><body></body></html>"#
        );
    }

    #[test]
    fn sem_client_nojs_nao_muda() {
        let entrada = r#"<html class="client-js"><body></body></html>"#;
        assert_eq!(marcar_com_javascript(entrada), entrada);
    }

    #[test]
    fn nao_mexe_fora_da_tag_html() {
        let entrada = r#"<p>client-nojs</p><html class="client-nojs">"#;
        let saida = marcar_com_javascript(entrada);
        assert_eq!(saida, r#"<p>client-nojs</p><html class="client-js">"#);
    }

    #[test]
    fn sem_tag_html_devolve_igual() {
        let entrada = r#"<div class="client-nojs"></div>"#;
        assert_eq!(marcar_com_javascript(entrada), entrada);
    }

    #[test]
    fn tag_html_em_maiusculas_tambem_funciona() {
        let entrada = r#"<HTML CLASS="client-nojs">"#;
        let saida = marcar_com_javascript(entrada);
        assert_eq!(saida, r#"<HTML CLASS="client-js">"#);
    }
}