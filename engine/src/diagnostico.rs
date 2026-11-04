// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Diagnóstico de página.
//! Passa o HTML pelo mesmo parser, CSS e layout do motor e descreve em texto curto
//! o que aconteceu: quanto texto o HTML tem, quanto foi ocultado por CSS, quanto foi
//! desenhado, quais blocos de texto não chegaram à tela e onde estão os elementos ocultos.
//! Só lê: não altera a renderização.

use crate::css::{self, Estilo, Folha, Info};
use crate::html::{parse, Element, Node};
use crate::layout::{layout, DrawCommand, TextMeasurer};

/// Elementos que não entram no texto da página (mesma lista do layout).
const SKIP_TAGS: &[&str] = &["head", "script", "style", "title", "noscript"];

/// Blocos cujo texto é conferido um a um.
const BLOCK_TAGS: &[&str] = &[
    "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "figcaption", "blockquote", "td", "th", "dd", "dt",
];

const MAX_BLOCOS: usize = 60;
const MAX_OCULTOS: usize = 30;
const MAX_LINHAS_ARVORE: usize = 40;
const PROFUNDIDADE_ARVORE: usize = 4;
const CHARS_EXIBIDOS: usize = 50;
const CHARS_CONFERIDOS: usize = 40;
const LIMITE_TEXTO_QUADRO: usize = 300;

/// Bloco de texto encontrado no HTML.
struct Bloco {
    caminho: String,
    exibir: String,
    /// Início do texto sem espaços, usado para conferir se foi desenhado.
    chave: String,
    oculto: bool,
}

/// Bloco aberto durante a percorrida. Acumula o texto visível dele.
struct Quadro {
    indice: usize,
    texto: String,
}

struct Diagnostico {
    folha: Folha,
    tem_css: bool,
    pais: Vec<Info>,
    abertos: Vec<Quadro>,
    blocos: Vec<Bloco>,
    ocultos: Vec<String>,
    visivel: usize,
    oculto_chars: usize,
    total_elementos: usize,
    profundidade_max: usize,
}

/// Gera o relatório de diagnóstico em texto, uma linha por item.
pub fn relatorio(html: &str, largura: f32, medidor: &dyn TextMeasurer) -> String {
    let nos = parse(html);
    let mut css_texto = String::new();
    coletar_css(&nos, &mut css_texto);

    let mut desenhado = String::new();
    for comando in layout(&nos, largura, medidor) {
        match comando {
            DrawCommand::Text { text, .. } => desenhado.push_str(&text),
        }
    }
    let desenhado_chars = contar(&desenhado);
    let desenhado_limpo: String = desenhado.chars().filter(|c| !c.is_whitespace()).collect();

    let mut d = Diagnostico {
        folha: Folha::parse(&css_texto),
        tem_css: !css_texto.trim().is_empty(),
        pais: Vec::new(),
        abertos: Vec::new(),
        blocos: Vec::new(),
        ocultos: Vec::new(),
        visivel: 0,
        oculto_chars: 0,
        total_elementos: 0,
        profundidade_max: 0,
    };
    d.percorrer(&nos, 1);

    let mut linhas: Vec<String> = Vec::new();
    linhas.push("DIAGNÓSTICO NUSKY".to_string());
    linhas.push(format!("Motor: {}", crate::version()));
    linhas.push(format!("Largura da tela: {} pt", largura));
    linhas.push(format!("HTML: {} bytes", html.len()));
    linhas.push(format!("CSS em <style>: {} bytes", css_texto.len()));
    linhas.push(format!(
        "Elementos: {} (profundidade máxima {})",
        d.total_elementos, d.profundidade_max
    ));
    linhas.push(String::new());

    linhas.push("TEXTO".to_string());
    linhas.push(format!("No HTML visível: {} caracteres", d.visivel));
    linhas.push(format!("Oculto por CSS: {} caracteres", d.oculto_chars));
    linhas.push(format!("Desenhado: {} caracteres", desenhado_chars));
    if desenhado_chars < d.visivel {
        linhas.push(format!(
            "AVISO: {} caracteres visíveis não chegaram ao desenho.",
            d.visivel - desenhado_chars
        ));
    } else {
        linhas.push("OK: todo o texto visível foi desenhado.".to_string());
    }

    linhas.push(String::new());
    linhas.push(format!("ELEMENTOS OCULTOS POR CSS: {}", d.ocultos.len()));
    for caminho in d.ocultos.iter().take(MAX_OCULTOS) {
        linhas.push(format!("  {}", caminho));
    }
    if d.ocultos.len() > MAX_OCULTOS {
        linhas.push(format!("  … e mais {}", d.ocultos.len() - MAX_OCULTOS));
    }

    // Problemas primeiro (prioridade 0), depois ocultos (1), depois os que foram desenhados (2).
    let mut blocos: Vec<(u8, &Bloco)> = d
        .blocos
        .iter()
        .filter(|b| !b.chave.is_empty())
        .map(|b| {
            let prioridade = if b.oculto {
                1
            } else if desenhado_limpo.contains(b.chave.as_str()) {
                2
            } else {
                0
            };
            (prioridade, b)
        })
        .collect();
    let sem_desenho = blocos.iter().filter(|(p, _)| *p == 0).count();
    blocos.sort_by_key(|(p, _)| *p);

    linhas.push(String::new());
    linhas.push(format!(
        "BLOCOS DE TEXTO: {} (sem desenho: {})",
        blocos.len(),
        sem_desenho
    ));
    for (prioridade, bloco) in blocos.iter().take(MAX_BLOCOS) {
        let estado = match *prioridade {
            0 => "SEM DESENHO",
            1 => "oculto",
            _ => "ok",
        };
        linhas.push(format!("[{}] {}: \"{}\"", estado, bloco.caminho, bloco.exibir));
    }
    if blocos.len() > MAX_BLOCOS {
        linhas.push(format!("… e mais {} blocos", blocos.len() - MAX_BLOCOS));
    }

    linhas.push(String::new());
    linhas.push("ÁRVORE (até nível 4)".to_string());
    let mut arvore: Vec<String> = Vec::new();
    arvore_de(&nos, 0, &mut arvore);
    linhas.extend(arvore.into_iter().take(MAX_LINHAS_ARVORE));

    linhas.join("\n")
}

