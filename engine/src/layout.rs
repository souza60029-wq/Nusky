// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Layout de bloco mínimo.
//! Empilha blocos verticalmente e quebra o texto em linhas por palavras.
//! Links (`<a href>`) viram comandos com o destino preenchido.
//! Aplica CSS básico (tamanho, negrito, margens, display: none e cor), lido das tags
//! <style> e dos atributos style, id e class.
//! Não mede texto sozinho: recebe um `TextMeasurer`, que a casca implementa.

use crate::css::{self, Estilo, Folha};
use crate::html::{Element, Node};

/// Responsável por medir texto. No iPhone, a casca implementa com CoreText.
/// Nos testes, usamos uma medida fixa.
pub trait TextMeasurer {
    /// Largura em pontos de `text` na fonte indicada.
    fn measure(&self, text: &str, font_size: f32, bold: bool) -> f32;
}

/// Comando de desenho produzido pelo motor. A casca apenas desenha.
#[derive(Debug, Clone, PartialEq)]
pub enum DrawCommand {
    Text {
        x: f32,
        y: f32,
        text: String,
        font_size: f32,
        bold: bool,
        /// Destino do link, como está no HTML (pode ser relativo).
        href: Option<String>,
        /// Cor definida pelo CSS da página, em r, g, b. None quando a página não definiu cor.
        color: Option<[u8; 3]>,
    },
}

const PAGE_MARGIN: f32 = 8.0;
const BASE_FONT: f32 = 16.0;
const LINE_HEIGHT: f32 = 1.3;

/// Elementos cujo conteúdo não aparece na página.
const SKIP_TAGS: &[&str] = &["head", "script", "style", "title"];

#[derive(Clone, Copy)]
struct Style {
    font_size: f32,
    bold: bool,
    margin_top: f32,
    margin_bottom: f32,
    color: Option<[u8; 3]>,
}

/// Elementos que começam um novo bloco. Os demais são inline.
fn is_block(tag: &str) -> bool {
    matches!(
        tag,
        "html"
            | "body"
            | "div"
            | "p"
            | "h1"
            | "h2"
            | "h3"
            | "h4"
            | "h5"
            | "h6"
            | "section"
            | "article"
            | "header"
            | "footer"
            | "main"
            | "nav"
            | "blockquote"
            | "ul"
            | "ol"
            | "li"
    )
}

/// Estilo padrão por tag. Valores em pontos. Sem cor: a cor vem do pai ou do CSS.
fn style_for(tag: &str) -> Style {
    match tag {
        "h1" => Style { font_size: 32.0, bold: true, margin_top: 21.0, margin_bottom: 21.0, color: None },
        "h2" => Style { font_size: 24.0, bold: true, margin_top: 19.0, margin_bottom: 19.0, color: None },
        "h3" => Style { font_size: 18.7, bold: true, margin_top: 18.0, margin_bottom: 18.0, color: None },
        "h4" | "h5" | "h6" => {
            Style { font_size: BASE_FONT, bold: true, margin_top: 16.0, margin_bottom: 16.0, color: None }
        }
        "p" => Style { font_size: BASE_FONT, bold: false, margin_top: 16.0, margin_bottom: 16.0, color: None },
        _ => Style { font_size: BASE_FONT, bold: false, margin_top: 0.0, margin_bottom: 0.0, color: None },
    }
}

/// Sobrepõe o CSS ao estilo base. Só o que o CSS definiu muda.
fn aplicar(base: Style, css: &Estilo) -> Style {
    Style {
        font_size: css.tamanho.unwrap_or(base.font_size),
        bold: css.negrito.unwrap_or(base.bold),
        margin_top: css.margem_topo.unwrap_or(base.margin_top),
        margin_bottom: css.margem_base.unwrap_or(base.margin_bottom),
        color: css.cor.or(base.color),
    }
}

/// Trecho de texto com o link e a cor ao qual pertence.
/// Usado para trechos do HTML, para palavras e para o que vai numa mesma linha.
#[derive(Clone)]
struct Span {
    text: String,
    href: Option<String>,
    color: Option<[u8; 3]>,
}

struct Ctx<'a> {
    measurer: &'a dyn TextMeasurer,
    folha: Folha,
    /// Falso quando a página não tem CSS: evita calcular estilos à toa.
    tem_css: bool,
    x0: f32,
    y: f32,
    width: f32,
    commands: Vec<DrawCommand>,
}

