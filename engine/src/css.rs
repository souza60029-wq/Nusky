// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Motor de CSS do Nusky.
//!
//! Suporta: seletores de tipo, `.classe`, `#id`, `*`, listas com vírgula,
//! atributos (`[a]`, `[a=v]`, `[a~=v]`, `[a|=v]`, `[a^=v]`, `[a$=v]`, `[a*=v]`),
//! descendente, `>`, `+` e `~` (só ao lado do alvo), `:not(...)`,
//! `:first-child` (só no alvo ou no irmão ao lado) e `:last-child` (só no alvo).
//! Pseudo de interação (hover, focus etc.) nunca casa.
//! `@media` por largura, com px, em e calc(a + b) / calc(a - b).
//! Esconde texto com `display: none`, `visibility: hidden`, `clip` de área
//! zero (texto de leitor de tela), `clip-path: inset(50%)` e
//! `transform: translate(-100%)` (gaveta fora da tela).
//! Regras com `display: none` que o motor não aplica ficam em `ignoradas`.
//! `regras_casadas` devolve, para o diagnóstico, as regras que casam com um
//! elemento e o texto das suas declarações. Não altera a renderização.
//! `:last-child` precisa saber se o elemento é o último da lista. Quem não
//! informa isso (`estilo_completo`, `regras_casadas`) faz a regra não casar;
//! quem informa usa `estilo_completo_ultimo` ou `regras_casadas_ultimo`.

use std::borrow::Cow;
use std::collections::HashMap;

const ERRO_COMPOSTO: &str = "seletor não suportado (combinador ou composto)";

/// Informações de um elemento usadas pelo CSS.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Info {
    pub tag: String,
    pub id: String,
    pub classes: Vec<String>,
    pub atributos: Vec<(String, String)>,
}

/// Como o elemento se comporta na página (só o que o motor entende).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Display {
    /// block, grid, list-item, flow-root: começa uma linha nova.
    Bloco,
    /// flex: os filhos ficam lado a lado (ou um sobre o outro, se `coluna`).
    Flex,
    /// inline, inline-block, inline-flex, contents: segue o fluxo do texto.
    Linha,
}

/// Estilo final de um elemento.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Estilo {
    pub tamanho: Option<f32>,
    pub negrito: Option<bool>,
    pub margem_topo: Option<f32>,
    pub margem_base: Option<f32>,
    pub cor: Option<(u8, u8, u8)>,
    /// Verdadeiro quando a página pediu `color: inherit` (ou currentcolor).
    pub cor_herdada: bool,
    pub oculto: bool,
    /// Cor de fundo sólida (translúcida ou transparente vira None).
    pub fundo: Option<(u8, u8, u8)>,
    pub display: Option<Display>,
    /// `flex-direction: column`.
    pub coluna: Option<bool>,
    /// `gap`, em pontos.
    pub espaco: Option<f32>,
    /// `justify-content`: 0 início, 1 centro, 2 fim, 3 espaço entre.
    pub justificar: Option<u8>,
    /// `text-align`: 0 esquerda, 1 centro, 2 direita.
    pub alinhamento: Option<u8>,
    pub pad_topo: Option<f32>,
    pub pad_base: Option<f32>,
    pub pad_esq: Option<f32>,
    pub pad_dir: Option<f32>,
    pub borda_largura: Option<f32>,
    /// Some(None) = borda transparente.
    pub borda_cor: Option<Option<(u8, u8, u8)>>,
    pub raio: Option<f32>,
    /// `width` em pontos (só valores absolutos: px, rem, em). Porcentagem e auto ficam None.
    pub largura: Option<f32>,
    /// `height` em pontos, com a mesma regra de `largura`.
    pub altura: Option<f32>,
    /// `font-style: italic` (ou oblique).
    pub italico: Option<bool>,
    /// A primeira fonte reconhecida da lista de `font-family` tem serifa (Georgia, Times, `serif`).
    pub serifa: Option<bool>,
}

/// Regra que o motor não aplicou, com o motivo.
#[derive(Debug, Clone)]
pub struct Ignorada {
    pub seletor: String,
    pub motivo: String,
}

/// Regra que casa com um elemento, com o texto original das declarações.
/// Usada pelo diagnóstico para mostrar a regra que esconde (ou deveria esconder) o texto.
#[derive(Debug, Clone)]
pub struct Casada {
    pub seletor: String,
    pub declaracoes: String,
}

/// Folha de estilo já analisada.
#[derive(Debug, Default)]
pub struct Folha {
    regras: Vec<Regra>,
    indice: Indice,
    pub ignoradas: Vec<Ignorada>,
    usa_irmaos: bool,
    nomes_atributos: Vec<String>,
    /// Propriedades personalizadas (`--nome`) que valem na raiz da página.
    vars: HashMap<String, String>,
    /// Verdadeiro na primeira leitura, que só colhe as propriedades personalizadas.
    fase_vars: bool,
    regras_vars: Vec<RegraVars>,
}

/// Propriedades personalizadas de uma regra, com o seletor que as aplica.
#[derive(Debug)]
struct RegraVars {
    seletor: Seletor,
    vars: Vec<(String, String)>,
}

impl Folha {
    /// Analisa com a largura padrão de 375 pt.
    pub fn parse(css: &str) -> Folha {
        Folha::parse_largura(css, 375.0)
    }

    /// Analisa escolhendo os `@media` pela largura informada.
    pub fn parse_largura(css: &str, largura: f32) -> Folha {
        let raiz = Info { tag: "html".to_string(), ..Info::default() };
        Folha::parse_com_raiz(css, largura, &raiz)
    }

    /// Analisa sabendo qual é o elemento raiz (`html`), para escolher quais
    /// propriedades personalizadas (`--cor: ...`) valem. `var(--cor)` é trocado
    /// pelo valor na hora da leitura. Só vale o que está declarado na raiz.
    pub fn parse_com_raiz(css: &str, largura: f32, raiz: &Info) -> Folha {
        let mut f = Folha::default();
        if css.contains("--") {
            f.fase_vars = true;
            analisa(css, largura, &mut f, None);
            f.fase_vars = false;
            let mut valem: Vec<(u32, usize)> = f
                .regras_vars
                .iter()
                .enumerate()
                .filter(|(_, r)| casa_seletor(&r.seletor, raiz, &[], &[], false))
                .map(|(i, r)| (r.seletor.especificidade, i))
                .collect();
            valem.sort_unstable();
            let mut mapa: HashMap<String, String> = HashMap::new();
            for (_, i) in valem {
                for (nome, valor) in &f.regras_vars[i].vars {
                    mapa.insert(nome.clone(), valor.clone());
                }
            }
            f.vars = mapa;
            f.regras_vars = Vec::new();
        }
        analisa(css, largura, &mut f, None);
        for (i, r) in f.regras.iter().enumerate() {
            indexa(&mut f.indice, &r.seletor, i);
        }
        f.nomes_atributos.sort();
        f.nomes_atributos.dedup();
        f
    }

    /// Verdadeiro se algum seletor usa irmãos ou `:first-child`.
    pub fn precisa_irmaos(&self) -> bool {
        self.usa_irmaos
    }

    /// Nomes de atributo usados nos seletores (em minúsculas).
    pub fn nomes_atributos(&self) -> &[String] {
        &self.nomes_atributos
    }
}

/// Diz se a lista de `font-family` pede uma fonte com serifa. Vale a primeira fonte conhecida;
/// nomes que o motor não conhece (fontes próprias do site) são pulados.
/// Devolve None quando nenhuma fonte da lista é conhecida.
fn familia_com_serifa(valor: &str) -> Option<bool> {
    const COM_SERIFA: [&str; 9] = [
        "serif", "ui-serif", "georgia", "times", "times new roman", "cambria", "palatino", "garamond", "baskerville",
    ];
    const SEM_SERIFA: [&str; 11] = [
        "sans-serif", "ui-sans-serif", "system-ui", "-apple-system", "helvetica", "helvetica neue", "arial", "inter",
        "roboto", "verdana", "ui-monospace",
    ];
    for parte in valor.split(',') {
        let nome = parte.trim().trim_matches(|c| c == '"' || c == '\'').trim().to_ascii_lowercase();
        if COM_SERIFA.contains(&nome.as_str()) {
            return Some(true);
        }
        if SEM_SERIFA.contains(&nome.as_str()) {
            return Some(false);
        }
    }
    None
}

/// Estilo de um elemento sem pais nem irmãos.
pub fn estilo_para(
    folha: &Folha,
    tag: &str,
    id: &str,
    classes: &[String],
    inline: Option<&str>,
) -> Estilo {
    let alvo = Info {
        tag: tag.to_string(),
        id: id.to_string(),
        classes: classes.to_vec(),
        atributos: Vec::new(),
    };
    estilo_completo(folha, &alvo, &[], &[], inline)
}

/// Estilo de um elemento com pais, sem irmãos.
pub fn estilo_com_pais(
    folha: &Folha,
    alvo: &Info,
    pais: &[Info],
    inline: Option<&str>,
) -> Estilo {
    estilo_completo(folha, alvo, pais, &[], inline)
}

