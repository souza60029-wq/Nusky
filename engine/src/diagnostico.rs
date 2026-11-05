// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Diagnóstico de página.
//! Passa o HTML pelo mesmo parser, CSS e layout do motor e descreve em texto o que aconteceu:
//! quanto texto o HTML tem, quanto foi ocultado por CSS, quanto foi desenhado, quais blocos
//! de texto não chegaram à tela, onde estão os elementos ocultos e quais regras `display: none`
//! o motor não aplicou.
//! Para cada bloco de texto, lista todas as regras que casam com ele, com os ancestrais e com
//! os elementos dentro dele. Para textos curtos visíveis, numera as regras num catálogo, marca
//! as que têm declarações de ocultação e as que o motor ignora.
//! Também inventaria as declarações de ocultação de todo o CSS da página, com a quantidade de
//! regras e se o motor as lê. Usa a mesma lista de irmãos anteriores do layout, para que
//! seletores `+`, `~` e `:first-child` deem o mesmo resultado na tela e no relatório.
//! Só lê: não altera a renderização.

use std::collections::{BTreeMap, HashMap};

use crate::css::{self, Estilo, Folha, Ignorada, Info};
use crate::html::{parse, Element, Node};
use crate::layout::{layout, DrawCommand, TextMeasurer};

/// Elementos que não entram no texto da página (mesma lista do layout).
const SKIP_TAGS: &[&str] = &["head", "script", "style", "title", "noscript"];

/// Blocos cujo texto é conferido um a um.
const BLOCK_TAGS: &[&str] = &[
    "p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "figcaption", "blockquote", "td", "th", "dd", "dt",
];

/// Propriedades que podem esconder texto. Entram no inventário e, quando o motor não as lê,
/// são marcadas no catálogo de regras dos textos curtos.
const PROPRIEDADES_DE_OCULTAR: &[&str] = &[
    "display",
    "visibility",
    "clip",
    "clip-path",
    "transform",
    "filter",
    "opacity",
    "font-size",
    "color",
    "-webkit-text-fill-color",
    "position",
    "left",
    "right",
    "top",
    "bottom",
    "inset",
    "text-indent",
    "width",
    "height",
    "max-width",
    "max-height",
    "overflow",
    "overflow-x",
    "overflow-y",
    "margin",
    "margin-left",
    "margin-right",
    "margin-top",
    "margin-bottom",
    "padding",
    "padding-left",
    "padding-right",
    "padding-top",
    "padding-bottom",
];

const MAX_BLOCOS: usize = 80;
const MAX_OCULTOS: usize = 200;
const MAX_LINHAS_ARVORE: usize = 40;
const PROFUNDIDADE_ARVORE: usize = 4;
const CHARS_EXIBIDOS: usize = 50;
const CHARS_CONFERIDOS: usize = 40;
const LIMITE_TEXTO_QUADRO: usize = 300;
const MAX_IGNORADAS_POR_MOTIVO: usize = 50;
const LIMITE_SELETOR: usize = 200;
const MAX_ACHADOS: usize = 60;
const MAX_BLOCOS_CURTOS: usize = 40;
const LIMITE_TEXTO_CURTO: usize = 40;
const LIMITE_DECLARACAO: usize = 300;
const MAX_GRUPOS_INVENTARIO: usize = 150;
const MAX_EXEMPLOS_INVENTARIO: usize = 5;

/// Uma regra que casa com um elemento, com onde ela casa.
#[derive(Clone)]
struct Achado {
    seletor: String,
    corpo: String,
    /// Onde casa: "próprio", "ancestral div.x" ou "descendente span.y".
    local: String,
}

