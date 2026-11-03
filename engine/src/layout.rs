// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Layout de bloco mínimo (v0.1).
//! Empilha blocos verticalmente e quebra o texto em linhas por palavras.
//! Não mede texto sozinho: recebe um `TextMeasurer`, que a casca implementa.

use crate::html::Node;

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

/// Estilo padrão por tag. Valores em pontos, sem CSS ainda.
fn style_for(tag: &str) -> Style {
    match tag {
        "h1" => Style { font_size: 32.0, bold: true, margin_top: 21.0, margin_bottom: 21.0 },
        "h2" => Style { font_size: 24.0, bold: true, margin_top: 19.0, margin_bottom: 19.0 },
        "h3" => Style { font_size: 18.7, bold: true, margin_top: 18.0, margin_bottom: 18.0 },
        "h4" | "h5" | "h6" => Style { font_size: BASE_FONT, bold: true, margin_top: 16.0, margin_bottom: 16.0 },
        "p" => Style { font_size: BASE_FONT, bold: false, margin_top: 16.0, margin_bottom: 16.0 },
        _ => Style { font_size: BASE_FONT, bold: false, margin_top: 0.0, margin_bottom: 0.0 },
    }
}

struct Ctx<'a> {
    measurer: &'a dyn TextMeasurer,
    x0: f32,
    y: f32,
    width: f32,
    commands: Vec<DrawCommand>,
}

impl Ctx<'_> {
    fn emit(&mut self, text: &str, style: Style, line_h: f32) {
        self.commands.push(DrawCommand::Text {
            x: self.x0,
            y: self.y,
            text: text.to_string(),
            font_size: style.font_size,
            bold: style.bold,
        });
        self.y += line_h;
    }
}

/// Gera os comandos de desenho para uma lista de nós de topo.
pub fn layout(nodes: &[Node], viewport_width: f32, measurer: &dyn TextMeasurer) -> Vec<DrawCommand> {
    let mut ctx = Ctx {
        measurer,
        x0: PAGE_MARGIN,
        y: PAGE_MARGIN,
        width: (viewport_width - 2.0 * PAGE_MARGIN).max(0.0),
        commands: Vec::new(),
    };
    let root = Style { font_size: BASE_FONT, bold: false, margin_top: 0.0, margin_bottom: 0.0 };
    let mut buf = String::new();
    layout_children(nodes, root, &mut buf, &mut ctx);
    flush_inline(&mut buf, root, &mut ctx);
    ctx.commands
}

/// Percorre os filhos. Texto e elementos inline são juntados em `buf`.
/// Ao encontrar um bloco, o texto acumulado vira linhas antes do bloco.
fn layout_children(nodes: &[Node], style: Style, buf: &mut String, ctx: &mut Ctx<'_>) {
    for node in nodes {
        match node {
            Node::Text(t) => buf.push_str(t),
            Node::Element(el) => {
                if SKIP_TAGS.contains(&el.tag.as_str()) {
                    continue;
                }
                if el.tag == "br" {
                    // Quebra de linha forçada ainda não existe; por enquanto vira espaço.
                    buf.push(' ');
                    continue;
                }
                if is_block(&el.tag) {
                    flush_inline(buf, style, ctx);
                    let block = style_for(&el.tag);
                    ctx.y += block.margin_top;
                    layout_children(&el.children, block, buf, ctx);
                    flush_inline(buf, block, ctx);
                    ctx.y += block.margin_bottom;
                } else {
                    layout_children(&el.children, style, buf, ctx);
                }
            }
        }
    }
}

/// Quebra o texto acumulado em linhas que cabem na largura disponível.
fn flush_inline(buf: &mut String, style: Style, ctx: &mut Ctx<'_>) {
    let words: Vec<String> = buf.split_whitespace().map(str::to_string).collect();
    buf.clear();
    if words.is_empty() {
        return;
    }

    let line_h = style.font_size * LINE_HEIGHT;
    let space_w = ctx.measurer.measure(" ", style.font_size, style.bold);
    let mut line = String::new();
    let mut line_w = 0.0_f32;

    for word in &words {
        let w = ctx.measurer.measure(word, style.font_size, style.bold);
        if !line.is_empty() && line_w + space_w + w > ctx.width {
            ctx.emit(&line, style, line_h);
            line.clear();
            line_w = 0.0;
        }
        if line.is_empty() {
            line.push_str(word);
            line_w = w;
        } else {
            line.push(' ');
            line.push_str(word);
            line_w += space_w + w;
        }
    }
    if !line.is_empty() {
        ctx.emit(&line, style, line_h);
    }
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
}