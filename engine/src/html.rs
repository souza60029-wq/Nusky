// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Parser de HTML mínimo do Nusky (v0.1).
//! Entende elementos, texto, comentários e atributos.
//! Entidades (`&amp;`, `&eacute;`, `&#233;`, `&#xE9;`) são decodificadas no texto e nos atributos.

#[derive(Debug, Clone, PartialEq)]
pub enum Node {
    Element(Element),
    Text(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Element {
    pub tag: String,
    /// Atributos com nome em minúsculas, na ordem em que aparecem.
    pub attrs: Vec<(String, String)>,
    pub children: Vec<Node>,
}

impl Element {
    /// Valor de um atributo. `name` deve estar em minúsculas.
    pub fn attr(&self, name: &str) -> Option<&str> {
        self.attrs
            .iter()
            .find(|(k, _)| k.as_str() == name)
            .map(|(_, v)| v.as_str())
    }
}

/// Elementos que nunca têm conteúdo nem tag de fechamento.
const VOID_TAGS: &[&str] = &[
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "source", "track", "wbr",
];

/// Converte uma string HTML numa lista de nós de topo.
pub fn parse(input: &str) -> Vec<Node> {
    // A raiz é um elemento sintético sem nome que guarda os nós de topo.
    let mut stack = vec![Element {
        tag: String::new(),
        attrs: Vec::new(),
        children: Vec::new(),
    }];
    let mut rest = input;

    while !rest.is_empty() {
        if rest.starts_with("<!--") {
            rest = match rest.find("-->") {
                Some(i) => &rest[i + 3..],
                None => "",
            };
        } else if rest.starts_with("<!") || rest.starts_with("<?") {
            rest = match rest.find('>') {
                Some(i) => &rest[i + 1..],
                None => "",
            };
        } else if rest.starts_with("</") {
            let (inner, after) = split_tag(rest, 2);
            close_tag(&mut stack, &tag_name(inner));
            rest = after;
        } else if rest.starts_with('<') && rest[1..].starts_with(|c: char| c.is_ascii_alphabetic()) {
            let (inner, after) = split_tag(rest, 1);
            let self_closing = inner.trim_end().ends_with('/');
            let name = tag_name(inner);
            let attrs = parse_attrs(inner);
            rest = after;
            if self_closing || VOID_TAGS.contains(&name.as_str()) {
                push_child(
                    &mut stack,
                    Node::Element(Element { tag: name, attrs, children: Vec::new() }),
                );
            } else {
                stack.push(Element { tag: name, attrs, children: Vec::new() });
            }
        } else {
            // Texto até o próximo '<'. O primeiro caractere é pulado, porque
            // pode ser um '<' solto (como em "a < b") que não inicia tag.
            let first = rest.chars().next().map_or(1, |c| c.len_utf8());
            let end = rest[first..].find('<').map_or(rest.len(), |i| i + first);
            push_text(&mut stack, &decode_entities(&rest[..end]));
            rest = &rest[end..];
        }
    }

    while stack.len() > 1 {
        pop_into_parent(&mut stack);
    }
    stack.pop().map(|root| root.children).unwrap_or_default()
}

/// Separa o conteúdo de uma tag (sem o '<' ou '</') do restante da entrada.
fn split_tag(rest: &str, skip: usize) -> (&str, &str) {
    match rest[skip..].find('>') {
        Some(i) => (&rest[skip..skip + i], &rest[skip + i + 1..]),
        None => (&rest[skip..], ""),
    }
}

/// Extrai o nome da tag em minúsculas, ignorando atributos e a barra final.
fn tag_name(inner: &str) -> String {
    inner
        .trim()
        .trim_end_matches('/')
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_ascii_lowercase()
}

/// Lê os atributos de uma tag (sem o nome).
/// Valores podem estar entre aspas simples, entre aspas duplas ou sem aspas.
fn parse_attrs(inner: &str) -> Vec<(String, String)> {
    let mut attrs = Vec::new();
    let s = inner.trim().trim_end_matches('/').trim_end();
    // Pula o nome da tag, que é o primeiro trecho sem espaço.
    let mut rest = s.trim_start_matches(|c: char| !c.is_whitespace());

    loop {
        rest = rest.trim_start();
        if rest.is_empty() {
            break;
        }
        let name_end = rest
            .find(|c: char| c.is_whitespace() || c == '=')
            .unwrap_or(rest.len());
        let name = rest[..name_end].to_ascii_lowercase();
        rest = &rest[name_end..];

        let (value, remaining) = match rest.trim_start().strip_prefix('=') {
            Some(after_eq) => read_value(after_eq.trim_start()),
            None => (String::new(), rest),
        };
        rest = remaining;

        if !name.is_empty() {
            attrs.push((name, decode_entities(&value)));
        }
    }
    attrs
}

/// Lê um valor de atributo e devolve o valor e o restante da entrada.
fn read_value(s: &str) -> (String, &str) {
    match s.chars().next() {
        Some(q @ ('"' | '\'')) => {
            let body = &s[1..];
            match body.find(q) {
                Some(end) => (body[..end].to_string(), &body[end + 1..]),
                None => (body.to_string(), ""),
            }
        }
        _ => {
            let end = s.find(char::is_whitespace).unwrap_or(s.len());
            (s[..end].to_string(), &s[end..])
        }
    }
}

/// Substitui as entidades de um trecho. Entidades desconhecidas ficam como estão.
fn decode_entities(s: &str) -> String {
    if !s.contains('&') {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let after = &rest[amp + 1..];
        match decode_one(after) {
            Some((ch, consumed)) => {
                out.push(ch);
                rest = &after[consumed..];
            }
            None => {
                out.push('&');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Decodifica a entidade que começa logo depois do '&'.
/// Devolve o caractere e quantos bytes foram consumidos, incluindo o ';'.
fn decode_one(s: &str) -> Option<(char, usize)> {
    // Procura o ';' só nos primeiros bytes, para não varrer o texto inteiro.
    let semi = s.bytes().take(32).position(|b| b == b';')?;
    if semi == 0 {
        return None;
    }
    let body = &s[..semi];
    let ch = if let Some(num) = body.strip_prefix('#') {
        let code = match num.strip_prefix(|c: char| c == 'x' || c == 'X') {
            Some(hex) => u32::from_str_radix(hex, 16).ok()?,
            None => num.parse::<u32>().ok()?,
        };
        char::from_u32(code)?
    } else {
        named_entity(body)?
    };
    Some((ch, semi + 1))
}

/// Entidades nomeadas mais comuns em páginas reais.
fn named_entity(name: &str) -> Option<char> {
    Some(match name {
        "amp" => '&',
        "lt" => '<',
        "gt" => '>',
        "quot" => '"',
        "apos" => '\'',
        "nbsp" => '\u{a0}',
        "copy" => '©',
        "reg" => '®',
        "trade" => '™',
        "hellip" => '…',
        "mdash" => '—',
        "ndash" => '–',
        "lsquo" => '‘',
        "rsquo" => '’',
        "ldquo" => '“',
        "rdquo" => '”',
        "laquo" => '«',
        "raquo" => '»',
        "middot" => '·',
        "bull" => '•',
        "deg" => '°',
        "times" => '×',
        "divide" => '÷',
        "plusmn" => '±',
        "euro" => '€',
        "pound" => '£',
        "yen" => '¥',
        "cent" => '¢',
        "sect" => '§',
        "para" => '¶',
        "iexcl" => '¡',
        "iquest" => '¿',
        "aacute" => 'á',
        "eacute" => 'é',
        "iacute" => 'í',
        "oacute" => 'ó',
        "uacute" => 'ú',
        "Aacute" => 'Á',
        "Eacute" => 'É',
        "Iacute" => 'Í',
        "Oacute" => 'Ó',
        "Uacute" => 'Ú',
        "agrave" => 'à',
        "egrave" => 'è',
        "igrave" => 'ì',
        "ograve" => 'ò',
        "ugrave" => 'ù',
        "atilde" => 'ã',
        "otilde" => 'õ',
        "Atilde" => 'Ã',
        "Otilde" => 'Õ',
        "acirc" => 'â',
        "ecirc" => 'ê',
        "icirc" => 'î',
        "ocirc" => 'ô',
        "ucirc" => 'û',
        "ccedil" => 'ç',
        "Ccedil" => 'Ç',
        "ntilde" => 'ñ',
        "Ntilde" => 'Ñ',
        "uuml" => 'ü',
        "Uuml" => 'Ü',
        "ouml" => 'ö',
        "auml" => 'ä',
        "szlig" => 'ß',
        _ => return None,
    })
}

/// Fecha o elemento aberto mais próximo com esse nome, fechando os que estão dentro dele.
/// Se não houver nenhum, a tag de fechamento é ignorada.
fn close_tag(stack: &mut Vec<Element>, name: &str) {
    if let Some(idx) = stack.iter().rposition(|e| e.tag == name) {
        if idx > 0 {
            while stack.len() > idx {
                pop_into_parent(stack);
            }
        }
    }
}

fn pop_into_parent(stack: &mut Vec<Element>) {
    if let Some(el) = stack.pop() {
        push_child(stack, Node::Element(el));
    }
}

fn push_child(stack: &mut Vec<Element>, node: Node) {
    stack
        .last_mut()
        .expect("a raiz sempre existe")
        .children
        .push(node);
}

/// Adiciona texto ao elemento atual, juntando com um texto anterior se houver.
fn push_text(stack: &mut Vec<Element>, text: &str) {
    if text.is_empty() {
        return;
    }
    let parent = stack.last_mut().expect("a raiz sempre existe");
    match parent.children.last_mut() {
        Some(Node::Text(prev)) => prev.push_str(text),
        _ => parent.children.push(Node::Text(text.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn el(tag: &str, children: Vec<Node>) -> Node {
        Node::Element(Element {
            tag: tag.to_string(),
            attrs: Vec::new(),
            children,
        })
    }

    fn text(s: &str) -> Node {
        Node::Text(s.to_string())
    }

    #[test]
    fn parses_headings_and_paragraphs() {
        let nodes = parse("<h1>Olá</h1><p>Texto</p>");
        assert_eq!(nodes, vec![el("h1", vec![text("Olá")]), el("p", vec![text("Texto")])]);
    }

    #[test]
    fn nested_elements() {
        let nodes = parse("<div><p>a <b>b</b> c</p></div>");
        assert_eq!(
            nodes,
            vec![el("div", vec![el("p", vec![text("a "), el("b", vec![text("b")]), text(" c")])])]
        );
    }

    #[test]
    fn tag_names_are_lowercased() {
        assert_eq!(parse("<P>x</P>"), vec![el("p", vec![text("x")])]);
    }

    #[test]
    fn void_and_self_closing_tags_have_no_children() {
        let nodes = parse("<p>a<br>b<hr/>c</p>");
        assert_eq!(
            nodes,
            vec![el("p", vec![text("a"), el("br", vec![]), text("b"), el("hr", vec![]), text("c")])]
        );
    }

    #[test]
    fn comments_and_doctype_are_ignored() {
        let nodes = parse("<!DOCTYPE html><!-- nota --><p>oi</p>");
        assert_eq!(nodes, vec![el("p", vec![text("oi")])]);
    }

    #[test]
    fn unclosed_tags_are_closed_at_end() {
        assert_eq!(parse("<p>oi"), vec![el("p", vec![text("oi")])]);
    }

    #[test]
    fn stray_closing_tag_is_ignored() {
        assert_eq!(parse("<p>oi</div></p>"), vec![el("p", vec![text("oi")])]);
    }

    #[test]
    fn attributes_are_parsed() {
        let nodes = parse(r#"<a href="/x" class='c' data-n=3 hidden>link</a>"#);
        match &nodes[0] {
            Node::Element(e) => {
                assert_eq!(e.tag, "a");
                assert_eq!(e.attr("href"), Some("/x"));
                assert_eq!(e.attr("class"), Some("c"));
                assert_eq!(e.attr("data-n"), Some("3"));
                assert_eq!(e.attr("hidden"), Some(""));
                assert_eq!(e.children, vec![text("link")]);
            }
            _ => panic!("esperava um elemento"),
        }
    }

    #[test]
    fn amp_in_attribute_is_decoded() {
        let nodes = parse(r#"<a href="/busca?a=1&amp;b=2">x</a>"#);
        match &nodes[0] {
            Node::Element(e) => assert_eq!(e.attr("href"), Some("/busca?a=1&b=2")),
            _ => panic!("esperava um elemento"),
        }
    }

    #[test]
    fn entities_in_text_are_decoded() {
        assert_eq!(parse("a &amp; b &lt;c&gt;"), vec![text("a & b <c>")]);
    }

    #[test]
    fn named_and_numeric_entities_are_decoded() {
        assert_eq!(parse("caf&eacute; &#233; &#xE9;"), vec![text("café é é")]);
    }

    #[test]
    fn unknown_or_bare_ampersand_is_kept() {
        assert_eq!(parse("a & b &foo; c"), vec![text("a & b &foo; c")]);
    }

    #[test]
    fn lone_less_than_is_text() {
        assert_eq!(parse("a < b"), vec![text("a < b")]);
    }

    #[test]
    fn multibyte_text_does_not_panic() {
        assert_eq!(parse("ação <b>é</b>"), vec![text("ação "), el("b", vec![text("é")])]);
    }
}