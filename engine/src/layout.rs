// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Layout de bloco mínimo.
//! Empilha blocos verticalmente e quebra o texto em linhas por palavras.
//! Tabelas (`<table>`) viram linhas e colunas: células lado a lado, com `colspan`,
//! e legenda (`<caption>`) acima das linhas.
//! Links (`<a href>`) viram comandos com o destino preenchido.
//! Aplica CSS básico (tamanho, negrito, margens, display: none e cor), lido das tags
//! <style> e dos atributos style, id e class. Seletores compostos (descendente, filho,
//! irmãos `+` e `~`, atributos, `:first-child` e `:last-child`) usam a cadeia de pais
//! e os irmãos de cada elemento.
//! Não mede texto sozinho: recebe um `TextMeasurer`, que a casca implementa.

use crate::css::{self, Display, Estilo, Folha, Info};
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

/// Caixa de fundo de um bloco: cor sólida e/ou borda, com cantos arredondados.
/// Fica numa lista à parte dos textos, na ordem em que deve ser pintada
/// (o bloco de fora vem antes do de dentro).
#[derive(Debug, Clone, PartialEq)]
pub struct Fundo {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub cor: Option<[u8; 3]>,
    /// Largura e cor da borda.
    pub borda: Option<(f32, [u8; 3])>,
    pub raio: f32,
}

/// Tudo o que o layout produz: textos, caixas de fundo e a cor de fundo da página.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Saida {
    pub comandos: Vec<DrawCommand>,
    pub fundos: Vec<Fundo>,
    /// Cor de fundo do `html` ou do `body`, se a página definiu.
    pub fundo_pagina: Option<[u8; 3]>,
}

/// Limite de caixas de fundo, para uma página enorme não ocupar memória demais.
const MAX_FUNDOS: usize = 4000;
/// Marca de quebra de linha (`<br>`) dentro do texto acumulado.
const QUEBRA: &str = "\u{1}";

const PAGE_MARGIN: f32 = 8.0;
const BASE_FONT: f32 = 16.0;
const LINE_HEIGHT: f32 = 1.3;
/// Espaço entre colunas de uma tabela.
const CELL_GAP: f32 = 8.0;
/// Folga vertical entre linhas de uma tabela.
const LINHA_FOLGA: f32 = 4.0;
/// Limite de colunas, para uma tabela malformada não ocupar memória demais.
const MAX_COLUNAS: usize = 50;

/// Elementos cujo conteúdo não aparece na página.
const SKIP_TAGS: &[&str] = &["head", "script", "style", "title"];

#[derive(Clone, Copy)]
struct Style {
    font_size: f32,
    bold: bool,
    margin_top: f32,
    margin_bottom: f32,
    color: Option<[u8; 3]>,
    /// `text-align`: 0 esquerda, 1 centro, 2 direita. Herdado.
    align: u8,
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

/// Grupos de linhas de uma tabela. Não criam caixa própria.
fn is_row_group(tag: &str) -> bool {
    matches!(tag, "thead" | "tbody" | "tfoot")
}

/// Estilo padrão por tag. Valores em pontos. Sem cor: a cor vem do pai ou do CSS.
fn style_for(tag: &str) -> Style {
    match tag {
        "h1" => Style { font_size: 32.0, bold: true, margin_top: 21.0, margin_bottom: 21.0, color: None, align: 0 },
        "h2" => Style { font_size: 24.0, bold: true, margin_top: 19.0, margin_bottom: 19.0, color: None, align: 0 },
        "h3" => Style { font_size: 18.7, bold: true, margin_top: 18.0, margin_bottom: 18.0, color: None, align: 0 },
        "h4" | "h5" | "h6" => {
            Style { font_size: BASE_FONT, bold: true, margin_top: 16.0, margin_bottom: 16.0, color: None, align: 0 }
        }
        "p" => Style { font_size: BASE_FONT, bold: false, margin_top: 16.0, margin_bottom: 16.0, color: None, align: 0 },
        _ => Style { font_size: BASE_FONT, bold: false, margin_top: 0.0, margin_bottom: 0.0, color: None, align: 0 },
    }
}

/// Converte a cor do CSS (tupla) para a cor do comando de desenho (vetor).
fn cor_do_css(cor: Option<(u8, u8, u8)>) -> Option<[u8; 3]> {
    cor.map(|(r, g, b)| [r, g, b])
}

/// Sobrepõe o CSS ao estilo base. Só o que o CSS definiu muda.
fn aplicar(base: Style, css: &Estilo) -> Style {
    Style {
        font_size: css.tamanho.unwrap_or(base.font_size),
        bold: css.negrito.unwrap_or(base.bold),
        margin_top: css.margem_topo.unwrap_or(base.margin_top),
        margin_bottom: css.margem_base.unwrap_or(base.margin_bottom),
        color: cor_do_css(css.cor).or(base.color),
        align: css.alinhamento.unwrap_or(base.align),
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
    /// Elementos abertos, do raiz até o pai imediato. Usada por seletores compostos.
    pais: Vec<Info>,
    x0: f32,
    y: f32,
    width: f32,
    commands: Vec<DrawCommand>,
    fundos: Vec<Fundo>,
    fundo_pagina: Option<[u8; 3]>,
    /// O próximo elemento tratado vira bloco (filho de flex).
    forcar_bloco: bool,
    /// Espaço (gap) entre os filhos do próximo `layout_children`.
    gap: f32,
    /// Os filhos do próximo `layout_children` viram blocos (filhos de flex em coluna).
    filhos_bloco: bool,
}

/// Célula de tabela já resolvida: CSS calculado, colunas que ocupa e medidas do texto.
struct Celula<'a> {
    el: &'a Element,
    estilo: Style,
    span: usize,
    /// Maior palavra, em pontos: a coluna não pode ficar menor que isso.
    minimo: f32,
    /// Texto inteiro numa linha, em pontos: largura ideal.
    ideal: f32,
    /// Sem texto visível: não ocupa largura nem altura.
    vazia: bool,
}

/// Linha de tabela já resolvida.
struct Linha<'a> {
    el: &'a Element,
    /// Grupo (thead, tbody ou tfoot) que contém a linha, se houver.
    grupo: Option<&'a Element>,
    celulas: Vec<Celula<'a>>,
}