/// Estilo completo. `pais` vai da raiz até o pai. `irmaos` vai do primeiro
/// até o irmão imediatamente anterior. Sem informação sobre o fim da lista,
/// `:last-child` não casa; para isso, use `estilo_completo_ultimo`.
pub fn estilo_completo(
    folha: &Folha,
    alvo: &Info,
    pais: &[Info],
    irmaos: &[Info],
    inline: Option<&str>,
) -> Estilo {
    estilo_completo_ultimo(folha, alvo, pais, irmaos, false, inline)
}

/// Como `estilo_completo`, mas informa se o elemento é o último elemento do pai.
pub fn estilo_completo_ultimo(
    folha: &Folha,
    alvo: &Info,
    pais: &[Info],
    irmaos: &[Info],
    e_ultimo: bool,
    inline: Option<&str>,
) -> Estilo {
    let cand = casam(folha, alvo, pais, irmaos, e_ultimo);
    let mut d = Decl::default();
    for &i in &cand {
        aplica(&mut d, &folha.regras[i].decl);
    }
    if let Some(texto) = inline {
        aplica(&mut d, &declaracoes_com(texto, &folha.vars));
    }
    para_estilo(d)
}

/// Regras que casam com o elemento, na ordem em que são aplicadas.
/// Não inclui o `style` do próprio elemento. Sem informação sobre o fim da
/// lista, `:last-child` não casa; para isso, use `regras_casadas_ultimo`.
pub fn regras_casadas(folha: &Folha, alvo: &Info, pais: &[Info], irmaos: &[Info]) -> Vec<Casada> {
    regras_casadas_ultimo(folha, alvo, pais, irmaos, false)
}

/// Como `regras_casadas`, mas informa se o elemento é o último elemento do pai.
pub fn regras_casadas_ultimo(
    folha: &Folha,
    alvo: &Info,
    pais: &[Info],
    irmaos: &[Info],
    e_ultimo: bool,
) -> Vec<Casada> {
    casam(folha, alvo, pais, irmaos, e_ultimo)
        .into_iter()
        .map(|i| Casada {
            seletor: folha.regras[i].origem.clone(),
            declaracoes: folha.regras[i].corpo.clone(),
        })
        .collect()
}

/// Índices das regras que casam com o elemento, em ordem de especificidade.
fn casam(folha: &Folha, alvo: &Info, pais: &[Info], irmaos: &[Info], e_ultimo: bool) -> Vec<usize> {
    let ind = &folha.indice;
    let mut cand: Vec<usize> = Vec::new();
    if !alvo.id.is_empty() {
        if let Some(v) = ind.ids.get(alvo.id.as_str()) {
            cand.extend_from_slice(v);
        }
    }
    for c in &alvo.classes {
        if let Some(v) = ind.classes.get(c.as_str()) {
            cand.extend_from_slice(v);
        }
    }
    let tag = alvo.tag.to_ascii_lowercase();
    if let Some(v) = ind.tags.get(tag.as_str()) {
        cand.extend_from_slice(v);
    }
    cand.extend_from_slice(&ind.universais);
    cand.sort_unstable();
    cand.dedup();
    cand.retain(|&i| casa_seletor(&folha.regras[i].seletor, alvo, pais, irmaos, e_ultimo));
    cand.sort_by_key(|&i| (folha.regras[i].seletor.especificidade, i));
    cand
}

// ---------------------------------------------------------------------------
// Estruturas internas
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, Default)]
struct Decl {
    tamanho: Option<f32>,
    negrito: Option<bool>,
    margem_topo: Option<f32>,
    margem_base: Option<f32>,
    cor: Option<(u8, u8, u8)>,
    oculto: Option<bool>,
    /// `true` quando visibility, clip, clip-path ou transform escondem o texto.
    escondido_visual: Option<bool>,
    cor_herdada: Option<bool>,
    /// Some(None) = fundo transparente (desfaz um fundo anterior).
    fundo: Option<Option<(u8, u8, u8)>>,
    display: Option<Display>,
    coluna: Option<bool>,
    espaco: Option<f32>,
    justificar: Option<u8>,
    alinhamento: Option<u8>,
    pad_topo: Option<f32>,
    pad_base: Option<f32>,
    pad_esq: Option<f32>,
    pad_dir: Option<f32>,
    borda_largura: Option<f32>,
    borda_cor: Option<Option<(u8, u8, u8)>>,
    raio: Option<f32>,
    largura: Option<f32>,
    altura: Option<f32>,
    italico: Option<bool>,
    serifa: Option<bool>,
}

