// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Interface C do motor, chamada pela casca Swift.
//!
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

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;

use crate::diagnostico::relatorio;
use crate::html::parse;
use crate::layout::{layout, DrawCommand, TextMeasurer};
use crate::preparo::marcar_com_javascript;

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

/// Libera uma string devolvida por `nusky_render` ou `nusky_diagnose`.
#[no_mangle]
pub extern "C" fn nusky_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
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
}