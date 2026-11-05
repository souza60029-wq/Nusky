// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! CSS básico: lê folhas de estilo e calcula o estilo de cada elemento.
//!
//! Seletores suportados: tipo, `.classe`, `#id`, `*`, listas com vírgula,
//! descendente (`div p`), filho direto (`div > p`) e `:not(...)`.
//! Pseudo-classes de interação (`:hover`, `:focus`, `:active`, `:visited`) nunca casam,
//! porque o motor não tem mouse nem estado de foco.
//! Blocos `@media` entram quando a condição casa com a largura da tela
//! (`min-width` e `max-width`, com os tipos `screen` e `all`).
//! Outras condições de `@media` (cor, orientação, impressão) não casam.
//! `@import` e `@font-face` são ignorados por inteiro.
//! Seletores com `+`, `~`, `[atributo]`, `::before` ou `:first-child` são ignorados.
//! Regras com `display: none` que não entram ficam em `Folha::ignoradas`, com o motivo,
//! só para o diagnóstico.
//!
//! Propriedades: color, font-size, font-weight, margin, margin-top, margin-bottom
//! e display (só none).
//!
//! Seletores compostos precisam dos pais do elemento. `estilo_com_pais` recebe essa lista.
//! `estilo_para` equivale a `estilo_com_pais` sem pais.

use std::collections::HashMap;

/// Largura usada quando o chamador não informa. É a largura do iPhone 6s (375 pt).
pub const LARGURA_PADRAO: f32 = 375.0;

/// Dados de um elemento usados para casar seletores.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Info {
    pub tag: String,
    pub id: Option<String>,
    pub classes: Vec<String>,
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

/// Regra `display: none` que o motor não aplicou, com o motivo.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Ignorada {
    pub seletor: String,
    pub motivo: String,
}

/// Como um composto se liga ao composto da direita.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Combinador {
    Descendente,
    Filho,
}

/// Seletor simples (um composto): tipo, id, classes e negações.
#[derive(Debug, Clone, Default, PartialEq)]
struct Simples {
    tag: Option<String>,
    id: Option<String>,
    classes: Vec<String>,
    /// Compostos que o elemento não pode casar (vindos de `:not(...)`).
    negados: Vec<Simples>,
    /// Pseudo-classe de interação: o composto nunca casa.
    impossivel: bool,
}

/// Seletor completo, por exemplo `div > p span`.
#[derive(Debug, Clone, PartialEq)]
struct Seletor {
    /// Composto que descreve o elemento (o último da cadeia).
    alvo: Simples,
    /// Compostos anteriores, do mais próximo ao mais distante.
    /// Cada item traz o combinador que o liga ao composto da direita.
    anteriores: Vec<(Combinador, Simples)>,
    especificidade: u32,
}

#[derive(Debug, Clone)]
struct Regra {
    seletor: Seletor,
    declaracoes: Vec<(String, String)>,
    ordem: usize,
}

/// Índice para não testar todas as regras em cada elemento.
/// Cada regra entra em uma só lista, pela chave mais específica do seu alvo.
#[derive(Debug, Clone, Default)]
struct Indice {
    por_id: HashMap<String, Vec<usize>>,
    por_classe: HashMap<String, Vec<usize>>,
    por_tipo: HashMap<String, Vec<usize>>,
    sem_chave: Vec<usize>,
}

/// Folha de estilo já analisada.
#[derive(Debug, Clone, Default)]
pub struct Folha {
    regras: Vec<Regra>,
    indice: Indice,
    /// Regras com `display: none` que o motor não aplicou, com o motivo.
    /// Só serve para o diagnóstico.
    pub ignoradas: Vec<Ignorada>,
}

/// Pseudo-classes que nunca casam, porque o motor não tem interação nem estado.
const PSEUDO_IMPOSSIVEIS: &[&str] = &[
    "hover",
    "focus",
    "focus-within",
    "focus-visible",
    "active",
    "visited",
];

impl Folha {
    /// Analisa o CSS com a largura padrão da tela (375 pt).
    pub fn parse(css: &str) -> Folha {
        Folha::parse_largura(css, LARGURA_PADRAO)
    }

    /// Analisa o CSS com a largura da tela informada.
    /// Blocos `@media` só entram se a condição casar com essa largura.
    pub fn parse_largura(css: &str, largura: f32) -> Folha {
        let limpo = remover_comentarios(css);
        let mut regras = Vec::new();
        let mut ignoradas = Vec::new();
        ler_blocos(&limpo, largura, &mut regras, &mut ignoradas);
        let indice = construir_indice(&regras);
        Folha {
            regras,
            indice,
            ignoradas,
        }
    }
}