/// Gera os comandos de desenho para uma lista de nós de topo.
pub fn layout(nodes: &[Node], viewport_width: f32, measurer: &dyn TextMeasurer) -> Vec<DrawCommand> {
    let mut css_texto = String::new();
    coletar_css(nodes, &mut css_texto);

    let mut ctx = Ctx {
        measurer,
        folha: Folha::parse(&css_texto),
        tem_css: !css_texto.trim().is_empty(),
        x0: PAGE_MARGIN,
        y: PAGE_MARGIN,
        width: (viewport_width - 2.0 * PAGE_MARGIN).max(0.0),
        commands: Vec::new(),
    };
    let root = Style {
        font_size: BASE_FONT,
        bold: false,
        margin_top: 0.0,
        margin_bottom: 0.0,
        color: None,
    };
    let mut buf: Vec<Span> = Vec::new();
    layout_children(nodes, root, None, &mut buf, &mut ctx);
    flush_inline(&mut buf, root, &mut ctx);
    ctx.commands
}

/// Junta o texto de todas as tags <style> do documento, na ordem em que aparecem.
fn coletar_css(nodes: &[Node], saida: &mut String) {
    for node in nodes {
        if let Node::Element(el) = node {
            if el.tag == "style" {
                for filho in &el.children {
                    if let Node::Text(t) = filho {
                        saida.push_str(t);
                        saida.push('\n');
                    }
                }
            } else {
                coletar_css(&el.children, saida);
            }
        }
    }
}

/// Calcula o CSS que vale para um elemento.
/// Sem <style> na página, só o atributo style pode trazer CSS.
fn estilo_do_elemento(el: &Element, ctx: &Ctx<'_>) -> Estilo {
    if !ctx.tem_css && el.attr("style").is_none() {
        return Estilo::default();
    }
    let classes: Vec<&str> = el.attr("class").unwrap_or("").split_whitespace().collect();
    css::estilo_para(&ctx.folha, &el.tag, el.attr("id"), &classes, el.attr("style"))
}

/// Percorre os filhos. Texto e elementos inline vão para `buf`.
/// Ao encontrar um bloco, o texto acumulado vira linhas antes do bloco.
fn layout_children(
    nodes: &[Node],
    style: Style,
    link: Option<&str>,
    buf: &mut Vec<Span>,
    ctx: &mut Ctx<'_>,
) {
    for node in nodes {
        match node {
            Node::Text(t) => buf.push(Span {
                text: t.clone(),
                href: link.map(str::to_string),
                color: style.color,
            }),
            Node::Element(el) => {
                if SKIP_TAGS.contains(&el.tag.as_str()) {
                    continue;
                }
                let css = estilo_do_elemento(el, ctx);
                if css.oculto {
                    continue;
                }
                if el.tag == "br" {
                    // Quebra de linha forçada ainda não existe; por enquanto vira espaço.
                    buf.push(Span {
                        text: " ".to_string(),
                        href: link.map(str::to_string),
                        color: style.color,
                    });
                    continue;
                }

                // Âncoras sem destino real (vazias ou "#topo") não viram links.
                let own_link = if el.tag == "a" {
                    el.attr("href")
                        .map(str::trim)
                        .filter(|h| !h.is_empty() && !h.starts_with('#'))
                } else {
                    None
                };
                let child_link = own_link.or(link);

                if is_block(&el.tag) {
                    flush_inline(buf, style, ctx);
                    // Bloco herda a cor do pai; tamanho e margens vêm da própria tag.
                    let block = aplicar(Style { color: style.color, ..style_for(&el.tag) }, &css);
                    ctx.y += block.margin_top;
                    layout_children(&el.children, block, child_link, buf, ctx);
                    flush_inline(buf, block, ctx);
                    ctx.y += block.margin_bottom;
                } else {
                    let mut inline = aplicar(style, &css);
                    // Link não herda a cor do texto ao redor: sem cor própria, fica com a cor de link.
                    if el.tag == "a" {
                        inline.color = css.cor;
                    }
                    layout_children(&el.children, inline, child_link, buf, ctx);
                }
            }
        }
    }
}