/// Gera os comandos de desenho para uma lista de nós de topo.
/// Os comandos saem ordenados de cima para baixo e da esquerda para a direita.
pub fn layout(nodes: &[Node], viewport_width: f32, measurer: &dyn TextMeasurer) -> Vec<DrawCommand> {
    layout_completo(nodes, viewport_width, measurer).comandos
}

/// Procura o elemento `html` na árvore.
fn achar_html(nodes: &[Node]) -> Option<&Element> {
    for node in nodes {
        if let Node::Element(el) = node {
            if el.tag == "html" {
                return Some(el);
            }
            if let Some(achado) = achar_html(&el.children) {
                return Some(achado);
            }
        }
    }
    None
}

/// Igual a `layout`, mas devolve também as caixas de fundo e a cor de fundo da página.
pub fn layout_completo(nodes: &[Node], viewport_width: f32, measurer: &dyn TextMeasurer) -> Saida {
    let mut css_texto = String::new();
    coletar_css(nodes, &mut css_texto);

    // A raiz com as classes e atributos reais: é ela que decide quais
    // propriedades personalizadas (`--cor`) valem (tema claro ou escuro).
    let folha = match achar_html(nodes) {
        Some(html) => {
            let raiz = Info {
                tag: "html".to_string(),
                id: html.attr("id").unwrap_or("").to_string(),
                classes: html
                    .attr("class")
                    .unwrap_or("")
                    .split_whitespace()
                    .map(str::to_string)
                    .collect(),
                atributos: html.attrs.clone(),
            };
            Folha::parse_com_raiz(&css_texto, viewport_width, &raiz)
        }
        None => Folha::parse_largura(&css_texto, viewport_width),
    };

    let mut ctx = Ctx {
        measurer,
        folha,
        tem_css: !css_texto.trim().is_empty(),
        pais: Vec::new(),
        x0: PAGE_MARGIN,
        y: PAGE_MARGIN,
        width: (viewport_width - 2.0 * PAGE_MARGIN).max(0.0),
        commands: Vec::new(),
        fundos: Vec::new(),
        fundo_pagina: None,
        forcar_bloco: false,
        gap: 0.0,
        filhos_bloco: false,
    };
    let root = Style {
        font_size: BASE_FONT,
        bold: false,
        margin_top: 0.0,
        margin_bottom: 0.0,
        color: None,
        align: 0,
    };
    let mut buf: Vec<Span> = Vec::new();
    layout_children(nodes, root, None, &mut buf, &mut ctx);
    flush_inline(&mut buf, root, &mut ctx);
    ordenar_por_posicao(&mut ctx.commands);
    Saida { comandos: ctx.commands, fundos: ctx.fundos, fundo_pagina: ctx.fundo_pagina }
}

/// Ordena os comandos de cima para baixo e, na mesma altura, da esquerda para a direita.
/// Tabelas desenham célula por célula, então sem isso a ordem sai misturada.
/// A janela de desenho da casca depende dessa ordem para achar o que está visível.
fn ordenar_por_posicao(commands: &mut [DrawCommand]) {
    commands.sort_by(|a, b| {
        let (ax, ay) = posicao(a);
        let (bx, by) = posicao(b);
        ay.partial_cmp(&by)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(ax.partial_cmp(&bx).unwrap_or(std::cmp::Ordering::Equal))
    });
}