/// Bloco de texto encontrado no HTML.
struct Bloco {
    caminho: String,
    exibir: String,
    /// Início do texto sem espaços, usado para conferir se foi desenhado.
    chave: String,
    oculto: bool,
    /// Regras do próprio bloco e dos ancestrais. Ordem: o próprio, depois os ancestrais
    /// do mais próximo para o mais distante.
    regras: Vec<Achado>,
    /// Regras dos elementos dentro do bloco (com texto ou não), na ordem em que aparecem.
    descendentes: Vec<Achado>,
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

/// Regra lida direto do texto do CSS, com o @media (ou @supports) que a envolve.
/// Não passa pelo motor: serve para o inventário de todo o CSS.
struct RegraBruta {
    seletor: String,
    midia: String,
    corpo: String,
}

/// Tipo de declaração de ocultação, com quantas regras a usam e alguns exemplos.
struct Grupo {
    quantidade: usize,
    exemplos: Vec<String>,
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

    let regras_css = regras_do_css(&css_texto);

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

    linhas.push(String::new());
    linhas.extend(inventario(&regras_css));

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

    // Blocos com regras (do próprio bloco, de ancestrais ou de elementos dentro dele) que têm
    // declaração de ocultação. Os visíveis vêm primeiro.
    let mut com_regras: Vec<(&Bloco, Vec<String>)> = Vec::new();
    for b in &d.blocos {
        if b.chave.is_empty() {
            continue;
        }
        let mut linhas_bloco: Vec<String> = Vec::new();
        for a in b.regras.iter().chain(b.descendentes.iter()) {
            let sus = declaracoes_suspeitas(&a.corpo);
            if !sus.is_empty() {
                let linha = format!("{}  ({})  →  {}", a.seletor, a.local, sus.join("; "));
                if !linhas_bloco.contains(&linha) {
                    linhas_bloco.push(linha);
                }
            }
        }
        if !linhas_bloco.is_empty() {
            com_regras.push((b, linhas_bloco));
        }
    }
    com_regras.sort_by_key(|(b, _)| if b.oculto { 1u8 } else { 0u8 });

    linhas.push(String::new());
    linhas.push(format!(
        "REGRAS QUE PODEM ESCONDER TEXTO: {} blocos",
        com_regras.len()
    ));
    linhas.push(
        "  Regras do bloco, de ancestrais ou de elementos dentro dele com declaração de ocultação."
            .to_string(),
    );
    linhas.push("  Outra regra pode tê-las desfeito depois; confira no Safari.".to_string());
    for (b, linhas_bloco) in com_regras.iter().take(MAX_ACHADOS) {
        let estado = if b.oculto {
            "oculto no Nusky"
        } else {
            "VISÍVEL no Nusky"
        };
        linhas.push(format!("[{}] {}: \"{}\"", estado, b.caminho, b.exibir));
        for linha in linhas_bloco {
            linhas.push(format!("    {}", linha));
        }
    }
    if com_regras.len() > MAX_ACHADOS {
        linhas.push(format!("… e mais {} blocos", com_regras.len() - MAX_ACHADOS));
    }

    // Textos curtos visíveis (menus, rótulos, títulos). Cada regra recebe um número no catálogo;
    // o bloco lista os números, com o lugar onde a regra casa.
    let curtos: Vec<&Bloco> = d
        .blocos
        .iter()
        .filter(|b| {
            !b.oculto
                && !b.chave.is_empty()
                && (!b.regras.is_empty() || !b.descendentes.is_empty())
                && b.exibir.chars().count() <= LIMITE_TEXTO_CURTO
        })
        .collect();

    let mut catalogo: Vec<(String, String)> = Vec::new();
    let mut indice: HashMap<(String, String), usize> = HashMap::new();
    let mut linhas_blocos: Vec<String> = Vec::new();
    for b in curtos.iter().take(MAX_BLOCOS_CURTOS) {
        linhas_blocos.push(format!("[VISÍVEL no Nusky] {}: \"{}\"", b.caminho, b.exibir));
        let mut ja: Vec<String> = Vec::new();
        for a in b.regras.iter().chain(b.descendentes.iter()) {
            let n = numerar(a, &mut catalogo, &mut indice);
            let linha = format!("    R{}  ({})", n, a.local);
            if !ja.contains(&linha) {
                ja.push(linha.clone());
                linhas_blocos.push(linha);
            }
        }
    }