/// Divide os trechos em palavras, mantendo o link e a cor de cada uma.
/// Uma palavra que atravessa dois trechos fica com o link e a cor do primeiro.
fn split_words(chunks: &[Span]) -> Vec<Span> {
    let mut words: Vec<Span> = Vec::new();
    let mut cur: Option<Span> = None;
    for chunk in chunks {
        for ch in chunk.text.chars() {
            if ch.is_whitespace() {
                words.extend(cur.take());
            } else {
                cur.get_or_insert_with(|| Span {
                    text: String::new(),
                    href: chunk.href.clone(),
                    color: chunk.color,
                })
                .text
                .push(ch);
            }
        }
    }
    words.extend(cur);
    words
}

/// Quebra o texto acumulado em linhas que cabem na largura disponível.
fn flush_inline(buf: &mut Vec<Span>, style: Style, ctx: &mut Ctx<'_>) {
    let words = split_words(buf);
    buf.clear();
    if words.is_empty() {
        return;
    }

    let line_h = style.font_size * LINE_HEIGHT;
    let space_w = ctx.measurer.measure(" ", style.font_size, style.bold);
    let mut line: Vec<Span> = Vec::new();
    let mut line_w = 0.0_f32;

    for word in words {
        let w = ctx.measurer.measure(&word.text, style.font_size, style.bold);
        if !line.is_empty() && line_w + space_w + w > ctx.width {
            emit_line(&line, style, line_h, ctx);
            line.clear();
            line_w = 0.0;
        }
        line_w = if line.is_empty() { w } else { line_w + space_w + w };
        line.push(word);
    }
    if !line.is_empty() {
        emit_line(&line, style, line_h, ctx);
    }
}

