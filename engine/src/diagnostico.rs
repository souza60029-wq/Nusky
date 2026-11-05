// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Diagnóstico de página.
//! Passa o HTML pelo mesmo parser, CSS e layout do motor e descreve em texto curto
//! o que aconteceu: quanto texto o HTML tem, quanto foi ocultado por CSS, quanto foi
//! desenhado, quais blocos de texto não chegaram à tela, onde estão os elementos ocultos,
//! quais regras `display: none` o motor não aplicou (com o motivo) e quais regras que
//! casam com um bloco de texto têm declarações que costumam esconder texto
//! (posição fora da tela, tamanho zero, cor transparente etc.), com o texto da regra.
//! Usa a mesma lista de irmãos anteriores do layout, para que seletores `+`, `~`
//! e `:first-child` deem o mesmo resultado na tela e no relatório.
//! Só lê: não altera a renderização.

use std::collections::BTreeMap;

use crate::css::{self, Estilo, Folha, Ignorada, Info};
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
const MAX_IGNORADAS_POR_MOTIVO: usize = 6;
const LIMITE_SELETOR: usize = 140;
const MAX_REGRAS_BLOCO: usize = 6;
const MAX_ACHADOS: usize = 30;

/// Bloco de texto encontrado no HTML.
struct Bloco {
    caminho: String,
    exibir: String,
    /// Início do texto sem espaços, usado para conferir se foi desenhado.
    chave: String,
    oculto: bool,
    /// Regras (do próprio bloco ou de ancestrais) com declarações que costumam esconder texto.
    achados: Vec<String>,
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
    /// Irmãos anteriores de cada nível de `pais`, na mesma ordem.
    pais_irmaos: Vec<Vec<Info>>,
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
        folha: Folha::parse_largura(&css_texto, largura),
        tem_css: !css_texto.trim().is_empty(),
        pais: Vec::new(),
        pais_irmaos: Vec::new(),
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

    linhas.push(String::new());
    linhas.push(format!(
        "REGRAS COM display: none NÃO APLICADAS: {}",
        d.folha.ignoradas.len()
    ));
    linhas.extend(resumo_ignoradas(&d.folha.ignoradas));

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

    // Blocos com texto e regras que podem esconder o texto. Os visíveis vêm primeiro,
    // porque são a diferença entre o Nusky e o Safari.
    let mut com_regras: Vec<&Bloco> = d
        .blocos
        .iter()
        .filter(|b| !b.achados.is_empty() && !b.chave.is_empty())
        .collect();
    com_regras.sort_by_key(|b| if b.oculto { 1 } else { 0 });

    linhas.push(String::new());
    linhas.push(format!(
        "REGRAS QUE PODEM ESCONDER TEXTO: {} blocos",
        com_regras.len()
    ));
    linhas.push(
        "  Regras do próprio bloco ou de ancestrais com declaração de ocultação.".to_string(),
    );
    linhas.push(
        "  Outra regra pode tê-las desfeito depois; confira no Safari.".to_string(),
    );
    for b in com_regras.iter().take(MAX_ACHADOS) {
        let estado = if b.oculto {
            "oculto no Nusky"
        } else {
            "VISÍVEL no Nusky"
        };
        linhas.push(format!("[{}] {}: \"{}\"", estado, b.caminho, b.exibir));
        for achado in &b.achados {
            linhas.push(format!("    {}", achado));
        }
    }
    if com_regras.len() > MAX_ACHADOS {
        linhas.push(format!("… e mais {} blocos", com_regras.len() - MAX_ACHADOS));
    }

    linhas.push(String::new());
    linhas.push("ÁRVORE (até nível 4)".to_string());
    let mut arvore: Vec<String> = Vec::new();
    arvore_de(&nos, 0, &mut arvore);
    linhas.extend(arvore.into_iter().take(MAX_LINHAS_ARVORE));

    linhas.join("\n")
}

impl Diagnostico {
    /// Percorre os filhos de um nó. Guarda a lista de irmãos anteriores só quando
    /// alguma regra da página precisa dela, como o layout faz.
    fn percorrer(&mut self, nos: &[Node], profundidade: usize) {
        let guarda_irmaos = self.folha.precisa_irmaos();
        let mut irmaos: Vec<Info> = Vec::new();
        for no in nos {
            match no {
                Node::Text(t) => {
                    self.visivel += contar(t);
                    for quadro in self.abertos.iter_mut() {
                        acrescentar(&mut quadro.texto, t, LIMITE_TEXTO_QUADRO);
                    }
                }
                Node::Element(el) => {
                    let info = info_do_elemento(el, self.folha.nomes_atributos());
                    let info = self.elemento(el, info, &irmaos, profundidade);
                    if guarda_irmaos {
                        irmaos.push(info);
                    }
                }
            }
        }
    }