    linhas.push(String::new());
    linhas.push(format!(
        "REGRAS QUE ATINGEM TEXTOS CURTOS VISÍVEIS: {} blocos",
        curtos.len()
    ));
    linhas.push(
        "  Cada regra tem um número (R1, R2…). Entre parênteses, onde ela casa: próprio, ancestral ou descendente."
            .to_string(),
    );
    linhas.push(
        "  No catálogo: [suspeita] = tem declaração que costuma esconder texto; [motor não lê: …] = propriedades de ocultação que o Nusky ignora."
            .to_string(),
    );
    linhas.extend(linhas_blocos);
    if curtos.len() > MAX_BLOCOS_CURTOS {
        linhas.push(format!("… e mais {} blocos", curtos.len() - MAX_BLOCOS_CURTOS));
    }

    linhas.push(String::new());
    linhas.push(format!(
        "CATÁLOGO DAS REGRAS DOS TEXTOS CURTOS: {} regras",
        catalogo.len()
    ));
    for (n, (seletor, corpo)) in catalogo.iter().enumerate() {
        let suspeita = if declaracoes_suspeitas(corpo).is_empty() {
            ""
        } else {
            " [suspeita]"
        };
        let nao = nao_lidas(corpo);
        let motor = if nao.is_empty() {
            String::new()
        } else {
            format!(" [motor não lê: {}]", nao.join(", "))
        };
        linhas.push(format!(
            "  R{}  {}  →  {}{}{}",
            n + 1,
            seletor,
            cortar(corpo, LIMITE_DECLARACAO),
            suspeita,
            motor
        ));
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

        // Regras do próprio elemento entram em todos os blocos abertos (ele está dentro deles).
        // Vale também para elementos ocultos, que costumam ser a causa do que sumiu.
        if self.tem_css && !self.abertos.is_empty() {
            let de_dentro = self.regras_do_elemento(&info, irmaos);
            for k in 0..self.abertos.len() {
                let idx = self.abertos[k].indice;
                self.blocos[idx]
                    .descendentes
                    .extend(de_dentro.iter().cloned());
            }
        }

        let regras = if e_bloco {
            self.regras_do_bloco(&info, irmaos)
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
                    regras,
                    descendentes: Vec::new(),
                });
            }
            return info;
        }

        if e_bloco {
            self.blocos.push(Bloco {
                caminho,
                exibir: String::new(),
                chave: String::new(),
                oculto: false,
                regras,
                descendentes: Vec::new(),
            });
            let indice = self.blocos.len() - 1;
            self.abertos.push(Quadro {
                indice,
                texto: String::new(),
            });
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

    /// Regras que casam com o bloco e com cada ancestral. O próprio bloco vem primeiro.
    fn regras_do_bloco(&self, info: &Info, irmaos: &[Info]) -> Vec<Achado> {
        let mut saida: Vec<Achado> = Vec::new();
        if !self.tem_css {
            return saida;
        }
        for c in css::regras_casadas(&self.folha, info, &self.pais, irmaos) {
            saida.push(Achado {
                seletor: seletor_exibido(&c.seletor),
                corpo: c.declaracoes,
                local: "próprio".to_string(),
            });
        }
        for (k, anc) in self.pais.iter().enumerate().rev() {
            let local = format!("ancestral {}", rotulo(anc));
            for c in css::regras_casadas(&self.folha, anc, &self.pais[..k], &self.pais_irmaos[k]) {
                saida.push(Achado {
                    seletor: seletor_exibido(&c.seletor),
                    corpo: c.declaracoes,
                    local: local.clone(),
                });
            }
        }
        saida
    }

    /// Regras que casam com um elemento dentro de bloco. Só o próprio elemento;
    /// os ancestrais já entram pela lista do bloco.
    fn regras_do_elemento(&self, info: &Info, irmaos: &[Info]) -> Vec<Achado> {
        let mut saida: Vec<Achado> = Vec::new();
        let local = format!("descendente {}", rotulo(info));
        for c in css::regras_casadas(&self.folha, info, &self.pais, irmaos) {
            saida.push(Achado {
                seletor: seletor_exibido(&c.seletor),
                corpo: c.declaracoes,
                local: local.clone(),
            });
        }
        saida
    }
}