/// Lê regras e blocos `@media` de um trecho de CSS. Chamado de novo dentro de cada `@media`
/// que casa, então regras aninhadas também entram.
fn ler_blocos(
    texto: &str,
    largura: f32,
    regras: &mut Vec<Regra>,
    ignoradas: &mut Vec<Ignorada>,
) {
    let mut resto = texto;

    while let Some(abre) = resto.find('{') {
        // Em "@import url(x); p", o seletor começa depois do último ';'.
        let cabeca = resto[..abre].rsplit(';').next().unwrap_or("").trim();
        let depois = &resto[abre + 1..];
        let fim = fim_do_bloco(depois);
        let corpo = &depois[..fim];
        resto = depois.get(fim + 1..).unwrap_or("");

        if let Some(condicao) = cabeca.strip_prefix("@media") {
            if media_casa(condicao, largura) {
                ler_blocos(corpo, largura, regras, ignoradas);
            } else {
                let motivo = format!("@media {} não casa com {} pt", condicao.trim(), largura);
                registrar_inativos(corpo, &motivo, ignoradas);
            }
            continue;
        }

        if cabeca.starts_with('@') {
            continue;
        }

        let declaracoes = parse_declaracoes(corpo);
        let oculta = esconde(&declaracoes);
        for parte in cabeca.split(',') {
            match parse_seletor(parte) {
                Some(seletor) => {
                    let ordem = regras.len();
                    regras.push(Regra {
                        seletor,
                        declaracoes: declaracoes.clone(),
                        ordem,
                    });
                }
                None => {
                    if oculta && !parte.trim().is_empty() {
                        ignoradas.push(Ignorada {
                            seletor: parte.trim().to_string(),
                            motivo: motivo_recusa(parte),
                        });
                    }
                }
            }
        }
    }
}

/// Varre um bloco `@media` que não casou e registra as regras que esconderiam elementos.
/// Não cria regras: só guarda o que ficou de fora, para o diagnóstico.
fn registrar_inativos(texto: &str, motivo: &str, ignoradas: &mut Vec<Ignorada>) {
    let mut resto = texto;

    while let Some(abre) = resto.find('{') {
        let cabeca = resto[..abre].rsplit(';').next().unwrap_or("").trim();
        let depois = &resto[abre + 1..];
        let fim = fim_do_bloco(depois);
        let corpo = &depois[..fim];
        resto = depois.get(fim + 1..).unwrap_or("");

        if cabeca.starts_with("@media") {
            registrar_inativos(corpo, motivo, ignoradas);
            continue;
        }
        if cabeca.is_empty() || cabeca.starts_with('@') {
            continue;
        }
        if esconde(&parse_declaracoes(corpo)) {
            ignoradas.push(Ignorada {
                seletor: cabeca.to_string(),
                motivo: motivo.to_string(),
            });
        }
    }
}

/// Diz se a lista de declarações esconde o elemento (`display: none`).
fn esconde(declaracoes: &[(String, String)]) -> bool {
    declaracoes
        .iter()
        .any(|(k, v)| k == "display" && v.eq_ignore_ascii_case("none"))
}

/// Diz por que um seletor foi recusado. Usado só pelo relatório de diagnóstico.
fn motivo_recusa(texto: &str) -> String {
    let t = texto.trim();
    if !t.is_ascii() {
        return "caracteres não ASCII no seletor".to_string();
    }
    if t.contains('[') {
        return "atributo [..] não suportado".to_string();
    }
    if t.contains('~') || t.contains('+') {
        return "combinador ~ ou + não suportado".to_string();
    }
    let nomes = nomes_de_pseudo(t);
    if nomes
        .iter()
        .any(|n| PSEUDO_IMPOSSIVEIS.contains(&n.as_str()))
    {
        return "pseudo de interação (hover, focus etc.): nunca casa".to_string();
    }
    if !nomes.is_empty() {
        return format!("pseudo não suportada: {}", nomes.join(", "));
    }
    "seletor não suportado (combinador ou composto)".to_string()
}

/// Nomes das pseudo-classes e pseudo-elementos de um seletor, em minúsculas.
fn nomes_de_pseudo(t: &str) -> Vec<String> {
    t.split(':')
        .skip(1)
        .filter_map(|p| {
            let nome: String = p
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '-')
                .collect();
            if nome.is_empty() {
                None
            } else {
                Some(nome.to_ascii_lowercase())
            }
        })
        .collect()
}