#[derive(Debug)]
struct Regra {
    seletor: Seletor,
    decl: Decl,
    /// Texto do seletor, como foi escrito (um por regra, depois da vírgula).
    origem: String,
    /// Declarações com espaços normalizados, para o diagnóstico.
    corpo: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Combinador {
    Descendente,
    Filho,
    Adjacente,
    Geral,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum OperadorAtributo {
    Existe,
    Igual,
    Palavra,
    Traco,
    Prefixo,
    Sufixo,
    Contem,
}

#[derive(Debug)]
struct Atributo {
    nome: String,
    op: OperadorAtributo,
    valor: String,
}

#[derive(Debug, Default)]
struct Simples {
    tag: Option<String>,
    id: Option<String>,
    classes: Vec<String>,
    atributos: Vec<Atributo>,
    primeiro_filho: bool,
    ultimo_filho: bool,
    negados: Vec<Simples>,
}

#[derive(Debug)]
struct Seletor {
    alvo: Simples,
    anteriores: Vec<(Combinador, Simples)>,
    especificidade: u32,
    usa_irmaos: bool,
}

#[derive(Debug, Default)]
struct Indice {
    ids: HashMap<String, Vec<usize>>,
    classes: HashMap<String, Vec<usize>>,
    tags: HashMap<String, Vec<usize>>,
    universais: Vec<usize>,
}

enum Token {
    Atomo(String),
    Comb(Combinador),
}

// ---------------------------------------------------------------------------
// Análise do arquivo
// ---------------------------------------------------------------------------

fn analisa(texto: &str, largura: f32, f: &mut Folha, media: Option<(&str, bool)>) {
    let limpo = remove_comentarios(texto);
    let mut resto: &str = &limpo;
    loop {
        resto = resto.trim_start();
        if resto.is_empty() {
            break;
        }
        if let Some(depois_arroba) = resto.strip_prefix('@') {
            let fim_nome = depois_arroba
                .find(|c: char| c == '{' || c == ';' || c.is_whitespace())
                .unwrap_or(depois_arroba.len());
            let nome = depois_arroba[..fim_nome].to_ascii_lowercase();
            let resto_nome = &depois_arroba[fim_nome..];
            let p = match resto_nome.find(|c: char| c == '{' || c == ';') {
                Some(p) => p,
                None => break,
            };
            let prelude = resto_nome[..p].trim();
            if resto_nome[p..].starts_with(';') {
                resto = &resto_nome[p + 1..];
                continue;
            }
            let (corpo, depois) = corpo_bloco(&resto_nome[p..]);
            resto = depois;
            if nome == "media" {
                let externa = media.map_or(true, |(_, a)| a);
                let ativa = externa && media_casa(prelude, largura);
                analisa(corpo, largura, f, Some((prelude, ativa)));
            }
        } else {
            let p = match resto.find('{') {
                Some(p) => p,
                None => break,
            };
            let seletor_txt = resto[..p].trim();
            let (corpo, depois) = corpo_bloco(&resto[p..]);
            resto = depois;
            regra(seletor_txt, corpo, largura, f, media);
        }
    }
}

fn regra(
    seletor_txt: &str,
    corpo: &str,
    largura: f32,
    f: &mut Folha,
    media: Option<(&str, bool)>,
) {
    if f.fase_vars {
        coletar_vars_da_regra(seletor_txt, corpo, f, media);
        return;
    }
    let decl = declaracoes_com(corpo, &f.vars);
    let corpo_limpo = corpo.split_whitespace().collect::<Vec<&str>>().join(" ");
    let oculta = decl.oculto == Some(true);
    let ativa = media.map_or(true, |(_, a)| a);
    for parte in divide_seletores(seletor_txt) {
        let parte = parte.trim();
        if parte.is_empty() {
            continue;
        }
        if !ativa {
            if oculta {
                let motivo = format!(
                    "@media {} não casa com {} pt",
                    media.map_or("", |(p, _)| p),
                    largura
                );
                f.ignoradas.push(Ignorada {
                    seletor: parte.to_string(),
                    motivo,
                });
            }
            continue;
        }
        match parse_seletor(&normaliza_raiz(parte)) {
            Ok(s) => {
                if s.usa_irmaos {
                    f.usa_irmaos = true;
                }
                colhe_atributos(&s, &mut f.nomes_atributos);
                f.regras.push(Regra {
                    seletor: s,
                    decl,
                    origem: parte.to_string(),
                    corpo: corpo_limpo.clone(),
                });
            }
            Err(m) => {
                if oculta {
                    f.ignoradas.push(Ignorada {
                        seletor: parte.to_string(),
                        motivo: m,
                    });
                }
            }
        }
    }
}

/// `s` começa com `{`. Devolve (conteúdo, resto depois do `}` final).
fn corpo_bloco(s: &str) -> (&str, &str) {
    let mut prof = 0usize;
    for (i, c) in s.char_indices() {
        if c == '{' {
            prof += 1;
        } else if c == '}' {
            prof -= 1;
            if prof == 0 {
                return (&s[1..i], &s[i + 1..]);
            }
        }
    }
    (&s[1..], "")
}

fn remove_comentarios(s: &str) -> String {
    let mut saida = String::with_capacity(s.len());
    let mut resto = s;
    while let Some(i) = resto.find("/*") {
        saida.push_str(&resto[..i]);
        match resto[i + 2..].find("*/") {
            Some(f) => resto = &resto[i + 2 + f + 2..],
            None => {
                resto = "";
                break;
            }
        }
    }
    saida.push_str(resto);
    saida
}

/// Divide a lista de seletores por vírgula, sem cortar dentro de `()`, `[]` ou aspas.
fn divide_seletores(texto: &str) -> Vec<&str> {
    let mut partes = Vec::new();
    let mut inicio = 0;
    let mut prof = 0i32;
    let mut aspas: Option<char> = None;
    for (i, c) in texto.char_indices() {
        if let Some(q) = aspas {
            if c == q {
                aspas = None;
            }
            continue;
        }
        match c {
            '"' | '\'' => aspas = Some(c),
            '(' | '[' => prof += 1,
            ')' | ']' => prof -= 1,
            ',' if prof == 0 => {
                partes.push(&texto[inicio..i]);
                inicio = i + 1;
            }
            _ => {}
        }
    }
    partes.push(&texto[inicio..]);
    partes
}

// ---------------------------------------------------------------------------
// Declarações e valores
// ---------------------------------------------------------------------------

#[cfg(test)]
fn declaracoes(texto: &str) -> Decl {
    declaracoes_com(texto, &HashMap::new())
}

fn declaracoes_com(texto: &str, vars: &HashMap<String, String>) -> Decl {
    let mut d = Decl::default();
    for par in texto.split(';') {
        let (nome, valor) = match par.split_once(':') {
            Some(x) => x,
            None => continue,
        };
        let nome = nome.trim().to_ascii_lowercase();
        let mut valor = valor.trim();
        if let Some(sem) = valor.strip_suffix("!important") {
            valor = sem.trim_end();
        }
        let valor_final: Cow<str> = if valor.contains("var(") {
            match substituir_vars(valor, vars) {
                Some(s) => Cow::Owned(s),
                None => continue,
            }
        } else {
            Cow::Borrowed(valor)
        };
        let valor: &str = &valor_final;
        match nome.as_str() {
            "font-size" => {
                if let Some(v) = comprimento(valor) {
                    d.tamanho = Some(v);
                }
            }
            "font-style" => {
                let v = valor.trim().to_ascii_lowercase();
                if v == "italic" || v.starts_with("oblique") {
                    d.italico = Some(true);
                } else if v == "normal" {
                    d.italico = Some(false);
                }
            }
            "font-family" => {
                d.serifa = familia_com_serifa(valor);
            }
            "font-weight" => {
                if let Some(v) = peso(valor) {
                    d.negrito = Some(v);
                }
            }
            "margin-top" => {
                if let Some(v) = comprimento(valor) {
                    d.margem_topo = Some(v);
                }
            }
            "margin-bottom" => {
                if let Some(v) = comprimento(valor) {
                    d.margem_base = Some(v);
                }
            }
            "margin" => {
                let vals: Vec<Option<f32>> = valor.split_whitespace().map(comprimento).collect();
                let (topo, base) = match vals.len() {
                    1 | 2 => (vals[0], vals[0]),
                    3 | 4 => (vals[0], vals[2]),
                    _ => (None, None),
                };
                if let Some(v) = topo {
                    d.margem_topo = Some(v);
                }
                if let Some(v) = base {
                    d.margem_base = Some(v);
                }
            }
            "display" => {
                d.oculto = Some(valor.eq_ignore_ascii_case("none"));
                d.display = match valor.to_ascii_lowercase().as_str() {
                    "block" | "grid" | "list-item" | "flow-root" => Some(Display::Bloco),
                    "flex" => Some(Display::Flex),
                    "inline" | "inline-block" | "inline-flex" | "inline-grid" | "contents" => {
                        Some(Display::Linha)
                    }
                    _ => None,
                };
            }
            "flex-direction" => {
                let v = valor.to_ascii_lowercase();
                if v.starts_with("column") {
                    d.coluna = Some(true);
                } else if v.starts_with("row") {
                    d.coluna = Some(false);
                }
            }
            "width" => {
                d.largura = comprimento(valor).filter(|v| *v >= 0.0);
            }
            "height" => {
                d.altura = comprimento(valor).filter(|v| *v >= 0.0);
            }
            "gap" | "column-gap" | "row-gap" => {
                let vals = dividir_valores(valor);
                if let Some(v) = vals.first().and_then(|t| comprimento(t)) {
                    d.espaco = Some(v);
                }
            }
            "justify-content" => {
                d.justificar = match valor.to_ascii_lowercase().as_str() {
                    "center" => Some(1),
                    "flex-end" | "end" | "right" => Some(2),
                    "space-between" | "space-around" | "space-evenly" => Some(3),
                    "flex-start" | "start" | "left" | "normal" => Some(0),
                    _ => None,
                };
            }
            "text-align" => {
                d.alinhamento = match valor.to_ascii_lowercase().as_str() {
                    "center" => Some(1),
                    "right" | "end" => Some(2),
                    "left" | "start" => Some(0),
                    _ => None,
                };
            }
            "opacity" => {
                if let Ok(n) = valor.trim().parse::<f32>() {
                    if n <= 0.0 {
                        d.escondido_visual = Some(true);
                    }
                }
            }
            "background-color" => {
                if let Some((r, g, b, a)) = cor_alfa(valor) {
                    d.fundo = Some(if a >= 0.85 { Some((r, g, b)) } else { None });
                }
            }
            "background" => {
                let v = valor.to_ascii_lowercase();
                if !v.contains("url(") && !v.contains("gradient") {
                    for t in dividir_valores(valor) {
                        if let Some((r, g, b, a)) = cor_alfa(t) {
                            d.fundo = Some(if a >= 0.85 { Some((r, g, b)) } else { None });
                            break;
                        }
                    }
                }
            }
            "padding" => {
                let vals: Vec<Option<f32>> =
                    dividir_valores(valor).iter().map(|t| comprimento(t)).collect();
                if let Some([topo, dir, base, esq]) = quatro_lados(&vals) {
                    d.pad_topo = topo.or(d.pad_topo);
                    d.pad_dir = dir.or(d.pad_dir);
                    d.pad_base = base.or(d.pad_base);
                    d.pad_esq = esq.or(d.pad_esq);
                }
            }
            "padding-inline" | "padding-block" => {
                let vals: Vec<Option<f32>> =
                    dividir_valores(valor).iter().map(|t| comprimento(t)).collect();
                if let Some([a, b, _, _]) = quatro_lados(&vals) {
                    if nome == "padding-inline" {
                        d.pad_esq = a.or(d.pad_esq);
                        d.pad_dir = b.or(d.pad_dir);
                    } else {
                        d.pad_topo = a.or(d.pad_topo);
                        d.pad_base = b.or(d.pad_base);
                    }
                }
            }
            "padding-top" => {
                if let Some(v) = comprimento(valor) {
                    d.pad_topo = Some(v);
                }
            }
            "padding-bottom" => {
                if let Some(v) = comprimento(valor) {
                    d.pad_base = Some(v);
                }
            }
            "padding-left" | "padding-inline-start" => {
                if let Some(v) = comprimento(valor) {
                    d.pad_esq = Some(v);
                }
            }
            "padding-right" | "padding-inline-end" => {
                if let Some(v) = comprimento(valor) {
                    d.pad_dir = Some(v);
                }
            }
            "border-width" => {
                let vals = dividir_valores(valor);
                if let Some(v) = vals.first().and_then(|t| comprimento(t)) {
                    d.borda_largura = Some(v);
                }
            }
            "border-style" => {
                let v = valor.to_ascii_lowercase();
                if v == "none" || v == "hidden" {
                    d.borda_largura = Some(0.0);
                }
            }
            "border-color" => {
                let vals = dividir_valores(valor);
                if let Some((r, g, b, a)) = vals.first().and_then(|t| cor_alfa(t)) {
                    d.borda_cor = Some(if a >= 0.5 { Some((r, g, b)) } else { None });
                }
            }
            "border" => {
                for t in dividir_valores(valor) {
                    let minusculo = t.to_ascii_lowercase();
                    if minusculo == "none" || minusculo == "hidden" {
                        d.borda_largura = Some(0.0);
                    } else if let Some((r, g, b, a)) = cor_alfa(t) {
                        d.borda_cor = Some(if a >= 0.5 { Some((r, g, b)) } else { None });
                    } else if let Some(v) = comprimento(t) {
                        d.borda_largura = Some(v);
                    }
                }
            }
            "border-radius" => {
                let vals = dividir_valores(valor);
                if let Some(t) = vals.first() {
                    if t.ends_with('%') {
                        d.raio = Some(9999.0);
                    } else if let Some(v) = comprimento(t) {
                        d.raio = Some(v);
                    }
                }
            }
            "visibility" => {
                let v = valor.to_ascii_lowercase();
                if v == "hidden" || v == "collapse" {
                    d.escondido_visual = Some(true);
                } else if v == "visible" {
                    d.escondido_visual = Some(false);
                }
            }
            "clip" => {
                if clip_escondido(valor) {
                    d.escondido_visual = Some(true);
                }
            }
            "clip-path" => {
                if inset_escondido(valor) {
                    d.escondido_visual = Some(true);
                }
            }
            "transform" => {
                if transform_fora_da_tela(valor) {
                    d.escondido_visual = Some(true);
                }
            }
            "color" => {
                let v = valor.to_ascii_lowercase();
                if v == "inherit" || v == "currentcolor" {
                    d.cor_herdada = Some(true);
                } else if let Some(c) = cor(valor) {
                    d.cor = Some(c);
                    d.cor_herdada = Some(false);
                }
            }
            _ => {}
        }
    }
    d
}

fn aplica(dst: &mut Decl, src: &Decl) {
    if src.tamanho.is_some() {
        dst.tamanho = src.tamanho;
    }
    if src.negrito.is_some() {
        dst.negrito = src.negrito;
    }
    if src.margem_topo.is_some() {
        dst.margem_topo = src.margem_topo;
    }
    if src.margem_base.is_some() {
        dst.margem_base = src.margem_base;
    }
    if src.cor.is_some() {
        dst.cor = src.cor;
    }
    if src.oculto.is_some() {
        dst.oculto = src.oculto;
    }
    if src.escondido_visual.is_some() {
        dst.escondido_visual = src.escondido_visual;
    }
    if src.cor_herdada.is_some() {
        dst.cor_herdada = src.cor_herdada;
    }
    if src.fundo.is_some() {
        dst.fundo = src.fundo;
    }
    if src.display.is_some() {
        dst.display = src.display;
    }
    if src.coluna.is_some() {
        dst.coluna = src.coluna;
    }
    if src.espaco.is_some() {
        dst.espaco = src.espaco;
    }
    if src.justificar.is_some() {
        dst.justificar = src.justificar;
    }
    if src.alinhamento.is_some() {
        dst.alinhamento = src.alinhamento;
    }
    if src.pad_topo.is_some() {
        dst.pad_topo = src.pad_topo;
    }
    if src.pad_base.is_some() {
        dst.pad_base = src.pad_base;
    }
    if src.pad_esq.is_some() {
        dst.pad_esq = src.pad_esq;
    }
    if src.pad_dir.is_some() {
        dst.pad_dir = src.pad_dir;
    }
    if src.borda_largura.is_some() {
        dst.borda_largura = src.borda_largura;
    }
    if src.borda_cor.is_some() {
        dst.borda_cor = src.borda_cor;
    }
    if src.raio.is_some() {
        dst.raio = src.raio;
    }
    if src.largura.is_some() {
        dst.largura = src.largura;
    }
    if src.altura.is_some() {
        dst.altura = src.altura;
    }
    if src.italico.is_some() {
        dst.italico = src.italico;
    }
    if src.serifa.is_some() {
        dst.serifa = src.serifa;
    }
}

fn para_estilo(d: Decl) -> Estilo {
    Estilo {
        tamanho: d.tamanho,
        negrito: d.negrito,
        margem_topo: d.margem_topo,
        margem_base: d.margem_base,
        cor: d.cor,
        cor_herdada: d.cor_herdada == Some(true),
        oculto: d.oculto == Some(true) || d.escondido_visual == Some(true),
        fundo: d.fundo.flatten(),
        display: d.display,
        coluna: d.coluna,
        espaco: d.espaco,
        justificar: d.justificar,
        alinhamento: d.alinhamento,
        pad_topo: d.pad_topo,
        pad_base: d.pad_base,
        pad_esq: d.pad_esq,
        pad_dir: d.pad_dir,
        borda_largura: d.borda_largura,
        borda_cor: d.borda_cor,
        raio: d.raio,
        largura: d.largura,
        altura: d.altura,
        italico: d.italico,
        serifa: d.serifa,
    }
}

/// Comprimento em px. em e rem valem 16 px, pt vale 4/3 px. `calc(a + b)` e `calc(a - b)`.
fn comprimento(v: &str) -> Option<f32> {
    let v = v.trim().to_ascii_lowercase();
    if let Some(inner) = v
        .strip_prefix("calc(")
        .and_then(|r| r.strip_suffix(')'))
    {
        return calculo(inner);
    }
    unidade(&v)
}

fn unidade(v: &str) -> Option<f32> {
    let (numero, fator): (&str, f32) = if let Some(n) = v.strip_suffix("px") {
        (n, 1.0)
    } else if let Some(n) = v.strip_suffix("rem") {
        (n, 16.0)
    } else if let Some(n) = v.strip_suffix("em") {
        (n, 16.0)
    } else if let Some(n) = v.strip_suffix("pt") {
        (n, 4.0 / 3.0)
    } else {
        (v, 1.0)
    };
    numero.trim().parse::<f32>().ok().map(|x| x * fator)
}

fn calculo(texto: &str) -> Option<f32> {
    let (esq, dir, sinal) = if let Some(p) = texto.find(" + ") {
        (&texto[..p], &texto[p + 3..], 1.0)
    } else if let Some(p) = texto.find(" - ") {
        (&texto[..p], &texto[p + 3..], -1.0)
    } else {
        return None;
    };
    Some(unidade(esq.trim())? + sinal * unidade(dir.trim())?)
}

/// `rect(topo, direita, base, esquerda)` com área de no máximo 1 px.
/// É o padrão de texto que só existe para leitor de tela.
fn clip_escondido(valor: &str) -> bool {
    let v = valor.trim().to_ascii_lowercase();
    let args = match v.strip_prefix("rect(").and_then(|r| r.strip_suffix(')')) {
        Some(a) => a,
        None => return false,
    };
    let nums: Option<Vec<f32>> = args
        .split(|c: char| c == ',' || c.is_whitespace())
        .filter(|s| !s.is_empty())
        .map(unidade)
        .collect();
    match nums {
        Some(n) if n.len() == 4 => {
            (n[2] - n[0]).abs() <= 1.0 && (n[1] - n[3]).abs() <= 1.0
        }
        _ => false,
    }
}

/// `inset(50%)` ou mais: o recorte deixa o texto invisível.
fn inset_escondido(valor: &str) -> bool {
    let v = valor.trim().to_ascii_lowercase();
    let args = match v.strip_prefix("inset(").and_then(|r| r.split(')').next()) {
        Some(a) => a,
        None => return false,
    };
    let primeiro = args.split_whitespace().next().unwrap_or("");
    match primeiro.strip_suffix('%').and_then(|n| n.parse::<f32>().ok()) {
        Some(p) => p >= 50.0,
        None => false,
    }
}

/// `translate(-100%)` e variantes: leva o elemento para fora da tela.
fn transform_fora_da_tela(valor: &str) -> bool {
    let v = valor.trim().to_ascii_lowercase();
    let nome_ok = ["translate(", "translatex(", "translate3d("]
        .iter()
        .any(|p| v.starts_with(*p));
    if !nome_ok {
        return false;
    }
    let dentro = match v.split_once('(') {
        Some((_, r)) => r,
        None => return false,
    };
    let primeiro = dentro
        .split(|c: char| c == ',' || c == ')')
        .next()
        .unwrap_or("")
        .trim();
    match primeiro
        .strip_suffix('%')
        .and_then(|n| n.trim().parse::<f32>().ok())
    {
        Some(p) => p <= -100.0,
        None => false,
    }
}

fn peso(v: &str) -> Option<bool> {
    let v = v.trim().to_ascii_lowercase();
    match v.as_str() {
        "bold" | "bolder" => Some(true),
        "normal" | "lighter" => Some(false),
        outro => outro.parse::<f32>().ok().map(|n| n >= 600.0),
    }
}

fn cor(v: &str) -> Option<(u8, u8, u8)> {
    let (r, g, b, a) = cor_alfa(v)?;
    if a >= 0.5 {
        Some((r, g, b))
    } else {
        None
    }
}

/// Cor com transparência: (r, g, b, alfa de 0 a 1).
/// Aceita #rgb, #rgba, #rrggbb, #rrggbbaa, rgb()/rgba() e hsl()/hsla(), com vírgulas
/// ou espaços e `/ alfa`, além de alguns nomes.
fn cor_alfa(v: &str) -> Option<(u8, u8, u8, f32)> {
    let v = v.trim().to_ascii_lowercase();
    if let Some(hex) = v.strip_prefix('#') {
        let d: Vec<u8> = hex
            .chars()
            .map(|c| c.to_digit(16).map(|x| x as u8))
            .collect::<Option<Vec<u8>>>()?;
        return match d.len() {
            3 => Some((d[0] * 17, d[1] * 17, d[2] * 17, 1.0)),
            4 => Some((d[0] * 17, d[1] * 17, d[2] * 17, (d[3] as f32) * 17.0 / 255.0)),
            6 => Some((d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5], 1.0)),
            8 => Some((
                d[0] * 16 + d[1],
                d[2] * 16 + d[3],
                d[4] * 16 + d[5],
                ((d[6] * 16 + d[7]) as f32) / 255.0,
            )),
            _ => None,
        };
    }
    let (tipo, resto) = if let Some(r) = v.strip_prefix("rgba(").or_else(|| v.strip_prefix("rgb(")) {
        ("rgb", r)
    } else if let Some(r) = v.strip_prefix("hsla(").or_else(|| v.strip_prefix("hsl(")) {
        ("hsl", r)
    } else {
        return cor_nomeada(&v);
    };
    let args = resto.strip_suffix(')')?;
    let args = args.replace(|c: char| c == ',' || c == '/', " ");
    let partes: Vec<&str> = args.split_whitespace().collect();
    if partes.len() < 3 {
        return None;
    }
    let alfa = match partes.get(3) {
        Some(a) => numero_ou_percentual(a, 1.0)?,
        None => 1.0,
    };
    let alfa = alfa.clamp(0.0, 1.0);
    if tipo == "rgb" {
        let canal = |s: &str| numero_ou_percentual(s, 255.0).map(|x| x.round().clamp(0.0, 255.0) as u8);
        return Some((canal(partes[0])?, canal(partes[1])?, canal(partes[2])?, alfa));
    }
    let h = partes[0].strip_suffix("deg").unwrap_or(partes[0]).parse::<f32>().ok()?;
    let sat = partes[1].strip_suffix('%')?.parse::<f32>().ok()? / 100.0;
    let luz = partes[2].strip_suffix('%')?.parse::<f32>().ok()? / 100.0;
    let (r, g, b) = hsl_para_rgb(h, sat.clamp(0.0, 1.0), luz.clamp(0.0, 1.0));
    Some((r, g, b, alfa))
}

/// Número puro ou porcentagem. `cheio` é o valor que 100% representa.
fn numero_ou_percentual(s: &str, cheio: f32) -> Option<f32> {
    match s.strip_suffix('%') {
        Some(n) => n.trim().parse::<f32>().ok().map(|x| x / 100.0 * cheio),
        None => s.parse::<f32>().ok(),
    }
}

fn hsl_para_rgb(h: f32, s: f32, l: f32) -> (u8, u8, u8) {
    let h = (((h % 360.0) + 360.0) % 360.0) / 360.0;
    let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let p = 2.0 * l - q;
    let canal = |t: f32| -> f32 {
        let mut t = t;
        if t < 0.0 {
            t += 1.0;
        }
        if t > 1.0 {
            t -= 1.0;
        }
        if t < 1.0 / 6.0 {
            p + (q - p) * 6.0 * t
        } else if t < 0.5 {
            q
        } else if t < 2.0 / 3.0 {
            p + (q - p) * (2.0 / 3.0 - t) * 6.0
        } else {
            p
        }
    };
    let byte = |x: f32| (x.clamp(0.0, 1.0) * 255.0).round() as u8;
    (byte(canal(h + 1.0 / 3.0)), byte(canal(h)), byte(canal(h - 1.0 / 3.0)))
}

fn cor_nomeada(v: &str) -> Option<(u8, u8, u8, f32)> {
    let c = match v {
        "transparent" => return Some((0, 0, 0, 0.0)),
        "black" => (0, 0, 0),
        "white" => (255, 255, 255),
        "red" => (255, 0, 0),
        "green" => (0, 128, 0),
        "blue" => (0, 0, 255),
        "gray" | "grey" => (128, 128, 128),
        "navy" => (0, 0, 128),
        "silver" => (192, 192, 192),
        "maroon" => (128, 0, 0),
        "purple" => (128, 0, 128),
        "orange" => (255, 165, 0),
        "yellow" => (255, 255, 0),
        "teal" => (0, 128, 128),
        "lime" => (0, 255, 0),
        "aqua" | "cyan" => (0, 255, 255),
        "fuchsia" | "magenta" => (255, 0, 255),
        "olive" => (128, 128, 0),
        _ => return None,
    };
    Some((c.0, c.1, c.2, 1.0))
}

/// Divide por espaços fora de parênteses: `1px solid hsl(0 0% 50%)` dá 3 partes.
fn dividir_valores(s: &str) -> Vec<&str> {
    let mut saida: Vec<&str> = Vec::new();
    let mut prof = 0i32;
    let mut inicio: Option<usize> = None;
    for (i, c) in s.char_indices() {
        if c == '(' {
            prof += 1;
            if inicio.is_none() {
                inicio = Some(i);
            }
        } else if c == ')' {
            prof -= 1;
        } else if c.is_whitespace() && prof <= 0 {
            if let Some(ini) = inicio.take() {
                saida.push(&s[ini..i]);
            }
        } else if inicio.is_none() {
            inicio = Some(i);
        }
    }
    if let Some(ini) = inicio {
        saida.push(&s[ini..]);
    }
    saida
}

/// Valores de 1 a 4 lados na ordem do CSS (topo, direita, base, esquerda).
fn quatro_lados(vals: &[Option<f32>]) -> Option<[Option<f32>; 4]> {
    match vals.len() {
        1 => Some([vals[0]; 4]),
        2 => Some([vals[0], vals[1], vals[0], vals[1]]),
        3 => Some([vals[0], vals[1], vals[2], vals[1]]),
        4 => Some([vals[0], vals[1], vals[2], vals[3]]),
        _ => None,
    }
}

/// Troca `var(--nome)` e `var(--nome, reserva)` pelos valores. None se faltar algum.
fn substituir_vars(valor: &str, vars: &HashMap<String, String>) -> Option<String> {
    let mut atual = valor.to_string();
    for _ in 0..8 {
        let ini = match atual.find("var(") {
            Some(i) => i,
            None => return Some(atual),
        };
        let abre = ini + 3;
        let mut prof = 0i32;
        let mut fim: Option<usize> = None;
        for (k, b) in atual.bytes().enumerate().skip(abre) {
            if b == b'(' {
                prof += 1;
            } else if b == b')' {
                prof -= 1;
                if prof == 0 {
                    fim = Some(k);
                    break;
                }
            }
        }
        let fim = fim?;
        let dentro = &atual[abre + 1..fim];
        let (nome, reserva) = match dentro.split_once(',') {
            Some((n, r)) => (n.trim(), Some(r.trim())),
            None => (dentro.trim(), None),
        };
        let novo: String = match vars.get(nome) {
            Some(v) => v.clone(),
            None => reserva?.to_string(),
        };
        atual = format!("{}{}{}", &atual[..ini], novo, &atual[fim + 1..]);
    }
    if atual.contains("var(") {
        None
    } else {
        Some(atual)
    }
}

/// `--nome: valor` de um bloco de declarações.
fn propriedades_personalizadas(corpo: &str) -> Vec<(String, String)> {
    let mut saida: Vec<(String, String)> = Vec::new();
    for par in corpo.split(';') {
        if let Some((nome, valor)) = par.split_once(':') {
            let nome = nome.trim();
            if nome.starts_with("--") && nome.len() > 2 {
                let valor = valor.trim();
                let valor = valor.strip_suffix("!important").map_or(valor, |s| s.trim_end());
                saida.push((nome.to_string(), valor.to_string()));
            }
        }
    }
    saida
}

/// `:root` vale o mesmo que `html`.
fn normaliza_raiz(seletor: &str) -> String {
    match seletor.strip_prefix(":root") {
        Some(resto) => format!("html{}", resto),
        None => seletor.to_string(),
    }
}

/// Primeira leitura: guarda as propriedades personalizadas de cada regra.
fn coletar_vars_da_regra(seletor_txt: &str, corpo: &str, f: &mut Folha, media: Option<(&str, bool)>) {
    if !corpo.contains("--") {
        return;
    }
    if !media.map_or(true, |(_, a)| a) {
        return;
    }
    let vars = propriedades_personalizadas(corpo);
    if vars.is_empty() {
        return;
    }
    for parte in divide_seletores(seletor_txt) {
        let parte = parte.trim();
        if parte.is_empty() {
            continue;
        }
        if let Ok(s) = parse_seletor(&normaliza_raiz(parte)) {
            f.regras_vars.push(RegraVars { seletor: s, vars: vars.clone() });
        }
    }
}

// ---------------------------------------------------------------------------
// @media
// ---------------------------------------------------------------------------

fn media_casa(prelude: &str, largura: f32) -> bool {
    let normal = prelude
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
        .to_ascii_lowercase();
    normal.split(',').any(|q| query_casa(q.trim(), largura))
}

fn query_casa(q: &str, largura: f32) -> bool {
    let mut resto = q;
    let mut negada = false;
    if let Some(r) = resto.strip_prefix("not ") {
        negada = true;
        resto = r;
    } else if let Some(r) = resto.strip_prefix("only ") {
        resto = r;
    }
    match partes_casam(resto, largura) {
        Some(v) => v != negada,
        None => false,
    }
}

/// `None` se houver condição desconhecida. Nesse caso a consulta não casa.
fn partes_casam(q: &str, largura: f32) -> Option<bool> {
    let mut tudo = true;
    for parte in q.split(" and ") {
        let parte = parte.trim();
        match parte.strip_prefix('(').and_then(|r| r.strip_suffix(')')) {
            Some(dentro) => {
                let (nome, valor) = dentro.split_once(':')?;
                let limite = comprimento(valor)?;
                match nome.trim() {
                    "min-width" => tudo = tudo && largura >= limite,
                    "max-width" => tudo = tudo && largura <= limite,
                    _ => return None,
                }
            }
            None => {
                if parte != "screen" && parte != "all" {
                    tudo = false;
                }
            }
        }
    }
    Some(tudo)
}

// ---------------------------------------------------------------------------
// Seletores: tokenização e análise
// ---------------------------------------------------------------------------

fn despeja(atual: &mut String, tokens: &mut Vec<Token>) {
    if !atual.is_empty() {
        tokens.push(Token::Atomo(std::mem::take(atual)));
    }
}

fn tokeniza(sel: &str) -> Vec<Token> {
    let mut tokens: Vec<Token> = Vec::new();
    let mut atual = String::new();
    let mut espaco = false;
    let mut colchete = false;
    let mut parenteses: i32 = 0;
    let mut aspas: Option<char> = None;
    for c in sel.chars() {
        if let Some(q) = aspas {
            atual.push(c);
            if c == q {
                aspas = None;
            }
            continue;
        }
        if colchete {
            atual.push(c);
            if c == ']' {
                colchete = false;
            } else if c == '"' || c == '\'' {
                aspas = Some(c);
            }
            continue;
        }
        if parenteses > 0 {
            atual.push(c);
            if c == '(' {
                parenteses += 1;
            } else if c == ')' {
                parenteses -= 1;
            }
            continue;
        }
        match c {
            ' ' | '\t' | '\n' | '\r' | '\u{c}' => {
                despeja(&mut atual, &mut tokens);
                espaco = true;
            }
            '>' | '+' | '~' => {
                despeja(&mut atual, &mut tokens);
                let comb = match c {
                    '>' => Combinador::Filho,
                    '+' => Combinador::Adjacente,
                    _ => Combinador::Geral,
                };
                tokens.push(Token::Comb(comb));
                espaco = false;
            }
            _ => {
                if espaco {
                    let atomo_antes = matches!(tokens.last(), Some(Token::Atomo(_)));
                    if atomo_antes {
                        tokens.push(Token::Comb(Combinador::Descendente));
                    }
                    espaco = false;
                }
                match c {
                    '[' => colchete = true,
                    '(' => parenteses += 1,
                    '"' | '\'' => aspas = Some(c),
                    _ => {}
                }
                atual.push(c);
            }
        }
    }
    despeja(&mut atual, &mut tokens);
    tokens
}

fn eh_irmao(c: Combinador) -> bool {
    matches!(c, Combinador::Adjacente | Combinador::Geral)
}

fn parse_seletor(texto: &str) -> Result<Seletor, String> {
    let mut compostos: Vec<Simples> = Vec::new();
    let mut combs: Vec<Combinador> = Vec::new();
    let mut esperando = true;
    for t in tokeniza(texto) {
        match t {
            Token::Atomo(s) => {
                if !esperando {
                    return Err(ERRO_COMPOSTO.to_string());
                }
                compostos.push(parse_composto(&s)?);
                esperando = false;
            }
            Token::Comb(c) => {
                if esperando {
                    return Err(ERRO_COMPOSTO.to_string());
                }
                combs.push(c);
                esperando = true;
            }
        }
    }
    if esperando || compostos.is_empty() {
        return Err(ERRO_COMPOSTO.to_string());
    }
    let n = compostos.len();

    // Irmão (+ ou ~) só é aceito ao lado do alvo.
    for (k, c) in combs.iter().enumerate() {
        if eh_irmao(*c) && k + 2 != n {
            return Err("irmão (+ ou ~) fora da posição suportada".to_string());
        }
    }

    // :first-child só no alvo ou no irmão ao lado.
    for (k, s) in compostos.iter().enumerate() {
        if s.primeiro_filho {
            let alvo_ok = k + 1 == n;
            let irmao_ok = k + 2 == n && eh_irmao(combs[n - 2]);
            if !alvo_ok && !irmao_ok {
                return Err("first-child fora do alvo ou do irmão ao lado".to_string());
            }
        }
    }

    // :last-child só no alvo.
    for s in compostos.iter().take(n - 1) {
        if s.ultimo_filho {
            return Err("last-child fora do alvo".to_string());
        }
    }

    let usa_primeiro = compostos.iter().any(|s| s.primeiro_filho);
    let alvo = match compostos.pop() {
        Some(a) => a,
        None => return Err(ERRO_COMPOSTO.to_string()),
    };
    let mut anteriores: Vec<(Combinador, Simples)> = Vec::new();
    while let Some(s) = compostos.pop() {
        if let Some(c) = combs.pop() {
            anteriores.push((c, s));
        }
    }
    let usa_irmao = anteriores.first().map_or(false, |(c, _)| eh_irmao(*c));
    let especificidade = especificidade_de(&alvo, &anteriores);
    Ok(Seletor {
        alvo,
        anteriores,
        especificidade,
        usa_irmaos: usa_irmao || usa_primeiro,
    })
}

fn eh_interacao(nome: &str) -> bool {
    matches!(
        nome,
        "hover" | "focus" | "focus-visible" | "focus-within" | "active" | "visited"
    )
}

fn parse_composto(texto: &str) -> Result<Simples, String> {
    let chars: Vec<char> = texto.chars().collect();
    let mut s = Simples::default();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '*' {
            i += 1;
        } else if c == '#' || c == '.' {
            let (nome, prox) = ident(&chars, i + 1);
            if nome.is_empty() {
                return Err(ERRO_COMPOSTO.to_string());
            }
            if c == '#' {
                s.id = Some(nome);
            } else {
                s.classes.push(nome);
            }
            i = prox;
        } else if c == '[' {
            let fim = match chars[i..].iter().position(|&ch| ch == ']') {
                Some(p) => i + p,
                None => return Err("atributo sem fechamento".to_string()),
            };
            let conteudo: String = chars[i + 1..fim].iter().collect();
            s.atributos.push(parse_atributo(&conteudo)?);
            i = fim + 1;
        } else if c == ':' {
            if chars.get(i + 1) == Some(&':') {
                return Err("pseudo-elemento não suportado".to_string());
            }
            let (nome, prox) = ident(&chars, i + 1);
            let nome = nome.to_ascii_lowercase();
            if nome.is_empty() {
                return Err(ERRO_COMPOSTO.to_string());
            }
            i = prox;
            if chars.get(i) == Some(&'(') {
                let fim = match fecha_parenteses(&chars, i) {
                    Some(f) => f,
                    None => return Err(ERRO_COMPOSTO.to_string()),
                };
                let interno: String = chars[i + 1..fim].iter().collect();
                i = fim + 1;
                if nome != "not" {
                    return Err(format!("pseudo não suportada: {}", nome));
                }
                let interno = interno.trim();
                if interno == "*" {
                    return Err("`:not(*)` não suportado".to_string());
                }
                let so_interacao = interno.strip_prefix(':').map_or(false, eh_interacao);
                if !so_interacao {
                    let negado = parse_composto(interno)?;
                    if negado.primeiro_filho || negado.ultimo_filho {
                        return Err("first-child ou last-child dentro de :not não suportado".to_string());
                    }
                    s.negados.push(negado);
                }
            } else if nome == "first-child" {
                s.primeiro_filho = true;
            } else if nome == "last-child" {
                s.ultimo_filho = true;
            } else if eh_interacao(&nome) {
                return Err("pseudo de interação (hover, focus etc.): nunca casa".to_string());
            } else {
                return Err(format!("pseudo não suportada: {}", nome));
            }
        } else {
            let (nome, prox) = ident(&chars, i);
            if nome.is_empty() {
                return Err(ERRO_COMPOSTO.to_string());
            }
            s.tag = Some(nome.to_ascii_lowercase());
            i = prox;
        }
    }
    Ok(s)
}

