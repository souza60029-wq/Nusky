// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/.

//! Interface C do motor, chamada pela casca Swift.
//!
//! Formato de saída de `nusky_render`: uma linha por comando de texto, com campos
//! separados por tab: `x<TAB>y<TAB>tamanho<TAB>negrito(0/1)<TAB>link<TAB>texto`.
//! O campo `link` fica vazio quando o texto não é link.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::html::parse;
use crate::layout::{layout, DrawCommand, TextMeasurer};

/// Medida aproximada, usada até a casca fornecer a medida real do CoreText.
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

/// Renderiza HTML (C string em UTF-8) para uma lista de comandos de texto.
/// Retorna null em caso de erro. Quem chama deve liberar o resultado
/// com `nusky_free_string`.
#[no_mangle]
pub extern "C" fn nusky_render(html: *const c_char, viewport_width: f32) -> *mut c_char {
    if html.is_null() {
        return std::ptr::null_mut();
    }
    let input = unsafe { CStr::from_ptr(html) }.to_string_lossy();
    let commands = layout(&parse(&input), viewport_width, &ApproxMeasurer);

    let mut out = String::new();
    for cmd in commands {
        match cmd {
            DrawCommand::Text { x, y, text, font_size, bold, href } => {
                out.push_str(&format!(
                    "{}\t{}\t{}\t{}\t{}\t{}\n",
                    x,
                    y,
                    font_size,
                    bold as u8,
                    sanitize(href.as_deref().unwrap_or("")),
                    sanitize(&text),
                ));
            }
        }
    }

    match CString::new(out) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Libera uma string devolvida por `nusky_render`.
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

    fn render_to_string(html: &str) -> String {
        let c = CString::new(html).unwrap();
        let ptr = nusky_render(c.as_ptr(), 400.0);
        assert!(!ptr.is_null());
        let out = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
        nusky_free_string(ptr);
        out
    }

    #[test]
    fn render_returns_tab_separated_lines() {
        assert_eq!(render_to_string("<p>oi</p>"), "8\t24\t16\t0\t\toi\n");
    }

    #[test]
    fn render_includes_link_target() {
        assert_eq!(render_to_string(r#"<a href="/x">oi</a>"#), "8\t8\t16\t0\t/x\toi\n");
    }

    #[test]
    fn null_input_returns_null() {
        assert!(nusky_render(std::ptr::null(), 400.0).is_null());
    }
}