/// Número do catálogo de uma regra. Mesma regra (seletor e declarações) ganha o mesmo número.
fn numerar(
    a: &Achado,
    catalogo: &mut Vec<(String, String)>,
    indice: &mut HashMap<(String, String), usize>,
) -> usize {
    let chave = (a.seletor.clone(), a.corpo.clone());
    if let Some(n) = indice.get(&chave) {
        return *n;
    }
    catalogo.push(chave.clone());
    let n = catalogo.len();
    indice.insert(chave, n);
    n
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

/// Lê todas as regras do CSS, sem passar pelo motor. Entram também as que o motor ignora.
fn regras_do_css(css: &str) -> Vec<RegraBruta> {
    let limpo = tirar_comentarios(css);
    let mut saida = Vec::new();
    varrer_blocos(&limpo, "", &mut saida);
    saida
}

/// Tira comentários /* ... */ do CSS.
fn tirar_comentarios(css: &str) -> String {
    let mut saida = String::with_capacity(css.len());
    let mut resto = css;
    loop {
        match resto.find("/*") {
            Some(i) => {
                saida.push_str(&resto[..i]);
                match resto[i + 2..].find("*/") {
                    Some(j) => resto = &resto[i + 2 + j + 2..],
                    None => break,
                }
            }
            None => {
                saida.push_str(resto);
                break;
            }
        }
    }
    saida
}

/// Percorre um bloco de CSS e junta as regras. Entra em @media e @supports; ignora o resto
/// (@font-face, @keyframes, @import etc.).
fn varrer_blocos(css: &str, midia: &str, saida: &mut Vec<RegraBruta>) {
    let bytes = css.as_bytes();
    let mut inicio = 0;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b';' => {
                inicio = i + 1;
                i += 1;
            }
            b'{' => {
                let cabecalho = css[inicio..i].trim();
                let mut profundidade = 1usize;
                let mut j = i + 1;
                while j < bytes.len() && profundidade > 0 {
                    match bytes[j] {
                        b'{' => profundidade += 1,
                        b'}' => profundidade -= 1,
                        _ => {}
                    }
                    j += 1;
                }
                let fim = if profundidade == 0 { j - 1 } else { bytes.len() };
                let corpo = &css[i + 1..fim];
                if let Some(at) = cabecalho.strip_prefix('@') {
                    let nome = at
                        .split(|c: char| c.is_whitespace() || c == '(')
                        .next()
                        .unwrap_or("");
                    if nome == "media" || nome == "supports" {
                        let nova = if midia.is_empty() {
                            cabecalho.to_string()
                        } else {
                            format!("{} {}", midia, cabecalho)
                        };
                        varrer_blocos(corpo, &nova, saida);
                    }
                } else if !cabecalho.is_empty() {
                    saida.push(RegraBruta {
                        seletor: cabecalho.to_string(),
                        midia: midia.to_string(),
                        corpo: corpo.to_string(),
                    });
                }
                i = j;
                inicio = j;
            }
            _ => i += 1,
        }
    }
}