    /// Trata um elemento e devolve a sua identificação, para entrar na lista de irmãos.
    fn elemento(&mut self, el: &Element, info: Info, irmaos: &[Info], profundidade: usize) -> Info {
        if SKIP_TAGS.contains(&el.tag.as_str()) {
            return info;
        }
        self.total_elementos += 1;
        self.profundidade_max = self.profundidade_max.max(profundidade);

        let caminho = caminho_de(&self.pais, &info);
        let estilo = self.estilo(el, &info, irmaos);
        let e_bloco = BLOCK_TAGS.contains(&el.tag.as_str());
        let achados = if e_bloco {
            self.achados(&info, irmaos)
        } else {
            Vec::new()
        };

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
                    achados,
                });
            }
            return info;
        }

        if e_bloco {
            self.blocos.push(Bloco {
                caminho: caminho.clone(),
                exibir: String::new(),
                chave: String::new(),
                oculto: false,
                achados,
            });
            let indice = self.blocos.len() - 1;
            self.abertos.push(Quadro { indice, texto: String::new() });
        }

        self.pais.push(info);
        self.pais_irmaos.push(irmaos.to_vec());
        self.percorrer(&el.children, profundidade + 1);
        self.pais_irmaos.pop();
        let info = self.pais.pop().unwrap_or_default();

        if e_bloco {
            if let Some(quadro) = self.abertos.pop() {
                let bloco = &mut self.blocos[quadro.indice];
                bloco.exibir = texto_exibido(&quadro.texto);
                bloco.chave = texto_conferido(&quadro.texto);
            }
        }
        info
    }

    /// Mesmo cálculo de CSS que o layout faz para cada elemento, com pais e irmãos anteriores.
    fn estilo(&self, el: &Element, info: &Info, irmaos: &[Info]) -> Estilo {
        if !self.tem_css && el.attr("style").is_none() {
            return Estilo::default();
        }
        css::estilo_completo(&self.folha, info, &self.pais, irmaos, el.attr("style"))
    }

    /// Regras que casam com o elemento ou com algum ancestral e têm declarações que
    /// costumam esconder texto. Mostra o texto da regra, não só o nome do elemento.
    fn achados(&self, info: &Info, irmaos: &[Info]) -> Vec<String> {
        let mut linhas: Vec<String> = Vec::new();
        if !self.tem_css {
            return linhas;
        }
        for c in css::regras_casadas(&self.folha, info, &self.pais, irmaos) {
            let sus = declaracoes_suspeitas(&c.declaracoes);
            if !sus.is_empty() {
                linhas.push(format!(
                    "{}  →  {}",
                    seletor_exibido(&c.seletor),
                    sus.join("; ")
                ));
            }
        }
        for (k, anc) in self.pais.iter().enumerate() {
            for c in css::regras_casadas(&self.folha, anc, &self.pais[..k], &self.pais_irmaos[k]) {
                let sus = declaracoes_suspeitas(&c.declaracoes);
                if !sus.is_empty() {
                    linhas.push(format!(
                        "{}  (ancestral {})  →  {}",
                        seletor_exibido(&c.seletor),
                        rotulo(anc),
                        sus.join("; ")
                    ));
                }
            }
        }
        linhas.truncate(MAX_REGRAS_BLOCO);
        linhas
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

/// Monta a identificação do elemento (tag, id, classes e atributos citados no CSS).
/// Só lê os atributos listados em `nomes`, igual ao layout.
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

/// Nome curto do elemento: tag, id e primeira classe. Ex.: `div#toc`, `p.x`.
fn rotulo(info: &Info) -> String {
    let mut s = info.tag.clone();
    if !info.id.is_empty() {
        s.push('#');
        s.push_str(&info.id);
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

/// Seletor com espaços normalizados, cortado para caber numa linha.
fn seletor_exibido(s: &str) -> String {
    let junto = s.split_whitespace().collect::<Vec<&str>>().join(" ");
    if junto.chars().count() > LIMITE_SELETOR {
        let curto: String = junto.chars().take(LIMITE_SELETOR).collect();
        format!("{}…", curto)
    } else {
        junto
    }
}

/// Agrupa as regras ignoradas pelo motivo. Grupos maiores vêm primeiro.
fn resumo_ignoradas(ignoradas: &[Ignorada]) -> Vec<String> {
    let mut grupos: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for item in ignoradas {
        grupos
            .entry(item.motivo.as_str())
            .or_default()
            .push(item.seletor.as_str());
    }

    let mut ordenados: Vec<(&str, Vec<&str>)> = grupos.into_iter().collect();
    ordenados.sort_by(|a, b| b.1.len().cmp(&a.1.len()));

    let mut linhas = Vec::new();
    for (motivo, seletores) in ordenados {
        linhas.push(format!("  {} ({}):", motivo, seletores.len()));
        for sel in seletores.iter().take(MAX_IGNORADAS_POR_MOTIVO) {
            linhas.push(format!("    {}", seletor_exibido(sel)));
        }
        if seletores.len() > MAX_IGNORADAS_POR_MOTIVO {
            linhas.push(format!(
                "    … e mais {}",
                seletores.len() - MAX_IGNORADAS_POR_MOTIVO
            ));
        }
    }
    linhas
}

/// Declarações que costumam esconder texto, no formato `nome: valor`.
/// O Nusky aplica algumas delas (display, visibility, clip, clip-path, transform)
/// e ignora as outras. Aqui só se lê o texto da regra.
fn declaracoes_suspeitas(corpo: &str) -> Vec<String> {
    let mut saida = Vec::new();
    for par in corpo.split(';') {
        let (nome, valor) = match par.split_once(':') {
            Some(x) => x,
            None => continue,
        };
        let nome = nome.trim().to_ascii_lowercase();
        let valor = valor.trim();
        let valor = valor.strip_suffix("!important").unwrap_or(valor).trim();
        if e_suspeita(&nome, &valor.to_ascii_lowercase()) {
            saida.push(format!("{}: {}", nome, valor));
        }
    }
    saida
}

/// Diz se uma declaração (nome e valor já em minúsculas) costuma esconder texto.
fn e_suspeita(nome: &str, v: &str) -> bool {
    match nome {
        "display" => v == "none",
        "visibility" => v == "hidden" || v == "collapse",
        "clip" | "clip-path" => v != "auto" && v != "none",
        "transform" => v.contains("scale(0") || v.contains("-100%") || v.contains("-999"),
        "opacity" | "font-size" => numero(v) == Some(0.0),
        "color" | "-webkit-text-fill-color" => {
            let sem = v.replace(' ', "");
            v == "transparent" || (sem.starts_with("rgba(") && sem.ends_with(",0)"))
        }
        "text-indent" | "left" | "right" | "top" | "bottom" | "margin" | "margin-left"
        | "margin-right" | "margin-top" | "margin-bottom" => {
            numero(v).map_or(false, |n| n.abs() >= 999.0)
        }
        "width" | "height" | "max-width" | "max-height" => {
            numero(v).map_or(false, |n| n <= 1.0)
        }
        _ => false,
    }
}

/// Número de um valor simples (px, em, rem, pt ou %). Sem unidade também vale.
fn numero(v: &str) -> Option<f32> {
    let limpo = v
        .trim_end_matches("px")
        .trim_end_matches("rem")
        .trim_end_matches("em")
        .trim_end_matches("pt")
        .trim_end_matches('%');
    limpo.trim().parse::<f32>().ok()
}

fn arvore_de(nos: &[Node], nivel: usize, saida: &mut Vec<String>) {
    for no in nos {
        if let Node::Element(el) = no {
            if SKIP_TAGS.contains(&el.tag.as_str()) || nivel >= PROFUNDIDADE_ARVORE {
                continue;
            }
            let info = info_do_elemento(el, &[]);
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

    #[test]
    fn ignored_hide_rules_are_listed() {
        let r = rel("<style>.a ~ .b .c { display: none }</style><p>x</p>");
        assert!(r.contains("REGRAS COM display: none NÃO APLICADAS: 1"));
        assert!(r.contains(".a ~ .b .c"));
    }

    #[test]
    fn attribute_rule_hides_by_attribute() {
        let r = rel("<style>[data-x] { display: none }</style><div data-x=\"1\">abc</div><p>de</p>");
        assert!(r.contains("Oculto por CSS: 3 caracteres"));
        assert!(r.contains("Desenhado: 2 caracteres"));
    }

    #[test]
    fn regra_que_tira_o_texto_da_tela_aparece_no_bloco_visivel() {
        let r = rel("<style>.x { position: absolute; left: -9999px }</style><li class=\"x\">Idioma</li>");
        assert!(r.contains("VISÍVEL no Nusky"));
        assert!(r.contains("left: -9999px"));
    }

    #[test]
    fn regra_de_ancestral_aparece_no_bloco() {
        let r = rel("<style>div.x { text-indent: -9999px }</style><div class=\"x\"><p>abc</p></div>");
        assert!(r.contains("(ancestral div.x)"));
    }

    #[test]
    fn declaracao_suspeita_e_reconhecida() {
        assert!(e_suspeita("text-indent", "-9999px"));
        assert!(e_suspeita("color", "transparent"));
        assert!(e_suspeita("font-size", "0"));
        assert!(!e_suspeita("color", "red"));
        assert!(!e_suspeita("margin", "0 auto"));
    }
}