impl Diagnostico {
    fn percorrer(&mut self, nos: &[Node], profundidade: usize) {
        for no in nos {
            match no {
                Node::Text(t) => {
                    self.visivel += contar(t);
                    for quadro in self.abertos.iter_mut() {
                        acrescentar(&mut quadro.texto, t, LIMITE_TEXTO_QUADRO);
                    }
                }
                Node::Element(el) => self.elemento(el, profundidade),
            }
        }
    }

    fn elemento(&mut self, el: &Element, profundidade: usize) {
        if SKIP_TAGS.contains(&el.tag.as_str()) {
            return;
        }
        self.total_elementos += 1;
        self.profundidade_max = self.profundidade_max.max(profundidade);

        let info = info_do_elemento(el);
        let caminho = caminho_de(&self.pais, &info);
        let estilo = self.estilo(el, &info);
        let e_bloco = BLOCK_TAGS.contains(&el.tag.as_str());

        if estilo.oculto {
            let mut texto = String::new();
            texto_de(&el.children, &mut texto);
            self.oculto_chars += contar(&texto);
            self.ocultos.push(caminho.clone());
            if e_bloco {
                self.blocos.push(Bloco {
                    caminho,
                    exibir: texto_exibido(&texto),
                    chave: texto_conferido(&texto),
                    oculto: true,
                });
            }
            return;
        }

        if e_bloco {
            self.blocos.push(Bloco {
                caminho: caminho.clone(),
                exibir: String::new(),
                chave: String::new(),
                oculto: false,
            });
            let indice = self.blocos.len() - 1;
            self.abertos.push(Quadro { indice, texto: String::new() });
        }

        self.pais.push(info);
        self.percorrer(&el.children, profundidade + 1);
        self.pais.pop();

        if e_bloco {
            if let Some(quadro) = self.abertos.pop() {
                let bloco = &mut self.blocos[quadro.indice];
                bloco.exibir = texto_exibido(&quadro.texto);
                bloco.chave = texto_conferido(&quadro.texto);
            }
        }
    }

    /// Mesmo cálculo de CSS que o layout faz para cada elemento.
    fn estilo(&self, el: &Element, info: &Info) -> Estilo {
        if !self.tem_css && el.attr("style").is_none() {
            return Estilo::default();
        }
        css::estilo_com_pais(&self.folha, info, &self.pais, el.attr("style"))
    }
}