/// Inventário das declarações de ocultação de todo o CSS: cada tipo aparece uma vez,
/// com a quantidade de regras, se o motor lê e alguns exemplos com o @media.
fn inventario(regras: &[RegraBruta]) -> Vec<String> {
    let mut grupos: BTreeMap<String, Grupo> = BTreeMap::new();
    for regra in regras {
        let sel = seletor_exibido(&regra.seletor);
        let exemplo = if regra.midia.is_empty() {
            sel
        } else {
            format!("{}  [{}]", sel, regra.midia)
        };
        for decl in declaracoes_suspeitas(&regra.corpo) {
            let grupo = grupos.entry(decl).or_insert_with(|| Grupo {
                quantidade: 0,
                exemplos: Vec::new(),
            });
            grupo.quantidade += 1;
            if grupo.exemplos.len() < MAX_EXEMPLOS_INVENTARIO {
                grupo.exemplos.push(exemplo.clone());
            }
        }
    }

    let mut ordenados: Vec<(String, Grupo)> = grupos.into_iter().collect();
    ordenados.sort_by(|a, b| b.1.quantidade.cmp(&a.1.quantidade));

    let mut linhas: Vec<String> = Vec::new();
    linhas.push(format!(
        "DECLARAÇÕES DE OCULTAÇÃO NO CSS: {} tipos",
        ordenados.len()
    ));
    linhas.push(format!(
        "  Regras lidas no CSS da página: {}. Cada tipo aparece uma vez, com a quantidade de regras.",
        regras.len()
    ));
    linhas.push("  motor lê: sim (aplica), parcial (só alguns valores), não (ignora).".to_string());
    for (decl, grupo) in ordenados.iter().take(MAX_GRUPOS_INVENTARIO) {
        let nome = decl.split_once(':').map(|(n, _)| n.trim()).unwrap_or("");
        linhas.push(format!(
            "  {}  ({} regras; motor lê: {})",
            decl,
            grupo.quantidade,
            motor_le(nome)
        ));
        for exemplo in &grupo.exemplos {
            linhas.push(format!("    {}", exemplo));
        }
        if grupo.quantidade > grupo.exemplos.len() {
            linhas.push(format!(
                "    … e mais {}",
                grupo.quantidade - grupo.exemplos.len()
            ));
        }
    }
    if ordenados.len() > MAX_GRUPOS_INVENTARIO {
        linhas.push(format!(
            "  … e mais {} tipos",
            ordenados.len() - MAX_GRUPOS_INVENTARIO
        ));
    }
    linhas.push(String::new());
    linhas
}

/// Diz se o motor lê uma propriedade: "sim", "parcial" (só alguns valores) ou "não".
fn motor_le(nome: &str) -> &'static str {
    match nome {
        "font-size" | "margin" | "margin-top" | "margin-bottom" => "sim",
        "display" | "visibility" | "clip" | "clip-path" | "transform" | "color" => "parcial",
        _ => "não",
    }
}

/// Propriedades de ocultação que a regra usa e o motor não lê, quando a regra parece
/// esconder texto (valor suspeito) ou posiciona o elemento fora do fluxo.
fn nao_lidas(corpo: &str) -> Vec<String> {
    let mut saida: Vec<String> = Vec::new();
    for par in corpo.split(';') {
        let (nome, valor) = match par.split_once(':') {
            Some(x) => x,
            None => continue,
        };
        let nome = nome.trim().to_ascii_lowercase();
        let valor = valor.trim();
        let valor = valor.strip_suffix("!important").unwrap_or(valor).trim();
        let valor = valor.to_ascii_lowercase();
        if !PROPRIEDADES_DE_OCULTAR.contains(&nome.as_str()) || motor_le(&nome) != "não" {
            continue;
        }
        let posiciona = matches!(nome.as_str(), "position" | "overflow" | "overflow-x" | "overflow-y")
            && matches!(valor.as_str(), "absolute" | "fixed" | "hidden");
        if (e_suspeita(&nome, &valor) || posiciona) && !saida.contains(&nome) {
            saida.push(nome);
        }
    }
    saida
}

/// Rótulo curto do elemento: tag, id e primeira classe. Ex.: `div#toc`, `p.x`.
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

/// Texto com espaços normalizados, cortado no limite dado (com reticências).
fn cortar(s: &str, limite: usize) -> String {
    let junto = s.split_whitespace().collect::<Vec<&str>>().join(" ");
    if junto.chars().count() > limite {
        let curto: String = junto.chars().take(limite).collect();
        format!("{}…", curto)
    } else {
        junto
    }
}

