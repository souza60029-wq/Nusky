// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Busca de sites pelo nome, feita no aparelho sobre a lista de sites.
//!
//! A lista é lida uma vez e preparada (palavras e frases já calculadas).
//! Cada busca só compara a consulta com o que já está pronto.
//!
//! Regras gerais, sem nomes de site no código:
//! - ignora maiúsculas, acentos, pontuação e palavras vazias;
//! - reduz plural e vogal final (gratuitas e gratuito viram a mesma coisa);
//! - aceita começo de palavra ("you" acha YouTube) e erro de digitação ("gitub" acha GitHub);
//! - cada palavra digitada precisa casar com alguma coisa do site ou do atalho.

use std::collections::HashMap;

use serde_json::Value;

/// Lista que vem junto com o app. Usada quando não há lista baixada.
pub const LISTA_EMBUTIDA: &str = include_str!("../../dados/sites.json");

/// Máximo de resultados devolvidos. Mais que isso não cabe na tela e custa tempo.
pub const MAX_RESULTADOS: usize = 20;

#[derive(Debug, Clone)]
pub struct Site {
    pub nome: String,
    pub url: String,
    pub apelidos: Vec<String>,
    pub tags: Vec<String>,
    pub atalhos: Vec<Atalho>,
}

#[derive(Debug, Clone)]
pub struct Atalho {
    pub titulo: String,
    pub caminho: String,
    pub apelidos: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Resultado {
    /// Índice do site na lista.
    pub site: usize,
    /// Índice do atalho dentro do site, se o resultado for um atalho.
    pub atalho: Option<usize>,
    pub pontos: u32,
    /// Quantas vezes esse endereço foi aberto pela busca. Fica só no aparelho.
    pub uso: u32,
}

const PALAVRAS_VAZIAS: &[&str] = &[
    "o", "a", "os", "as", "um", "uma", "de", "do", "da", "dos", "das", "em", "no", "na",
    "nos", "nas", "para", "pra", "por", "com", "e", "site", "sites", "www", "http",
    "https", "br", "org", "net", "io", "pt", "melhor", "melhores", "ir", "abrir",
    "acessar", "entrar",
];

/// Lista pronta para busca. Montada uma vez, quando a lista carrega.
pub struct Indice {
    pub versao: u32,
    pub data: String,
    sites: Vec<Site>,
    indexados: Vec<SiteIndexado>,
}

struct SiteIndexado {
    /// Nome, apelidos e tags do site.
    campos: Vec<Campo>,
    /// Para cada atalho, os campos próprios dele (título e apelidos).
    atalhos: Vec<Vec<Campo>>,
}

impl Indice {
    /// Lê o JSON da lista. Se algo estiver errado, devolve a mensagem e nada é carregado.
    pub fn carregar(json: &str) -> Result<Indice, String> {
        let raiz: Value =
            serde_json::from_str(json).map_err(|e| format!("Lista inválida: {e}"))?;
        let versao = raiz.get("versao").and_then(Value::as_u64).unwrap_or(0) as u32;
        let data = raiz
            .get("data")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let itens = raiz
            .get("sites")
            .and_then(Value::as_array)
            .ok_or_else(|| "Lista sem o campo 'sites'.".to_string())?;
        let sites = itens
            .iter()
            .map(site_de_json)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Indice::montar(versao, data, sites))
    }

    /// Monta o índice a partir de sites já prontos.
    pub fn montar(versao: u32, data: String, sites: Vec<Site>) -> Indice {
        let indexados = sites.iter().map(indexar).collect();
        Indice { versao, data, sites, indexados }
    }

    pub fn sites(&self) -> &[Site] {
        &self.sites
    }

    pub fn total(&self) -> usize {
        self.sites.len()
    }

    /// Endereço para abrir: a página principal ou o atalho.
    pub fn endereco(&self, r: &Resultado) -> String {
        let site = &self.sites[r.site];
        match r.atalho.and_then(|k| site.atalhos.get(k)) {
            Some(a) => format!("{}{}", site.url, a.caminho),
            None => site.url.clone(),
        }
    }