fn parse_atributo(txt: &str) -> Result<Atributo, String> {
    let t = txt.trim();
    let erro = format!("atributo [{}] com forma não suportada", t);
    let (antes, valor_txt, op) = match t.find('=') {
        None => (t, "", OperadorAtributo::Existe),
        Some(p) => {
            let antes = &t[..p];
            let (nome, op) = if let Some(n) = antes.strip_suffix('~') {
                (n, OperadorAtributo::Palavra)
            } else if let Some(n) = antes.strip_suffix('|') {
                (n, OperadorAtributo::Traco)
            } else if let Some(n) = antes.strip_suffix('^') {
                (n, OperadorAtributo::Prefixo)
            } else if let Some(n) = antes.strip_suffix('$') {
                (n, OperadorAtributo::Sufixo)
            } else if let Some(n) = antes.strip_suffix('*') {
                (n, OperadorAtributo::Contem)
            } else {
                (antes, OperadorAtributo::Igual)
            };
            (nome, &t[p + 1..], op)
        }
    };
    let nome = antes.trim().to_ascii_lowercase();
    if nome.is_empty() || !nome.chars().all(eh_ident) {
        return Err(erro);
    }
    if op == OperadorAtributo::Existe {
        return Ok(Atributo {
            nome,
            op,
            valor: String::new(),
        });
    }
    let v = valor_txt.trim();
    let valor = match v.chars().next() {
        Some(q) if q == '"' || q == '\'' => match v[1..].strip_suffix(q) {
            Some(x) => x.to_string(),
            None => return Err(erro),
        },
        _ => {
            if v.is_empty() || v.contains(char::is_whitespace) {
                return Err(erro);
            }
            v.to_string()
        }
    };
    Ok(Atributo { nome, op, valor })
}

