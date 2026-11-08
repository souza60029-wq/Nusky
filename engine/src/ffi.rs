// engine/src/ffi.rs
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Interface C do motor, chamada pela casca Swift.
//!
//! Renderização:
//! `nusky_render` recebe HTML e, opcionalmente, uma função de medição fornecida pela casca.
//! Formato de saída: uma linha por comando de texto, com campos separados por tab:
//! `x<TAB>y<TAB>tamanho<TAB>negrito(0/1)<TAB>link<TAB>cor<TAB>texto`.
//! O campo `link` fica vazio quando o texto não é link.
//! O campo `cor` é `r,g,b` (0 a 255), ou vazio quando a página não definiu cor.
//!
//! Antes do layout, o HTML passa por `preparo::marcar_com_javascript`, que troca
//! "client-nojs" por "client-js" na tag <html>.
//!
//! `nusky_diagnose` aceita os mesmos argumentos e devolve um relatório em texto
//! (ver `diagnostico.rs`). Não altera a renderização.
//!
//! Árvore para o JavaScript:
//! `nusky_arvore` devolve a árvore do HTML (depois de `marcar_com_javascript`) em JSON.
//! Elementos: `{"t":"e","g":tag,"a":{atributos},"c":[filhos]}`.
//! Textos: `{"t":"x","v":texto}`. Comentários: `{"t":"c","v":texto}` (o React depende deles).
//! O resultado é uma lista de nós de topo.
//!
//! Busca de sites:
//! - `nusky_busca_carregar`: lê a lista (JSON). Sem argumento, usa a lista embutida.
//!   Se a lista estiver errada, devolve 1 e mantém a lista que já estava carregada.
//! - `nusky_busca_versao`: versão da lista em uso (0 se nenhuma foi carregada).
//! - `nusky_busca_data`: data da lista em uso, no formato aaaa-mm-dd (vazia se não houver).
//! - `nusky_busca_definir_usos`: recebe as contagens de abertura, uma por linha,
//!   no formato `endereco<TAB>contagem`. Vêm do aparelho.
//! - `nusky_busca_registrar_uso`: soma uma abertura a um endereço.
//! - `nusky_busca`: devolve os resultados, uma linha por item:
//!   `endereco<TAB>nome do site<TAB>título do atalho (vazio se for o site)`.
//! - `nusky_busca_sugestao`: devolve `nome<TAB>endereço` do site mais parecido, ou vazio.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::sync::Mutex;

use serde_json::{json, Value};

use crate::busca::{indice_embutido, Indice};
use crate::diagnostico::relatorio;
use crate::html::{parse, parse_com_comentarios, Node, TAG_COMENTARIO};
use crate::layout::{layout, DrawCommand, TextMeasurer};
use crate::preparo::marcar_com_javascript;

/// Lista embutida no app, para ler o cabeçalho (versão e data) sem depender de `busca.rs`.
const TEXTO_EMBUTIDO: &str = include_str!("../../dados/sites.json");

/// Função de medição da casca: largura em pontos de um texto UTF-8 terminado em NUL,
/// na fonte indicada. `bold` é 0 ou 1.
pub type MeasureFn = extern "C" fn(text: *const c_char, font_size: f32, bold: c_int) -> f32;

/// Mede com a função da casca. Guarda os resultados desta renderização,
/// para não cruzar a fronteira C para cada palavra repetida.
struct CallbackMeasurer {
    measure: MeasureFn,
    cache: RefCell<HashMap<(String, u32, bool), f32>>,
}

impl TextMeasurer for CallbackMeasurer {
    fn measure(&self, text: &str, font_size: f32, bold: bool) -> f32 {
        let key = (text.to_string(), font_size.to_bits(), bold);
        if let Some(width) = self.cache.borrow().get(&key) {
            return *width;
        }
        let width = match CString::new(text.replace('\0', "")) {
            Ok(c) => (self.measure)(c.as_ptr(), font_size, bold as c_int),
            Err(_) => 0.0,
        };
        self.cache.borrow_mut().insert(key, width);
        width
    }
}

/// Medida aproximada, usada quando a casca não fornece a função de medição.
struct ApproxMeasurer;

impl TextMeasurer for ApproxMeasurer {
    fn measure(&self, text: &str, font_size: f32, _bold: bool) -> f32 {
        text.chars().count() as f32 * font_size * 0.5
    }
}