    /// Procura sites e atalhos. `usos` diz quantas vezes cada endereço foi aberto, vindo do aparelho.
    /// Os resultados vêm do mais relevante para o menos. Lista vazia quando nada casa.
    pub fn buscar(&self, consulta: &str, usos: &HashMap<String, u32>) -> Vec<Resultado> {
        let palavras = palavras_de(consulta);
        if palavras.is_empty() {
            return Vec::new();
        }
        let junta = palavras.concat();

        let mut achados = Vec::new();
        for (i, (site, pronto)) in self.sites.iter().zip(&self.indexados).enumerate() {
            if let Some(pontos) = pontuar(&palavras, &junta, &pronto.campos, &[]) {
                let uso = usos.get(&site.url).copied().unwrap_or(0);
                achados.push(Resultado { site: i, atalho: None, pontos, uso });
            }

            for (k, (atalho, campos_atalho)) in site.atalhos.iter().zip(&pronto.atalhos).enumerate() {
                // O atalho só aparece se a busca casar com o próprio atalho.
                // Assim, "github" mostra o site, e não todos os atalhos dele.
                let casa_proprio = palavras
                    .iter()
                    .any(|p| campos_atalho.iter().any(|c| melhor_no_campo(p, c) > 0));
                if !casa_proprio {
                    continue;
                }
                if let Some(pontos) = pontuar(&palavras, &junta, campos_atalho, &pronto.campos) {
                    let endereco = format!("{}{}", site.url, atalho.caminho);
                    let uso = usos.get(&endereco).copied().unwrap_or(0);
                    achados.push(Resultado { site: i, atalho: Some(k), pontos, uso });
                }
            }
        }

        achados.sort_by(|a, b| {
            let pa = a.pontos + bonus_de_uso(a.uso);
            let pb = b.pontos + bonus_de_uso(b.uso);
            pb.cmp(&pa)
                .then_with(|| self.sites[a.site].nome.cmp(&self.sites[b.site].nome))
        });
        achados.truncate(MAX_RESULTADOS);
        achados
    }

    /// Quando nada casa, sugere o site com nome parecido (até 3 letras diferentes).
    pub fn sugestao(&self, consulta: &str) -> Option<usize> {
        let junta = palavras_de(consulta).concat();
        let tamanho = junta.chars().count();
        if tamanho < 4 {
            return None;
        }
        let mut melhor: Option<(usize, usize)> = None;
        for (i, pronto) in self.indexados.iter().enumerate() {
            for c in pronto.campos.iter().filter(|c| c.peso >= 90) {
                if c.frase.chars().count().abs_diff(tamanho) > 3 {
                    continue;
                }
                let d = distancia(&junta, &c.frase);
                if d <= 3 && melhor.map_or(true, |(_, md)| d < md) {
                    melhor = Some((i, d));
                }
            }
        }
        melhor.map(|(i, _)| i)
    }
}

/// Lista embutida, pronta para uso. Usada quando não há lista baixada.
pub fn indice_embutido() -> Result<Indice, String> {
    Indice::carregar(LISTA_EMBUTIDA)
}

// MARK: - Leitura do JSON

fn site_de_json(item: &Value) -> Result<Site, String> {
    let nome = texto_obrigatorio(item, "nome")?;
    let url = texto_obrigatorio(item, "url")?;
    if !url.starts_with("https://") {
        return Err(format!("Endereço de '{nome}' precisa começar com https://."));
    }
    let atalhos = match item.get("atalhos").and_then(Value::as_array) {
        Some(lista) => lista
            .iter()
            .map(atalho_de_json)
            .collect::<Result<Vec<_>, _>>()?,
        None => Vec::new(),
    };
    Ok(Site {
        nome,
        url,
        apelidos: lista_de_textos(item, "apelidos"),
        tags: lista_de_textos(item, "tags"),
        atalhos,
    })
}

fn atalho_de_json(item: &Value) -> Result<Atalho, String> {
    let titulo = texto_obrigatorio(item, "titulo")?;
    let caminho = texto_obrigatorio(item, "caminho")?;
    if !caminho.starts_with('/') {
        return Err(format!("Caminho de '{titulo}' precisa começar com /."));
    }
    Ok(Atalho {
        titulo,
        caminho,
        apelidos: lista_de_textos(item, "apelidos"),
    })
}