fn eh_ident(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || c == '_' || (c as u32) >= 0x80
}

fn ident(chars: &[char], inicio: usize) -> (String, usize) {
    let mut nome = String::new();
    let mut i = inicio;
    while i < chars.len() && eh_ident(chars[i]) {
        nome.push(chars[i]);
        i += 1;
    }
    (nome, i)
}

fn fecha_parenteses(chars: &[char], abre: usize) -> Option<usize> {
    let mut prof = 0i32;
    for (j, &c) in chars.iter().enumerate().skip(abre) {
        if c == '(' {
            prof += 1;
        } else if c == ')' {
            prof -= 1;
            if prof == 0 {
                return Some(j);
            }
        }
    }
    None
}

fn soma_especificidade(s: &Simples, t: &mut (u32, u32, u32)) {
    if s.id.is_some() {
        t.0 += 1;
    }
    t.1 += s.classes.len() as u32
        + s.atributos.len() as u32
        + (s.primeiro_filho as u32)
        + (s.ultimo_filho as u32);
    if s.tag.is_some() {
        t.2 += 1;
    }
    for n in &s.negados {
        soma_especificidade(n, t);
    }
}

fn especificidade_de(alvo: &Simples, anteriores: &[(Combinador, Simples)]) -> u32 {
    let mut total = (0u32, 0u32, 0u32);
    soma_especificidade(alvo, &mut total);
    for (_, s) in anteriores {
        soma_especificidade(s, &mut total);
    }
    total.0 * 10000 + total.1 * 100 + total.2
}