/// Diz se uma lista de consultas de mídia (`screen, (max-width: 999px)`) casa com a largura.
fn media_casa(lista: &str, largura: f32) -> bool {
    lista
        .split(',')
        .any(|consulta| consulta_casa(consulta, largura))
}

/// Uma consulta de mídia, com `and`, `not` ou `only` opcionais.
fn consulta_casa(consulta: &str, largura: f32) -> bool {
    let minuscula = consulta.trim().to_ascii_lowercase();
    let (negada, sem_prefixo) = if let Some(resto) = minuscula.strip_prefix("not ") {
        (true, resto)
    } else {
        (false, minuscula.strip_prefix("only ").unwrap_or(minuscula.as_str()))
    };
    let casa = sem_prefixo
        .split(" and ")
        .all(|parte| condicao_casa(parte.trim(), largura));
    casa != negada
}

/// Uma condição de uma consulta: `(min-width: 320px)`, `(max-width: 999px)` ou um tipo de mídia.
/// Qualquer condição desconhecida não casa.
fn condicao_casa(parte: &str, largura: f32) -> bool {
    if let Some(dentro) = parte.strip_prefix('(').and_then(|p| p.strip_suffix(')')) {
        let Some((nome, valor)) = dentro.split_once(':') else {
            return false;
        };
        let Some(medida) = comprimento_media(valor) else {
            return false;
        };
        return match nome.trim() {
            "min-width" => largura >= medida,
            "max-width" => largura <= medida,
            _ => false,
        };
    }
    matches!(parte, "all" | "screen")
}