fn texto_obrigatorio(v: &Value, chave: &str) -> Result<String, String> {
    v.get(chave)
        .and_then(Value::as_str)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("Campo '{chave}' ausente ou vazio."))
}

fn lista_de_textos(v: &Value, chave: &str) -> Vec<String> {
    v.get(chave)
        .and_then(Value::as_array)
        .map(|itens| {
            itens
                .iter()
                .filter_map(Value::as_str)
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

// MARK: - Preparo

/// Um trecho pesquisável de um site ou atalho, com peso próprio.
struct Campo {
    tokens: Vec<String>,
    frase: String,
    peso: u32,
}

fn campo(texto: &str, peso: u32) -> Campo {
    let tokens = palavras_de(texto);
    let frase = tokens.concat();
    Campo { tokens, frase, peso }
}

fn indexar(site: &Site) -> SiteIndexado {
    SiteIndexado {
        campos: campos_do_site(site),
        atalhos: site.atalhos.iter().map(campos_do_atalho).collect(),
    }
}

fn campos_do_site(site: &Site) -> Vec<Campo> {
    let mut campos = vec![campo(&site.nome, 100)];
    campos.extend(site.apelidos.iter().map(|a| campo(a, 90)));
    campos.extend(site.tags.iter().map(|t| campo(t, 50)));
    campos
}

fn campos_do_atalho(atalho: &Atalho) -> Vec<Campo> {
    let mut campos = vec![campo(&atalho.titulo, 90)];
    campos.extend(atalho.apelidos.iter().map(|a| campo(a, 90)));
    campos
}

// MARK: - Pontuação

/// Soma a melhor coincidência de cada palavra. Se alguma palavra não casar, devolve None.
fn pontuar(palavras: &[String], junta: &str, a: &[Campo], b: &[Campo]) -> Option<u32> {
    let mut total = 0;
    for p in palavras {
        let melhor = a
            .iter()
            .chain(b.iter())
            .map(|c| melhor_no_campo(p, c))
            .max()
            .unwrap_or(0);
        if melhor == 0 {
            return None;
        }
        total += melhor;
    }
    // Bônus quando a busca inteira é um nome ou apelido, com ou sem espaços ("chat gpt" = "chatgpt").
    if a.iter().chain(b.iter()).any(|c| c.peso >= 90 && c.frase == junta) {
        total += 50;
    }
    Some(total)
}

fn melhor_no_campo(palavra: &str, c: &Campo) -> u32 {
    c.tokens
        .iter()
        .map(|t| pontos_da_palavra(palavra, t) * c.peso / 100)
        .max()
        .unwrap_or(0)
}

fn pontos_da_palavra(palavra: &str, alvo: &str) -> u32 {
    if palavra == alvo {
        return 100;
    }
    if palavra.chars().count() >= 3 && alvo.starts_with(palavra) {
        return 80;
    }
    if erro_aceitavel(palavra, alvo) {
        return 60;
    }
    0
}

/// Quantas letras podem estar erradas, conforme o tamanho da palavra.
/// Palavras curtas não aceitam erro, senão "ia" acharia qualquer coisa.
fn limite_de_erro(tamanho: usize) -> usize {
    match tamanho {
        0..=4 => 0,
        5..=8 => 1,
        _ => 2,
    }
}

/// Confere erro de digitação. Antes de calcular a distância, descarta palavras de tamanho muito diferente.
fn erro_aceitavel(palavra: &str, alvo: &str) -> bool {
    let n = palavra.chars().count();
    let limite = limite_de_erro(n);
    if limite == 0 {
        return false;
    }
    if n.abs_diff(alvo.chars().count()) > limite {
        return false;
    }
    distancia(palavra, alvo) <= limite
}

/// Bônus pequeno para o que foi aberto muitas vezes. Limitado, para não passar do que casa melhor.
fn bonus_de_uso(uso: u32) -> u32 {
    uso.min(10) * 2
}

// MARK: - Texto

fn palavras_de(texto: &str) -> Vec<String> {
    let mut limpo = String::new();
    for c in texto.to_lowercase().chars() {
        let c = sem_acento(c);
        limpo.push(if c.is_alphanumeric() { c } else { ' ' });
    }
    limpo
        .split_whitespace()
        .filter(|p| !PALAVRAS_VAZIAS.contains(p))
        .map(raiz)
        .collect()
}

fn sem_acento(c: char) -> char {
    match c {
        'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
        'é' | 'è' | 'ê' | 'ë' => 'e',
        'í' | 'ì' | 'î' | 'ï' => 'i',
        'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
        'ú' | 'ù' | 'û' | 'ü' => 'u',
        'ç' => 'c',
        'ñ' => 'n',
        outro => outro,
    }
}

/// Reduz a palavra à raiz: tira o "s" do plural e a vogal final.
fn raiz(palavra: &str) -> String {
    let mut p = palavra.to_string();
    if p.chars().count() > 3 && p.ends_with('s') {
        p.pop();
    }
    if p.chars().count() > 4 && (p.ends_with('a') || p.ends_with('o') || p.ends_with('e')) {
        p.pop();
    }
    p
}

/// Número mínimo de trocas, apagas ou inserções de letras para transformar `a` em `b`.
/// Trocar duas letras vizinhas conta como um erro só.
fn distancia(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let (n, m) = (a.len(), b.len());
    let mut d = vec![vec![0usize; m + 1]; n + 1];
    for i in 0..=n {
        d[i][0] = i;
    }
    for j in 0..=m {
        d[0][j] = j;
    }
    for i in 1..=n {
        for j in 1..=m {
            let custo = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            d[i][j] = (d[i - 1][j] + 1)
                .min(d[i][j - 1] + 1)
                .min(d[i - 1][j - 1] + custo);
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                d[i][j] = d[i][j].min(d[i - 2][j - 2] + 1);
            }
        }
    }
    d[n][m]
}

#[cfg(test)]
mod testes {
    use super::*;

    fn site(nome: &str, url: &str, apelidos: &[&str], tags: &[&str], atalhos: Vec<Atalho>) -> Site {
        Site {
            nome: nome.into(),
            url: url.into(),
            apelidos: apelidos.iter().map(|s| s.to_string()).collect(),
            tags: tags.iter().map(|s| s.to_string()).collect(),
            atalhos,
        }
    }

    fn atalho(titulo: &str, caminho: &str, apelidos: &[&str]) -> Atalho {
        Atalho {
            titulo: titulo.into(),
            caminho: caminho.into(),
            apelidos: apelidos.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn lista() -> Vec<Site> {
        vec![
            site(
                "Arena", "https://arena.ai",
                &["arena", "lmarena", "lm arena"],
                &["ia", "inteligência artificial", "chat"],
                vec![],
            ),
            site(
                "ChatGPT", "https://chatgpt.com",
                &["chatgpt", "chat gpt", "openai"],
                &["ia", "inteligência artificial", "chat", "gratuito", "escrever"],
                vec![],
            ),
            site(
                "Claude", "https://claude.ai",
                &["claude", "anthropic"],
                &["ia", "inteligência artificial", "chat", "programação"],
                vec![],
            ),
            site(
                "Discord", "https://discord.com",
                &["discord"],
                &["conversa", "chat", "voz"],
                vec![],
            ),
            site(
                "Wikipédia", "https://pt.wikipedia.org",
                &["wikipedia", "wikipédia", "wiki"],
                &["enciclopédia", "pesquisa"],
                vec![atalho("Esplanada", "/wiki/Wikip%C3%A9dia:Esplanada", &["esplanada"])],
            ),
            site(
                "GitHub", "https://github.com",
                &["github", "git hub", "gitub"],
                &["código", "programação"],
                vec![
                    atalho("Explorar", "/explore", &["explorar", "explore"]),
                    atalho("Meu perfil", "/souza60029-wq", &["meu perfil", "meus repositórios", "perfil"]),
                ],
            ),
            site(
                "YouTube", "https://youtube.com",
                &["youtube", "you tube", "yt"],
                &["vídeo", "vídeos", "assistir", "música"],
                vec![],
            ),
            site(
                "Pinterest", "https://pinterest.com",
                &["pinterest"],
                &["imagens", "inspiração"],
                vec![],
            ),
        ]
    }

    fn indice() -> Indice {
        Indice::montar(1, "teste".into(), lista())
    }

    fn primeiro(consulta: &str) -> String {
        let indice = indice();
        indice
            .buscar(consulta, &HashMap::new())
            .first()
            .map(|r| indice.sites()[r.site].nome.clone())
            .unwrap_or_default()
    }

    #[test]
    fn erro_de_letra_acha_o_site() {
        assert_eq!(primeiro("gitub"), "GitHub");
    }

    #[test]
    fn espacos_e_maiusculas_nao_importam() {
        assert_eq!(primeiro("git hub"), "GitHub");
        assert_eq!(primeiro("GITHUB.COM"), "GitHub");
    }

    #[test]
    fn nome_com_espaco_acha_o_nome_colado() {
        assert_eq!(primeiro("chat gpt"), "ChatGPT");
    }

    #[test]
    fn prefixo_acha_o_site() {
        assert_eq!(primeiro("you"), "YouTube");
    }

    #[test]
    fn sem_acento_acha_o_site() {
        assert_eq!(primeiro("wikipedia"), "Wikipédia");
    }

    #[test]
    fn tag_acha_varios_sites() {
        let indice = indice();
        let achados = indice.buscar("ia", &HashMap::new());
        let nomes: Vec<String> = achados
            .iter()
            .map(|r| indice.sites()[r.site].nome.clone())
            .collect();
        assert!(nomes.contains(&"ChatGPT".to_string()));
        assert!(nomes.contains(&"Claude".to_string()));
        assert!(nomes.contains(&"Arena".to_string()));
        assert!(!nomes.contains(&"YouTube".to_string()));
    }

    #[test]
    fn plural_e_genero_se_encontram() {
        assert_eq!(primeiro("gratuitas"), "ChatGPT");
    }

    #[test]
    fn atalho_aparece_com_o_site() {
        let indice = indice();
        let achados = indice.buscar("meu perfil", &HashMap::new());
        assert_eq!(achados[0].atalho, Some(1));
        assert_eq!(indice.sites()[achados[0].site].nome, "GitHub");
        assert_eq!(indice.endereco(&achados[0]), "https://github.com/souza60029-wq");
    }

    #[test]
    fn nome_do_site_nao_mostra_todos_os_atalhos() {
        let indice = indice();
        let achados = indice.buscar("github", &HashMap::new());
        assert!(achados.iter().all(|r| r.atalho.is_none()));
    }

    #[test]
    fn palavra_sem_sentido_nao_acha_nada() {
        assert!(indice().buscar("xyzqw", &HashMap::new()).is_empty());
    }

    #[test]
    fn so_palavras_vazias_nao_acham_nada() {
        assert!(indice().buscar("o de", &HashMap::new()).is_empty());
    }

    #[test]
    fn uso_sobe_o_resultado() {
        let indice = indice();
        let mut usos = HashMap::new();
        usos.insert("https://claude.ai".to_string(), 10);
        let achados = indice.buscar("ia", &usos);
        assert_eq!(indice.sites()[achados[0].site].nome, "Claude");
    }

    #[test]
    fn sugestao_corrige_letra_trocada() {
        let indice = indice();
        let achado = indice
            .sugestao("chatgtp")
            .map(|i| indice.sites()[i].nome.clone());
        assert_eq!(achado, Some("ChatGPT".to_string()));
    }

    #[test]
    fn troca_de_letras_conta_como_um_erro() {
        assert_eq!(distancia("gitub", "github"), 1);
        assert_eq!(distancia("ab", "ba"), 1);
    }

    #[test]
    fn lista_embutida_carrega() {
        let indice = indice_embutido().expect("dados/sites.json precisa ser válido");
        assert!(indice.total() > 0);
        assert!(indice.versao >= 1);
    }

    #[test]
    fn endereco_sem_https_e_recusado() {
        let json = r#"{"versao":1,"sites":[{"nome":"Teste","url":"http://teste.com"}]}"#;
        assert!(Indice::carregar(json).is_err());
    }

    #[test]
    fn json_quebrado_e_recusado() {
        assert!(Indice::carregar("{ isto não é json").is_err());
    }
}