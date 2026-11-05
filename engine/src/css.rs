//! Motor de CSS do Nusky.
//!
//! Suporta: seletores de tipo, `.classe`, `#id`, `*`, listas com vírgula,
//! atributos (`[a]`, `[a=v]`, `[a~=v]`, `[a|=v]`, `[a^=v]`, `[a$=v]`, `[a*=v]`),
//! descendente, `>`, `+` e `~` (só ao lado do alvo), `:not(...)`,
//! `:first-child` (só no alvo ou no irmão ao lado).
//! Pseudo de interação (hover, focus etc.) nunca casa.
//! `@media` por largura, com px, em e calc(a + b) / calc(a - b).
//! Regras com `display: none` que o motor não aplica ficam em `ignoradas`.

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

/// Estilo final de um elemento.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Estilo {
    pub tamanho: Option<f32>,
    pub negrito: Option<bool>,
    pub margem_topo: Option<f32>,
    pub margem_base: Option<f32>,
    pub cor: Option<(u8, u8, u8)>,
    pub oculto: bool,
}

/// Regra que o motor não aplicou, com o motivo.
#[derive(Debug, Clone)]
pub struct Ignorada {
    pub seletor: String,
    pub motivo: String,
}

/// Folha de estilo já analisada.
#[derive(Debug, Default)]
pub struct Folha {
    regras: Vec<Regra>,
    indice: Indice,
    pub ignoradas: Vec<Ignorada>,
    usa_irmaos: bool,
    nomes_atributos: Vec<String>,
}

impl Folha {
    /// Analisa com a largura padrão de 375 pt.
    pub fn parse(css: &str) -> Folha {
        Folha::parse_largura(css, 375.0)
    }

    /// Analisa escolhendo os `@media` pela largura informada.
    pub fn parse_largura(css: &str, largura: f32) -> Folha {
        let mut f = Folha::default();
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
/// até o irmão imediatamente anterior.
pub fn estilo_completo(
    folha: &Folha,
    alvo: &Info,
    pais: &[Info],
    irmaos: &[Info],
    inline: Option<&str>,
) -> Estilo {
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
    cand.retain(|&i| casa_seletor(&folha.regras[i].seletor, alvo, pais, irmaos));
    cand.sort_by_key(|&i| (folha.regras[i].seletor.especificidade, i));

    let mut d = Decl::default();
    for &i in &cand {
        aplica(&mut d, &folha.regras[i].decl);
    }
    if let Some(texto) = inline {
        aplica(&mut d, &declaracoes(texto));
    }
    para_estilo(d)
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
}

#[derive(Debug)]
struct Regra {
    seletor: Seletor,
    decl: Decl,
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
    let decl = declaracoes(corpo);
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
        match parse_seletor(parte) {
            Ok(s) => {
                if s.usa_irmaos {
                    f.usa_irmaos = true;
                }
                colhe_atributos(&s, &mut f.nomes_atributos);
                f.regras.push(Regra { seletor: s, decl });
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

fn declaracoes(texto: &str) -> Decl {
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
        match nome.as_str() {
            "font-size" => {
                if let Some(v) = comprimento(valor) {
                    d.tamanho = Some(v);
                }
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
            }
            "color" => {
                if let Some(c) = cor(valor) {
                    d.cor = Some(c);
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
}

fn para_estilo(d: Decl) -> Estilo {
    Estilo {
        tamanho: d.tamanho,
        negrito: d.negrito,
        margem_topo: d.margem_topo,
        margem_base: d.margem_base,
        cor: d.cor,
        oculto: d.oculto == Some(true),
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

fn peso(v: &str) -> Option<bool> {
    let v = v.trim().to_ascii_lowercase();
    match v.as_str() {
        "bold" | "bolder" => Some(true),
        "normal" | "lighter" => Some(false),
        outro => outro.parse::<f32>().ok().map(|n| n >= 600.0),
    }
}

fn cor(v: &str) -> Option<(u8, u8, u8)> {
    let v = v.trim().to_ascii_lowercase();
    if let Some(hex) = v.strip_prefix('#') {
        let d: Vec<u8> = hex
            .chars()
            .map(|c| c.to_digit(16).map(|x| x as u8))
            .collect::<Option<Vec<u8>>>()?;
        return match d.len() {
            3 => Some((d[0] * 17, d[1] * 17, d[2] * 17)),
            6 => Some((d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5])),
            _ => None,
        };
    }
    if let Some(args) = v
        .strip_prefix("rgb(")
        .and_then(|r| r.strip_suffix(')'))
    {
        let p: Vec<u8> = args
            .split(',')
            .map(|s| s.trim().parse::<u8>().ok())
            .collect::<Option<Vec<u8>>>()?;
        if p.len() == 3 {
            return Some((p[0], p[1], p[2]));
        }
        return None;
    }
    match v.as_str() {
        "black" => Some((0, 0, 0)),
        "white" => Some((255, 255, 255)),
        "red" => Some((255, 0, 0)),
        "green" => Some((0, 128, 0)),
        "blue" => Some((0, 0, 255)),
        "gray" | "grey" => Some((128, 128, 128)),
        "navy" => Some((0, 0, 128)),
        _ => None,
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
                    if negado.primeiro_filho {
                        return Err("first-child dentro de :not não suportado".to_string());
                    }
                    s.negados.push(negado);
                }
            } else if nome == "first-child" {
                s.primeiro_filho = true;
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
        + (if s.primeiro_filho { 1 } else { 0 });
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

fn casa_simples(s: &Simples, info: &Info, e_primeiro: bool) -> bool {
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
    if s.primeiro_filho && !e_primeiro {
        return false;
    }
    if !s.atributos.iter().all(|a| casa_atributo(a, info)) {
        return false;
    }
    s.negados.iter().all(|n| !casa_simples(n, info, e_primeiro))
}

/// Casa a cadeia de ancestrais. `topo` é o limite exclusivo de `pais`:
/// o elemento atual é filho de `pais[topo - 1]`.
fn casa_ancestrais(rest: &[(Combinador, Simples)], pais: &[Info], topo: usize) -> bool {
    match rest.first() {
        None => true,
        Some((comb, s)) => match comb {
            Combinador::Filho => {
                topo > 0
                    && casa_simples(s, &pais[topo - 1], false)
                    && casa_ancestrais(&rest[1..], pais, topo - 1)
            }
            Combinador::Descendente => (0..topo).rev().any(|i| {
                casa_simples(s, &pais[i], false) && casa_ancestrais(&rest[1..], pais, i)
            }),
            _ => false,
        },
    }
}

fn casa_seletor(sel: &Seletor, alvo: &Info, pais: &[Info], irmaos: &[Info]) -> bool {
    if !casa_simples(&sel.alvo, alvo, irmaos.is_empty()) {
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
                    casa_simples(s, &irmaos[c], c == 0)
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
}