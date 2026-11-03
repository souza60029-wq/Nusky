//! CSS básico: lê folhas de estilo e calcula o estilo de cada elemento.
//!
//! Suporta seletores simples (`p`, `.classe`, `#id`, `p.classe`, listas com vírgula)
//! e as propriedades: color, font-size, font-weight, margin, margin-top,
//! margin-bottom e display (só `none`). Seletores compostos (`div p`, `a:hover`)
//! são ignorados sem afetar o restante da folha.
//!
//! Este módulo ainda não está ligado ao layout.

/// Seletor simples: tipo, id e classes.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Simples {
    pub tag: Option<String>,
    pub id: Option<String>,
    pub classes: Vec<String>,
}

impl Simples {
    /// Peso da regra: id vale mais que classe, classe mais que tipo.
    fn especificidade(&self) -> u32 {
        let ids = self.id.is_some() as u32;
        let classes = self.classes.len() as u32;
        let tags = self.tag.is_some() as u32;
        ids * 10_000 + classes * 100 + tags
    }
}

/// Estilo calculado de um elemento. `None` significa "não definido".
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Estilo {
    pub cor: Option<[u8; 3]>,
    pub tamanho: Option<f32>,
    pub negrito: Option<bool>,
    pub margem_topo: Option<f32>,
    pub margem_base: Option<f32>,
    pub oculto: bool,
}

#[derive(Debug, Clone)]
struct Regra {
    seletor: Simples,
    declaracoes: Vec<(String, String)>,
    ordem: usize,
}

/// Folha de estilo já analisada.
#[derive(Debug, Clone, Default)]
pub struct Folha {
    regras: Vec<Regra>,
}

impl Folha {
    pub fn parse(css: &str) -> Folha {
        let limpo = remover_comentarios(css);
        let mut regras = Vec::new();
        for bloco in limpo.split('}') {
            let Some((seletores, corpo)) = bloco.split_once('{') else {
                continue;
            };
            let declaracoes = parse_declaracoes(corpo);
            for parte in seletores.split(',') {
                if let Some(seletor) = parse_simples(parte) {
                    let ordem = regras.len();
                    regras.push(Regra {
                        seletor,
                        declaracoes: declaracoes.clone(),
                        ordem,
                    });
                }
            }
        }
        Folha { regras }
    }
}

impl Estilo {
    fn aplicar(&mut self, propriedade: &str, valor: &str) {
        match propriedade {
            "color" => {
                if let Some(c) = parse_cor(valor) {
                    self.cor = Some(c);
                }
            }
            "font-size" => {
                if let Some(p) = parse_px(valor) {
                    self.tamanho = Some(p);
                }
            }
            "font-weight" => {
                let novo = match valor {
                    "bold" | "bolder" => Some(true),
                    "normal" | "lighter" => Some(false),
                    _ => valor.parse::<u32>().ok().map(|n| n >= 600),
                };
                if novo.is_some() {
                    self.negrito = novo;
                }
            }
            "margin" => {
                if let Some(p) = parse_px(valor) {
                    self.margem_topo = Some(p);
                    self.margem_base = Some(p);
                }
            }
            "margin-top" => {
                if let Some(p) = parse_px(valor) {
                    self.margem_topo = Some(p);
                }
            }
            "margin-bottom" => {
                if let Some(p) = parse_px(valor) {
                    self.margem_base = Some(p);
                }
            }
            "display" => self.oculto = valor.eq_ignore_ascii_case("none"),
            _ => {}
        }
    }
}

/// Calcula o estilo de um elemento. Ordem: folha por especificidade, depois o estilo inline.
pub fn estilo_para(
    folha: &Folha,
    tag: &str,
    id: Option<&str>,
    classes: &[&str],
    inline: Option<&str>,
) -> Estilo {
    let mut casadas: Vec<&Regra> = folha
        .regras
        .iter()
        .filter(|r| casa(&r.seletor, tag, id, classes))
        .collect();
    casadas.sort_by(|a, b| {
        a.seletor
            .especificidade()
            .cmp(&b.seletor.especificidade())
            .then(a.ordem.cmp(&b.ordem))
    });

    let mut estilo = Estilo::default();
    for regra in casadas {
        for (k, v) in &regra.declaracoes {
            estilo.aplicar(k, v);
        }
    }
    if let Some(texto) = inline {
        for (k, v) in parse_declaracoes(texto) {
            estilo.aplicar(&k, &v);
        }
    }
    estilo
}

fn casa(s: &Simples, tag: &str, id: Option<&str>, classes: &[&str]) -> bool {
    if let Some(t) = &s.tag {
        if !t.eq_ignore_ascii_case(tag) {
            return false;
        }
    }
    if let Some(sid) = &s.id {
        if id != Some(sid.as_str()) {
            return false;
        }
    }
    s.classes
        .iter()
        .all(|c| classes.iter().any(|x| *x == c.as_str()))
}

fn remover_comentarios(css: &str) -> String {
    let mut saida = String::with_capacity(css.len());
    let mut resto = css;
    while let Some(inicio) = resto.find("/*") {
        saida.push_str(&resto[..inicio]);
        match resto[inicio + 2..].find("*/") {
            Some(fim) => resto = &resto[inicio + 2 + fim + 2..],
            None => return saida,
        }
    }
    saida.push_str(resto);
    saida
}