/// Desenha uma linha. Palavras vizinhas com o mesmo link e a mesma cor viram um só comando,
/// para a casca criar menos elementos de tela.
fn emit_line(line: &[Span], style: Style, line_h: f32, ctx: &mut Ctx<'_>) {
    let mut runs: Vec<Span> = Vec::new();
    for (i, word) in line.iter().enumerate() {
        if i > 0 {
            if let Some(last) = runs.last_mut() {
                last.text.push(' ');
            }
        }
        let continues = runs
            .last()
            .map_or(false, |r| r.href == word.href && r.color == word.color);
        if continues {
            if let Some(last) = runs.last_mut() {
                last.text.push_str(&word.text);
            }
        } else {
            runs.push(Span {
                text: word.text.clone(),
                href: word.href.clone(),
                color: word.color,
            });
        }
    }

    let mut x = ctx.x0;
    for run in runs {
        let w = ctx.measurer.measure(&run.text, style.font_size, style.bold);
        ctx.commands.push(DrawCommand::Text {
            x,
            y: ctx.y,
            text: run.text,
            font_size: style.font_size,
            bold: style.bold,
            href: run.href,
            color: run.color,
        });
        x += w;
    }
    ctx.y += line_h;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::html::parse;

    /// Cada caractere tem metade do tamanho da fonte. Fica previsível nos testes.
    struct FixedMeasurer;

    impl TextMeasurer for FixedMeasurer {
        fn measure(&self, text: &str, font_size: f32, _bold: bool) -> f32 {
            text.chars().count() as f32 * font_size * 0.5
        }
    }

    fn run(html: &str, width: f32) -> Vec<DrawCommand> {
        layout(&parse(html), width, &FixedMeasurer)
    }

    fn text_of(cmd: &DrawCommand) -> &str {
        match cmd {
            DrawCommand::Text { text, .. } => text,
        }
    }

    #[test]
    fn paragraph_position_includes_margins() {
        let cmds = run("<p>oi</p>", 400.0);
        assert_eq!(
            cmds,
            vec![DrawCommand::Text {
                x: 8.0,
                y: 24.0,
                text: "oi".to_string(),
                font_size: 16.0,
                bold: false,
                href: None,
                color: None,
            }]
        );
    }

    #[test]
    fn heading_is_bold_and_larger() {
        let cmds = run("<h1>Título</h1>", 400.0);
        match &cmds[0] {
            DrawCommand::Text { font_size, bold, .. } => {
                assert_eq!(*font_size, 32.0);
                assert!(*bold);
            }
        }
    }

    #[test]
    fn long_text_wraps_by_words() {
        // Largura útil = 36 - 16 = 20. Cada palavra de 2 letras mede 16 px.
        let cmds = run("<p>aa bb cc</p>", 36.0);
        let words: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(words, vec!["aa", "bb", "cc"]);
    }

    #[test]
    fn lines_go_down_in_order() {
        let cmds = run("<p>aa bb cc</p>", 36.0);
        let ys: Vec<f32> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { y, .. } => *y,
            })
            .collect();
        assert!(ys[0] < ys[1] && ys[1] < ys[2]);
    }

    #[test]
    fn paragraphs_stack_vertically() {
        let cmds = run("<p>um</p><p>dois</p>", 400.0);
        assert_eq!(cmds.len(), 2);
        let (y1, y2) = match (&cmds[0], &cmds[1]) {
            (DrawCommand::Text { y: a, .. }, DrawCommand::Text { y: b, .. }) => (*a, *b),
        };
        assert!(y2 > y1);
    }

    #[test]
    fn script_and_style_are_not_drawn() {
        let cmds = run("<p>a</p><script>var x = 1;</script><style>p{}</style>", 400.0);
        assert_eq!(cmds.len(), 1);
        assert_eq!(text_of(&cmds[0]), "a");
    }

    #[test]
    fn empty_input_produces_nothing() {
        assert!(run("", 400.0).is_empty());
    }

    #[test]
    fn links_keep_their_target() {
        let cmds = run(r#"<p>veja <a href="/wiki">aqui</a> agora</p>"#, 400.0);
        let links: Vec<(&str, &str)> = cmds
            .iter()
            .filter_map(|c| match c {
                DrawCommand::Text { text, href: Some(h), .. } => Some((text.as_str(), h.as_str())),
                _ => None,
            })
            .collect();
        assert_eq!(links.len(), 1);
        assert_eq!(links[0].1, "/wiki");
        assert_eq!(links[0].0.trim(), "aqui");
    }

    #[test]
    fn fragment_links_are_not_links() {
        let cmds = run(r##"<p><a href="#topo">topo</a></p>"##, 400.0);
        assert!(cmds
            .iter()
            .all(|c| matches!(c, DrawCommand::Text { href: None, .. })));
    }

    #[test]
    fn css_changes_font_size_and_margin() {
        let cmds = run("<style>p { font-size: 20px; margin-top: 4px }</style><p>oi</p>", 400.0);
        match &cmds[0] {
            DrawCommand::Text { y, font_size, .. } => {
                assert_eq!(*font_size, 20.0);
                assert_eq!(*y, 12.0);
            }
        }
    }

    #[test]
    fn display_none_hides_element() {
        let cmds = run(
            r#"<style>.oculto { display: none }</style><p class="oculto">a</p><p>b</p>"#,
            400.0,
        );
        assert_eq!(cmds.len(), 1);
        assert_eq!(text_of(&cmds[0]), "b");
    }

    #[test]
    fn inline_style_wins_over_sheet() {
        let cmds = run(
            r#"<style>p { font-size: 20px }</style><p style="font-size: 10px">a</p>"#,
            400.0,
        );
        match &cmds[0] {
            DrawCommand::Text { font_size, .. } => assert_eq!(*font_size, 10.0),
        }
    }

    #[test]
    fn inline_style_works_without_style_sheet() {
        let cmds = run(r#"<p style="font-size: 20px">a</p>"#, 400.0);
        match &cmds[0] {
            DrawCommand::Text { font_size, .. } => assert_eq!(*font_size, 20.0),
        }
    }

    #[test]
    fn color_from_css_reaches_the_text() {
        let cmds = run(r#"<p style="color: red">a</p>"#, 400.0);
        match &cmds[0] {
            DrawCommand::Text { color, .. } => assert_eq!(*color, Some([255, 0, 0])),
        }
    }

    #[test]
    fn color_is_inherited_by_text_inside_blocks() {
        let cmds = run(r#"<div style="color: #00ff00"><p>a</p></div>"#, 400.0);
        match &cmds[0] {
            DrawCommand::Text { color, .. } => assert_eq!(*color, Some([0, 255, 0])),
        }
    }

    #[test]
    fn links_do_not_inherit_color() {
        let cmds = run(r#"<p style="color: red">x <a href="/y">y</a></p>"#, 400.0);
        let link = cmds
            .iter()
            .find(|c| matches!(c, DrawCommand::Text { href: Some(_), .. }))
            .expect("deve haver um link");
        match link {
            DrawCommand::Text { color, .. } => assert_eq!(*color, None),
        }
    }
}