/// Posição (x, y) de um comando de desenho.
fn posicao(cmd: &DrawCommand) -> (f32, f32) {
    match cmd {
        DrawCommand::Text { x, y, .. } => (*x, *y),
    }
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

/// Monta a identificação do elemento (tag, id, classes e atributos citados no CSS).
/// Só lê os atributos listados em `nomes`, para não copiar o que nenhuma regra usa.
fn info_do_elemento(el: &Element, nomes: &[String]) -> Info {
    let atributos = nomes
        .iter()
        .filter_map(|nome| el.attr(nome).map(|v| (nome.clone(), v.to_string())))
        .collect();
    Info {
        tag: el.tag.clone(),
        id: el.attr("id").unwrap_or("").to_string(),
        classes: el
            .attr("class")
            .unwrap_or("")
            .split_whitespace()
            .map(str::to_string)
            .collect(),
        atributos,
    }
}

/// Calcula o CSS que vale para um elemento, considerando pais, irmãos anteriores
/// e se é o último elemento da lista. Sem <style> na página, só o atributo style
/// pode trazer CSS.
fn estilo_do_elemento(
    el: &Element,
    info: &Info,
    irmaos: &[Info],
    ultimo: bool,
    ctx: &Ctx<'_>,
) -> Estilo {
    if !ctx.tem_css && el.attr("style").is_none() {
        return Estilo::default();
    }
    css::estilo_completo_ultimo(&ctx.folha, info, &ctx.pais, irmaos, ultimo, el.attr("style"))
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
    // Irmãos anteriores só são guardados quando alguma regra os usa.
    let guarda_irmaos = ctx.folha.precisa_irmaos();
    // Último elemento da lista. Texto não conta, como no CSS.
    let ultimo_idx = nodes.iter().rposition(|n| matches!(n, Node::Element(_)));
    let mut irmaos: Vec<Info> = Vec::new();
    // Espaço entre blocos irmãos (gap de um flex em coluna).
    let gap = std::mem::take(&mut ctx.gap);
    let filhos_bloco = std::mem::take(&mut ctx.filhos_bloco);
    for (i, node) in nodes.iter().enumerate() {
        match node {
            Node::Text(t) => buf.push(Span {
                text: t.clone(),
                href: link.map(str::to_string),
                color: style.color,
            }),
            Node::Element(el) => {
                let info = info_do_elemento(el, ctx.folha.nomes_atributos());
                let ultimo = Some(i) == ultimo_idx;
                let y_antes = ctx.y;
                ctx.forcar_bloco = filhos_bloco;
                let info = tratar_elemento(el, info, &irmaos, ultimo, style, link, buf, ctx);
                if gap > 0.0 && !ultimo && ctx.y > y_antes {
                    ctx.y += gap;
                }
                if guarda_irmaos {
                    irmaos.push(info);
                }
            }
        }
    }
}

/// Trata um elemento e devolve a sua identificação, para entrar na lista de irmãos.
/// Elementos ignorados ou ocultos também entram na lista, porque contam como irmãos.
fn tratar_elemento(
    el: &Element,
    info: Info,
    irmaos: &[Info],
    ultimo: bool,
    style: Style,
    link: Option<&str>,
    buf: &mut Vec<Span>,
    ctx: &mut Ctx<'_>,
) -> Info {
    // Filho de flex vira bloco; o pedido vale só para este elemento.
    let forcar = std::mem::take(&mut ctx.forcar_bloco);
    if SKIP_TAGS.contains(&el.tag.as_str()) {
        return info;
    }
    let css = estilo_do_elemento(el, &info, irmaos, ultimo, ctx);
    if css.oculto {
        return info;
    }
    if el.tag == "br" {
        // Quebra de linha forçada: `flush_inline` entende esta marca.
        buf.push(Span {
            text: QUEBRA.to_string(),
            href: link.map(str::to_string),
            color: style.color,
        });
        return info;
    }

    if el.tag == "table" {
        flush_inline(buf, style, ctx);
        let block = aplicar(Style { color: style.color, ..style_for(&el.tag) }, &css);
        ctx.y += block.margin_top;
        ctx.pais.push(info);
        layout_table(el, block, link, ctx);
        let info = ctx.pais.pop().unwrap_or_default();
        ctx.y += block.margin_bottom;
        return info;
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

    // O CSS manda: `display: block/flex/grid` quebra linha, `inline` não.
    let eh_bloco = forcar
        || match css.display {
            Some(Display::Linha) => false,
            Some(_) => true,
            None => is_block(&el.tag),
        };

    if eh_bloco {
        flush_inline(buf, style, ctx);
        // Bloco herda a cor e o alinhamento do pai; tamanho e margens vêm da própria tag.
        let block = aplicar(
            Style { color: style.color, align: style.align, ..style_for(&el.tag) },
            &css,
        );
        ctx.y += block.margin_top;

        // Caixa do bloco: preenchimento (padding) e borda diminuem a área do conteúdo.
        let x_antes = ctx.x0;
        let largura_antes = ctx.width;
        let pad_esq = css.pad_esq.unwrap_or(0.0).max(0.0);
        let pad_dir = css.pad_dir.unwrap_or(0.0).max(0.0);
        let pad_topo = css.pad_topo.unwrap_or(0.0).max(0.0);
        let pad_base = css.pad_base.unwrap_or(0.0).max(0.0);
        let borda_l = css.borda_largura.unwrap_or(0.0).max(0.0);
        let topo_caixa = ctx.y;

        let eh_raiz = el.tag == "html" || el.tag == "body";
        if eh_raiz {
            if let Some((r, g, b)) = css.fundo {
                ctx.fundo_pagina = Some([r, g, b]);
            }
        }
        let indice_fundo = if eh_raiz { None } else { reservar_fundo(ctx, topo_caixa, &css) };

        ctx.x0 = x_antes + pad_esq + borda_l;
        ctx.width = (largura_antes - pad_esq - pad_dir - 2.0 * borda_l).max(0.0);
        ctx.y += pad_topo + borda_l;

        ctx.pais.push(info);
        let flex_linha = css.display == Some(Display::Flex) && css.coluna != Some(true);
        if flex_linha {
            layout_flex_linha(el, block, child_link, &css, ctx);
        } else {
            if css.display == Some(Display::Flex) {
                ctx.gap = css.espaco.unwrap_or(0.0).max(0.0);
                ctx.filhos_bloco = true;
            }
            layout_children(&el.children, block, child_link, buf, ctx);
        }
        let info = ctx.pais.pop().unwrap_or_default();
        flush_inline(buf, block, ctx);

        ctx.y += pad_base + borda_l;
        ctx.x0 = x_antes;
        ctx.width = largura_antes;
        fechar_fundo(ctx, indice_fundo, topo_caixa);
        ctx.y += block.margin_bottom;
        info
    } else {
        let mut inline = aplicar(style, &css);
        // Link não herda a cor do texto ao redor: sem cor própria, fica com a cor de link.
        if el.tag == "a" {
            inline.color = cor_do_css(css.cor);
        }
        ctx.pais.push(info);
        layout_children(&el.children, inline, child_link, buf, ctx);
        ctx.pais.pop().unwrap_or_default()
    }
}

/// Reserva um lugar na lista de fundos para o bloco que começa em `topo`.
/// A altura só se sabe no fim; `fechar_fundo` completa. Devolve None quando o bloco
/// não tem fundo nem borda visíveis.
fn reservar_fundo(ctx: &mut Ctx<'_>, topo: f32, css: &Estilo) -> Option<usize> {
    let cor = css.fundo.map(|(r, g, b)| [r, g, b]);
    let largura_borda = css.borda_largura.unwrap_or(0.0);
    let borda = match css.borda_cor.flatten() {
        Some((r, g, b)) if largura_borda > 0.0 => Some((largura_borda, [r, g, b])),
        _ => None,
    };
    if cor.is_none() && borda.is_none() {
        return None;
    }
    if ctx.fundos.len() >= MAX_FUNDOS {
        return None;
    }
    ctx.fundos.push(Fundo {
        x: ctx.x0,
        y: topo,
        w: ctx.width,
        h: 0.0,
        cor,
        borda,
        raio: css.raio.unwrap_or(0.0).max(0.0),
    });
    Some(ctx.fundos.len() - 1)
}

/// Completa a altura do fundo reservado. Sem altura, o fundo é descartado.
fn fechar_fundo(ctx: &mut Ctx<'_>, indice: Option<usize>, topo: f32) {
    let Some(i) = indice else { return };
    let altura = ctx.y - topo;
    if altura > 0.0 && ctx.fundos[i].w > 0.0 {
        ctx.fundos[i].h = altura;
    } else {
        ctx.fundos.remove(i);
    }
}

/// Filho de um flex em linha, já medido.
struct ItemFlex<'a> {
    el: &'a Element,
    /// Posição do elemento na lista de irmãos (para os seletores de irmãos).
    pos: usize,
    ultimo: bool,
    minimo: f32,
    ideal: f32,
}

/// Flex em linha: os filhos ficam lado a lado, cada um com a largura do seu texto.
/// Com espaço de sobra, `justify-content` reparte a sobra. Sem espaço, os filhos
/// ficam entre a maior palavra e o texto inteiro, e o texto quebra dentro de cada um.
/// Texto solto dentro do flex (fora de um elemento) faz o bloco voltar ao layout normal.
fn layout_flex_linha(
    el: &Element,
    style: Style,
    link: Option<&str>,
    css: &Estilo,
    ctx: &mut Ctx<'_>,
) {
    let solto = el
        .children
        .iter()
        .any(|n| matches!(n, Node::Text(t) if !t.trim().is_empty()));
    if solto {
        let mut buf: Vec<Span> = Vec::new();
        layout_children(&el.children, style, link, &mut buf, ctx);
        flush_inline(&mut buf, style, ctx);
        return;
    }

    let guarda_irmaos = ctx.folha.precisa_irmaos();
    let ultimo_idx = el.children.iter().rposition(|n| matches!(n, Node::Element(_)));
    let mut infos: Vec<Info> = Vec::new();
    let mut itens: Vec<ItemFlex<'_>> = Vec::new();
    for (i, node) in el.children.iter().enumerate() {
        let filho = match node {
            Node::Element(f) => f,
            Node::Text(_) => continue,
        };
        let info = info_do_elemento(filho, ctx.folha.nomes_atributos());
        let ultimo = Some(i) == ultimo_idx;
        let pos = infos.len();
        let irmaos_f: &[Info] = if guarda_irmaos { &infos[..] } else { &[] };
        let css_f = estilo_do_elemento(filho, &info, irmaos_f, ultimo, ctx);
        if !SKIP_TAGS.contains(&filho.tag.as_str()) && !css_f.oculto {
            let estilo_f = aplicar(
                Style { color: style.color, align: style.align, ..style_for(&filho.tag) },
                &css_f,
            );
            let (minimo, ideal, vazia) = medir_celula(filho, estilo_f, ctx);
            if !vazia {
                let extra = css_f.pad_esq.unwrap_or(0.0).max(0.0)
                    + css_f.pad_dir.unwrap_or(0.0).max(0.0)
                    + 2.0 * css_f.borda_largura.unwrap_or(0.0).max(0.0);
                itens.push(ItemFlex { el: filho, pos, ultimo, minimo: minimo + extra, ideal: ideal + extra + 1.0 });
            }
        }
        if guarda_irmaos {
            infos.push(info);
        } else {
            infos.push(Info::default());
        }
    }
    if itens.is_empty() {
        return;
    }

    let n = itens.len();
    let espaco = css.espaco.unwrap_or(0.0).max(0.0);
    let x_base = ctx.x0;
    let w_base = ctx.width;
    let disponivel = (w_base - espaco * (n as f32 - 1.0)).max(0.0);
    let soma_ideal: f32 = itens.iter().map(|i| i.ideal).sum();
    let soma_min: f32 = itens.iter().map(|i| i.minimo).sum();
    let larguras: Vec<f32> = if soma_ideal <= disponivel {
        itens.iter().map(|i| i.ideal).collect()
    } else if soma_min <= disponivel && soma_ideal > soma_min {
        let folga = disponivel - soma_min;
        let faixa = soma_ideal - soma_min;
        itens.iter().map(|i| i.minimo + folga * (i.ideal - i.minimo) / faixa).collect()
    } else if soma_min > 0.0 {
        let k = disponivel / soma_min;
        itens.iter().map(|i| i.minimo * k).collect()
    } else {
        vec![disponivel / n as f32; n]
    };

    let usado: f32 = larguras.iter().sum();
    let sobra = (disponivel - usado).max(0.0);
    let (deslocamento, espaco_extra) = match css.justificar {
        Some(1) => (sobra / 2.0, 0.0),
        Some(2) => (sobra, 0.0),
        Some(3) if n > 1 => (0.0, sobra / (n as f32 - 1.0)),
        _ => (0.0, 0.0),
    };

    let topo = ctx.y;
    let mut fundo = topo;
    let mut x = x_base + deslocamento;
    for (item, largura) in itens.iter().zip(larguras.iter()) {
        ctx.x0 = x;
        ctx.width = *largura;
        ctx.y = topo;
        ctx.forcar_bloco = true;
        let info = info_do_elemento(item.el, ctx.folha.nomes_atributos());
        let irmaos: &[Info] = if guarda_irmaos { &infos[..item.pos] } else { &[] };
        let mut buf: Vec<Span> = Vec::new();
        tratar_elemento(item.el, info, irmaos, item.ultimo, style, link, &mut buf, ctx);
        flush_inline(&mut buf, style, ctx);
        fundo = fundo.max(ctx.y);
        x += largura + espaco + espaco_extra;
    }
    ctx.x0 = x_base;
    ctx.width = w_base;
    ctx.y = fundo;
}

/// Desenha uma tabela. A legenda (caption) vai primeiro, na largura toda.
/// Depois, cada linha ocupa a altura da célula mais alta.
/// Colunas são dimensionadas pelo texto de cada uma, dentro da largura disponível.
fn layout_table(el: &Element, style: Style, link: Option<&str>, ctx: &mut Ctx<'_>) {
    let mut linhas: Vec<Linha<'_>> = Vec::new();
    let mut legendas: Vec<(&Element, Style)> = Vec::new();
    coletar_linhas(&el.children, None, style, &mut linhas, &mut legendas, ctx);

    let x_base = ctx.x0;
    let w_base = ctx.width;

    for &(legenda, estilo) in legendas.iter() {
        let info = info_do_elemento(legenda, ctx.folha.nomes_atributos());
        ctx.pais.push(info);
        let mut buf: Vec<Span> = Vec::new();
        layout_children(&legenda.children, estilo, link, &mut buf, ctx);
        flush_inline(&mut buf, estilo, ctx);
        ctx.pais.pop();
    }
    if !legendas.is_empty() {
        ctx.y += LINHA_FOLGA;
    }

    if linhas.is_empty() {
        return;
    }
    let larguras = larguras_das_colunas(&linhas, ctx.width);
    if larguras.is_empty() {
        return;
    }

    for linha in &linhas {
        let topo = ctx.y;
        let mut fundo = topo;
        if let Some(grupo) = linha.grupo {
            let info = info_do_elemento(grupo, ctx.folha.nomes_atributos());
            ctx.pais.push(info);
        }
        let info = info_do_elemento(linha.el, ctx.folha.nomes_atributos());
        ctx.pais.push(info);

        let mut col = 0usize;
        for celula in &linha.celulas {
            let fim = col + celula.span;
            let x_rel: f32 = larguras[..col].iter().sum();
            let largura: f32 = larguras[col..fim].iter().sum::<f32>() - CELL_GAP;
            ctx.x0 = x_base + x_rel;
            ctx.width = largura.max(0.0);
            ctx.y = topo;

            let info = info_do_elemento(celula.el, ctx.folha.nomes_atributos());
            ctx.pais.push(info);
            let mut buf_celula: Vec<Span> = Vec::new();
            layout_children(&celula.el.children, celula.estilo, link, &mut buf_celula, ctx);
            flush_inline(&mut buf_celula, celula.estilo, ctx);
            let _ = ctx.pais.pop();

            fundo = fundo.max(ctx.y);
            col = fim;
        }

        let _ = ctx.pais.pop();
        if linha.grupo.is_some() {
            let _ = ctx.pais.pop();
        }
        ctx.x0 = x_base;
        ctx.width = w_base;
        ctx.y = fundo + LINHA_FOLGA;
    }
}

/// Junta as linhas de uma tabela, descendo por thead, tbody e tfoot.
/// Legendas (caption) vão para `legendas`, com o estilo já calculado.
/// Linhas e células ocultas pelo CSS ficam de fora. Linhas sem texto também.
fn coletar_linhas<'a>(
    nodes: &'a [Node],
    grupo: Option<&'a Element>,
    style: Style,
    linhas: &mut Vec<Linha<'a>>,
    legendas: &mut Vec<(&'a Element, Style)>,
    ctx: &mut Ctx<'_>,
) {
    let guarda_irmaos = ctx.folha.precisa_irmaos();
    let ultimo_idx = nodes.iter().rposition(|n| matches!(n, Node::Element(_)));
    let mut irmaos: Vec<Info> = Vec::new();
    for (i, node) in nodes.iter().enumerate() {
        let el: &'a Element = match node {
            Node::Element(el) => el,
            Node::Text(_) => continue,
        };
        let info = info_do_elemento(el, ctx.folha.nomes_atributos());
        let ultimo = Some(i) == ultimo_idx;
        let css = estilo_do_elemento(el, &info, &irmaos, ultimo, ctx);
        let tag = el.tag.as_str();
        let visivel = !SKIP_TAGS.contains(&tag) && !css.oculto;

        let info = if !visivel {
            info
        } else if is_row_group(tag) {
            ctx.pais.push(info);
            coletar_linhas(&el.children, Some(el), style, linhas, legendas, ctx);
            ctx.pais.pop().unwrap_or_default()
        } else if tag == "caption" {
            legendas.push((el, aplicar(style, &css)));
            info
        } else if tag == "tr" {
            ctx.pais.push(info);
            let celulas = coletar_celulas(el, aplicar(style, &css), ctx);
            if !celulas.iter().all(|c| c.vazia) {
                linhas.push(Linha { el, grupo, celulas });
            }
            ctx.pais.pop().unwrap_or_default()
        } else {
            info
        };

        if guarda_irmaos {
            irmaos.push(info);
        }
    }
}