/// Lê um comprimento de consulta de mídia em px ou em em (16 px por em).
fn comprimento_media(valor: &str) -> Option<f32> {
    let v = valor.trim();
    if let Some(numero) = v.strip_suffix("px") {
        numero.trim().parse::<f32>().ok()
    } else if let Some(numero) = v.strip_suffix("em") {
        numero.trim().parse::<f32>().ok().map(|n| n * 16.0)
    } else {
        None
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

/// Calcula o estilo de um elemento sem informação de pais.
/// Seletores compostos com descendente ou filho direto não casam aqui.
pub fn estilo_para(
    folha: &Folha,
    tag: &str,
    id: Option<&str>,
    classes: &[&str],
    inline: Option<&str>,
) -> Estilo {
    let alvo = Info {
        tag: tag.to_string(),
        id: id.map(str::to_string),
        classes: classes.iter().map(|c| c.to_string()).collect(),
    };
    estilo_com_pais(folha, &alvo, &[], inline)
}

/// Calcula o estilo de um elemento.
/// `pais` vai do ancestral mais externo (raiz) até o pai imediato.
/// Ordem: folha por especificidade e ordem do arquivo, depois o estilo inline.
pub fn estilo_com_pais(
    folha: &Folha,
    alvo: &Info,
    pais: &[Info],
    inline: Option<&str>,
) -> Estilo {
    let mut candidatas: Vec<usize> = Vec::new();
    if let Some(id) = &alvo.id {
        if let Some(v) = folha.indice.por_id.get(id) {
            candidatas.extend_from_slice(v);
        }
    }
    for classe in &alvo.classes {
        if let Some(v) = folha.indice.por_classe.get(classe) {
            candidatas.extend_from_slice(v);
        }
    }
    if let Some(v) = folha.indice.por_tipo.get(&alvo.tag) {
        candidatas.extend_from_slice(v);
    }
    candidatas.extend_from_slice(&folha.indice.sem_chave);
    candidatas.sort_unstable();
    candidatas.dedup();

    let mut casadas: Vec<&Regra> = candidatas
        .iter()
        .map(|&i| &folha.regras[i])
        .filter(|r| casa_seletor(&r.seletor, alvo, pais))
        .collect();
    casadas.sort_by(|a, b| {
        a.seletor
            .especificidade
            .cmp(&b.seletor.especificidade)
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

fn construir_indice(regras: &[Regra]) -> Indice {
    let mut indice = Indice::default();
    for (i, regra) in regras.iter().enumerate() {
        let alvo = &regra.seletor.alvo;
        if let Some(id) = &alvo.id {
            indice.por_id.entry(id.clone()).or_default().push(i);
        } else if let Some(classe) = alvo.classes.first() {
            indice.por_classe.entry(classe.clone()).or_default().push(i);
        } else if let Some(tag) = &alvo.tag {
            indice.por_tipo.entry(tag.clone()).or_default().push(i);
        } else {
            indice.sem_chave.push(i);
        }
    }
    indice
}

fn casa_seletor(sel: &Seletor, alvo: &Info, pais: &[Info]) -> bool {
    casa_simples(&sel.alvo, alvo) && casa_ancestrais(&sel.anteriores, pais, pais.len())
}

fn casa_simples(s: &Simples, el: &Info) -> bool {
    if let Some(t) = &s.tag {
        if !t.eq_ignore_ascii_case(&el.tag) {
            return false;
        }
    }
    if let Some(sid) = &s.id {
        if el.id.as_deref() != Some(sid.as_str()) {
            return false;
        }
    }
    if !s.classes.iter().all(|c| el.classes.iter().any(|x| x == c)) {
        return false;
    }
    !s.negados.iter().any(|n| casa_simples(n, el))
}

/// Confere os compostos anteriores contra os pais.
/// `pos` é quantos pais ainda podem ser usados; o pai imediato é `pais[pos - 1]`.
/// No descendente, testa todos os ancestrais possíveis, para não perder um caminho válido.
fn casa_ancestrais(anteriores: &[(Combinador, Simples)], pais: &[Info], pos: usize) -> bool {
    let Some(((comb, simples), resto)) = anteriores.split_first() else {
        return true;
    };
    match comb {
        Combinador::Filho => {
            pos > 0
                && casa_simples(simples, &pais[pos - 1])
                && casa_ancestrais(resto, pais, pos - 1)
        }
        Combinador::Descendente => (0..pos).rev().any(|j| {
            casa_simples(simples, &pais[j]) && casa_ancestrais(resto, pais, j)
        }),
    }
}

/// Peso da regra: id vale mais que classe, classe mais que tipo.
fn peso(s: &Simples) -> u32 {
    (s.id.is_some() as u32) * 10_000
        + (s.classes.len() as u32) * 100
        + (s.tag.is_some() as u32)
}

/// Acha o `}` que fecha o bloco. Conta chaves aninhadas (de @media, por exemplo).
fn fim_do_bloco(texto: &str) -> usize {
    let mut profundidade = 1usize;
    for (i, c) in texto.char_indices() {
        match c {
            '{' => profundidade += 1,
            '}' => {
                profundidade -= 1;
                if profundidade == 0 {
                    return i;
                }
            }
            _ => {}
        }
    }
    texto.len()
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

/// Analisa um seletor completo. Retorna None se houver algo que o motor não entende.
fn parse_seletor(texto: &str) -> Option<Seletor> {
    let t = texto.trim();
    if t.is_empty() || !t.is_ascii() {
        return None;
    }

    // Divide em compostos, guardando o combinador que vem antes de cada um.
    let mut blocos: Vec<(Combinador, String)> = Vec::new();
    let mut atual = String::new();
    let mut combinador = Combinador::Descendente;
    let mut profundidade = 0u32;

    for c in t.chars() {
        if profundidade == 0 {
            if c == '+' || c == '~' {
                return None;
            }
            if c.is_whitespace() || c == '>' {
                if !atual.is_empty() {
                    blocos.push((combinador, std::mem::take(&mut atual)));
                    combinador = Combinador::Descendente;
                }
                if c == '>' {
                    if blocos.is_empty() {
                        return None;
                    }
                    combinador = Combinador::Filho;
                }
                continue;
            }
        }
        match c {
            '(' => profundidade += 1,
            ')' => profundidade = profundidade.checked_sub(1)?,
            _ => {}
        }
        atual.push(c);
    }

    if profundidade != 0 {
        return None;
    }
    if !atual.is_empty() {
        blocos.push((combinador, atual));
    } else if combinador == Combinador::Filho {
        return None;
    }

    let mut compostos: Vec<(Combinador, Simples)> = Vec::with_capacity(blocos.len());
    for (comb, bloco) in blocos {
        let simples = parse_composto(&bloco)?;
        if simples.impossivel {
            return None;
        }
        compostos.push((comb, simples));
    }

    // O último composto é o alvo. Os anteriores recebem o combinador do composto à direita.
    let (comb_alvo, alvo) = compostos.pop()?;
    let mut anteriores: Vec<(Combinador, Simples)> = Vec::new();
    let mut direita = comb_alvo;
    while let Some((esquerda, simples)) = compostos.pop() {
        anteriores.push((direita, simples));
        direita = esquerda;
    }

    let especificidade = peso(&alvo) + anteriores.iter().map(|(_, s)| peso(s)).sum::<u32>();
    Some(Seletor {
        alvo,
        anteriores,
        especificidade,
    })
}

/// Analisa um composto, como `p`, `.a.b`, `#x`, `*` ou `a:not(.y)`.
fn parse_composto(texto: &str) -> Option<Simples> {
    if !texto.is_ascii() {
        return None;
    }
    let bytes = texto.as_bytes();
    let mut s = Simples::default();
    let mut i = 0;

    if bytes.first() == Some(&b'*') {
        i = 1;
    } else {
        let inicio = i;
        while i < bytes.len() && eh_ident(bytes[i]) {
            i += 1;
        }
        if i > inicio {
            s.tag = Some(texto[inicio..i].to_ascii_lowercase());
        }
    }

    while i < bytes.len() {
        let marca = bytes[i];
        i += 1;
        match marca {
            b'.' => {
                let (nome, proximo) = ident_em(texto, i)?;
                s.classes.push(nome.to_string());
                i = proximo;
            }
            b'#' => {
                let (nome, proximo) = ident_em(texto, i)?;
                if s.id.is_some() {
                    return None;
                }
                s.id = Some(nome.to_string());
                i = proximo;
            }
            b':' => {
                let (nome, proximo) = ident_em(texto, i)?;
                let nome = nome.to_ascii_lowercase();
                i = proximo;
                if bytes.get(i) == Some(&b'(') {
                    let fecha = i + texto[i..].find(')')?;
                    let argumento = texto[i + 1..fecha].trim();
                    i = fecha + 1;
                    if nome != "not" {
                        return None;
                    }
                    let negado = parse_composto(argumento)?;
                    if negado.impossivel {
                        // :not(:hover) é sempre verdadeiro, então não muda nada.
                        continue;
                    }
                    if negado == Simples::default() {
                        // :not(*) nunca casa.
                        return None;
                    }
                    s.negados.push(negado);
                } else if PSEUDO_IMPOSSIVEIS.contains(&nome.as_str()) {
                    s.impossivel = true;
                } else {
                    return None;
                }
            }
            _ => return None,
        }
    }
    Some(s)
}

fn eh_ident(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'-' || c == b'_'
}

/// Lê um nome a partir de `inicio`. Devolve o nome e a posição logo depois dele.
fn ident_em(texto: &str, inicio: usize) -> Option<(&str, usize)> {
    let bytes = texto.as_bytes();
    let mut fim = inicio;
    while fim < bytes.len() && eh_ident(bytes[fim]) {
        fim += 1;
    }
    (fim > inicio).then(|| (&texto[inicio..fim], fim))
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

    fn info(tag: &str, id: Option<&str>, classes: &[&str]) -> Info {
        Info {
            tag: tag.to_string(),
            id: id.map(str::to_string),
            classes: classes.iter().map(|c| c.to_string()).collect(),
        }
    }

    fn cor_com_pais(css: &str, alvo: &Info, pais: &[Info]) -> Option<[u8; 3]> {
        estilo_com_pais(&Folha::parse(css), alvo, pais, None).cor
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

    #[test]
    fn descendente_casa_com_ancestral() {
        let css = "div p { color: red }";
        let p = info("p", None, &[]);
        assert_eq!(cor_com_pais(css, &p, &[info("div", None, &[])]), Some([255, 0, 0]));
        assert_eq!(cor_com_pais(css, &p, &[info("section", None, &[])]), None);
    }

    #[test]
    fn filho_direto_exige_pai_imediato() {
        let css = "div > p { color: red }";
        let p = info("p", None, &[]);
        let div_longe = [info("div", None, &[]), info("section", None, &[])];
        let div_perto = [info("section", None, &[]), info("div", None, &[])];
        assert_eq!(cor_com_pais(css, &p, &div_longe), None);
        assert_eq!(cor_com_pais(css, &p, &div_perto), Some([255, 0, 0]));
    }

    #[test]
    fn descendente_volta_atras_quando_o_pai_nao_casa() {
        // O <p> mais próximo tem pai <section>. O <p> de fora tem pai <div>.
        let css = "div > p span { color: red }";
        let span = info("span", None, &[]);
        let pais = [
            info("div", None, &[]),
            info("p", None, &[]),
            info("section", None, &[]),
            info("p", None, &[]),
        ];
        assert_eq!(cor_com_pais(css, &span, &pais), Some([255, 0, 0]));
    }

    #[test]
    fn not_exclui_a_classe() {
        let css = "p:not(.x) { color: red }";
        assert_eq!(estilo(css, "p").cor, Some([255, 0, 0]));
        let com_classe = info("p", None, &["x"]);
        assert_eq!(cor_com_pais(css, &com_classe, &[]), None);
    }

    #[test]
    fn not_de_pseudo_de_interacao_sempre_vale() {
        assert_eq!(estilo("p:not(:focus) { color: red }", "p").cor, Some([255, 0, 0]));
    }

    #[test]
    fn hover_nunca_casa() {
        assert_eq!(estilo("a:hover { color: red }", "a").cor, None);
    }

    #[test]
    fn pseudo_nao_suportado_e_ignorado() {
        assert_eq!(estilo("p::before { color: red }", "p").cor, None);
        assert_eq!(estilo("li:first-child { color: red }", "li").cor, None);
    }

    #[test]
    fn at_regras_sao_ignoradas() {
        let css = "@media print { p { color: red } } @import url(x.css); span { color: blue }";
        assert_eq!(estilo(css, "p").cor, None);
        assert_eq!(estilo(css, "span").cor, Some([0, 0, 255]));
    }

    #[test]
    fn universal_casa_tudo() {
        assert_eq!(estilo("* { color: blue }", "span").cor, Some([0, 0, 255]));
    }

    #[test]
    fn comentarios_sao_ignorados() {
        assert_eq!(estilo("/* x { */ span { color: blue }", "span").cor, Some([0, 0, 255]));
    }

    #[test]
    fn media_max_width_casa_em_tela_pequena() {
        let css = "@media screen and (max-width: 999px) { nav { display: none } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert!(estilo_para(&folha, "nav", None, &[], None).oculto);
    }

    #[test]
    fn media_min_width_nao_casa_em_tela_pequena() {
        let css = "@media (min-width: 720px) { p { color: red } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(estilo_para(&folha, "p", None, &[], None).cor, None);
    }

    #[test]
    fn media_min_width_casa_em_tela_grande() {
        let css = "@media (min-width: 320px) { p { color: red } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(estilo_para(&folha, "p", None, &[], None).cor, Some([255, 0, 0]));
    }

    #[test]
    fn media_lista_com_virgula_casa_se_uma_casar() {
        let css = "@media print, (max-width: 500px) { p { color: red } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(estilo_para(&folha, "p", None, &[], None).cor, Some([255, 0, 0]));
    }

    #[test]
    fn media_not_inverte_a_consulta() {
        let css = "@media not all and (min-width: 720px) { p { color: red } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(estilo_para(&folha, "p", None, &[], None).cor, Some([255, 0, 0]));
    }

    #[test]
    fn media_condicao_desconhecida_fica_de_fora() {
        let css = "@media (prefers-color-scheme: dark) { p { color: red } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(estilo_para(&folha, "p", None, &[], None).cor, None);
    }

    #[test]
    fn media_com_em_usa_16_px() {
        // 30em = 480 px, então 375 pt casa com max-width.
        let css = "@media (max-width: 30em) { p { color: red } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(estilo_para(&folha, "p", None, &[], None).cor, Some([255, 0, 0]));
    }

    #[test]
    fn parse_padrao_usa_375_pt() {
        let css = "@media (max-width: 400px) { p { color: red } }";
        assert_eq!(estilo(css, "p").cor, Some([255, 0, 0]));
    }

    #[test]
    fn seletor_com_til_e_registrado_como_ignorado() {
        let folha = Folha::parse(".a ~ .b { display: none }");
        assert_eq!(folha.ignoradas.len(), 1);
        assert!(folha.ignoradas[0].motivo.contains('~'));
    }

    #[test]
    fn regra_sem_display_none_nao_e_registrada() {
        let folha = Folha::parse(".a ~ .b { color: red }");
        assert!(folha.ignoradas.is_empty());
    }

    #[test]
    fn media_inativo_registra_regra_ocultadora() {
        let css = "@media (min-width: 720px) { nav { display: none } }";
        let folha = Folha::parse_largura(css, 375.0);
        assert_eq!(folha.ignoradas.len(), 1);
        assert!(folha.ignoradas[0].motivo.contains("não casa"));
    }
}