fn colhe_simples(s: &Simples, nomes: &mut Vec<String>) {
    for a in &s.atributos {
        if !nomes.contains(&a.nome) {
            nomes.push(a.nome.clone());
        }
    }
    for n in &s.negados {
        colhe_simples(n, nomes);
    }
}

fn colhe_atributos(s: &Seletor, nomes: &mut Vec<String>) {
    colhe_simples(&s.alvo, nomes);
    for (_, c) in &s.anteriores {
        colhe_simples(c, nomes);
    }
}

fn indexa(ind: &mut Indice, s: &Seletor, i: usize) {
    if let Some(id) = &s.alvo.id {
        ind.ids.entry(id.clone()).or_insert_with(Vec::new).push(i);
    } else if let Some(c) = s.alvo.classes.first() {
        ind.classes.entry(c.clone()).or_insert_with(Vec::new).push(i);
    } else if let Some(t) = &s.alvo.tag {
        ind.tags.entry(t.clone()).or_insert_with(Vec::new).push(i);
    } else {
        ind.universais.push(i);
    }
}

// ---------------------------------------------------------------------------
// Casamento
// ---------------------------------------------------------------------------

fn casa_atributo(a: &Atributo, info: &Info) -> bool {
    let w = match info.atributos.iter().find(|(n, _)| *n == a.nome) {
        Some((_, v)) => v.as_str(),
        None => return false,
    };
    match a.op {
        OperadorAtributo::Existe => true,
        OperadorAtributo::Igual => w == a.valor.as_str(),
        OperadorAtributo::Palavra => {
            !a.valor.is_empty() && w.split_whitespace().any(|p| p == a.valor.as_str())
        }
        OperadorAtributo::Traco => {
            w == a.valor.as_str() || w.starts_with(format!("{}-", a.valor).as_str())
        }
        OperadorAtributo::Prefixo => !a.valor.is_empty() && w.starts_with(a.valor.as_str()),
        OperadorAtributo::Sufixo => !a.valor.is_empty() && w.ends_with(a.valor.as_str()),
        OperadorAtributo::Contem => !a.valor.is_empty() && w.contains(a.valor.as_str()),
    }
}