/// Junta as células de uma linha, com CSS e medidas de cada uma.
fn coletar_celulas<'a>(
    linha: &'a Element,
    estilo_linha: Style,
    ctx: &mut Ctx<'_>,
) -> Vec<Celula<'a>> {
    let guarda_irmaos = ctx.folha.precisa_irmaos();
    let ultimo_idx = linha.children.iter().rposition(|n| matches!(n, Node::Element(_)));
    let mut irmaos: Vec<Info> = Vec::new();
    let mut celulas: Vec<Celula<'a>> = Vec::new();
    for (i, node) in linha.children.iter().enumerate() {
        let el: &'a Element = match node {
            Node::Element(el) => el,
            Node::Text(_) => continue,
        };
        let info = info_do_elemento(el, ctx.folha.nomes_atributos());
        let ultimo = Some(i) == ultimo_idx;
        let css = estilo_do_elemento(el, &info, &irmaos, ultimo, ctx);
        let tag = el.tag.as_str();
        let visivel = !SKIP_TAGS.contains(&tag) && !css.oculto;

        if visivel && (tag == "td" || tag == "th") {
            // Cabeçalho (th) sai em negrito, como no navegador.
            let base = if tag == "th" { Style { bold: true, ..estilo_linha } } else { estilo_linha };
            let estilo = aplicar(base, &css);
            let span = span_da_celula(el);
            let (minimo, ideal, vazia) = medir_celula(el, estilo, ctx);
            celulas.push(Celula { el, estilo, span, minimo, ideal, vazia });
        }

        if guarda_irmaos {
            irmaos.push(info);
        }
    }
    celulas
}