/// Tab, quebra de linha e NUL quebrariam o formato; trocamos por espaço.
fn sanitize(s: &str) -> String {
    s.replace(|c: char| matches!(c, '\t' | '\n' | '\r' | '\0'), " ")
}

/// Cor como "r,g,b", ou vazio quando a página não definiu cor.
fn formatar_cor(cor: Option<[u8; 3]>) -> String {
    match cor {
        Some([r, g, b]) => format!("{},{},{}", r, g, b),
        None => String::new(),
    }
}

/// Renderiza HTML (C string em UTF-8) para uma lista de comandos de texto.
/// Retorna null em caso de erro. Quem chama deve liberar o resultado
/// com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_render(
    html: *const c_char,
    viewport_width: f32,
    measure: Option<MeasureFn>,
) -> *mut c_char {
    if html.is_null() {
        return ptr::null_mut();
    }
    let bruto = unsafe { CStr::from_ptr(html) }.to_string_lossy();
    let input = marcar_com_javascript(&bruto);
    let nodes = parse(&input);

    let commands = match measure {
        Some(f) => layout(
            &nodes,
            viewport_width,
            &CallbackMeasurer { measure: f, cache: RefCell::new(HashMap::new()) },
        ),
        None => layout(&nodes, viewport_width, &ApproxMeasurer),
    };

    let mut out = String::new();
    for cmd in commands {
        match cmd {
            DrawCommand::Text { x, y, text, font_size, bold, href, color } => {
                out.push_str(&format!(
                    "{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                    x,
                    y,
                    font_size,
                    bold as u8,
                    sanitize(href.as_deref().unwrap_or("")),
                    formatar_cor(color),
                    sanitize(&text),
                ));
            }
        }
    }

    match CString::new(out) {
        Ok(s) => s.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Gera o relatório de diagnóstico da página (texto em UTF-8).
/// Mesmos argumentos de `nusky_render`. Retorna null em caso de erro.
/// Quem chama deve liberar o resultado com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_diagnose(
    html: *const c_char,
    viewport_width: f32,
    measure: Option<MeasureFn>,
) -> *mut c_char {
    if html.is_null() {
        return ptr::null_mut();
    }
    let bruto = unsafe { CStr::from_ptr(html) }.to_string_lossy();
    let input = marcar_com_javascript(&bruto);

    let texto = match measure {
        Some(f) => relatorio(
            &input,
            viewport_width,
            &CallbackMeasurer { measure: f, cache: RefCell::new(HashMap::new()) },
        ),
        None => relatorio(&input, viewport_width, &ApproxMeasurer),
    };

    // NUL não cabe numa C string; trocamos por espaço.
    match CString::new(texto.replace('\0', " ")) {
        Ok(s) => s.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// MARK: - Árvore para o JavaScript

/// Um nó do HTML como JSON. Elementos: `t` = "e", `g` = tag, `a` = atributos, `c` = filhos.
/// Textos: `t` = "x", `v` = texto.
fn no_para_json(no: &Node) -> Value {
    match no {
        Node::Text(texto) => json!({ "t": "x", "v": texto }),
        Node::Element(el) if el.tag == TAG_COMENTARIO => {
            json!({ "t": "c", "v": el.attr("data").unwrap_or("") })
        }
        Node::Element(el) => {
            let mut atributos = serde_json::Map::new();
            // Em HTML vale o primeiro atributo quando o nome se repete.
            for (nome, valor) in &el.attrs {
                atributos
                    .entry(nome.clone())
                    .or_insert_with(|| Value::String(valor.clone()));
            }
            let filhos: Vec<Value> = el.children.iter().map(no_para_json).collect();
            json!({ "t": "e", "g": el.tag.clone(), "a": atributos, "c": filhos })
        }
    }
}

/// Árvore do HTML em JSON, depois de `marcar_com_javascript`. Lista de nós de topo.
pub fn arvore_de(html: &str) -> String {
    let nodes = parse_com_comentarios(&marcar_com_javascript(html));
    Value::Array(nodes.iter().map(no_para_json).collect()).to_string()
}

/// Devolve a árvore do HTML em JSON (ver `arvore_de`). Retorna null se o HTML for null.
/// Quem chama deve liberar o resultado com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_arvore(html: *const c_char) -> *mut c_char {
    if html.is_null() {
        return ptr::null_mut();
    }
    let bruto = unsafe { CStr::from_ptr(html) }.to_string_lossy();
    devolver(arvore_de(&bruto))
}

/// Libera uma string devolvida por `nusky_render`, `nusky_diagnose`, `nusky_arvore` ou as funções de busca.
#[no_mangle]
pub extern "C" fn nusky_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

// MARK: - Busca

/// Estado da busca: a lista pronta, sua origem e as contagens de abertura vindas do aparelho.
struct Estado {
    indice: Indice,
    usos: HashMap<String, u32>,
    versao: i32,
    data: String,
}

/// Guardado aqui para a lista ficar na memória entre as chamadas.
static BUSCA: Mutex<Option<Estado>> = Mutex::new(None);

/// Roda `f` sobre o estado da busca. Se ainda não houver lista, carrega a embutida.
/// Devolve None se nem a lista embutida conseguir carregar.
fn com_busca<R>(f: impl FnOnce(&mut Estado) -> R) -> Option<R> {
    let mut guarda = BUSCA.lock().unwrap_or_else(|e| e.into_inner());
    if guarda.is_none() {
        let indice = indice_embutido().ok()?;
        let (versao, data) = origem_de(TEXTO_EMBUTIDO);
        *guarda = Some(Estado { indice, usos: HashMap::new(), versao, data });
    }
    guarda.as_mut().map(f)
}

fn ler_texto(p: *const c_char) -> Option<String> {
    if p.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned())
    }
}