/// `primeiro` e `ultimo` dizem a posição do elemento entre seus irmãos.
/// Ancestrais não têm essa informação; quem chama passa `false` para eles.
fn casa_simples(s: &Simples, info: &Info, primeiro: bool, ultimo: bool) -> bool {
    if let Some(t) = &s.tag {
        if !info.tag.eq_ignore_ascii_case(t) {
            return false;
        }
    }
    if let Some(i) = &s.id {
        if info.id != *i {
            return false;
        }
    }
    if !s.classes.iter().all(|c| info.classes.iter().any(|ic| ic == c)) {
        return false;
    }
    if s.primeiro_filho && !primeiro {
        return false;
    }
    if s.ultimo_filho && !ultimo {
        return false;
    }
    if !s.atributos.iter().all(|a| casa_atributo(a, info)) {
        return false;
    }
    s.negados
        .iter()
        .all(|n| !casa_simples(n, info, primeiro, ultimo))
}

/// Casa a cadeia de ancestrais. `topo` é o limite exclusivo de `pais`:
/// o elemento atual é filho de `pais[topo - 1]`.
fn casa_ancestrais(rest: &[(Combinador, Simples)], pais: &[Info], topo: usize) -> bool {
    match rest.first() {
        None => true,
        Some((comb, s)) => match comb {
            Combinador::Filho => {
                topo > 0
                    && casa_simples(s, &pais[topo - 1], false, false)
                    && casa_ancestrais(&rest[1..], pais, topo - 1)
            }
            Combinador::Descendente => (0..topo).rev().any(|i| {
                casa_simples(s, &pais[i], false, false) && casa_ancestrais(&rest[1..], pais, i)
            }),
            _ => false,
        },
    }
}