fn parse_simples(texto: &str) -> Option<Simples> {
    let t = texto.trim();
    if t.is_empty()
        || t
            .chars()
            .any(|c| c.is_whitespace() || matches!(c, '>' | '+' | '~' | ':' | '[' | '*' | '@'))
    {
        return None;
    }

    let mut simples = Simples::default();
    let inicio = t.find(|c: char| c == '.' || c == '#').unwrap_or(t.len());
    if inicio > 0 {
        let tipo = &t[..inicio];
        if !tipo.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
            return None;
        }
        simples.tag = Some(tipo.to_ascii_lowercase());
    }

    let mut resto = &t[inicio..];
    while let Some(marca) = resto.chars().next() {
        let corpo = &resto[1..];
        let fim = corpo
            .find(|c: char| c == '.' || c == '#')
            .unwrap_or(corpo.len());
        let nome = &corpo[..fim];
        if nome.is_empty()
            || !nome
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        {
            return None;
        }
        match marca {
            '.' => simples.classes.push(nome.to_string()),
            '#' if simples.id.is_none() => simples.id = Some(nome.to_string()),
            _ => return None,
        }
        resto = &corpo[fim..];
    }

    if simples.tag.is_none() && simples.id.is_none() && simples.classes.is_empty() {
        None
    } else {
        Some(simples)
    }
}

fn parse_declaracoes(corpo: &str) -> Vec<(String, String)> {
    corpo
        .split(';')
        .filter_map(|declaracao| {
            let (propriedade, valor) = declaracao.split_once(':')?;
            let propriedade = propriedade.trim().to_ascii_lowercase();
            let valor = valor.replace("!important", "").trim().to_string();
            let nome_valido = !propriedade.is_empty()
                && propriedade
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-');
            if nome_valido && !valor.is_empty() {
                Some((propriedade, valor))
            } else {
                None
            }
        })
        .collect()
}

fn parse_cor(valor: &str) -> Option<[u8; 3]> {
    let v = valor.trim().to_ascii_lowercase();
    let nomeada = match v.as_str() {
        "black" => Some([0, 0, 0]),
        "white" => Some([255, 255, 255]),
        "red" => Some([255, 0, 0]),
        "green" => Some([0, 128, 0]),
        "blue" => Some([0, 0, 255]),
        "gray" | "grey" => Some([128, 128, 128]),
        _ => None,
    };
    if nomeada.is_some() {
        return nomeada;
    }

    let hex = v.strip_prefix('#')?;
    if !hex.is_ascii() {
        return None;
    }
    let digitos: Vec<u8> = hex
        .chars()
        .map(|c| c.to_digit(16).map(|d| d as u8))
        .collect::<Option<Vec<u8>>>()?;
    match digitos.as_slice() {
        &[r, g, b] => Some([r * 17, g * 17, b * 17]),
        &[r1, r2, g1, g2, b1, b2] => Some([r1 * 16 + r2, g1 * 16 + g2, b1 * 16 + b2]),
        _ => None,
    }
}

fn parse_px(valor: &str) -> Option<f32> {
    let v = valor.trim();
    let numero = v.strip_suffix("px").unwrap_or(v).trim();
    let n: f32 = numero.parse().ok()?;
    (n.is_finite() && n >= 0.0).then_some(n)
}

#[cfg(test)]
mod testes {
    use super::*;

    fn estilo(css: &str, tag: &str) -> Estilo {
        estilo_para(&Folha::parse(css), tag, None, &[], None)
    }

    #[test]
    fn aplica_cor_tamanho_e_negrito_por_tipo() {
        let e = estilo("p { color: #f00; font-size: 20px; font-weight: bold }", "p");
        assert_eq!(e.cor, Some([255, 0, 0]));
        assert_eq!(e.tamanho, Some(20.0));
        assert_eq!(e.negrito, Some(true));
    }

    #[test]
    fn classe_vence_tipo_mesmo_vindo_antes() {
        let css = ".destaque { color: blue } p { color: black }";
        let e = estilo_para(&Folha::parse(css), "p", None, &["destaque"], None);
        assert_eq!(e.cor, Some([0, 0, 255]));
    }

    #[test]
    fn id_vence_classe() {
        let css = "#topo { color: red } .x { color: blue }";
        let e = estilo_para(&Folha::parse(css), "div", Some("topo"), &["x"], None);
        assert_eq!(e.cor, Some([255, 0, 0]));
    }

    #[test]
    fn estilo_inline_vence_a_folha() {
        let e = estilo_para(
            &Folha::parse("p { color: red }"),
            "p",
            None,
            &[],
            Some("color: green"),
        );
        assert_eq!(e.cor, Some([0, 128, 0]));
    }

    #[test]
    fn display_none_oculta() {
        assert!(estilo("nav { display: none }", "nav").oculto);
        assert!(!estilo("nav { display: none }", "p").oculto);
    }

    #[test]
    fn margens_em_px() {
        let e = estilo("p { margin: 8px; margin-bottom: 12px }", "p");
        assert_eq!(e.margem_topo, Some(8.0));
        assert_eq!(e.margem_base, Some(12.0));
    }

    #[test]
    fn ignora_seletor_composto_e_comentarios() {
        let css = "/* cabecalho */ div p { color: red } a:hover { color: red } span { color: blue }";
        assert_eq!(estilo(css, "p").cor, None);
        assert_eq!(estilo(css, "span").cor, Some([0, 0, 255]));
    }

    #[test]
    fn valores_invalidos_sao_ignorados() {
        let e = estilo("p { font-size: 2em; color: #zz0 }", "p");
        assert_eq!(e.tamanho, None);
        assert_eq!(e.cor, None);
    }

    #[test]
    fn lista_de_seletores() {
        let css = "h1, h2 { font-weight: bold }";
        assert_eq!(estilo(css, "h2").negrito, Some(true));
        assert_eq!(estilo(css, "h1").negrito, Some(true));
    }
}