fn devolver(texto: String) -> *mut c_char {
    match CString::new(texto.replace('\0', " ")) {
        Ok(s) => s.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Versão e data do cabeçalho de uma lista. Se o cabeçalho não puder ser lido, devolve (0, "").
fn origem_de(texto: &str) -> (i32, String) {
    let Ok(valor) = serde_json::from_str::<serde_json::Value>(texto) else {
        return (0, String::new());
    };
    let versao = valor
        .get("versao")
        .and_then(|v| v.as_i64())
        .and_then(|v| i32::try_from(v).ok())
        .unwrap_or(0);
    let data = valor
        .get("data")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    (versao, data)
}

/// Lê linhas `endereco<TAB>contagem`. Linhas fora do formato são ignoradas.
fn ler_usos(texto: &str) -> HashMap<String, u32> {
    texto
        .lines()
        .filter_map(|linha| {
            let (endereco, contagem) = linha.split_once('\t')?;
            Some((endereco.to_string(), contagem.trim().parse().ok()?))
        })
        .collect()
}

/// Texto de resultados da busca, uma linha por item. Separado para poder ser testado.
fn formatar_busca(indice: &Indice, consulta: &str, usos: &HashMap<String, u32>) -> String {
    let mut out = String::new();
    for r in indice.buscar(consulta, usos) {
        let site = &indice.sites()[r.site];
        let rotulo = r
            .atalho
            .and_then(|k| site.atalhos.get(k))
            .map(|a| a.titulo.as_str())
            .unwrap_or("");
        out.push_str(&format!(
            "{}\t{}\t{}\n",
            sanitize(&indice.endereco(&r)),
            sanitize(&site.nome),
            sanitize(rotulo),
        ));
    }
    out
}

/// Texto da sugestão ("você quis dizer…"), ou vazio. Separado para poder ser testado.
fn formatar_sugestao(indice: &Indice, consulta: &str) -> String {
    match indice.sugestao(consulta) {
        Some(i) => {
            let site = &indice.sites()[i];
            format!("{}\t{}\n", sanitize(&site.nome), sanitize(&site.url))
        }
        None => String::new(),
    }
}

/// Carrega a lista de sites. `json` é o conteúdo de `dados/sites.json`, em UTF-8.
/// Se for null, carrega a lista embutida no app.
/// Retorna 0 se deu certo, ou 1 se a lista estiver errada (a anterior continua valendo).
/// As contagens de abertura são mantidas.
#[no_mangle]
pub extern "C" fn nusky_busca_carregar(json: *const c_char) -> c_int {
    let novo = match ler_texto(json) {
        Some(texto) => Indice::carregar(&texto).map(|i| (i, origem_de(&texto))),
        None => indice_embutido().map(|i| (i, origem_de(TEXTO_EMBUTIDO))),
    };
    match novo {
        Ok((indice, (versao, data))) => {
            let mut guarda = BUSCA.lock().unwrap_or_else(|e| e.into_inner());
            let usos = guarda.take().map(|e| e.usos).unwrap_or_default();
            *guarda = Some(Estado { indice, usos, versao, data });
            0
        }
        Err(_) => 1,
    }
}

/// Versão da lista em uso. Devolve 0 se nenhuma lista tiver versão legível.
#[no_mangle]
pub extern "C" fn nusky_busca_versao() -> c_int {
    com_busca(|e| e.versao).unwrap_or(0)
}

/// Data da lista em uso (aaaa-mm-dd). Vazia se não houver. Retorna null só em erro de memória.
/// Quem chama deve liberar o resultado com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_busca_data() -> *mut c_char {
    let texto = com_busca(|e| e.data.clone()).unwrap_or_default();
    devolver(texto)
}

/// Substitui as contagens de abertura. Texto com uma linha por endereço: `endereco<TAB>contagem`.
#[no_mangle]
pub extern "C" fn nusky_busca_definir_usos(texto: *const c_char) {
    if let Some(t) = ler_texto(texto) {
        let usos = ler_usos(&t);
        com_busca(|e| e.usos = usos);
    }
}

/// Soma uma abertura ao endereço, quando o site ou atalho é aberto pela busca.
#[no_mangle]
pub extern "C" fn nusky_busca_registrar_uso(endereco: *const c_char) {
    if let Some(e) = ler_texto(endereco) {
        com_busca(|estado| *estado.usos.entry(e).or_insert(0) += 1);
    }
}

/// Busca por nome. Devolve linhas `endereco<TAB>nome<TAB>título do atalho`.
/// Lista vazia quando nada casa. Retorna null se o texto for null.
/// Quem chama deve liberar o resultado com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_busca(consulta: *const c_char) -> *mut c_char {
    let Some(texto) = ler_texto(consulta) else {
        return ptr::null_mut();
    };
    let saida = com_busca(|e| formatar_busca(&e.indice, &texto, &e.usos)).unwrap_or_default();
    devolver(saida)
}