/// Quantas colunas a célula ocupa. Valor inválido vira 1.
fn span_da_celula(el: &Element) -> usize {
    el.attr("colspan")
        .and_then(|v| v.trim().parse::<usize>().ok())
        .unwrap_or(1)
        .clamp(1, MAX_COLUNAS)
}

/// Mede o texto visível da célula: (maior palavra, texto numa linha, sem texto).
/// Texto escondido pelo CSS não entra na conta, para não inflar a coluna.
fn medir_celula(el: &Element, estilo: Style, ctx: &mut Ctx<'_>) -> (f32, f32, bool) {
    let info = info_do_elemento(el, ctx.folha.nomes_atributos());
    ctx.pais.push(info);
    let mut texto = String::new();
    texto_visivel(&el.children, ctx, &mut texto);
    ctx.pais.pop();

    let palavras: Vec<&str> = texto.split_whitespace().collect();
    if palavras.is_empty() {
        return (0.0, 0.0, true);
    }
    let ideal = ctx.measurer.measure(&palavras.join(" "), estilo.font_size, estilo.bold);
    let minimo = palavras
        .iter()
        .map(|p| ctx.measurer.measure(p, estilo.font_size, estilo.bold))
        .fold(0.0_f32, f32::max);
    (minimo, ideal, false)
}