/// Seletor com espaços normalizados, cortado para caber numa linha.
fn seletor_exibido(s: &str) -> String {
    cortar(s, LIMITE_SELETOR)
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
        "transform" => {
            v.contains("scale(0") || v.contains("scalex(0") || v.contains("scaley(0") || grande(v)
        }
        "filter" => v.contains("opacity(0)") || v.contains("opacity(0%)"),
        "opacity" | "font-size" => numero(v) == Some(0.0),
        "color" | "-webkit-text-fill-color" => {
            let sem = v.replace(' ', "");
            v == "transparent" || (sem.starts_with("rgba(") && sem.ends_with(",0)"))
        }
        "text-indent" | "left" | "right" | "top" | "bottom" | "inset" | "margin" | "margin-left"
        | "margin-right" | "margin-top" | "margin-bottom" | "padding" | "padding-left"
        | "padding-right" | "padding-top" | "padding-bottom" => grande(v),
        "width" | "height" | "max-width" | "max-height" => {
            numero(v).map_or(false, |n| n <= 1.0)
        }
        _ => false,
    }
}

/// Valor de posicionamento ou recuo grande o bastante para tirar o texto da tela.
fn grande(v: &str) -> bool {
    if v.contains("-999") || v.contains("-100%") {
        return true;
    }
    match numero(v) {
        Some(n) => {
            n.abs() >= 999.0
                || (n.abs() >= 100.0 && (v.ends_with('%') || v.ends_with("vw") || v.ends_with("vh")))
        }
        None => false,
    }
}

/// Número de um valor simples (px, em, rem, pt, vw, vh ou %). Sem unidade também vale.
fn numero(v: &str) -> Option<f32> {
    let limpo = v
        .trim_end_matches("px")
        .trim_end_matches("rem")
        .trim_end_matches("em")
        .trim_end_matches("pt")
        .trim_end_matches("vw")
        .trim_end_matches("vh")
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
            saida.push(format!(
                "{}{} ({} filhos)",
                "  ".repeat(nivel),
                rotulo(&info),
                filhos
            ));
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
    fn regra_de_filho_com_texto_aparece_no_bloco() {
        let r = rel("<style>span.x { position: absolute; left: -9999px }</style><ul><li><span class=\"x\">Idioma</span></li></ul>");
        assert!(r.contains("(descendente span.x)"));
        assert!(r.contains("left: -9999px"));
    }

    #[test]
    fn texto_curto_mostra_todas_as_regras_que_casam() {
        let r = rel("<style>li.x { color: red }</style><ul><li class=\"x\">Idioma</li></ul>");
        assert!(r.contains("REGRAS QUE ATINGEM TEXTOS CURTOS VISÍVEIS: 1 blocos"));
        assert!(r.contains("color: red"));
    }

    #[test]
    fn catalogo_marca_regras_suspeitas_e_nao_lidas() {
        let r = rel("<style>li.x { position: absolute; left: -9999px }</style><ul><li class=\"x\">Idioma</li></ul>");
        assert!(r.contains("CATÁLOGO DAS REGRAS DOS TEXTOS CURTOS"));
        assert!(r.contains("[suspeita]"));
        assert!(r.contains("[motor não lê: position, left]"));
    }

    #[test]
    fn inventario_lista_declaracoes_de_ocultacao_com_midia() {
        let r = rel("<style>@media print { .a { display: none } } .b { left: -9999px }</style><p>x</p>");
        assert!(r.contains("DECLARAÇÕES DE OCULTAÇÃO NO CSS"));
        assert!(r.contains("display: none"));
        assert!(r.contains("[@media print]"));
        assert!(r.contains("left: -9999px"));
    }

    #[test]
    fn comentarios_nao_entram_no_inventario() {
        let r = rel("<style>/* .x { left: -9999px } */ .y { color: red }</style><p>a</p>");
        assert!(!r.contains("left: -9999px"));
    }

    #[test]
    fn declaracao_suspeita_e_reconhecida() {
        assert!(e_suspeita("text-indent", "-9999px"));
        assert!(e_suspeita("left", "calc(-9999px)"));
        assert!(e_suspeita("left", "100vw"));
        assert!(e_suspeita("color", "transparent"));
        assert!(e_suspeita("font-size", "0"));
        assert!(e_suspeita("filter", "opacity(0)"));
        assert!(!e_suspeita("color", "red"));
        assert!(!e_suspeita("margin", "0 auto"));
        assert!(!e_suspeita("width", "100%"));
    }
}