/// Sugestão quando a busca não acha nada. Devolve `nome<TAB>endereço`, ou vazio.
/// Retorna null se o texto for null. Quem chama deve liberar com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_busca_sugestao(consulta: *const c_char) -> *mut c_char {
    let Some(texto) = ler_texto(consulta) else {
        return ptr::null_mut();
    };
    let saida = com_busca(|e| formatar_sugestao(&e.indice, &texto)).unwrap_or_default();
    devolver(saida)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render_with(html: &str, measure: Option<MeasureFn>) -> String {
        let c = CString::new(html).unwrap();
        let p = nusky_render(c.as_ptr(), 400.0, measure);
        assert!(!p.is_null());
        let out = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
        nusky_free_string(p);
        out
    }

    /// Medida fictícia: qualquer palavra mede 300 px.
    extern "C" fn wide_measure(_text: *const c_char, _size: f32, _bold: c_int) -> f32 {
        300.0
    }

    #[test]
    fn render_returns_tab_separated_lines() {
        assert_eq!(render_with("<p>oi</p>", None), "8\t24\t16\t0\t\t\toi\n");
    }

    #[test]
    fn render_includes_link_target() {
        assert_eq!(render_with(r#"<a href="/x">oi</a>"#, None), "8\t8\t16\t0\t/x\t\toi\n");
    }

    #[test]
    fn render_includes_css_color() {
        assert_eq!(
            render_with(r#"<p style="color: red">oi</p>"#, None),
            "8\t24\t16\t0\t\t255,0,0\toi\n"
        );
    }

    #[test]
    fn callback_measure_drives_wrapping() {
        // Com 300 px por palavra, duas palavras não cabem em 384 px úteis.
        let out = render_with("<p>aa bb</p>", Some(wide_measure));
        assert_eq!(out.lines().count(), 2);
    }

    #[test]
    fn entities_are_decoded_in_output() {
        assert_eq!(render_with("<p>a &amp; b</p>", None), "8\t24\t16\t0\t\t\ta & b\n");
    }

    #[test]
    fn null_input_returns_null() {
        assert!(nusky_render(ptr::null(), 400.0, None).is_null());
    }

    #[test]
    fn diagnose_returns_report() {
        let c = CString::new("<p>oi</p>").unwrap();
        let p = nusky_diagnose(c.as_ptr(), 400.0, None);
        assert!(!p.is_null());
        let out = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
        nusky_free_string(p);
        assert!(out.contains("No HTML visível: 2 caracteres"));
    }

    #[test]
    fn diagnose_null_input_returns_null() {
        assert!(nusky_diagnose(ptr::null(), 400.0, None).is_null());
    }

    #[test]
    fn arvore_leva_tags_textos_e_atributos() {
        let valor: Value = serde_json::from_str(&arvore_de(r#"<p class="x">oi</p>"#)).unwrap();
        assert_eq!(valor[0]["t"], "e");
        assert_eq!(valor[0]["g"], "p");
        assert_eq!(valor[0]["a"]["class"], "x");
        assert_eq!(valor[0]["c"][0]["t"], "x");
        assert_eq!(valor[0]["c"][0]["v"], "oi");
    }

    #[test]
    fn arvore_mantem_script_como_texto() {
        let valor: Value = serde_json::from_str(&arvore_de("<script>if (a<b) {}</script>")).unwrap();
        assert_eq!(valor[0]["g"], "script");
        assert_eq!(valor[0]["c"][0]["v"], "if (a<b) {}");
    }

    #[test]
    fn arvore_leva_comentarios() {
        let valor: Value = serde_json::from_str(&arvore_de("<div><!--$--><i></i><!--/$--></div>")).unwrap();
        assert_eq!(valor[0]["c"][0]["t"], "c");
        assert_eq!(valor[0]["c"][0]["v"], "$");
        assert_eq!(valor[0]["c"][1]["g"], "i");
        assert_eq!(valor[0]["c"][2]["t"], "c");
        assert_eq!(valor[0]["c"][2]["v"], "/$");
    }

    #[test]
    fn render_continua_ignorando_comentarios() {
        let saida = render_with("<p>a<!--$-->b</p>", None);
        assert!(saida.contains("ab") || (saida.contains('a') && saida.contains('b')));
        assert!(!saida.contains('$'));
    }

    #[test]
    fn arvore_null_devolve_null() {
        assert!(nusky_arvore(ptr::null()).is_null());
    }

    #[test]
    fn busca_acha_com_erro_de_digitacao() {
        let indice = indice_embutido().unwrap();
        let saida = formatar_busca(&indice, "gitub", &HashMap::new());
        let primeira = saida.lines().next().unwrap();
        assert!(primeira.starts_with("https://github.com\tGitHub\t"));
    }

    #[test]
    fn busca_mostra_atalho_com_titulo() {
        let indice = indice_embutido().unwrap();
        let saida = formatar_busca(&indice, "meu perfil", &HashMap::new());
        let primeira = saida.lines().next().unwrap();
        assert_eq!(primeira, "https://github.com/souza60029-wq\tGitHub\tMeu perfil");
    }

    #[test]
    fn busca_sem_resultado_fica_vazia() {
        let indice = indice_embutido().unwrap();
        assert!(formatar_busca(&indice, "xyzqw", &HashMap::new()).is_empty());
    }

    #[test]
    fn sugestao_traz_nome_e_endereco() {
        let indice = indice_embutido().unwrap();
        let saida = formatar_sugestao(&indice, "chatgtp");
        assert!(saida.starts_with("ChatGPT\thttps://chatgpt.com"));
    }

    #[test]
    fn usos_ignoram_linhas_erradas() {
        let usos = ler_usos("https://a.com\t3\nlinha quebrada\nhttps://b.com\tx\n");
        assert_eq!(usos.get("https://a.com"), Some(&3));
        assert_eq!(usos.get("https://b.com"), None);
    }

    #[test]
    fn lista_errada_nao_substitui_a_atual() {
        assert_eq!(nusky_busca_carregar(CString::new("{ isto não é json").unwrap().as_ptr()), 1);
    }

    #[test]
    fn origem_le_versao_e_data_do_cabecalho() {
        let (versao, data) = origem_de(r#"{"versao": 7, "data": "2026-12-01", "sites": []}"#);
        assert_eq!(versao, 7);
        assert_eq!(data, "2026-12-01");
    }

    #[test]
    fn origem_sem_cabecalho_devolve_zero_e_vazio() {
        assert_eq!(origem_de("{}"), (0, String::new()));
        assert_eq!(origem_de("não é json"), (0, String::new()));
    }

    #[test]
    fn lista_embutida_tem_versao_legivel() {
        assert!(origem_de(TEXTO_EMBUTIDO).0 > 0);
        assert!(!origem_de(TEXTO_EMBUTIDO).1.is_empty());
    }
}