/// Junta o texto que aparece de uma subárvore, respeitando o CSS e sem script e style.
/// Usado só para medir: o desenho passa pelo layout normal.
fn texto_visivel(nodes: &[Node], ctx: &mut Ctx<'_>, saida: &mut String) {
    let guarda_irmaos = ctx.folha.precisa_irmaos();
    let ultimo_idx = nodes.iter().rposition(|n| matches!(n, Node::Element(_)));
    let mut irmaos: Vec<Info> = Vec::new();
    for (i, node) in nodes.iter().enumerate() {
        match node {
            Node::Text(t) => {
                saida.push_str(t);
                saida.push(' ');
            }
            Node::Element(el) => {
                let info = info_do_elemento(el, ctx.folha.nomes_atributos());
                let ultimo = Some(i) == ultimo_idx;
                let css = estilo_do_elemento(el, &info, &irmaos, ultimo, ctx);
                let visivel = !SKIP_TAGS.contains(&el.tag.as_str()) && !css.oculto;
                if visivel {
                    if el.tag == "br" {
                        saida.push(' ');
                    }
                    ctx.pais.push(info.clone());
                    texto_visivel(&el.children, ctx, saida);
                    ctx.pais.pop();
                }
                if guarda_irmaos {
                    irmaos.push(info);
                }
            }
        }
    }
}

