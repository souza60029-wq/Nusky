// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Parser de HTML mínimo do Nusky (v0.1).
//! Entende elementos, texto e comentários. Atributos são ignorados por enquanto.

#[derive(Debug, Clone, PartialEq)]
pub enum Node {
    Element(Element),
    Text(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Element {
    pub tag: String,
    pub children: Vec<Node>,
}

/// Elementos que nunca têm conteúdo nem tag de fechamento.
const VOID_TAGS: &[&str] = &[
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "source", "track", "wbr",
];

/// Converte uma string HTML numa lista de nós de topo.
pub fn parse(input: &str) -> Vec<Node> {
    // A raiz é um elemento sintético sem nome que guarda os nós de topo.
    let mut stack = vec![Element { tag: String::new(), children: Vec::new() }];
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
            rest = after;
            if self_closing || VOID_TAGS.contains(&name.as_str()) {
                push_child(&mut stack, Node::Element(Element { tag: name, children: Vec::new() }));
            } else {
                stack.push(Element { tag: name, children: Vec::new() });
            }
        } else {
            // Texto até o próximo '<'. O primeiro caractere é pulado, porque
            // pode ser um '<' solto (como em "a < b") que não inicia tag.
            let first = rest.chars().next().map_or(1, |c| c.len_utf8());
            let end = rest[first..].find('<').map_or(rest.len(), |i| i + first);
            push_text(&mut stack, &rest[..end]);
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
        Node::Element(Element { tag: tag.to_string(), children })
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
    fn attributes_are_skipped_for_now() {
        assert_eq!(parse(r#"<a href="x">link</a>"#), vec![el("a", vec![text("link")])]);
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