/// Junta o texto de todas as tags <style>, como o layout faz.
fn coletar_css(nos: &[Node], saida: &mut String) {
    for no in nos {
        if let Node::Element(el) = no {
            if el.tag == "noscript" {
                continue;
            }
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

fn info_do_elemento(el: &Element) -> Info {
    Info {
        tag: el.tag.clone(),
        id: el.attr("id").map(str::to_string),
        classes: el
            .attr("class")
            .unwrap_or("")
            .split_whitespace()
            .map(str::to_string)
            .collect(),
    }
}

/// Nome curto do elemento: tag, id e primeira classe. Ex.: `div#toc`, `p.x`.
fn rotulo(info: &Info) -> String {
    let mut s = info.tag.clone();
    if let Some(id) = &info.id {
        s.push('#');
        s.push_str(id);
    }
    if let Some(classe) = info.classes.first() {
        s.push('.');
        s.push_str(classe);
    }
    s
}

/// Caminho até o elemento, com no máximo os últimos 4 níveis. Ex.: `div#toc > p`.
fn caminho_de(pais: &[Info], info: &Info) -> String {
    let mut partes: Vec<String> = pais.iter().map(rotulo).collect();
    partes.push(rotulo(info));
    let inicio = partes.len().saturating_sub(4);
    let corte = if inicio > 0 { "… > " } else { "" };
    format!("{}{}", corte, partes[inicio..].join(" > "))
}

/// Caracteres que não são espaço. É a medida usada nas contagens.
fn contar(s: &str) -> usize {
    s.chars().filter(|c| !c.is_whitespace()).count()
}

/// Junta o texto de um trecho do HTML, sem script, style, head, title e noscript.
fn texto_de(nos: &[Node], saida: &mut String) {
    for no in nos {
        match no {
            Node::Text(t) => saida.push_str(t),
            Node::Element(el) => {
                if !SKIP_TAGS.contains(&el.tag.as_str()) {
                    texto_de(&el.children, saida);
                }
            }
        }
    }
}

/// Acrescenta texto até o limite, em caracteres.
fn acrescentar(s: &mut String, t: &str, limite: usize) {
    let mut n = s.chars().count();
    for ch in t.chars() {
        if n >= limite {
            break;
        }
        s.push(ch);
        n += 1;
    }
}

/// Texto com espaços normalizados, cortado para caber numa linha do relatório.
fn texto_exibido(texto: &str) -> String {
    let junto = texto.split_whitespace().collect::<Vec<&str>>().join(" ");
    if junto.chars().count() > CHARS_EXIBIDOS {
        let curto: String = junto.chars().take(CHARS_EXIBIDOS).collect();
        format!("{}…", curto)
    } else {
        junto
    }
}

/// Início do texto sem espaços. Serve para conferir se o trecho foi desenhado.
fn texto_conferido(texto: &str) -> String {
    texto
        .chars()
        .filter(|c| !c.is_whitespace())
        .take(CHARS_CONFERIDOS)
        .collect()
}

fn arvore_de(nos: &[Node], nivel: usize, saida: &mut Vec<String>) {
    for no in nos {
        if let Node::Element(el) = no {
            if SKIP_TAGS.contains(&el.tag.as_str()) || nivel >= PROFUNDIDADE_ARVORE {
                continue;
            }
            let info = info_do_elemento(el);
            let filhos = el
                .children
                .iter()
                .filter(|c| matches!(c, Node::Element(_)))
                .count();
            saida.push(format!("{}{} ({} filhos)", "  ".repeat(nivel), rotulo(&info), filhos));
            arvore_de(&el.children, nivel + 1, saida);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Cada caractere tem metade do tamanho da fonte, como nos outros testes.
    struct Medidor;

    impl TextMeasurer for Medidor {
        fn measure(&self, text: &str, font_size: f32, _bold: bool) -> f32 {
            text.chars().count() as f32 * font_size * 0.5
        }
    }

    fn rel(html: &str) -> String {
        relatorio(html, 400.0, &Medidor)
    }

    #[test]
    fn counts_visible_and_drawn_text() {
        let r = rel("<p>abc</p>");
        assert!(r.contains("No HTML visível: 3 caracteres"));
        assert!(r.contains("Desenhado: 3 caracteres"));
        assert!(r.contains("OK: todo o texto visível foi desenhado."));
    }

    #[test]
    fn script_text_is_not_counted() {
        let r = rel("<p>a</p><script>var x = 1;</script>");
        assert!(r.contains("No HTML visível: 1 caracteres"));
    }

    #[test]
    fn hidden_text_is_reported_apart() {
        let r = rel("<style>.x { display: none }</style><p class=\"x\">abc</p><p>de</p>");
        assert!(r.contains("Oculto por CSS: 3 caracteres"));
        assert!(r.contains("Desenhado: 2 caracteres"));
    }

    #[test]
    fn hidden_path_shows_ancestors() {
        let r = rel("<style>div#toc > p { display: none }</style><div id=\"toc\"><p>x</p></div>");
        assert!(r.contains("div#toc > p"));
    }

    #[test]
    fn visible_block_is_marked_ok() {
        let r = rel("<p>texto de teste</p>");
        assert!(r.contains("[ok] p: \"texto de teste\""));
    }

    #[test]
    fn hidden_block_is_marked() {
        let r = rel("<style>.x { display: none }</style><p class=\"x\">oculto aqui</p>");
        assert!(r.contains("[oculto] p.x: \"oculto aqui\""));
    }
}