/// Largura de cada coluna. A soma fica igual à largura disponível.
/// Com espaço de sobra, a sobra é repartida pelo tamanho do texto.
/// Sem espaço, cada coluna fica entre a maior palavra e o texto inteiro.
fn larguras_das_colunas(linhas: &[Linha<'_>], largura: f32) -> Vec<f32> {
    let n = linhas
        .iter()
        .map(|l| l.celulas.iter().map(|c| c.span).sum::<usize>())
        .max()
        .unwrap_or(0);
    if n == 0 {
        return Vec::new();
    }

    let mut minimas = vec![0.0_f32; n];
    let mut ideais = vec![0.0_f32; n];
    for linha in linhas {
        let mut col = 0usize;
        for c in &linha.celulas {
            if c.span == 1 && !c.vazia {
                minimas[col] = minimas[col].max(c.minimo + CELL_GAP);
                ideais[col] = ideais[col].max(c.ideal + CELL_GAP);
            }
            col += c.span;
        }
    }

    // Célula que cobre várias colunas: a diferença é repartida entre elas.
    for linha in linhas {
        let mut col = 0usize;
        for c in &linha.celulas {
            if c.span > 1 && !c.vazia {
                let fim = col + c.span;
                let k = c.span as f32;
                let atual_min: f32 = minimas[col..fim].iter().sum();
                let atual_ideal: f32 = ideais[col..fim].iter().sum();
                let falta_min = (c.minimo + CELL_GAP - atual_min).max(0.0) / k;
                let falta_ideal = (c.ideal + CELL_GAP - atual_ideal).max(0.0) / k;
                for i in col..fim {
                    minimas[i] += falta_min;
                    ideais[i] += falta_ideal;
                }
            }
            col += c.span;
        }
    }

    let soma_min: f32 = minimas.iter().sum();
    let soma_ideal: f32 = ideais.iter().sum();
    if soma_ideal <= 0.0 {
        return vec![largura / n as f32; n];
    }
    if soma_ideal <= largura {
        let sobra = largura - soma_ideal;
        return ideais.iter().map(|i| *i + sobra * *i / soma_ideal).collect();
    }
    if soma_min <= largura {
        let folga = largura - soma_min;
        let faixa = soma_ideal - soma_min;
        return minimas
            .iter()
            .zip(ideais.iter())
            .map(|(m, i)| *m + folga * (*i - *m) / faixa)
            .collect();
    }
    let k = largura / soma_min;
    minimas.iter().map(|m| *m * k).collect()
}

/// Divide os trechos em palavras, mantendo o link e a cor de cada uma.
/// Uma palavra que atravessa dois trechos fica com o link e a cor do primeiro.
fn split_words(chunks: &[Span]) -> Vec<Span> {
    let mut words: Vec<Span> = Vec::new();
    let mut cur: Option<Span> = None;
    for chunk in chunks {
        for ch in chunk.text.chars() {
            if ch == '\u{1}' {
                words.extend(cur.take());
                words.push(Span { text: QUEBRA.to_string(), href: None, color: None });
            } else if ch.is_whitespace() {
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
        if word.text == QUEBRA {
            if line.is_empty() {
                ctx.y += line_h;
            } else {
                emit_line(&line, style, line_h, ctx);
                line.clear();
                line_w = 0.0;
            }
            continue;
        }
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

    let larguras: Vec<f32> = runs
        .iter()
        .map(|r| ctx.measurer.measure(&r.text, style.font_size, style.bold))
        .collect();
    let total: f32 = larguras.iter().sum();
    let deslocamento = match style.align {
        1 => ((ctx.width - total) / 2.0).max(0.0),
        2 => (ctx.width - total).max(0.0),
        _ => 0.0,
    };
    let mut x = ctx.x0 + deslocamento;
    for (run, w) in runs.into_iter().zip(larguras) {
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

    #[test]
    fn descendant_selector_reaches_nested_text() {
        let cmds = run(
            "<style>div p { font-size: 20px }</style><div><p>a</p></div>",
            400.0,
        );
        match &cmds[0] {
            DrawCommand::Text { font_size, .. } => assert_eq!(*font_size, 20.0),
        }
    }

    #[test]
    fn child_selector_only_matches_direct_child() {
        let cmds = run(
            "<style>div > p { font-size: 20px }</style><div><span><p>a</p></span></div>",
            400.0,
        );
        match &cmds[0] {
            DrawCommand::Text { font_size, .. } => assert_eq!(*font_size, 16.0),
        }
    }

    #[test]
    fn hides_whole_menu_by_ancestor_class() {
        let cmds = run(
            r#"<style>.menu p { display: none }</style><div class="menu"><p>x</p><p>y</p></div><p>z</p>"#,
            400.0,
        );
        assert_eq!(cmds.len(), 1);
        assert_eq!(text_of(&cmds[0]), "z");
    }

    #[test]
    fn sibling_selector_reaches_the_next_element() {
        let cmds = run(
            r#"<style>.a + p { display: none }</style><div class="a">x</div><p>y</p><p>z</p>"#,
            400.0,
        );
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["x", "z"]);
    }

    #[test]
    fn first_child_hides_only_the_first_item() {
        let cmds = run(
            "<style>li:first-child { display: none }</style><ul><li>um</li><li>dois</li></ul>",
            400.0,
        );
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["dois"]);
    }

    #[test]
    fn last_child_hides_only_the_last_item() {
        let cmds = run(
            "<style>li:last-child { display: none }</style><ul><li>um</li><li>dois</li></ul>",
            400.0,
        );
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["um"]);
    }

    #[test]
    fn script_depois_do_item_conta_como_irmao() {
        let cmds = run(
            "<style>li:last-child { display: none }</style><ul><li>um</li><li>dois</li><script></script></ul>",
            400.0,
        );
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["um", "dois"]);
    }

    #[test]
    fn texto_depois_do_icone_some_como_no_botao_da_wikipedia() {
        let cmds = run(
            r#"<style>.b span + span:last-child { clip: rect(1px,1px,1px,1px) }</style><a class="b"><span></span><span>Idioma</span></a>"#,
            400.0,
        );
        assert!(cmds.is_empty());
    }

    #[test]
    fn table_puts_cells_side_by_side() {
        let cmds = run(
            r#"<table><tr><th>Capital</th><td>Brasília</td></tr></table>"#,
            400.0,
        );
        let pos: Vec<(&str, f32, f32)> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { text, x, y, .. } => (text.as_str(), *x, *y),
            })
            .collect();
        assert_eq!(pos.len(), 2);
        assert_eq!(pos[0].0, "Capital");
        assert_eq!(pos[1].0, "Brasília");
        assert_eq!(pos[0].2, pos[1].2);
        assert!(pos[1].1 > pos[0].1);
    }

    #[test]
    fn table_rows_stack_vertically() {
        let cmds = run(
            r#"<table><tr><td>a</td></tr><tr><td>b</td></tr></table>"#,
            400.0,
        );
        let ys: Vec<f32> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { y, .. } => *y,
            })
            .collect();
        assert_eq!(ys.len(), 2);
        assert!(ys[1] > ys[0]);
    }

    #[test]
    fn th_is_bold_and_td_is_not() {
        let cmds = run(r#"<table><tr><th>a</th><td>b</td></tr></table>"#, 400.0);
        match (&cmds[0], &cmds[1]) {
            (DrawCommand::Text { bold: a, .. }, DrawCommand::Text { bold: b, .. }) => {
                assert!(*a);
                assert!(!*b);
            }
        }
    }

    #[test]
    fn colspan_cell_covers_the_row() {
        let cmds = run(
            r#"<table><tr><th colspan="2">Título</th></tr><tr><td>a</td><td>b</td></tr></table>"#,
            400.0,
        );
        let pos: Vec<(&str, f32, f32)> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { text, x, y, .. } => (text.as_str(), *x, *y),
            })
            .collect();
        let textos: Vec<&str> = pos.iter().map(|p| p.0).collect();
        assert_eq!(textos, vec!["Título", "a", "b"]);
        // "a" fica embaixo do título; "b" fica depois de "a" na mesma linha.
        assert!(pos[1].2 > pos[0].2);
        assert!(pos[2].1 > pos[1].1);
        assert_eq!(pos[2].2, pos[1].2);
    }

    #[test]
    fn hidden_row_takes_no_space() {
        let cmds = run(
            r#"<style>.oculta { display: none }</style><table><tr class="oculta"><td>a</td></tr><tr><td>b</td></tr></table>"#,
            400.0,
        );
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["b"]);
    }

    #[test]
    fn text_around_table_keeps_order() {
        let cmds = run(
            "<p>antes</p><table><tr><td>meio</td></tr></table><p>depois</p>",
            400.0,
        );
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["antes", "meio", "depois"]);
    }

    #[test]
    fn caption_is_drawn_above_the_rows() {
        let cmds = run(
            "<table><caption>Título</caption><tr><td>a</td></tr></table>",
            400.0,
        );
        let pos: Vec<(&str, f32)> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { text, y, .. } => (text.as_str(), *y),
            })
            .collect();
        assert_eq!(pos.len(), 2);
        assert_eq!(pos[0].0, "Título");
        assert_eq!(pos[1].0, "a");
        assert!(pos[0].1 < pos[1].1);
    }

    #[test]
    fn hidden_text_does_not_widen_the_column() {
        // "b" fica na segunda coluna. Se o texto escondido contasse,
        // a primeira coluna ocuparia quase toda a largura e "b" sairia longe.
        let cmds = run(
            r#"<style>.x { display: none }</style><table><tr><td><span class="x">muito longo texto aqui</span>a</td><td>b</td></tr></table>"#,
            400.0,
        );
        let pos: Vec<(&str, f32)> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { text, x, .. } => (text.as_str(), *x),
            })
            .collect();
        assert_eq!(pos.len(), 2);
        assert_eq!(pos[0].0, "a");
        assert_eq!(pos[1].0, "b");
        assert!(pos[1].1 < 300.0);
    }

    #[test]
    fn comandos_saem_em_ordem_de_altura() {
        // A primeira coluna quebra em duas linhas; a segunda ("b") fica numa só.
        // Sem ordenar, "b" sairia antes da segunda linha da primeira coluna.
        let cmds = run(
            "<table><tr><td>palavra palavra palavra palavra palavra palavra palavra palavra palavra palavra</td><td>b</td></tr></table>",
            400.0,
        );
        let ys: Vec<f32> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { y, .. } => *y,
            })
            .collect();
        assert!(ys.len() > 2);
        assert!(ys.windows(2).all(|w| w[0] <= w[1]));
    }

    // --- Fundos, flex, quebra de linha e alinhamento (0.0.3) ---

    fn completo(html: &str, width: f32) -> Saida {
        layout_completo(&parse(html), width, &FixedMeasurer)
    }

    #[test]
    fn bloco_com_fundo_gera_caixa() {
        let s = completo(
            "<style>.c{background-color:#102030;padding:10px}</style><div class=c>oi</div>",
            400.0,
        );
        assert_eq!(s.fundos.len(), 1);
        let f = &s.fundos[0];
        assert_eq!(f.cor, Some([0x10, 0x20, 0x30]));
        assert_eq!(f.x, 8.0);
        assert!(f.h > 20.0);
        // O texto fica dentro do padding.
        match &s.comandos[0] {
            DrawCommand::Text { x, y, .. } => {
                assert_eq!(*x, 18.0);
                assert_eq!(*y, 18.0);
            }
        }
    }

    #[test]
    fn fundo_do_body_vira_fundo_da_pagina() {
        let s = completo(
            "<style>body{background-color:#000}</style><body><p>oi</p></body>",
            400.0,
        );
        assert_eq!(s.fundo_pagina, Some([0, 0, 0]));
        assert!(s.fundos.is_empty());
    }

    #[test]
    fn fundos_aninhados_saem_de_fora_para_dentro() {
        let s = completo(
            "<style>.a{background-color:#111}.b{background-color:#222}</style><div class=a><div class=b>oi</div></div>",
            400.0,
        );
        assert_eq!(s.fundos.len(), 2);
        assert_eq!(s.fundos[0].cor, Some([0x11, 0x11, 0x11]));
        assert_eq!(s.fundos[1].cor, Some([0x22, 0x22, 0x22]));
    }

    #[test]
    fn variavel_da_classe_do_html_vale() {
        let s = completo(
            "<html class=\"escuro\"><style>.escuro{--t:10 20 30}p{color:rgb(var(--t))}</style><body><p>oi</p></body></html>",
            400.0,
        );
        match &s.comandos[0] {
            DrawCommand::Text { color, .. } => assert_eq!(*color, Some([10, 20, 30])),
        }
    }

    #[test]
    fn flex_em_linha_poe_filhos_lado_a_lado() {
        let cmds = run(
            "<style>.f{display:flex}</style><div class=f><span>aa</span><span>bb</span></div>",
            400.0,
        );
        let pos: Vec<(f32, f32)> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { x, y, .. } => (*x, *y),
            })
            .collect();
        assert_eq!(pos.len(), 2);
        assert_eq!(pos[0].1, pos[1].1);
        assert!(pos[1].0 > pos[0].0);
    }

    #[test]
    fn flex_em_coluna_empilha() {
        let cmds = run(
            "<style>.f{display:flex;flex-direction:column}</style><div class=f><span>aa</span><span>bb</span></div>",
            400.0,
        );
        let ys: Vec<f32> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { y, .. } => *y,
            })
            .collect();
        assert_eq!(ys.len(), 2);
        assert!(ys[1] > ys[0]);
    }

    #[test]
    fn display_block_em_span_quebra_linha() {
        let cmds = run(
            "<style>.b{display:block}</style><span class=b>aa</span><span class=b>bb</span>",
            400.0,
        );
        assert_eq!(cmds.len(), 2);
        let ys: Vec<f32> = cmds
            .iter()
            .map(|c| match c {
                DrawCommand::Text { y, .. } => *y,
            })
            .collect();
        assert!(ys[1] > ys[0]);
    }

    #[test]
    fn br_quebra_a_linha() {
        let cmds = run("<p>aa<br>bb</p>", 400.0);
        let textos: Vec<&str> = cmds.iter().map(text_of).collect();
        assert_eq!(textos, vec!["aa", "bb"]);
    }

    #[test]
    fn text_align_center_desloca_o_texto() {
        let cmds = run("<style>p{text-align:center}</style><p>aa</p>", 400.0);
        match &cmds[0] {
            DrawCommand::Text { x, .. } => assert!(*x > 100.0),
        }
    }
}