fn casa_seletor(
    sel: &Seletor,
    alvo: &Info,
    pais: &[Info],
    irmaos: &[Info],
    e_ultimo: bool,
) -> bool {
    if !casa_simples(&sel.alvo, alvo, irmaos.is_empty(), e_ultimo) {
        return false;
    }
    match sel.anteriores.first() {
        None => true,
        Some((comb, s)) => match comb {
            Combinador::Adjacente | Combinador::Geral => {
                let n = irmaos.len();
                let inicio = if *comb == Combinador::Adjacente {
                    n.saturating_sub(1)
                } else {
                    0
                };
                (inicio..n).any(|c| {
                    casa_simples(s, &irmaos[c], c == 0, false)
                        && casa_ancestrais(&sel.anteriores[1..], pais, pais.len())
                })
            }
            _ => casa_ancestrais(&sel.anteriores, pais, pais.len()),
        },
    }
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

#[cfg(test)]
mod testes {
    use super::*;

    fn info(tag: &str, id: &str, classes: &[&str], atributos: &[(&str, &str)]) -> Info {
        Info {
            tag: tag.to_string(),
            id: id.to_string(),
            classes: classes.iter().map(|c| c.to_string()).collect(),
            atributos: atributos
                .iter()
                .map(|(n, v)| (n.to_string(), v.to_string()))
                .collect(),
        }
    }

    fn oculto(css: &str, alvo: &Info, pais: &[Info], irmaos: &[Info]) -> bool {
        let f = Folha::parse(css);
        estilo_completo(&f, alvo, pais, irmaos, None).oculto
    }

    #[test]
    fn italico_e_serifa() {
        let f = Folha::parse(".a{font-style:italic;font-family:\"Foo\", Georgia, serif}.b{font-family:Inter, Georgia}.c{font-style:normal}");
        let a = estilo_para(&f, "p", "", &["a".to_string()], None);
        assert_eq!(a.italico, Some(true));
        assert_eq!(a.serifa, Some(true));
        let b = estilo_para(&f, "p", "", &["b".to_string()], None);
        assert_eq!(b.serifa, Some(false));
        let c = estilo_para(&f, "p", "", &["c".to_string()], None);
        assert_eq!(c.italico, Some(false));
        assert_eq!(c.serifa, None);
    }

    #[test]
    fn largura_e_altura_em_valores_absolutos() {
        let f = Folha::parse(".a{width:2rem;height:10px}.b{width:100%;height:auto}");
        let a = estilo_para(&f, "img", "", &["a".to_string()], None);
        assert_eq!(a.largura, Some(32.0));
        assert_eq!(a.altura, Some(10.0));
        let b = estilo_para(&f, "img", "", &["b".to_string()], None);
        assert_eq!(b.largura, None);
        assert_eq!(b.altura, None);
    }

    #[test]
    fn le_tamanho_negrito_e_cor() {
        let f = Folha::parse("h1 { font-size: 2em; font-weight: bold; color: #f00 }");
        let e = estilo_para(&f, "h1", "", &[], None);
        assert_eq!(e.tamanho, Some(32.0));
        assert_eq!(e.negrito, Some(true));
        assert_eq!(e.cor, Some((255, 0, 0)));
    }

    #[test]
    fn media_calc_max_width_casa_em_tela_pequena() {
        let f = Folha::parse(
            "@media screen and (max-width: calc(640px - 1px)) { p { display: none } }",
        );
        assert!(estilo_para(&f, "p", "", &[], None).oculto);
    }

    #[test]
    fn media_calc_min_width_nao_casa_em_tela_pequena() {
        let f = Folha::parse("@media (min-width: calc(640px - 1px)) { p { display: none } }");
        assert!(!estilo_para(&f, "p", "", &[], None).oculto);
    }

    #[test]
    fn media_calc_com_em() {
        let f = Folha::parse("@media (max-width: 40em) { p { display: none } }");
        assert!(estilo_para(&f, "p", "", &[], None).oculto);
    }

    #[test]
    fn media_calc_com_operacao_desconhecida_nao_casa() {
        let f = Folha::parse("@media (max-width: calc(640px * 2)) { p { display: none } }");
        assert!(!estilo_para(&f, "p", "", &[], None).oculto);
    }

    #[test]
    fn seletor_com_acento_casa() {
        let f = Folha::parse("p.café { display: none }");
        let alvo = info("p", "", &["café"], &[]);
        assert!(estilo_completo(&f, &alvo, &[], &[], None).oculto);
    }

    #[test]
    fn atributo_presenca_casa() {
        let alvo = info("div", "", &[], &[("data-x", "")]);
        assert!(oculto("[data-x] { display: none }", &alvo, &[], &[]));
    }

    #[test]
    fn atributo_palavra_casa_entre_espacos() {
        let alvo = info("div", "", &[], &[("class", "a b c")]);
        assert!(oculto("[class~=b] { display: none }", &alvo, &[], &[]));
    }

    #[test]
    fn atributo_prefixo() {
        let alvo = info("a", "", &[], &[("href", "https://x")]);
        assert!(oculto("[href^=http] { display: none }", &alvo, &[], &[]));
    }

    #[test]
    fn atributo_igual_sem_aspas() {
        let alvo = info("div", "", &[], &[("role", "note")]);
        assert!(oculto("[role=note] { display: none }", &alvo, &[], &[]));
    }

    #[test]
    fn virgula_dentro_de_atributo_nao_divide_seletor() {
        assert_eq!(divide_seletores("p[title=\"a,b\"], span").len(), 2);
        let alvo = info("p", "", &[], &[("title", "a,b")]);
        assert!(oculto("p[title=\"a,b\"] { display: none }", &alvo, &[], &[]));
    }

    #[test]
    fn irmao_adjacente_casa_so_com_o_anterior_imediato() {
        let css = ".a + p { display: none }";
        let p = info("p", "", &[], &[]);
        let a = info("div", "", &["a"], &[]);
        let x = info("span", "", &[], &[]);
        assert!(!oculto(css, &p, &[], &[a.clone(), x.clone()]));
        assert!(oculto(css, &p, &[], &[x, a]));
    }

    #[test]
    fn irmao_geral_casa_com_qualquer_anterior() {
        let css = ".a ~ p { display: none }";
        let p = info("p", "", &[], &[]);
        let a = info("div", "", &["a"], &[]);
        let x = info("span", "", &[], &[]);
        assert!(oculto(css, &p, &[], &[a, x]));
    }

    #[test]
    fn irmao_com_ancestral_usa_os_pais_do_alvo() {
        let css = "div .a + p { display: none }";
        let p = info("p", "", &[], &[]);
        let a = info("div", "", &["a"], &[]);
        let div = info("div", "", &[], &[]);
        let span = info("span", "", &[], &[]);
        assert!(oculto(css, &p, &[div], &[a.clone()]));
        assert!(!oculto(css, &p, &[span], &[a]));
    }

    #[test]
    fn first_child_casa_so_sem_irmaos_antes() {
        let css = "p:first-child { display: none }";
        let p = info("p", "", &[], &[]);
        let x = info("span", "", &[], &[]);
        assert!(oculto(css, &p, &[], &[]));
        assert!(!oculto(css, &p, &[], &[x]));
    }

    #[test]
    fn first_child_em_ancestral_fica_de_fora() {
        let f = Folha::parse("li:first-child p { display: none }");
        assert_eq!(f.ignoradas.len(), 1);
    }

    #[test]
    fn last_child_casa_so_no_ultimo_elemento() {
        let f = Folha::parse("li:last-child { display: none }");
        let li = info("li", "", &[], &[]);
        let x = info("span", "", &[], &[]);
        assert!(estilo_completo_ultimo(&f, &li, &[], &[x.clone()], true, None).oculto);
        assert!(!estilo_completo_ultimo(&f, &li, &[], &[x], false, None).oculto);
    }

    #[test]
    fn last_child_sem_informacao_de_fim_nao_casa() {
        let f = Folha::parse("li:last-child { display: none }");
        let li = info("li", "", &[], &[]);
        assert!(!estilo_completo(&f, &li, &[], &[], None).oculto);
    }

    #[test]
    fn last_child_em_ancestral_fica_de_fora() {
        let f = Folha::parse("ul:last-child li { display: none }");
        assert_eq!(f.ignoradas.len(), 1);
    }

    #[test]
    fn texto_depois_do_icone_some_com_span_last_child() {
        let f = Folha::parse(".b span + span:last-child { clip: rect(1px,1px,1px,1px) }");
        let texto = info("span", "", &[], &[]);
        let icone = info("span", "", &["minerva-icon"], &[]);
        let a = info("a", "", &["b"], &[]);
        assert!(estilo_completo_ultimo(&f, &texto, &[a.clone()], &[icone.clone()], true, None).oculto);
        assert!(!estilo_completo_ultimo(&f, &texto, &[a], &[icone], false, None).oculto);
    }

    #[test]
    fn irmao_depois_de_ancestral_fica_de_fora() {
        let f = Folha::parse(".a + .b p { display: none }");
        assert_eq!(f.ignoradas.len(), 1);
        assert!(f.ignoradas[0].motivo.contains("irmão"));
    }

    #[test]
    fn precisa_irmaos_so_quando_a_folha_usa() {
        assert!(!Folha::parse("p { display: none }").precisa_irmaos());
        assert!(Folha::parse("p:first-child { color: red }").precisa_irmaos());
    }

    #[test]
    fn nomes_de_atributo_sao_coletados() {
        let f = Folha::parse("[data-x], a[href] { color: red }");
        let nomes = f.nomes_atributos();
        assert!(nomes.iter().any(|s| s.as_str() == "data-x"));
        assert!(nomes.iter().any(|s| s.as_str() == "href"));
    }

    #[test]
    fn has_e_ignorado_e_registrado() {
        let f = Folha::parse("p:has(a) { display: none }");
        assert_eq!(f.ignoradas.len(), 1);
        assert!(f.ignoradas[0].motivo.contains("has"));
    }

    #[test]
    fn seletor_com_til_fora_da_posicao_e_registrado() {
        let f = Folha::parse(".a ~ .b .c { display: none }");
        assert_eq!(f.ignoradas.len(), 1);
        assert!(f.ignoradas[0].motivo.contains("irmão"));
    }

    #[test]
    fn regra_sem_display_none_nao_e_registrada() {
        let f = Folha::parse("p:hover { color: red }");
        assert!(f.ignoradas.is_empty());
    }

    #[test]
    fn media_inativo_registra_regra_ocultadora() {
        let f = Folha::parse("@media print { p { display: none } }");
        assert_eq!(f.ignoradas.len(), 1);
        assert!(f.ignoradas[0].motivo.contains("print"));
    }

    #[test]
    fn visibility_hidden_esconde() {
        let alvo = info("div", "", &[], &[]);
        assert!(oculto("div { visibility: hidden }", &alvo, &[], &[]));
    }

    #[test]
    fn visibility_visible_desfaz_na_ordem() {
        let alvo = info("div", "", &[], &[]);
        assert!(!oculto(
            "div { visibility: hidden } div { visibility: visible }",
            &alvo,
            &[],
            &[]
        ));
    }

    #[test]
    fn clip_de_leitor_de_tela_esconde() {
        let alvo = info("span", "", &[], &[]);
        assert!(oculto("span { clip: rect(0,0,0,0) }", &alvo, &[], &[]));
        assert!(oculto("span { clip: rect(1px, 1px, 1px, 1px) }", &alvo, &[], &[]));
    }

    #[test]
    fn clip_com_area_grande_nao_esconde() {
        let alvo = info("span", "", &[], &[]);
        assert!(!oculto("span { clip: rect(0, 100px, 100px, 0) }", &alvo, &[], &[]));
    }

    #[test]
    fn clip_path_inset_50_esconde() {
        let alvo = info("span", "", &[], &[]);
        assert!(oculto("span { clip-path: inset(50%) }", &alvo, &[], &[]));
        assert!(!oculto("span { clip-path: inset(10%) }", &alvo, &[], &[]));
    }

    #[test]
    fn transform_fora_da_tela_esconde() {
        let nav = info("nav", "", &[], &[]);
        assert!(oculto("nav { transform: translate3d(-100%, 0, 0) }", &nav, &[], &[]));
        assert!(!oculto("nav { transform: translate3d(20%, 0, 0) }", &nav, &[], &[]));
        assert!(!oculto("nav { transform: rotate(90deg) }", &nav, &[], &[]));
    }

    #[test]
    fn regras_casadas_devolvem_o_texto_da_regra() {
        let f = Folha::parse(".x { text-indent: -9999px }");
        let alvo = info("span", "", &["x"], &[]);
        let r = regras_casadas(&f, &alvo, &[], &[]);
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].seletor, ".x");
        assert!(r[0].declaracoes.contains("text-indent: -9999px"));
    }

    #[test]
    fn regras_casadas_nao_incluem_regra_que_nao_casa() {
        let f = Folha::parse(".x { text-indent: -9999px }");
        let alvo = info("span", "", &["y"], &[]);
        assert!(regras_casadas(&f, &alvo, &[], &[]).is_empty());
    }
}

